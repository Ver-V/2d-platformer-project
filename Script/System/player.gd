extends CombatBody2D
class_name Player

@onready var sprite: AnimatedSprite2D = $PlayerAni
@onready var sword_area: Area2D = $AttackPivot/SwordArea
@onready var sword_shape: CollisionShape2D = $AttackPivot/SwordArea/CollisionShape2D
@onready var attack_pivot: Marker2D = $AttackPivot
@onready var status_label: Label = $StatusLabel
# 기존 서 있는 충돌체 (이름이 다를 수 있으니 확인하세요!)
@onready var collision_stand: CollisionShape2D = $PlayerCol
# [추가] 새로 만든 죽었을 때용 충돌체
@onready var collision_died: CollisionShape2D = $Collisiondied

@export_group("Movement")
@export var movespeed: float = 120.0
@export var jumpforce: float = -350.0
@export var jump_cut_factor: float = 0.35
@export var fall_gravity_mult: float = 1.0
@export var max_fall_speed: float = 280.0

@export_group("Advanced Movement")
@export var acceleration: float = 1400.0   # 바닥 가속도 (높을수록 쫀쫀함)
@export var friction: float = 2000.0       # 바닥 마찰력 (떼면 미끄러지듯 멈춤)

@export_group("Jump Forgiveness")
@export var coyote_time: float = 0.15     # 절벽에서 떨어져도 점프 가능한 시간
@export var jump_buffer_time: float = 0.1 # 바닥에 닿기 전 미리 점프 입력받는 시간

# 내부 타이머
var _coyote_timer: float = 0.0
var _jump_buffer_timer: float = 0.0
var _was_on_floor: bool = false # [추가] 착지 감지용

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
var status_tween: Tween # [추가됨] 팝업 애니메이션 겹침 방지용

signal died
signal death_started

func _ready() -> void:
	add_to_group("player")
	
	# ----------------------------------------------------------------
	# [1] 위치 동기화 (체크포인트)
	# ----------------------------------------------------------------
	var current_scene = get_tree().current_scene
	if current_scene and GameManager.has_checkpoint and GameManager.last_scene_path == current_scene.scene_file_path:
		global_position = GameManager.last_checkpoint_pos
	
	# ----------------------------------------------------------------
	# [2] 스탯 동기화 (무조건 GameManager 값 가져오기)
	# ----------------------------------------------------------------
	hp = GameManager.player_current_hp
	max_hp = GameManager.player_max_hp
	attack_damage = GameManager.player_damage
	player_parry_damage_multifac = GameManager.player_parry_damage_multifac

	# ----------------------------------------------------------------
	# [3] 초기 세팅 (애니메이션, 시그널 등)
	# ----------------------------------------------------------------
	if sprite != null:
		sprite.play("Stand")
		if not sprite.animation_finished.is_connected(_on_animation_finished):
			sprite.animation_finished.connect(_on_animation_finished)
	
	if sword_area != null:
		sword_area.area_entered.connect(_on_sword_area_entered)
		if not sword_area.body_entered.is_connected(_on_sword_body_entered):
			sword_area.body_entered.connect(_on_sword_body_entered)
		sword_shape.disabled = true
	
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
	move_and_slide()

func _on_animation_finished() -> void:
	if sprite.animation == "Attack":
		is_attacking = false

# -------------------------------------------------------
# [수정] 데이터는 GM에게 요청하고, Player는 시각 처리만 함
# -------------------------------------------------------

func update_gold(amount: int) -> void:
	# 이미 GM에 구현된 함수가 있으므로 그대로 사용
	GameManager.add_gold(amount)
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
		
# --- CombatBody2D Overrides ---
func get_invuln_time() -> float: return invuln_time
func get_blink_interval() -> float: return blink_interval
func get_knockback_decay() -> float: return knockback_decay
func get_blink_node() -> CanvasItem: return sprite


