extends CombatBody2D
class_name Player

enum State { IDLE, RUN, JUMP, FALL, ATTACK, GUARD, DEAD }
var current_state: State = State.IDLE

@onready var sprite: AnimatedSprite2D = $PlayerAni
@onready var sword_area: Area2D = $AttackPivot/SwordArea
@onready var sword_shape: CollisionShape2D = $AttackPivot/SwordArea/CollisionShape2D
@onready var attack_pivot: Marker2D = $AttackPivot
@onready var status_label: Label = $StatusLabel
# 기존 서 있는 충돌체
@onready var collision_stand: CollisionShape2D = $PlayerCol
@onready var collision_died: CollisionShape2D = $Collisiondied
@onready var sfx_player: AudioStreamPlayer2D = $SFXPlayer
@onready var anim_player: AnimationPlayer = $AnimationPlayer
@onready var guard_area: Area2D = $AttackPivot/GuardArea
@onready var guard_shape: CollisionShape2D = $AttackPivot/GuardArea/CollisionShape2D

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

# 내부 타이머
var _coyote_timer: float = 0.0
var _jump_buffer_timer: float = 0.0
var _was_on_floor: bool = false
var _menu_exit_cooldown: float = 0.0
@export_group("Visuals")
@export var dust_particles_scene: PackedScene = preload("res://Scenes/System/DustParticles.tscn")

@export_group("Combat")
@export var invuln_time: float = 0.8
@export var blink_interval: float = 0.05
@export var knockback_decay: float = 1800.0
@export var is_attacking: bool = false 
@export var attack_cooldown: float = 0.8
@export var attack_damage: float = 10.0
@export var player_parry_damage_multifac: float = 1.5
var _cooldown_left: float = 0.0
var is_parry_success: bool = false
var status_tween: Tween
var _squash_tween: Tween
var _base_sprite_scale: Vector2

var is_guarding: bool = false
var guard_timer: float = 0.0
var guard_cooldown_timer: float = 0.0

const GUARD_DURATION: float = 0.5          # 가드 지속 시간
const PERFECT_GUARD_WINDOW: float = 0.2     # 퍼펙트 가드 판정 시간
const GUARD_COOLDOWN_TIME: float = 1.5      # 가드 재사용 대기 시간

var has_perfect_guard_bonus: bool = false

signal died
signal death_started

func _ready() -> void:
	add_to_group("player")
	
	if sprite:
		_base_sprite_scale = sprite.scale
	
	var current_scene = get_tree().current_scene
	if current_scene and GameManager.has_checkpoint and GameManager.last_scene_path == current_scene.scene_file_path:
		global_position = GameManager.last_checkpoint_pos
	
	hp = GameManager.player_current_hp
	max_hp = GameManager.player_max_hp
	attack_damage = GameManager.player_damage
	player_parry_damage_multifac = GameManager.player_parry_damage_multifac

	if sword_area != null:
		sword_area.area_entered.connect(_on_sword_area_entered)
		if not sword_area.body_entered.is_connected(_on_sword_body_entered):
			sword_area.body_entered.connect(_on_sword_body_entered)
		sword_shape.disabled = true
	
	if guard_area != null:
		guard_area.area_entered.connect(_on_guard_area_entered)
		guard_shape.disabled = true
	
	# 애니메이션 종료 신호 연결
	if anim_player:
		anim_player.animation_finished.connect(_on_animation_finished)
	
	# UI 갱신 신호 보내기 (현재 상태를 UI에 반영)
	GameManager.update_hp(hp)
	GameManager.gold_changed.emit(GameManager.gold)
	
	# 씬 전환 후 띄울 메시지가 있다면 표시 (예: "저장됨")
	if GameManager.pending_status != "":
		await get_tree().create_timer(0.2).timeout
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
			is_attacking = false
			sword_shape.set_deferred("disabled", true)
		State.GUARD:
			is_guarding = false
			guard_shape.set_deferred("disabled", true)
			guard_cooldown_timer = GUARD_COOLDOWN_TIME

	current_state = new_state
	
	# 2. 새로운 상태 진입(Enter) 처리
	match current_state:
		State.ATTACK:
			is_attacking = true
			is_parry_success = false 
			print("Playing Attack Animation...")
			anim_player.play("Attack")
			sword_shape.disabled = false
			_cooldown_left = attack_cooldown
			
			# (이전의 강제 0.3초 타이머 로직은 삭제되고, _ready()에서 연결된 animation_finished 신호로 처리됨)
		State.GUARD:
			is_guarding = true
			guard_timer = 0.0
			velocity.x = 0
			sfx_player.play_guard()
			anim_player.play("guard")
			guard_shape.set_deferred("disabled", false)
		State.DEAD:
			# 사망 처리 로직
			death_started.emit()
			collision_stand.set_deferred("disabled", true)
			collision_died.set_deferred("disabled", false)
			velocity.x = 0 
			reset_combat_state()
			set_process_input(false)
			anim_player.play("died")
			HUD.show_death_screen()
			
			if is_attacking:
				sword_shape.set_deferred("disabled",true)
				
			get_tree().create_timer(4.0).timeout.connect(func():
				set_physics_process(false)
				died.emit()
			)
		State.JUMP, State.FALL:
			if anim_player.current_animation != "Jump":
				anim_player.play("Jump")

