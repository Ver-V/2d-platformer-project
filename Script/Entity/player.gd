extends CombatBody2D
class_name Player

# 플레이어 본체: 상태 전환(FSM), 이동·점프, 피격·사망, 상태이상 이어받기.
# 공격·패링은 Combat, 가드는 Guard, 팝업·먼지·게이지 같은 연출은 Visuals 자식 노드가 맡는다.

enum State { IDLE, RUN, JUMP, FALL, ATTACK, GUARD, DEAD, CHARGE }
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

@export_group("Air Control")
# 정점 체공: 점프 키를 누르고 있으면 속도가 apex_threshold보다 느린 정점 근처에서 중력이 apex_gravity_mult배 (셀레스트식 공중 조작 여유)
@export var apex_threshold: float = 40.0
@export var apex_gravity_mult: float = 0.5
# 빠른 낙하: 공중에서 아래(down)를 누르고 있으면 낙하 속도 상한이 fast_fall_speed까지 fast_fall_accel로 올라간다 (떼면 같은 속도로 돌아온다)
@export var fast_fall_speed: float = 300.0
@export var fast_fall_accel: float = 600.0

@export_group("Advanced Movement")
@export var acceleration: float = 1200.0   # 바닥 가속도 (높을수록 쫀쫀함)
@export var friction: float = 2500.0       # 바닥 마찰력 (떼면 미끄러지듯 멈춤)

@export_group("Jump Forgiveness")
@export var coyote_time: float = 0.2     # 절벽에서 떨어져도 점프 가능한 시간
@export var jump_buffer_time: float = 0.15 # 바닥에 닿기 전 미리 점프 입력받는 시간

@export_group("Water")
# 물 타일(WaterTileMap) 안: 이동·점프·중력이 느려지고, 점프 키를 누르고 있으면 떠오른다. 호흡 게이지(BreathEffect)가 생긴다
@export var water_move_mult: float = 0.5
@export var water_jump_mult: float = 0.25    # 점프 힘·떠오르는 속도 배율 (jumpforce 기준)
@export var water_gravity_mult: float = 0.25
@export var water_max_fall_speed: float = 50.0
@export var water_rise_accel: float = 600.0  # 점프 키를 누르는 동안 떠오르는 속도까지 붙는 가속
@export var water_exit_jump_height: float = 24.0 # 떠오르며 수면을 벗어날 때 수면 위로 솟는 높이(px) — 한 칸 높이 턱을 오를 수 있게

@export_group("Hazard Respawn")
# 가시에 맞으면 (죽지 않았을 때) 화면이 어두워졌다가 마지막으로 밟은 안전한 땅(last_safe_position)에서 다시 시작한다
@export var hazard_respawn_fade: float = 0.5 # 어두워졌다 밝아지는 시간 합 (SceneTransition)

@export_group("Hurt")
@export var invuln_time: float = 0.8
@export var blink_interval: float = 0.05
@export var knockback_decay: float = 1800.0

const BREATH_EFFECT: StatusEffect = preload("res://resources/status_effects/breath.tres")
const SND_IN_WATER: AudioStream = preload("res://Assets/sounds/environment/in_water.wav")
const WATER_SENSE_OFFSET := Vector2(0, -10) # 몸 가운데 (발 원점에서 위로)
var in_water: bool = false
var _water_loop: AudioStreamPlayer2D # 물속에 있는 동안 반복 재생 (SFXPlayer와 따로 두어 점프·공격 소리에 끊기지 않게)

const CORNER_CORRECTION_PX: int = 4    # 모서리 보정 최대 픽셀 거리 (몸 폭 10px의 40%)
const LEDGE_POP_PX: int = 6            # 턱 끝 올려 주기: 발이 턱보다 이만큼 아래여도 밀고 있으면 올려 준다
const LEDGE_POP_MAX_RISE: float = 60.0 # 이보다 빨리 오르는 중엔 하지 않는다 (정점 근처·떨어지는 중에만)
const KNOCKBACK_COOLDOWN: float = 0.7  # 넉백을 다시 받을 수 있기까지 (짧을수록 금방 다시 움직임)