func show_popup(text: String, color: Color = Color.YELLOW) -> void:
	if status_label == null: return

	# [추가됨] 이전 트윈이 실행 중이면 취소하여 겹침 방지
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
	
	
func _on_death() -> void:
	death_started.emit()
	collision_stand.set_deferred("disabled", true)
	collision_died.set_deferred("disabled", false)
	velocity.x = 0 
	reset_combat_state()
	set_process_input(false)
	sprite.play("died")
	HUD.show_death_screen()
	
	is_attacking = false
	sword_shape.set_deferred("disabled",true)
	
	await get_tree().create_timer(4.0).timeout
	
	set_physics_process(false)
	died.emit()

func attack() -> void:
	if is_attacking or _cooldown_left > 0.0 : return
	
	_cooldown_left = attack_cooldown
	is_attacking = true
	is_parry_success = false 
	
	sprite.play("Attack")
	
	sword_shape.disabled = false
	await get_tree().create_timer(0.25).timeout
	
	# 데미지를 입어서 캔슬되지 않았을 때만 원상복구
	if is_instance_valid(sword_shape) and is_attacking:
		sword_shape.disabled = true

func _on_sword_area_entered(area: Area2D) -> void:
	if area is Projectile:
		var p: Projectile = area as Projectile

		if p.attempt_parry(global_position):
			is_parry_success = true
			
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
		if is_parry_success:
			return

		if body.has_method("apply_damage"):
			# 넉백 방향 계산 (플레이어 -> 적)
			var knock_dir = (body.global_position - global_position).normalized()
			var knock_force = Vector2(knock_dir.x * 400, -200)
			body.apply_damage(int(attack_damage), knock_force)
			GameManager.apply_hitstop(0.25, 0.1)
			
			var stage = get_tree().current_scene
			if stage and stage.has_method("apply_camera_shake"):
				stage.apply_camera_shake(2.0)
			
		elif body.has_method("take_damage"):
			body.take_damage(attack_damage, global_position)
			GameManager.apply_hitstop(0.25, 0.1)
			
			var stage = get_tree().current_scene
			if stage and stage.has_method("apply_camera_shake"):
				stage.apply_camera_shake(2.0)
			
func apply_damage(amount: int, knockback: Vector2 = Vector2.ZERO, ignore_cd: bool = false, or_invuln_time: float = -1.0) -> bool:
	# [체크 1] super(부모)를 호출해서 실제 체력을 깎고 결과를 받아야 함!
	var took_damage = super.apply_damage(amount, knockback, ignore_cd, or_invuln_time)
	
	# [체크 2] 데미지를 입었을 때만 상태를 초기화
	if took_damage:
		GameManager.update_hp(hp)
		HUD.show_hud_temporarily()
		is_attacking = false
		sword_shape.set_deferred("disabled", true)
		GameManager.apply_hitstop(0.25, 0.2)
		
		# [수정 1] 죽었을 때 확인
		if hp <= 0:
			velocity.x = 0 # 좌우 이동만 멈춤 (떨어지는 건 유지!)
	
	return took_damage
	