func update_gold(amount: int) -> void:
	# 이미 GM에 구현된 함수가 있으므로 그대로 사용
	GameManager.update_gold(amount)
	HUD.show_hud_temporarily() 

func update_damage(amount: int) -> void:
	# 1. GM에게 "공격력 좀 바꿔줘" 요청
	GameManager.add_player_damage(amount)
	
	# 2. GM이 바꾼 최신값을 내 변수에 동기화 (중요!)
	attack_damage = GameManager.player_damage 
	
	if amount > 0:
		show_popup("Damage Up!", Color.RED)

func update_parry_ratio(amount: float) -> void:
	# 1. GM에게 "패링 배율 좀 바꿔줘" 요청
	GameManager.add_parry_ratio(amount)
	
	# 2. GM이 바꾼 최신값을 동기화
	player_parry_damage_multifac = GameManager.player_parry_damage_multifac
	
	if amount > 0:
		show_popup("Parry Power Up!", Color.CYAN)
		
func get_invuln_time() -> float: return invuln_time
func get_blink_interval() -> float: return blink_interval
func get_knockback_decay() -> float: return knockback_decay
func get_blink_node() -> CanvasItem: return sprite


func show_popup(text: String, color: Color = Color.YELLOW) -> void:
	if status_label == null: return

	if status_tween:
		status_tween.kill()

	status_label.text = text
	status_label.modulate = color
	status_label.visible = true
	
	status_label.position.y = -45.0 
	status_label.modulate.a = 1.0 

	status_tween = create_tween()
	var tween = status_tween

	tween.set_parallel(true)

	tween.tween_property(status_label, "position:y", -75.0, 1.0).set_trans(Tween.TRANS_SINE)
	tween.tween_property(status_label, "modulate:a", 0.0, 1.5).set_ease(Tween.EASE_IN)
	
	tween.chain().tween_callback(func(): status_label.visible = false)
	
	
func _on_sword_area_entered(area: Area2D) -> void:
	if area is Projectile:
		var p: Projectile = area as Projectile

		# 퍼펙트 가드 보너스가 있으면 +10 전달 (성공 시에만 소모하도록 아래에서 처리)
		var extra = 10 if has_perfect_guard_bonus else 0

		if p.attempt_parry(global_position, extra):
			is_parry_success = true
			sfx_player.play_parry()
			
			# 패링 성공 시에만 보너스 소모 및 팝업 출력
			if has_perfect_guard_bonus:
				has_perfect_guard_bonus = false
				show_popup("Counter Parry!", Color.CYAN)
			
			var stage = get_tree().current_scene
			if stage and stage.has_method("apply_camera_shake"):
				stage.apply_camera_shake(3.0)
			
			# 성공했을 때만 잠깐 대기 후 히트스탑
			await get_tree().create_timer(0.05).timeout
			GameManager.apply_hitstop(0.15, 0.2)
		
		# else: 실패한 경우(패링 불가 탄환)에는 아무것도 안 함.
		# is_parry_success가 false로 유지되므로, 
		# 칼이 몬스터 몸에 닿았을 때 정상적으로 데미지가 들어감.
		