# 내부 타이머
var _coyote_timer: float = 0.0
var _jump_buffer_timer: float = 0.0
var _air_jump_available: bool = false # 더블 점프: 땅·물에 닿으면 다시 한 번 쓸 수 있다
var _air_peak_y: float = INF # 이번 체공에서 가장 높이 올라간 곳 (트램펄린이 여기까지 되돌려 보낸다. INF = 아직 모름 → 튕기지 않음)
var _ground_y: float = INF # 마지막으로 밟은 트램펄린이 아닌 바닥(물속이면 지금 높이). 트램펄린 높이 상한의 기준 (INF = 아직 모름)
var _air_jump_deferred: bool = false # 착지 직전이라 미뤄 둔 더블 점프: 선입력 시간 안에 못 내려서면 그때 쓴다
const TUTORIAL_SPIKES := &"TUTORIAL_SPIKES" # 가시에 처음 찔려 안전한 땅으로 돌아왔을 때
const TUTORIAL_FAST_FALL := &"TUTORIAL_FAST_FALL" # 처음으로 최고 속도로 한동안 떨어졌을 때 (아래 키를 안 누르고)
const FAST_FALL_HINT_TIME := 0.6
var _terminal_fall_time: float = 0.0
var _fall_cap: float = -1.0 # 지금 낙하 속도 상한 (빠른 낙하면 max_fall_speed보다 높다). 음수 = 아직 안 정함
var _bounce_rising: bool = false # 트램펄린에 튕겨 오르는 중: 점프 키를 떼도 점프 컷 없이 끝까지 솟는다
var _was_on_floor: bool = false
var _menu_exit_cooldown: float = 0.0
# 마지막으로 안전한 땅(가시가 아닌 일반 지형 타일)을 밟은 위치. 나갈 때 이어 하기 위치로 쓴다 (BaseStage.get_resume_position)
var last_safe_position: Vector2 = Vector2.ZERO
var has_safe_position: bool = false
var _last_damage_cause: String = "unknown" # 마지막으로 피해를 준 것 (사망 로그용)
# 사인 (해골에 표시): "enemy:<몹 씬 경로>" / "spikes" / "status:<상태이상 id>" / "unknown". DeathCause.describe로 읽는 글이 된다
var death_cause: String = "unknown"
var _hazard_respawning: bool = false

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
	_setup_water_sound()

	# 상태이상에 처음 걸리면 그 상태이상 도움말을 한 번 띄운다
	get_status_effects().effect_added.connect(func(effect: StatusEffect) -> void:
		if hp > 0 and effect.tutorial_key != &"":
			TutorialPopup.show_once(effect.tutorial_key))

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
	var from_charge := current_state == State.CHARGE
	var heavy := from_charge and combat.is_charge_ready()
	match current_state:
		State.ATTACK:
			combat.end_attack()
		State.GUARD:
			guard.end()
		State.CHARGE:
			combat.end_charge()
			visuals.set_charge_flash(false)

	current_state = new_state

	# 2. 새로운 상태 진입(Enter) 처리
	match current_state:
		State.ATTACK:
			# 끝은 animation_finished("Attack")에서
			anim_player.play("Attack", -1, combat.attack_speed_mult)
			if from_charge: # 모으던 자세(칼을 든 프레임)에서 이어서 휘두른다
				anim_player.seek(PlayerCombat.HEAVY_POSE_TIME, true)
			combat.begin_attack(heavy)
		State.CHARGE:
			# 공격 키를 누르는 동안 휘두르기 직전 자세로 멈춰 있다. 끝은 키를 뗄 때(_process_charge)
			anim_player.play("Attack")
			anim_player.seek(PlayerCombat.HEAVY_POSE_TIME, true)
			anim_player.pause()
			combat.begin_charge()
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
	hit = _apply_moon_damage(hit)
	if guard.can_block(hit):
		return guard.block(hit)
	# CombatBody2D.receive_hit과 같지만, 잠에서 깨우기(_after_damaged)를 상태이상보다 먼저 한다 —
	# 그래야 이 타격의 졸음으로 잠드는 순간 바로 깨지 않는다 (늑대의 잠 탄환 세 번째 등)
	var result := _take_hit(hit)
	if HitData.landed(result):
		_last_damage_cause = PlayLog.describe_source(hit.source)
		death_cause = DeathCause.of_source(hit.source)
	_after_damaged(result)
	if result == HitData.Result.HIT:
		for effect in hit.status_effects:
			apply_status_effect(effect)
	return result

