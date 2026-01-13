extends CombatBody2D
class_name Player

@onready var sprite: AnimatedSprite2D = $PlayerAni
@onready var sword_area: Area2D = $AttackPivot/SwordArea
@onready var sword_shape: CollisionShape2D = $AttackPivot/SwordArea/CollisionShape2D
@onready var attack_pivot: Marker2D = $AttackPivot
@onready var status_label: Label = $StatusLabel

@export_group("Movement")
@export var movespeed: float = 120.0
@export var jumpforce: float = -350.0
@export var jump_cut_factor: float = 0.35
@export var fall_gravity_mult: float = 1.0
@export var max_fall_speed: float = 280.0

@export_group("Combat")
@export var invuln_time: float = 0.8
@export var blink_interval: float = 0.05
@export var knockback_decay: float = 1800.0
@export var is_attacking: bool = false 
@export var attack_cooldown: float = 0.8
var _cooldown_left: float = 0.0

signal died

func _ready() -> void:
	# super._ready() 제거됨 (필요 없음)
	add_to_group("player")
	
	# [핵심] 게임 시작 시 체크포인트 확인
	# "혹시 저장이 되어있고(has_checkpoint), 지금 이 씬이 저장된 그 씬(last_scene_path)인가?"
	if GameManager.has_checkpoint and GameManager.last_scene_path == get_tree().current_scene.scene_file_path:
		global_position = GameManager.last_checkpoint_pos
		
		# [추가] 로드된 체력 정보 적용 (이게 없으면 HP가 1인 상태로 시작할 수 있음)
		hp = GameManager.player_current_hp
		max_hp = GameManager.player_max_hp
		
		print("체크포인트 위치로 이동했습니다. HP: ", hp)
		
	else:
		max_hp = 100
		hp = 100
		# 새 게임 시작 시 GameManager 정보도 갱신
		GameManager.player_current_hp = hp
		GameManager.player_max_hp = max_hp
		GameManager.update_hp(hp)
		
	if sprite != null:
		sprite.play("Stand") # 시작 시 기본 자세
		if not sprite.animation_finished.is_connected(_on_animation_finished):
			sprite.animation_finished.connect(_on_animation_finished)
	
	if sword_area != null:
		sword_area.area_entered.connect(_on_sword_area_entered)
		sword_shape.disabled = true 
	
	GameManager.update_hp(hp)
	
	if GameManager.pending_status != "":
		await get_tree().create_timer(0.2).timeout 
		show_status(GameManager.pending_status)
		GameManager.pending_status = ""
		
	velocity = Vector2.ZERO 
	floor_snap_length = 20.0 
	apply_floor_snap() # block spawn jump
	move_and_slide()
		
# [추가] 애니메이션이 끝났을 때 호출되는 함수
func _on_animation_finished() -> void:
	# 공격 모션이 끝까지 재생됐다면 공격 상태 해제
	if sprite.animation == "Attack":
		is_attacking = false
		
		
# --- CombatBody2D Overrides ---
func get_invuln_time() -> float: return invuln_time
func get_blink_interval() -> float: return blink_interval
func get_knockback_decay() -> float: return knockback_decay
func get_blink_node() -> CanvasItem: return sprite


func show_popup(text: String, color: Color = Color.YELLOW) -> void:
	if status_label == null: return
	
	# 1. 텍스트랑 색상 설정
	status_label.text = text
	status_label.modulate = color # 글자 색상 (기본 노랑)
	status_label.visible = true
	
	# 2. 위치 초기화 (머리 위로)
	# 원래 위치(Label이 에디터에 있는 위치)를 기준으로 잡거나 상수로 지정
	status_label.position.y = -45.0 # 머리 위 시작 위치
	status_label.modulate.a = 1.0   # 투명도 100% (완전 불투명)
	
	# 3. 애니메이션 (Tween) - 위로 뜨면서 투명해짐
	var tween = create_tween()
	tween.set_parallel(true) # 동시에 실행
	
	# 0.8초 동안 Y축으로 -30만큼 더 올라감 (둥둥~)
	tween.tween_property(status_label, "position:y", -75.0, 1.0).set_trans(Tween.TRANS_SINE)
	# 0.8초 동안 투명해짐
	tween.tween_property(status_label, "modulate:a", 0.0, 1.5).set_ease(Tween.EASE_IN)
	
	# 애니메이션 끝나면 다시 숨김
	tween.chain().tween_callback(func(): status_label.visible = false)
	
	