func _on_sword_body_entered(body: Node) -> void:
	# 1. 적 그룹인지 확인
	if body.is_in_group("enemies"):
		await get_tree().process_frame
		
		# 이미 투사체를 패링했다면 검으로 직접 데미지를 주지 않음
		if is_parry_success:
			return

		if body.has_method("apply_damage"):
			# 데미지 계산 (보너스 확인)
			var extra = 10 if has_perfect_guard_bonus else 0
			var final_damage = attack_damage + extra

			# 넉백 방향 계산 (플레이어 -> 적)
			var knock_dir = (body.global_position - global_position).normalized()
			var knock_force = Vector2(knock_dir.x * 400, -200)
			var hit_applied: bool = body.apply_damage(int(final_damage), knock_force)
			
			if hit_applied:
				# 실제로 데미지가 들어갔을 때만 보너스 소모
				if has_perfect_guard_bonus:
					has_perfect_guard_bonus = false
					show_popup("Counter Hit!", Color.ORANGE)
				GameManager.apply_hitstop(0.25, 0.1)
			
				var stage = get_tree().current_scene
				if stage and stage.has_method("apply_camera_shake"):
					stage.apply_camera_shake(2.0)
			
		elif body.has_method("take_damage"):
			# take_damage를 쓰는 적들을 위한 처리
			var extra = 10 if has_perfect_guard_bonus else 0
			var final_damage = attack_damage + extra

			body.take_damage(final_damage, global_position)
			
			# take_damage는 성공 여부 리턴이 없으므로 일단 소모
			if has_perfect_guard_bonus:
				has_perfect_guard_bonus = false
				show_popup("Counter Hit!", Color.ORANGE)
				
			GameManager.apply_hitstop(0.25, 0.1)
			
func _on_guard_area_entered(area: Area2D) -> void:
	if not is_guarding: return

	# 닿은 것이 투사체인지 확인
	if area is Projectile:
		var p: Projectile = area as Projectile

		# 1. 퍼펙트 가드 타이밍 체크
		if guard_timer <= PERFECT_GUARD_WINDOW:
			# 퍼펙트 가드 보너스 부여
			has_perfect_guard_bonus = true
			
			show_popup("Perfect Guard!", Color.CYAN)
			sfx_player.play_perfect_guard()
			GameManager.apply_hitstop(0.15, 0.1)

			# 무적 시간 부여 및 투사체 제거
			start_invuln(0.2)
			p.queue_free()

		# 2. 일반 가드 (타이밍은 놓쳤지만 가드 중일 때)
		else:
			var p_vel = p.velocity
			p.queue_free()
			apply_damage(10, p_vel.normalized() * 100.0, false, 0.2, true)
			
func apply_damage(amount: int, knockback: Vector2 = Vector2.ZERO, ignore_cd: bool = false, or_invuln_time: float = -1.0, is_projectile: bool = false) -> bool:
	if is_guarding and amount > 0 and not is_invulnerable() and is_projectile:
		var can_guard = false
		if knockback.x != 0:
			if (knockback.x * attack_pivot.scale.x) < 0:
				can_guard = true
				
		if can_guard:
			if guard_timer <= PERFECT_GUARD_WINDOW:
				show_popup("Perfect Guard!", Color.CYAN)
				GameManager.apply_hitstop(0.15, 0.1)
				sfx_player.play_perfect_guard()
				
				var stage = get_tree().current_scene
				if stage and stage.has_method("apply_camera_shake"):
					stage.apply_camera_shake(3.0)
				
				has_perfect_guard_bonus = true
				start_invuln(0.2)
				return false
			else:
				amount = 5
				show_popup("Guard", Color.GRAY)
				sfx_player.play_guard()

	if is_guarding and amount <= 5:
		return false

	var took_damage = super.apply_damage(amount, knockback, ignore_cd, or_invuln_time, is_projectile)
	
	if took_damage:
		sfx_player.play_hurt()
		GameManager.update_hp(hp)
		HUD.show_hud_temporarily()
		GameManager.apply_hitstop(0.25, 0.2)
		
		if current_state == State.ATTACK or current_state == State.GUARD:
			change_state(State.IDLE if is_on_floor() else State.FALL)
	
	return took_damage