# 달빛(MoonPhase)으로 사나워진 몹의 타격은 피해가 배율만큼 바뀐다 (원래 HitData는 건드리지 않는다)
func _apply_moon_damage(hit: HitData) -> HitData:
	var mult := MoonPhase.damage_mult_from(hit.source)
	if is_equal_approx(mult, 1.0) or hit.amount <= 0:
		return hit
	var scaled := hit.duplicate_hit()
	scaled.amount = maxi(1, roundi(hit.amount * mult))
	return scaled

# 상태이상 없이 피해만 (가드로 깎인 피해 등)
func take_damage_only(hit: HitData) -> HitData.Result:
	var result := _take_hit(hit)
	if HitData.landed(result):
		_last_damage_cause = PlayLog.describe_source(hit.source)
		death_cause = DeathCause.of_source(hit.source)
	_after_damaged(result)
	return result

# 피해가 실제로 들어갔을 때의 반응 (소리·HUD·히트스탑·공격/가드 끊기·잠에서 깨기)
func _after_damaged(result: HitData.Result) -> void:
	if not HitData.landed(result):
		return
	var drowsy := get_status_effects().get_effect(&"drowsy") as DrowsyEffect
	if drowsy != null:
		drowsy.wake()
	sfx_player.play_hurt()
	GameManager.update_hp(hp)
	HUD.show_hud_temporarily()
	HUD.show_damage_vignette(hp, max_hp)
	GameManager.apply_hitstop(0.25, 0.2)
	if current_state == State.ATTACK or current_state == State.GUARD or current_state == State.CHARGE:
		change_state(State.IDLE if is_on_floor() else State.FALL)

# 상태이상 틱은 빨간 피격 비네트 대신 상태이상별 화면 점멸(screen_tint)로 표시한다
func _on_status_damaged(_amount: int) -> void:
	_last_damage_cause = "status"
	death_cause = "status:%s" % last_status_cause
	GameManager.update_hp(hp)
	HUD.show_hud_temporarily()

# 씬을 떠날 때 걸려 있는 상태이상은 GameManager에 맡겨 다음 씬의 플레이어가 이어받는다.
# 휴식·사망은 그 전에 이미 해제하므로 넘어가지 않는다. 화면 점멸은 다음 플레이어가 다시 켠다.
func _exit_tree() -> void:
	if _hazard_respawning: # 가시 복귀 중에 씬이 바뀌어도 조작 잠금이 남지 않게
		_hazard_respawning = false
		GameManager.ui_closed(self)
	if hp > 0 and is_instance_valid(_status_effects):
		GameManager.carried_status_effects = _status_effects.detach_all()
	HUD.clear_status_tints()

func _on_death() -> void:
	PlayLog.player_died(get_tree().current_scene.scene_file_path if get_tree().current_scene else "", global_position, _last_damage_cause)
	change_state(State.DEAD)
	_water_loop.stop()

# --- 물 ---
# 몸 가운데가 물 칸 안이면 수영. 떠오르며 물 밖으로 나오는 순간 수면 위로 water_exit_jump_height만큼 솟게 한다
func _update_water() -> void:
	var now := WaterTileMap.is_water_at(get_tree(), global_position + WATER_SENSE_OFFSET)
	if in_water and not now:
		if velocity.y < 0.0 and Input.is_action_pressed("jump") and not GameManager.is_menu_open:
			var exit_speed := -sqrt(2.0 * get_gravity().y * water_exit_jump_height)
			velocity.y = minf(velocity.y, exit_speed)
		# 물속 허우적 동작(Run)을 끝내고 공중 동작으로
		if current_state == State.JUMP or current_state == State.FALL:
			anim_player.play("Jump")
	if now and not in_water:
		sfx_player.play_enter_water()
		_water_loop.play()
	elif in_water and not now:
		_water_loop.stop()
	in_water = now
	var breath := get_status_effects().get_effect(&"breath") as BreathEffect
	if in_water and breath == null and hp > 0:
		breath = apply_status_effect(BREATH_EFFECT) as BreathEffect
		if breath != null and GameManager.breath_bonus > 0.0: # 호흡량 소모품
			breath.max_breath += GameManager.breath_bonus
			breath.breath = breath.max_breath
	if breath != null:
		breath.submerged = in_water