func _on_death() -> void:
	# 1. 일단 멈춤 (이동, 충돌, 입력 방지)
	reset_motion()
	set_physics_process(false)
	set_process_input(false) # 키 입력도 막아야 함
	
	# 2. [중요] 여기서 기다립니다! (아직 살아있을 때)
	await get_tree().create_timer(0.5).timeout
	
	# 3. 다 기다린 뒤에 신호 발송
	# 아까 Stage 스크립트에서 player.died 신호를 받으면 restart_stage() 하게 되어있죠?
	# 그러니까 여기서 emit()만 하면 Stage가 알아서 리스폰 시킵니다.
	died.emit()

func attack() -> void:
	if is_attacking or _cooldown_left > 0.0 : return # 이미 공격 중이면 실행 안 함
	
	_cooldown_left = attack_cooldown
	
	is_attacking = true
	sprite.play("Attack") # 반복(Loop)이 꺼져 있어야 함!
	
	# --- 공격 판정 (히트박스) ---
	sword_shape.disabled = false
	
	# 판정은 0.1초만 유지하고 끄기 (애니메이션보다 짧게)
	# (취향에 따라 이 부분을 없애고 애니메이션 끝날 때 꺼도 됨)
	await get_tree().create_timer(0.25).timeout
	sword_shape.disabled = true

func _on_sword_area_entered(area: Area2D) -> void:
	if area is Projectile:
		var p: Projectile = area as Projectile
		p.attempt_parry(global_position)

func apply_damage(amount: int, knockback: Vector2 = Vector2.ZERO, ignore_cd: bool = false, or_invuln_time: float = -1.0) -> bool:
	# [체크 1] super(부모)를 호출해서 실제 체력을 깎고 결과를 받아야 함!
	var took_damage = super.apply_damage(amount, knockback, ignore_cd, or_invuln_time)
	
	# [체크 2] 데미지를 입었을 때만 상태를 초기화
	if took_damage:
		GameManager.update_hp(hp)
		
		is_attacking = false
		sword_shape.set_deferred("disabled", true)
		
	# [체크 3] 결과를 반드시 return 해야 함! (tile_map이 이걸 보고 성공 여부를 판단함)
	return took_damage
	
func _physics_process(delta: float) -> void:
	# 쿨타임 감소
	if _cooldown_left > 0.0:
		_cooldown_left -= delta
	
	# 1. 중력
	var g := get_gravity()
	if not is_on_floor():
		var mult := 1.0
		if velocity.y > 0.0: mult = fall_gravity_mult
		velocity += g * mult * delta
		if Input.is_action_just_released("jump") and velocity.y < 0.0:
			velocity.y *= jump_cut_factor
		if velocity.y > max_fall_speed:
			velocity.y = max_fall_speed

	# 2. 이동 입력값 먼저 계산 (중요!)
	var dir_input := Input.get_axis("left", "right")

	# 3. [핵심] 공격 캔슬 로직 (방향 불일치 시 캔슬)
	if is_attacking:
		# 현재 바라보는 방향 (1: 오른쪽, -1: 왼쪽)
		var facing_dir = attack_pivot.scale.x 
		
		# 이동 입력이 있는데(0이 아님) && 바라보는 방향과 다를 때 (역방향)
		# 예: 오른쪽(1) 보고 있는데 왼쪽(-1) 키를 누름 -> 조건 성립 -> 캔슬
		if dir_input != 0 and dir_input != facing_dir:
			is_attacking = false
			sword_shape.disabled = true
			# 여기서 캔슬되면 아래 로직에 의해 즉시 방향이 뒤집히고 이동 모션이 나옴

	# 4. 공격 시작 입력
	if Input.is_action_just_pressed("attack"):
		attack()

	# 5. 방향 전환 및 이동 처리
	# 캔슬이 위에서 발생했다면 is_attacking은 false가 되었으므로, 여기서 즉시 방향이 바뀜
	if not is_attacking and dir_input != 0:
		if dir_input > 0:
			sprite.flip_h = false
			attack_pivot.scale.x = 1
		else:
			sprite.flip_h = true
			attack_pivot.scale.x = -1
	
	# [이동 적용]
	# 공격 중이라도 같은 방향이면 velocity가 적용됨 (무빙샷)
	# 캔슬 되었다면 반대 방향 velocity가 적용됨 (즉시 턴)
	velocity.x = dir_input * movespeed
	
	# 6. 점프
	if is_on_floor() and Input.is_action_just_pressed("jump"):
		velocity.y = jumpforce

	# 7. 넉백 및 이동 실행
	var kb: Vector2 = update_knockback(delta)
	velocity += kb
	move_and_slide()
	velocity -= kb
	
	_update_animation(dir_input)
	
func get_knockback_cooldown() -> float:
	return 0.7  # 0.3초 뒤에는 바로 움직일 수 있음!
	
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