func _on_death() -> void:
	change_state(State.DEAD)

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
	# 보너스 효과 쉐이더 연동 (빛나는 오라)
	if sprite and sprite.material is ShaderMaterial:
		sprite.material.set_shader_parameter("glow_active", has_perfect_guard_bonus)
		sprite.material.set_shader_parameter("glow_intensity", 2.0 if has_perfect_guard_bonus else 0.0)

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
	if _cooldown_left > 0.0: _cooldown_left -= delta
	if guard_cooldown_timer > 0.0: guard_cooldown_timer -= delta
	if _menu_exit_cooldown > 0.0: _menu_exit_cooldown -= delta
	_coyote_timer -= delta
	_jump_buffer_timer -= delta
	
	if is_on_floor():
		_coyote_timer = coyote_time
		if current_state == State.FALL or current_state == State.JUMP:
			if current_state != State.ATTACK and current_state != State.GUARD:
				change_state(State.IDLE)
				
	if not is_on_floor() and current_state != State.ATTACK and current_state != State.GUARD:
		if velocity.y > 0:
			change_state(State.FALL)
		else:
			if current_state != State.JUMP: # 점프 중이 아닐 때만 전환
				change_state(State.JUMP)

	# 글로벌 입력 처리 (어느 상태에서든 입력 받으면 플라스크/상호작용 가능)
	if Input.is_action_just_pressed("use_flask"):
		GameManager.use_flask()

	match current_state:
		State.IDLE, State.RUN, State.JUMP, State.FALL:
			_handle_corner_correction() # 천장 보정 적용
			_process_movement(delta)
		State.ATTACK:
			_handle_corner_correction()
			_process_attack(delta)
		State.GUARD:
			_process_guard(delta)
		State.DEAD:
			pass

	# 착지 이펙트 로직
	if is_on_floor() and not _was_on_floor:
		# 낙하 속도에 비례한 강도 계산 (최소 0.5 ~ 최대 2.0)
		var impact_intensity = 1.0
		if max_fall_speed > 0:
			impact_intensity = remap(abs(velocity.y), 0, max_fall_speed, 0.5, 2.0)
		
		impact_intensity = clamp(impact_intensity, 0.5, 2.0)
		
		spawn_dust(Vector2(0, 0), impact_intensity)
		apply_squash(1.0 + (0.3 * impact_intensity), 1.0 - (0.3 * impact_intensity)) # 원래 값으로 복구
		
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
	if Input.is_action_just_pressed("attack") and _cooldown_left <= 0.0 and _menu_exit_cooldown <= 0.0:
		change_state(State.ATTACK)
		return
		
	if Input.is_action_just_pressed("guard") and is_on_floor() and guard_cooldown_timer <= 0.0:
		change_state(State.GUARD)
		return

	# 점프 선입력
	if Input.is_action_just_pressed("jump") and _menu_exit_cooldown <= 0.0:
		_jump_buffer_timer = jump_buffer_time

	# 점프 실행
	if _jump_buffer_timer > 0.0 and _coyote_timer > 0.0:
		velocity.y = jumpforce
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0
		sfx_player.play_jump()
		spawn_dust(Vector2(0, 0))
		apply_squash(0.8, 1.2) # 점프 시 길쭉하게
		change_state(State.JUMP)

	# 방향 전환
	if dir_input != 0:
		sprite.flip_h = dir_input < 0
		attack_pivot.scale.x = 1 if dir_input > 0 else -1

	# 가감속 물리 이동
	var target_speed = dir_input * movespeed
	if is_on_floor():
		if dir_input != 0:
			velocity.x = move_toward(velocity.x, target_speed, acceleration * delta)
		else:
			velocity.x = move_toward(velocity.x, 0, friction * delta)
	else:
		velocity.x = target_speed

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
	if _jump_buffer_timer > 0.0 and _coyote_timer > 0.0:
		velocity.y = jumpforce
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0
		sfx_player.play_jump() # 사운드 누락 추가
		spawn_dust(Vector2(0, 0))
		apply_squash(0.8, 1.2)
		change_state(State.JUMP)
		
	# 공격 중에도 이동 및 방향 전환 허용 (조작감 향상)
	var target_speed = dir_input * movespeed
	if is_on_floor():
		if dir_input != 0:
			velocity.x = move_toward(velocity.x, target_speed, acceleration * delta)
		else:
			velocity.x = move_toward(velocity.x, 0, friction * delta)
	else:
		velocity.x = target_speed

	if dir_input != 0:
		sprite.flip_h = dir_input < 0
		attack_pivot.scale.x = 1 if dir_input > 0 else -1

	move_with_knockback(delta)

func _process_guard(delta: float) -> void:
	apply_gravity(delta)
	velocity.x = 0 # 가드 중 이동 불가
	
	guard_timer += delta # 퍼펙트 가드 판정을 위해 시간 측정은 계속 함
	
	# (GUARD_DURATION에 의한 강제 상태 전환 제거됨. 애니메이션 종료 신호에 맡김)
		
	move_with_knockback(delta)

