extends CombatBody2D
class_name Player

# 플레이어 본체: 상태 전환(FSM), 이동·점프, 피격·사망, 상태이상 이어받기.
# 공격·패링은 Combat, 가드는 Guard, 팝업·먼지·게이지 같은 연출은 Visuals 자식 노드가 맡는다.

enum State { IDLE, RUN, JUMP, FALL, ATTACK, GUARD, DEAD }
var current_state: State = State.IDLE

@onready var combat: PlayerCombat = $Combat
@onready var guard: PlayerGuard = $Guard
@onready var visuals: PlayerVisuals = $Visuals

@onready var sprite: AnimatedSprite2D = $PlayerAni
@onready var attack_pivot: Marker2D = $AttackPivot
@onready var status_label: Label = $StatusLabel
# 기존 서 있는 충돌체
@onready var collision_stand: CollisionShape2D = $PlayerCol
@onready var collision_died: CollisionShape2D = $Collisiondied
@onready var sfx_player: AudioStreamPlayer2D = $SFXPlayer
@onready var anim_player: AnimationPlayer = $AnimationPlayer
@onready var magnet_area: Area2D = $MagnetArea

@export_group("Movement")
@export var movespeed: float = 120.0
@export var jumpforce: float = -350.0
@export var jump_cut_factor: float = 0.45
@export var fall_gravity_mult: float = 1.0
@export var max_fall_speed: float = 280.0

@export_group("Advanced Movement")
@export var acceleration: float = 1200.0   # 바닥 가속도 (높을수록 쫀쫀함)
@export var friction: float = 2500.0       # 바닥 마찰력 (떼면 미끄러지듯 멈춤)

@export_group("Jump Forgiveness")
@export var coyote_time: float = 0.2     # 절벽에서 떨어져도 점프 가능한 시간
@export var jump_buffer_time: float = 0.15 # 바닥에 닿기 전 미리 점프 입력받는 시간

@export_group("Hurt")
@export var invuln_time: float = 0.8
@export var blink_interval: float = 0.05
@export var knockback_decay: float = 1800.0

const CORNER_CORRECTION_PX: int = 4    # 모서리 보정 최대 픽셀 거리 (몸 폭 10px의 40%)
const KNOCKBACK_COOLDOWN: float = 0.7  # 넉백을 다시 받을 수 있기까지 (짧을수록 금방 다시 움직임)

# 내부 타이머
var _coyote_timer: float = 0.0
var _jump_buffer_timer: float = 0.0
var _was_on_floor: bool = false
var _menu_exit_cooldown: float = 0.0

signal died
signal death_started

func _ready() -> void:
	add_to_group("player")

	var current_scene = get_tree().current_scene
	if current_scene and GameManager.has_checkpoint and GameManager.last_scene_path == current_scene.scene_file_path:
		global_position = GameManager.last_checkpoint_pos

	hp = GameManager.player_current_hp
	max_hp = GameManager.player_max_hp

	combat.setup(self)
	guard.setup(self)
	visuals.setup(self)
	magnet_area.area_entered.connect(_on_magnet_area_entered)

	# 이전 씬에서 걸려 있던 상태이상을 남은 시간 그대로 이어받는다 (엘리베이터·문 등으로 이동해도 풀리지 않게)
	get_status_effects().attach_all(GameManager.carried_status_effects)
	GameManager.carried_status_effects.clear()

	# 애니메이션 종료 신호 연결
	if anim_player:
		anim_player.animation_finished.connect(_on_animation_finished)

	# UI 갱신 신호 보내기 (현재 상태를 UI에 반영)
	GameManager.update_hp(hp)
	GameManager.gold_changed.emit(GameManager.gold)

	# 씬 전환 후 띄울 메시지가 있다면 표시 (예: "저장됨")
	if GameManager.pending_status != "":
		await Wait.seconds(self, 0.2)
		show_status(GameManager.pending_status)
		GameManager.pending_status = ""

	velocity = Vector2.ZERO
	floor_snap_length = 2.0
	apply_floor_snap()

	change_state(State.IDLE)
	move_and_slide()