func _setup_water_sound() -> void:
	_water_loop = AudioStreamPlayer2D.new()
	_water_loop.name = "WaterLoop"
	_water_loop.stream = SND_IN_WATER
	_water_loop.bus = &"SFX"
	_water_loop.finished.connect(func():
		if in_water and hp > 0:
			_water_loop.play())
	add_child(_water_loop)

# 물속: 중력이 약하고 낙하 속도 상한이 낮다. 점프 키를 누르고 있으면 천천히 떠오른다
func _apply_water_gravity(delta: float) -> void:
	velocity.y += get_gravity().y * water_gravity_mult * delta
	if not GameManager.is_menu_open and hp > 0 and Input.is_action_pressed("jump"):
		velocity.y = move_toward(velocity.y, jumpforce * water_jump_mult, water_rise_accel * delta)
	velocity.y = minf(velocity.y, water_max_fall_speed)

# --- 졸음 (DrowsyEffect) ---
func is_asleep() -> bool:
	var drowsy := get_status_effects().get_effect(&"drowsy") as DrowsyEffect
	return drowsy != null and drowsy.is_asleep()

# 잠든 동안: 조작(이동·점프·공격·가드·플라스크)이 전부 막히고 그 자리에 서서 존다. 중력·넉백은 그대로 받고, 맞으면 깬다.
# 머리 위 Zzz... 말풍선은 Visuals가 is_asleep()을 보고 띄운다
func _process_asleep(delta: float) -> void:
	if current_state == State.ATTACK or current_state == State.GUARD or current_state == State.CHARGE:
		change_state(State.IDLE if is_on_floor() else State.FALL)
	if is_on_floor():
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)
		if current_state == State.RUN or current_state == State.JUMP or current_state == State.FALL:
			change_state(State.IDLE)
	else:
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)
		if velocity.y > 0.0 and current_state != State.FALL:
			change_state(State.FALL)
	# apply_gravity는 점프 키(점프 컷·물속 떠오르기)를 읽으므로 키 입력 없이 중력만
	if in_water:
		velocity.y = minf(velocity.y + get_gravity().y * water_gravity_mult * delta, water_max_fall_speed)
	elif not is_on_floor():
		velocity.y = minf(velocity.y + get_gravity().y * fall_gravity_mult * delta, max_fall_speed)
	_jump_buffer_timer = 0.0
	move_with_knockback(delta)
	if anim_player.has_animation("sleep"):
		if anim_player.current_animation != "sleep":
			anim_player.play("sleep")
	else:
		_update_animation(0)
	_was_on_floor = is_on_floor()

# --- 이동 ---
func apply_gravity(delta: float) -> void:
	if in_water:
		_apply_water_gravity(delta)
		return
	if is_on_floor():
		_fall_cap = max_fall_speed # 착지하면 빠른 낙하 상한도 원래대로
		_terminal_fall_time = 0.0
		return

	var g := get_gravity()
	var controllable := not GameManager.is_menu_open and hp > 0
	var mult := 1.0
	if velocity.y > 0.0: mult = fall_gravity_mult
	if controllable and absf(velocity.y) < apex_threshold and Input.is_action_pressed("jump"):
		mult *= apex_gravity_mult # 정점 체공

	velocity += g * mult * delta

	# 점프 컷 (점프 키 뗐을 때 상승력 감소)
	if controllable:
		if Input.is_action_just_released("jump") and velocity.y < 0.0 and not _bounce_rising:
			velocity.y *= jump_cut_factor

	# 빠른 낙하: 아래를 누르는 동안 낙하 속도 상한이 서서히 오른다
	var cap_goal := fast_fall_speed if controllable and Input.is_action_pressed("down") else max_fall_speed
	if _fall_cap < 0.0:
		_fall_cap = max_fall_speed
	_fall_cap = move_toward(_fall_cap, maxf(cap_goal, max_fall_speed), fast_fall_accel * delta)
	if velocity.y > _fall_cap:
		velocity.y = _fall_cap
	_update_fast_fall_hint(delta, controllable)