func _physics_process(delta: float) -> void:
	if get_tree().paused:
		return
		
	if GameManager.is_menu_open:
		velocity.x = 0
		if not is_on_floor():
			var g := get_gravity()
			var mult := 1.0
			if velocity.y > 0.0: mult = fall_gravity_mult
			velocity += g * mult * delta
			if velocity.y > max_fall_speed:
				velocity.y = max_fall_speed
		move_and_slide()
		_update_animation(0)
		return
		
	if hp <= 0:
		# 공중에 떠 있다면? -> 중력 적용!
		if not is_on_floor():
			velocity += get_gravity() * delta
		else:
			# 바닥에 닿았다면 -> 미끄러짐 방지
			velocity.x = 0
			
		move_and_slide() # [중요] 이게 있어야 실제로 떨어집니다!
		return # 살았을 때 로직은 실행하지 않고 종료
	# 쿨타임 감소
	if _cooldown_left > 0.0:
		_cooldown_left -= delta
	
	# [조작감 개선] 1. 타이머 감소
	_coyote_timer -= delta
	_jump_buffer_timer -= delta
	
	if is_on_floor():
		_coyote_timer = coyote_time

	# 2. 중력
	var g := get_gravity()
	if not is_on_floor():
		var mult := 1.0
		if velocity.y > 0.0: mult = fall_gravity_mult
		velocity += g * mult * delta
		if Input.is_action_just_released("jump") and velocity.y < 0.0:
			velocity.y *= jump_cut_factor
		if velocity.y > max_fall_speed:
			velocity.y = max_fall_speed

	# 3. 이동 입력값 계산
	var dir_input := Input.get_axis("left", "right")

	# 4. 공격 캔슬 로직
	if is_attacking:
		var facing_dir = attack_pivot.scale.x 
		if dir_input != 0 and dir_input != facing_dir:
			is_attacking = false
			sword_shape.disabled = true

	# 5. 공격 시작 입력
	if Input.is_action_just_pressed("attack"):
		attack()
	
	if Input.is_action_just_pressed("use_flask"):
		if GameManager.use_flask():
			pass
		
	# 6. 방향 전환
	if not is_attacking and dir_input != 0:
		if dir_input > 0:
			sprite.flip_h = false
			attack_pivot.scale.x = 1
		else:
			sprite.flip_h = true
			attack_pivot.scale.x = -1
	
	# [조작감 개선] 7. 가감속을 적용한 이동 처리
	var target_speed = dir_input * movespeed
	if is_on_floor():
		if dir_input != 0:
			velocity.x = move_toward(velocity.x, target_speed, acceleration * delta)
		else:
			velocity.x = move_toward(velocity.x, 0, friction * delta)
	else:
		velocity.x = target_speed
	
	# [조작감 개선] 8. 점프 (선입력 & 코요테 타임 적용)
	if Input.is_action_just_pressed("jump"):
		_jump_buffer_timer = jump_buffer_time

	if _jump_buffer_timer > 0.0 and _coyote_timer > 0.0:
		velocity.y = jumpforce
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0
		spawn_dust(Vector2(0, 0)) # 점프 시 발밑에 먼지 생성

	# [추가] 착지 순간 감지
	if is_on_floor() and not _was_on_floor:
		spawn_dust(Vector2(0, 0)) # 착지 시 발밑에 먼지 생성
	
	_was_on_floor = is_on_floor() # 상태 업데이트
	
	move_with_knockback(delta)
	
	_update_animation(dir_input)

# [추가] 먼지 파티클 소환 함수
func spawn_dust(offset: Vector2 = Vector2.ZERO) -> void:
	if dust_particles_scene:
		var dust = dust_particles_scene.instantiate()
		get_parent().add_child(dust)
		dust.global_position = global_position + offset
		dust.emitting = true
		# 수명이 다하면 자동으로 삭제되도록 타이머 연결
		await get_tree().create_timer(dust.lifetime).timeout
		dust.queue_free()
	
func get_knockback_cooldown() -> float:
	return 0.7  # 0.7초 뒤에는 바로 움직일 수 있음!
	
# 애니메이션 관리 전용 함수
func _update_animation(dir_input: float) -> void:
	# 공격 중이면 다른 애니메이션이 덮어쓰지 못하게 리턴
	if is_attacking:
		return
		
	# 공중에 있을 때 (점프/낙하)
	if not is_on_floor():
		# 점프 애니메이션이 있다면 사용 (없으면 그냥 둠)
		if sprite.sprite_frames.has_animation("Jump"):
			sprite.play("Jump")
		return

	# 바닥에 있을 때
	if dir_input != 0:
		sprite.play("Run")  # 혹은 "Walk"
	else:
		sprite.play("Stand") # 혹은 "Idle"
		
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
	# 닿은 녀석(area)이 'attract_to'라는 함수를 가지고 있나? (즉, 코인인가?)
	if area.has_method("attract_to"):
		# "나(self)한테 빨려와라!" 명령
		area.attract_to(self)