func change_state(new_state: State) -> void:
	if current_state == new_state: return

	# 1. 이전 상태 종료(Exit) 처리
	match current_state:
		State.ATTACK:
			combat.end_attack()
		State.GUARD:
			guard.end()

	current_state = new_state

	# 2. 새로운 상태 진입(Enter) 처리
	match current_state:
		State.ATTACK:
			# 끝은 animation_finished("Attack")에서
			anim_player.play("Attack")
			combat.begin_attack()
		State.GUARD:
			# 끝은 animation_finished("guard")에서
			velocity.x = 0
			anim_player.play("guard")
			guard.begin()
		State.DEAD:
			death_started.emit()
			collision_stand.set_deferred("disabled", true)
			collision_died.set_deferred("disabled", false)
			velocity.x = 0
			reset_combat_state()
			set_process_input(false)
			anim_player.play("died")
			HUD.show_death_screen()
			get_tree().create_timer(4.0).timeout.connect(func():
				set_physics_process(false)
				died.emit()
			)
		State.JUMP, State.FALL:
			if anim_player.current_animation != "Jump":
				anim_player.play("Jump")

# --- 다른 시스템(아이템·상자·세이브 포인트·상태이상 등)이 부르는 공개 함수 ---
func update_damage(amount: int) -> void:
	combat.update_damage(amount)

func update_parry_ratio(amount: float) -> void:
	combat.update_parry_ratio(amount)

func show_popup(text: String, color: Color = Color.YELLOW) -> void:
	visuals.show_popup(text, color)

func show_status(action_type: String) -> void:
	visuals.show_status(action_type)

func shake_camera(amount: float) -> void:
	var stage = get_tree().current_scene
	if stage and stage.has_method("apply_camera_shake"):
		stage.apply_camera_shake(amount)

# --- CombatBody2D 설정 ---
func get_invuln_time() -> float: return invuln_time
func get_blink_interval() -> float: return blink_interval
func get_knockback_decay() -> float: return knockback_decay
func get_knockback_cooldown() -> float: return KNOCKBACK_COOLDOWN
func get_blink_node() -> CanvasItem: return sprite

# --- 피격 ---
func receive_hit(hit: HitData) -> HitData.Result:
	if guard.can_block(hit):
		return guard.block(hit)
	var result := super.receive_hit(hit)
	_after_damaged(result)
	return result

# 상태이상 없이 피해만 (가드로 깎인 피해 등)
func take_damage_only(hit: HitData) -> HitData.Result:
	var result := _take_hit(hit)
	_after_damaged(result)
	return result

# 피해가 실제로 들어갔을 때의 반응 (소리·HUD·히트스탑·공격/가드 끊기)
func _after_damaged(result: HitData.Result) -> void:
	if not HitData.landed(result):
		return
	sfx_player.play_hurt()
	GameManager.update_hp(hp)
	HUD.show_hud_temporarily()
	HUD.show_damage_vignette(hp, max_hp)
	GameManager.apply_hitstop(0.25, 0.2)
	if current_state == State.ATTACK or current_state == State.GUARD:
		change_state(State.IDLE if is_on_floor() else State.FALL)

# 상태이상 틱은 빨간 피격 비네트 대신 상태이상별 화면 점멸(screen_tint)로 표시한다
func _on_status_damaged(_amount: int) -> void:
	GameManager.update_hp(hp)
	HUD.show_hud_temporarily()

# 씬을 떠날 때 걸려 있는 상태이상은 GameManager에 맡겨 다음 씬의 플레이어가 이어받는다.
# 휴식·사망은 그 전에 이미 해제하므로 넘어가지 않는다. 화면 점멸은 다음 플레이어가 다시 켠다.
func _exit_tree() -> void:
	if hp > 0 and is_instance_valid(_status_effects):
		GameManager.carried_status_effects = _status_effects.detach_all()
	HUD.clear_status_tints()

func _on_death() -> void:
	change_state(State.DEAD)

# --- 이동 ---
func apply_gravity(delta: float) -> void:
	if is_on_floor(): return

	var g := get_gravity()
	var mult := 1.0
	if velocity.y > 0.0: mult = fall_gravity_mult

	velocity += g * mult * delta

	# 점프 컷 (점프 키 뗐을 때 상승력 감소)
	if not GameManager.is_menu_open and hp > 0:
		if Input.is_action_just_released("jump") and velocity.y < 0.0:
			velocity.y *= jump_cut_factor

	if velocity.y > max_fall_speed:
		velocity.y = max_fall_speed