# 아래 키 없이 최고 속도로 한동안 떨어지면 빠른 낙하를 한 번 알려 준다
func _update_fast_fall_hint(delta: float, controllable: bool) -> void:
	if controllable and velocity.y >= max_fall_speed - 1.0 and not Input.is_action_pressed("down"):
		_terminal_fall_time += delta
		if _terminal_fall_time >= FAST_FALL_HINT_TIME:
			Tutorials.show_once(self, TUTORIAL_FAST_FALL)
	else:
		_terminal_fall_time = 0.0

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

	_update_water()
	if is_asleep():
		_process_asleep(delta)
		return
	# 공통 타이머 감소
	combat.tick(delta)
	guard.tick(delta)
	if _menu_exit_cooldown > 0.0: _menu_exit_cooldown -= delta
	_coyote_timer -= delta
	_jump_buffer_timer -= delta

	if is_on_floor() or in_water:
		_air_jump_available = true
	if is_on_floor():
		_coyote_timer = coyote_time
		if current_state == State.FALL or current_state == State.JUMP:
			change_state(State.IDLE)
		if not _try_bounce(): # 트램펄린 위면 늘 튕기므로, 여기 남는 바닥은 트램펄린이 아니다
			_air_peak_y = global_position.y
			_ground_y = global_position.y
	elif in_water:
		_air_peak_y = global_position.y # 헤엄친 높이는 치지 않고, 수면을 땅으로 친다
		_ground_y = global_position.y
	else:
		_air_peak_y = minf(_air_peak_y, global_position.y)
	if velocity.y >= 0.0:
		_bounce_rising = false

	_update_deferred_air_jump()

	if not is_on_floor() and current_state != State.ATTACK and current_state != State.GUARD and current_state != State.CHARGE:
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
		State.CHARGE:
			_handle_corner_correction(delta)
			_process_charge(delta)
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
	_update_safe_position()

# 무너지는 블록·움직이는 발판(타일맵이 아닌 바닥)과 가시 타일맵(damage 데이터가 있는 타일셋)은 안전한 땅이 아니다
func _update_safe_position() -> void:
	if not is_on_floor():
		return
	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		if collision.get_normal().y > -0.7:
			continue
		var floor_layer := collision.get_collider() as TileMapLayer
		if floor_layer == null or (floor_layer.tile_set != null and floor_layer.tile_set.get_custom_data_layer_by_name("damage") != -1):
			continue
		last_safe_position = global_position
		has_safe_position = true
		return

func _process_movement(delta: float) -> void:
	var dir_input := Input.get_axis("left", "right")

	# 상태 전환: 방향키 입력 시 RUN, 아니면 IDLE (바닥일 때만. 트램펄린에 튕겨 막 솟는 프레임은 제외)
	if is_on_floor() and velocity.y >= 0.0:
		if dir_input != 0:
			if current_state != State.RUN: change_state(State.RUN)
		else:
			if current_state != State.IDLE: change_state(State.IDLE)

	# 상태 전이 (공격, 가드)
	if Input.is_action_just_pressed("attack") and combat.can_attack() and _menu_exit_cooldown <= 0.0:
		# 강공격을 배웠으면 누르는 동안 모으고, 떼는 순간 휘두른다 (짧게 누르면 일반 공격)
		change_state(State.CHARGE if combat.can_charge() else State.ATTACK)
		return

	if Input.is_action_just_pressed("guard") and is_on_floor() and guard.can_start():
		change_state(State.GUARD)
		return

	# 점프 선입력 (공중에서 새로 누르면 더블 점프)
	if Input.is_action_just_pressed("jump") and _menu_exit_cooldown <= 0.0:
		_jump_buffer_timer = jump_buffer_time
		_try_double_jump()

	_try_jump()
	_face(dir_input)
	_apply_run(dir_input, delta)
	apply_gravity(delta)
	_handle_ledge_pop(dir_input)
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

