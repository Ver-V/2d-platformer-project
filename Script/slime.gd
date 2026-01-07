extends EnemyBase
class_name Slime

@export var gravity: float = 980.0
@export var max_fall_speed: float = 200.0

@export var slime_max_hp: int = 30
@export var slime_contact_damage: int = 10
@export var slime_move_speed: float = 60.0
@export var slime_knockback_res: float = 0.0

@export var turn_on_wall: bool = true
@export var turn_on_ledge: bool = true

@export var floor_ray_x: float = 14.0
@export var floor_ray_y: float = 24.0

@export var jump_impulse: float = -200.0
@export var jump_cooldown: float = 2.5
@export var jump_only_when_player_near: bool = true

@export var jump_chase_speed: float = 90.0
@export var jump_chase_time: float = 0.12

# ### [임시 추가] 슈팅 관련 변수 시작 ###
@export_group("Shooting Test")
@export var projectile_scene: PackedScene # 인스펙터에 Projectile.tscn을 꼭 넣으세요!
@export var shoot_interval: float = 0.5   # 발사 간격
@export var shoot_range: float = 1000.0    # 사거리

var _shoot_timer: float = 0.0
var _next_shot_parryable: bool = true     # 번갈아 쏘기 위한 플래그
# ### [임시 추가] 슈팅 관련 변수 끝 ###

var dir: int = -1
var _jump_left: float = 0.0
var _air_chase_left: float = 0.0

func _ready() -> void:
	max_hp_base = slime_max_hp
	contact_damage_base = slime_contact_damage
	move_speed_base = slime_move_speed
	knockback_resist = slime_knockback_res
	super._ready()
	
func _process(delta: float) -> void:
	super._process(delta)
	
	# [추가] 타겟이 없으면, 게임 내의 플레이어를 강제로 찾아서 등록해라!
	if target == null:
		var players = get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			target = players[0]

	if _jump_left > 0.0:
		_jump_left -= delta
		if _jump_left < 0.0:
			_jump_left = 0.0

	if _air_chase_left > 0.0:
		_air_chase_left -= delta
		if _air_chase_left < 0.0:
			_air_chase_left = 0.0
			
	# ### [수정됨] 슈팅 타이머 로직 ###
	if target != null:
		# 1. 거리를 먼저 잽니다.
		var dist = global_position.distance_to(target.global_position)
		
		# 2. 사거리 안에 있을 때만!
		if dist <= shoot_range:
			_shoot_timer -= delta
			
			if _shoot_timer <= 0.0:
				_try_shoot_projectile()
				_shoot_timer = shoot_interval # 쏘고 나서 쿨타임 적용
		
		else:
			# 3. [핵심] 사거리 밖이라면? -> 쿨타임을 0으로 만들어둠 (장전 완료 상태)
			# 이렇게 해야 사거리에 들어오는 순간 조건(<=0.0)이 맞아 떨어져서 바로 쏩니다.
			# (약간의 딜레이를 주고 싶다면 0.5 정도로 설정해도 됨)
			_shoot_timer = 0.0
	# ### 슈팅 타이머 로직 끝 ###

func _physics_process(delta: float) -> void:
	if floor_ray != null:
		floor_ray.target_position = Vector2(floor_ray_x * float(dir), floor_ray_y)

	velocity.y += gravity * delta
	if velocity.y > max_fall_speed:
		velocity.y = max_fall_speed

	if is_on_floor():
		velocity.x = float(dir) * move_speed
	else:
		if _air_chase_left > 0.0 and target != null:
			var dx: float = target.global_position.x - global_position.x
			var sgn: float = 1.0 if dx >= 0.0 else -1.0
			velocity.x = sgn * jump_chase_speed
		else:
			velocity.x = float(dir) * move_speed

	if turn_on_ledge and is_on_floor() and floor_ray != null:
		floor_ray.force_raycast_update()
		if not floor_ray.is_colliding():
			dir = -dir

	if is_on_floor() and _jump_left <= 0.0:
		var can_jump: bool = (not jump_only_when_player_near) or (target != null)
		if can_jump:
			if turn_on_ledge and floor_ray != null:
				floor_ray.target_position = Vector2(floor_ray_x * float(dir), floor_ray_y)
				floor_ray.force_raycast_update()
				if not floor_ray.is_colliding():
					return	
			if target != null:
				var dx2: float = target.global_position.x - global_position.x
				dir = 1 if dx2 >= 0.0 else -1

			velocity.y = jump_impulse
			_air_chase_left = jump_chase_time
			_jump_left = jump_cooldown

	super._physics_process(delta)
	
	if turn_on_wall and is_on_wall():
		dir = -dir
		velocity.x = 0.0

# ### [임시 추가] 발사 함수 전체 시작 ###
func _try_shoot_projectile() -> void:
	# [디버그 1] 함수가 호출은 되는지 확인
	# print("발사 시도 중...") 
	
	if projectile_scene == null:
		return
		
	if target == null:
		# print("타겟(플레이어)이 없음")
		return

	var p = projectile_scene.instantiate()
	p.shooter = self
	# [수정 1] 총알 생성 위치: 슬라임 발바닥이 아니라 '몸통/입' 높이로 올리기
	# Vector2(0, -10) -> 위로 10픽셀 (슬라임 크기에 맞춰 조절하세요)
	var spawn_pos = global_position + Vector2(0, -4) 
	p.global_position = spawn_pos
	
	# [수정 2] 목표 지점: 플레이어 발바닥이 아니라 '가슴/몸통' 높이로 잡기
	# Vector2(0, -12) -> 플레이어 키의 절반 정도 높이만큼 위로
	var target_center = target.global_position + Vector2(0, -10)
	
	# 방향 계산: (보정된 목표 - 보정된 시작점)
	var shot_dir = (target_center - spawn_pos).normalized()
	p.direction = shot_dir
	
	p.is_parryable = _next_shot_parryable
	# 색상 변경
	if _next_shot_parryable:
		p.modulate = Color(1, 0.6, 1)
	else:
		p.modulate = Color(1, 0.2, 0.2)
	
	get_tree().current_scene.add_child(p)
	_next_shot_parryable = not _next_shot_parryable
# ### [임시 추가] 발사 함수 전체 끝 ###