func _physics_process(delta: float) -> void:
	if get_tree().paused:
		return

	if GameManager.is_menu_open:
		velocity.x = 0
		apply_gravity(delta)
		move_and_slide()

		# 대화나 메뉴 중일 때 바닥에 있으면 강제로 IDLE 상태로 전환하여 애니메이션 고정
		if current_state != State.DEAD and is_on_floor():
			change_state(State.IDLE)

		_update_animation(0)
		_menu_exit_cooldown = 0.2 # 메뉴가 닫힐 때 0.2초간 입력 방지
		return

	if hp <= 0: # DEAD 상태 보완 (낙하 등)
		apply_gravity(delta)
		if is_on_floor():
			velocity.x = 0
		move_and_slide()
		return

	# 공통 타이머 감소
	combat.tick(delta)
	guard.tick(delta)
	if _menu_exit_cooldown > 0.0: _menu_exit_cooldown -= delta
	_coyote_timer -= delta
	_jump_buffer_timer -= delta

	if is_on_floor():
		_coyote_timer = coyote_time
		if current_state == State.FALL or current_state == State.JUMP:
			change_state(State.IDLE)

	if not is_on_floor() and current_state != State.ATTACK and current_state != State.GUARD:
		if velocity.y > 0:
			change_state(State.FALL)
		elif current_state != State.JUMP: # 점프 중이 아닐 때만 전환
			change_state(State.JUMP)

	# 글로벌 입력 처리 (어느 상태에서든 입력 받으면 플라스크 사용 가능)
	if Input.is_action_just_pressed("use_flask"):
		GameManager.use_flask()

	match current_state:
		State.IDLE, State.RUN, State.JUMP, State.FALL:
			_handle_corner_correction(delta) # 천장 보정 적용
			_process_movement(delta)
		State.ATTACK:
			_handle_corner_correction(delta)
			_process_attack(delta)
		State.GUARD:
			_process_guard(delta)
		State.DEAD:
			pass

	# 착지 이펙트: 낙하 속도에 비례한 강도 (0.5 ~ 2.0)
	if is_on_floor() and not _was_on_floor:
		var impact_intensity := 1.0
		if max_fall_speed > 0:
			impact_intensity = remap(abs(velocity.y), 0, max_fall_speed, 0.5, 2.0)
		impact_intensity = clampf(impact_intensity, 0.5, 2.0)
		visuals.spawn_dust(Vector2.ZERO, impact_intensity)
		visuals.apply_squash(1.0 + (0.3 * impact_intensity), 1.0 - (0.3 * impact_intensity))

	_was_on_floor = is_on_floor()

func _process_movement(delta: float) -> void:
	var dir_input := Input.get_axis("left", "right")

	# 상태 전환: 방향키 입력 시 RUN, 아니면 IDLE (바닥일 때만)
	if is_on_floor():
		if dir_input != 0:
			if current_state != State.RUN: change_state(State.RUN)
		else:
			if current_state != State.IDLE: change_state(State.IDLE)

	# 상태 전이 (공격, 가드)
	if Input.is_action_just_pressed("attack") and combat.can_attack() and _menu_exit_cooldown <= 0.0:
		change_state(State.ATTACK)
		return

	if Input.is_action_just_pressed("guard") and is_on_floor() and guard.can_start():
		change_state(State.GUARD)
		return

	# 점프 선입력
	if Input.is_action_just_pressed("jump") and _menu_exit_cooldown <= 0.0:
		_jump_buffer_timer = jump_buffer_time

	_try_jump()
	_face(dir_input)
	_apply_run(dir_input, delta)
	apply_gravity(delta)
	move_with_knockback(delta)
	_update_animation(dir_input)

func _process_attack(delta: float) -> void:
	apply_gravity(delta)

	var dir_input := Input.get_axis("left", "right")

	# 인터럽트: 점프 (즉시 캔슬 후 점프)
	if Input.is_action_just_pressed("jump") and _menu_exit_cooldown <= 0.0:
		_jump_buffer_timer = jump_buffer_time

	# 공격 중 점프 캔슬 (바닥에 있거나 코요테 타임이 남아있을 때만)
	_try_jump()
	# 공격 중에도 이동 및 방향 전환 허용 (조작감 향상)
	_apply_run(dir_input, delta)
	_face(dir_input)
	move_with_knockback(delta)