# 강공격 모으기: 키를 떼면 휘두른다 (HEAVY_CHARGE_TIME 이상 모았으면 강공격). 점프·가드로 취소, 이동은 느리게
func _process_charge(delta: float) -> void:
	if not Input.is_action_pressed("attack"):
		change_state(State.ATTACK)
		return
	if _menu_exit_cooldown <= 0.0 and Input.is_action_just_pressed("jump"):
		change_state(State.IDLE if is_on_floor() else State.FALL)
		_process_movement(delta)
		return
	if Input.is_action_just_pressed("guard") and is_on_floor() and guard.can_start():
		change_state(State.GUARD)
		return
	var was_ready := combat.is_charge_ready()
	combat.tick_charge(delta)
	if combat.is_charge_ready() and not was_ready:
		visuals.set_charge_flash(true)
	apply_gravity(delta)
	var dir_input := Input.get_axis("left", "right")
	_face(dir_input)
	velocity.x = dir_input * movespeed * PlayerCombat.CHARGE_MOVE_RATIO
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

# 더블 점프: 해금 후, 바닥 점프(코요테 포함)를 못 하는 공중에서 점프를 새로 누르면 같은 힘으로 한 번 더 뛴다.
# 곧 착지할 거리면 쓰지 않고 선입력으로 남긴다 (착지 직전에 누른 점프가 더블 점프로 새지 않게)
func _try_double_jump() -> void:
	if not GameManager.double_jump_unlocked or not _air_jump_available:
		return
	if is_on_floor() or _coyote_timer > 0.0 or in_water:
		return
	if _lands_within_buffer():
		_air_jump_deferred = true # 곧 착지한다: 선입력으로 남겨 두면 착지하자마자 땅 점프가 나간다. 못 내려서면 그때 더블 점프
		return
	_do_double_jump()

func _do_double_jump() -> void:
	_air_jump_deferred = false
	_air_jump_available = false
	_jump_buffer_timer = 0.0
	_bounce_rising = false
	velocity.y = jumpforce
	sfx_player.play_jump()
	visuals.spawn_dust()
	visuals.apply_squash(0.8, 1.2)
	change_state(State.JUMP)

# 양털 트램펄린(WoolBounce)에 내려앉으면 떨어지기 시작한 높이(이번 체공의 최고점)까지 1:1로 되돌려 보낸다:
# 더블 점프 후 내려앉으면 더블 점프 높이만큼 다시 솟는다. 점프 한 번보다 덜 떨어졌으면(서 있기 포함) 점프 한 번만큼,
# 마지막 땅(_ground_y)에서 점프 + 더블 점프로 닿는 높이보다 위로는 보내지 않는다 (튕김·더블 점프 반복으로 끝없이 오르지 않게).
# 튕김이 바닥 점프 몫이라 코요테·선입력은 지우고(튕김을 덮어쓰지 않게) 공중 점프는 다시 채운다. 물속에선 튕기지 않는다
func _try_bounce() -> bool:
	if in_water:
		return false
	var pad := _floor_bouncer()
	if pad == null:
		return false
	var g := get_gravity().y
	var dt := get_physics_process_delta_time()
	var jump_height := WoolBounce.rise_height(g, absf(jumpforce), dt, true)
	var target_y := _air_peak_y
	if is_finite(_ground_y):
		var ceiling_y := _ground_y - jump_height - WoolBounce.rise_height(g, absf(jumpforce), dt, false)
		target_y = maxf(target_y, ceiling_y)
	var height := maxf(global_position.y - target_y, jump_height)
	velocity.y = -WoolBounce.launch_speed(g, height, dt)
	_bounce_rising = true
	_air_peak_y = global_position.y
	_coyote_timer = 0.0
	_jump_buffer_timer = 0.0
	_air_jump_available = true
	pad.play_bounce()
	TutorialPopup.show_once(pad.tutorial_key)
	visuals.apply_squash(0.8, 1.2)
	if current_state == State.IDLE or current_state == State.RUN or current_state == State.FALL:
		change_state(State.JUMP)
	return true

# 발밑 바로 아래의 트램펄린 (바닥 스냅으로 붙으면 충돌 기록이 안 남으므로 살짝 내려 보는 시험 이동으로 찾는다)
func _floor_bouncer() -> WoolBounce:
	var collision := move_and_collide(Vector2(0, 2), true)
	if collision != null and collision.get_normal().y <= -0.7:
		return collision.get_collider() as WoolBounce
	return null