# 먼지 파티클 소환 함수
func spawn_dust(offset: Vector2 = Vector2.ZERO, scale_mult: float = 1.0) -> void:
	if dust_particles_scene:
		var dust = dust_particles_scene.instantiate()
		var target_parent = get_parent()
		if target_parent == null:
			target_parent = get_tree().current_scene
			
		if target_parent:
			target_parent.add_child(dust)
			dust.global_position = global_position + offset
			dust.scale *= scale_mult # 강도에 따라 크기 조절
			dust.emitting = true
			# 수명이 다하면 자동으로 삭제되도록 타이머 연결
			await get_tree().create_timer(dust.lifetime).timeout
			dust.queue_free()
	
# 시각적 찰진 효과 (Squash and Stretch)
func apply_squash(x: float, y: float) -> void:
	if _squash_tween:
		_squash_tween.kill()
	
	_squash_tween = create_tween()
	# 원래 스케일에 비례해서 squash 적용
	sprite.scale = Vector2(_base_sprite_scale.x * x, _base_sprite_scale.y * y)
	# 복구할 때도 원래 스케일(_base_sprite_scale)로 복구
	_squash_tween.tween_property(sprite, "scale", _base_sprite_scale, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

#모서리 보정 
func _handle_corner_correction() -> void:
	if velocity.y >= 0: return # 상승 중일 때만 작동
	
	# 캐릭터 위쪽 판정을 위해 약간 위쪽 위치에서 테스트
	var step := 2.0
	var check_dist := 4.0 # 보정해줄 최대 픽셀 거리 (보통 4~8픽셀)
	
	# 머리 바로 위가 막혀있는지 확인
	if test_move(global_transform, Vector2(0, -step)):
		# 왼쪽으로 살짝 옮기면 비어있는지 확인
		for i in range(1, int(check_dist) + 1):
			if not test_move(global_transform.translated(Vector2(-i, -step)), Vector2(0, 0)):
				global_position.x -= 1.2 # 살짝 밀어줌
				return
		
		# 오른쪽으로 살짝 옮기면 비어있는지 확인
		for i in range(1, int(check_dist) + 1):
			if not test_move(global_transform.translated(Vector2(i, -step)), Vector2(0, 0)):
				global_position.x += 1.2 # 살짝 밀어줌
				return

func get_knockback_cooldown() -> float:
	return 0.7  # 0.7초 뒤에는 바로 움직일 수 있음!
	
# 애니메이션 관리 전용 함수
func _update_animation(dir_input: float) -> void:
	match current_state:
		State.ATTACK:
			pass # Attack 애니메이션은 change_state에서 play() 됨
		State.GUARD:
			pass # Guard 애니메이션은 change_state에서 play() 됨
		State.DEAD:
			pass # Dead 애니메이션은 change_state에서 play() 됨
		State.JUMP, State.FALL:
			pass # 진입(change_state) 시 1회만 실행됨
		State.RUN:
			if dir_input != 0 and anim_player.current_animation != "Run": 
				anim_player.play("Run")
		State.IDLE:
			if anim_player.current_animation != "Stand":
				anim_player.play("Stand")
		
func show_status(action_type: String) -> void:
	var msg: String = ""
	var color: Color = Color.WHITE
	
	# 상황별로 텍스트와 색상을 여기서 결정합니다 (case 문과 같음)
	match action_type:
		"save":
			msg = "Saved!"
			color = Color(0.347, 0.824, 0.885, 1.0) # 연두색
		"heal":
			msg = "Healed!"
			color = Color(1.0, 0.3, 0.3) # 빨간색
		"mana":
			msg = "Mana Up!"
			color = Color(0.3, 0.3, 1.0) # 파란색
		"key":
			msg = "Key Found"
			color = Color(0.8, 0.8, 0.8) # 은색
		"rest":
			msg = "Rested"
			color = Color(0.429, 0.793, 0.33, 1.0)
		"full":
			msg = "Inventory Full"
			color = Color.ORANGE
		_: # default (그 외 나머지)
			msg = "!"
			color = Color.WHITE
	
	# 결정된 내용으로 원래 있던 팝업 함수 실행
	show_popup(msg, color)
		
func _on_magnet_area_area_entered(area):
	# 닿은 녀석(area)이 'attract_to'라는 함수를 가지고 있나?
	if area.has_method("attract_to"):
		# "나(self)한테 빨려와라!" 명령
		area.attract_to(self)

func _on_animation_finished(anim_name: String) -> void:
	if anim_name == "Attack":
		if current_state == State.ATTACK:
			change_state(State.IDLE if is_on_floor() else State.FALL)
	elif anim_name == "guard":
		if current_state == State.GUARD:
			change_state(State.IDLE)