func _process_guard(delta: float) -> void:
	# 가드 후딜 캔슬: 가드 중 이동/점프를 새로 누르면 즉시 풀고 그 입력을 이번 프레임에 처리한다
	# (누르고 있던 방향키는 캔슬하지 않고 아래에서 느리게 걷기로 처리 — 달리다 가드해도 바로 풀리지 않게)
	if _menu_exit_cooldown <= 0.0 and (Input.is_action_just_pressed("left") \
			or Input.is_action_just_pressed("right") or Input.is_action_just_pressed("jump")):
		change_state(State.IDLE)
		_process_movement(delta)
		return

	apply_gravity(delta)
	# 가드 전부터 누르던 방향키로는 느리게 걷는다 (바라보는 방향은 그대로 — 뒤로 걸으면 뒷걸음질)
	velocity.x = Input.get_axis("left", "right") * movespeed * guard.move_speed_ratio
	guard.tick_guarding(delta) # 퍼펙트 가드 판정용
	# 가드 지속 시간은 guard 애니메이션 종료 신호로 결정한다.
	move_with_knockback(delta)

# 선입력과 코요테 타임이 겹치면 점프
func _try_jump() -> void:
	if _jump_buffer_timer <= 0.0 or _coyote_timer <= 0.0:
		return
	velocity.y = jumpforce
	_jump_buffer_timer = 0.0
	_coyote_timer = 0.0
	sfx_player.play_jump()
	visuals.spawn_dust()
	visuals.apply_squash(0.8, 1.2) # 점프 시 길쭉하게
	change_state(State.JUMP)

func _face(dir_input: float) -> void:
	if dir_input != 0:
		sprite.flip_h = dir_input < 0
		attack_pivot.scale.x = 1 if dir_input > 0 else -1

# 바닥에선 가감속, 공중에선 즉시 목표 속도
func _apply_run(dir_input: float, delta: float) -> void:
	var target_speed := dir_input * movespeed
	if not is_on_floor():
		velocity.x = target_speed
	elif dir_input != 0:
		velocity.x = move_toward(velocity.x, target_speed, acceleration * delta)
	else:
		velocity.x = move_toward(velocity.x, 0, friction * delta)

# 모서리 보정
func _handle_corner_correction(delta: float) -> void:
	if velocity.y >= 0: return # 상승 중일 때만 작동

	# 이번 프레임에 실제로 올라갈 거리만큼 검사한다 (고정 2px이면 빠른 상승 중에 놓친다)
	var motion := Vector2(0, velocity.y * delta)
	if not test_move(global_transform, motion): return

	# 가까운 거리부터 좌우를 번갈아 보고, 찾은 거리만큼 한 번에 옮긴다
	for i in range(1, CORNER_CORRECTION_PX + 1):
		for dir in [-1, 1]:
			var offset := Vector2(dir * i, 0)
			if test_move(global_transform, offset): continue # 옆이 벽이면 옮길 수 없음
			if not test_move(global_transform.translated(offset), motion):
				global_position.x += offset.x
				return

# 애니메이션 관리 전용 함수 (ATTACK·GUARD·DEAD·JUMP·FALL은 change_state에서 재생)
func _update_animation(dir_input: float) -> void:
	match current_state:
		State.RUN:
			if dir_input != 0 and anim_player.current_animation != "Run":
				anim_player.play("Run")
		State.IDLE:
			if anim_player.current_animation != "Stand":
				anim_player.play("Stand")

func _on_magnet_area_entered(area: Area2D) -> void:
	# 코인 등 끌려오는 물체
	if area.has_method("attract_to"):
		area.attract_to(self)

func _on_animation_finished(anim_name: String) -> void:
	if anim_name == "Attack":
		if current_state == State.ATTACK:
			change_state(State.IDLE if is_on_floor() else State.FALL)
	elif anim_name == "guard":
		if current_state == State.GUARD:
			change_state(State.IDLE)