# 미뤄 둔 더블 점프: 착지하면(땅 점프가 대신 나간다) 버리고, 선입력 시간이 다 되도록 공중이면 지금 쓴다
func _update_deferred_air_jump() -> void:
	if not _air_jump_deferred:
		return
	if is_on_floor() or in_water or not _air_jump_available:
		_air_jump_deferred = false
	elif _jump_buffer_timer <= 0.0:
		if current_state == State.IDLE or current_state == State.RUN or current_state == State.JUMP or current_state == State.FALL:
			_do_double_jump()
		else:
			_air_jump_deferred = false

# 떨어지는 중이고, 점프 선입력 시간(jump_buffer_time) 안에 발밑 바닥에 닿을 거리인가 (가로 이동도 반영)
func _lands_within_buffer() -> bool:
	if velocity.y <= 0.0:
		return false
	var t := jump_buffer_time
	var reach := velocity.y * t + 0.5 * get_gravity().y * fall_gravity_mult * t * t
	return test_move(global_transform, Vector2(velocity.x * t, reach))

# 선입력과 코요테 타임이 겹치면 점프
func _try_jump() -> void:
	if _jump_buffer_timer <= 0.0 or _coyote_timer <= 0.0:
		return
	velocity.y = jumpforce * (water_jump_mult if in_water else 1.0)
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
	var target_speed := dir_input * movespeed * (water_move_mult if in_water else 1.0)
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

# 턱 끝 올려 주기: 공중에서 벽 쪽으로 밀고 있는데 발이 턱 위끝보다 LEDGE_POP_PX 이내로 아래면, 그만큼 올려서 턱에 올라서게 한다
# ("분명 닿았는데 떨어졌다"를 줄인다). 머리 위가 막혔거나 빠르게 오르는 중이면 하지 않는다
func _handle_ledge_pop(dir_input: float) -> void:
	if is_on_floor() or in_water or dir_input == 0.0 or velocity.y < -LEDGE_POP_MAX_RISE:
		return
	var side := Vector2(signf(dir_input), 0)
	if not test_move(global_transform, side):
		return # 앞이 막혀 있지 않다
	for i in range(1, LEDGE_POP_PX + 1):
		var up := Vector2(0, -i)
		if test_move(global_transform, up):
			return # 머리 위가 막혔다
		if not test_move(global_transform.translated(up), side):
			global_position.y -= i
			velocity.y = minf(velocity.y, 0.0)
			return

# --- 가시에 맞은 뒤 다시 시작 ---
# HazardSensor가 가시 피해가 들어가고 살아 있으면 부른다. 어두워진 사이에 마지막 안전한 땅으로 옮기고, 그동안 조작을 막는다
func respawn_from_hazard() -> void:
	if _hazard_respawning or not has_safe_position or hp <= 0:
		return
	_hazard_respawning = true
	GameManager.ui_opened(self, false)
	SceneTransition.start_transition(_warp_to_safe_ground, hazard_respawn_fade)
	await Wait.seconds(self, hazard_respawn_fade * 0.5 + 0.5) # 어두워짐 + 어두운 채 대기 (밝아지기 시작하면 다시 움직인다)
	GameManager.ui_closed(self)
	_hazard_respawning = false
	Tutorials.show_once(self, TUTORIAL_SPIKES)

func _warp_to_safe_ground() -> void:
	if not is_instance_valid(self) or hp <= 0:
		return
	global_position = last_safe_position
	velocity = Vector2.ZERO
	knockback_vel = Vector2.ZERO
	_knockback_left = 0.0
	_air_peak_y = global_position.y
	_ground_y = global_position.y
	_air_jump_deferred = false
	_jump_buffer_timer = 0.0

func is_hazard_respawning() -> bool:
	return _hazard_respawning

# 애니메이션 관리 전용 함수 (ATTACK·GUARD·DEAD·JUMP·FALL은 change_state에서 재생)
func _update_animation(dir_input: float) -> void:
	# 물속에서는 서 있든 떠 있든 걷기 동작을 계속 (허우적거림)
	if in_water:
		if anim_player.current_animation != "Run":
			anim_player.play("Run")
		return
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
