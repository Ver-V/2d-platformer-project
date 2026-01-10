extends Area2D
class_name Projectile

@export_group("Stats")
@export var speed: float = 100.0
@export var damage: int = 1
@export var life_time: float = 10.0
var shooter: Node2D = null # [추가] 나를 쏜 놈을 기억하는 변수
var _reflected: bool = false
@export_group("Parry")
@export var is_parryable: bool = false         # 이 옵션을 켜면 패링 가능
@export var parried_speed_mult: float = 1.5    # 반사되면 속도 1.5배
@export var parried_color: Color = Color(0.464, 0.727, 0.67, 1.0) # 반사시 색상 변경

@onready var anim_sprite: AnimatedSprite2D = $AnimatedSprite2D

@export_group("Homing Settings")
@export var start_homing: bool = false     # 적이 쏠 때부터 유도탄인가?
@export var enemy_homing_speed: float = 2.0 # 적 유도탄의 회전 속도 (너무 빠르면 피하기 힘듦)
var _is_homing: bool = false   # 현재 유도 모드인가?
var _homing_target: Node2D = null # 누구를 쫓을 것인가?
@export var homing_turn_speed: float = 10.0 # 유도 회전 속도 (클수록 급커브 가능)

var direction: Vector2 = Vector2.RIGHT
var velocity: Vector2 = Vector2.ZERO
var _current_life: float = 0.0

# 투사체의 소유자 (초기엔 'enemy'라고 가정)
# "enemy"면 플레이어를 때리고, "player"면 적을 때림
var team: String = "enemy" 

func _ready() -> void:
	# 수명이 다하면 사라지도록 타이머 연결 혹은 직접 계산
	_current_life = life_time
	
	# 초기 속도 설정
	velocity = direction.normalized() * speed
	
	if anim_sprite:
		anim_sprite.play("default")
	
	# 벽이나 바닥에 닿으면 사라짐 (Body Entered)
	body_entered.connect(_on_body_entered)
	
	if start_homing and team == "enemy":
		_is_homing = true
		homing_turn_speed = enemy_homing_speed # 적 전용 회전 속도 적용
		
		# "player" 그룹에 있는 노드(플레이어)를 찾아서 타겟으로 설정
		var players = get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			_homing_target = players[0]
	
	# Area(플레이어 히트박스 등)와의 충돌은 Player나 Enemy쪽에서 처리하거나
	# 여기서 area_entered로 처리할 수도 있지만, 보통 투사체는 '몸'에 닿는 걸 체크함.

func _physics_process(delta: float) -> void:
	if _is_homing:
		if is_instance_valid(_homing_target):
			# 1. 목표 지점 계산 (상대방의 가슴/명치 노리기)
			var target_pos = _homing_target.global_position + Vector2(0, -10)
			
			# 2. 목표 방향 벡터
			var desired_dir = (target_pos - global_position).normalized()
			
			# 3. 현재 이동 방향(velocity)을 목표 방향으로 서서히 회전 (Slerp)
			# direction 변수를 갱신
			direction = direction.slerp(desired_dir, homing_turn_speed * delta).normalized()
			
			# 4. 실제 속도(velocity)에 적용
			velocity = direction * speed
		else:
			# 타겟이 죽거나 사라지면 유도 중단 (그냥 직진)
			_is_homing = false
	
	# 이동
	global_position += velocity * delta
	
	# 회전 (선택사항: 진행 방향을 바라보게)
	if velocity != Vector2.ZERO:
		rotation = velocity.angle()

	# 수명 체크
	_current_life -= delta
	if _current_life <= 0.0:
		queue_free()

func _on_body_entered(body: Node) -> void:
	# 1. 벽/지형에 닿았을 때 (TileMapLayer 등)
	if body is TileMapLayer or body is TileMap:
		_destroy_projectile()
		return

	# 2. CombatBody2D(플레이어 또는 적)에 닿았을 때
	if body is CombatBody2D:
		# 같은 팀이면 통과 (예: 적이 쏜 게 적을 맞추지 않음)
		if _is_same_team(body):
			return
			
		# 데미지 적용
		var knock_dir = velocity.normalized()
		# 넉백값은 투사체 설정에 따라 조절 가능. 일단 하드코딩 혹은 export 변수 사용
		var applied = body.apply_damage(damage, knock_dir * 150.0)
		
		if applied:
			_destroy_projectile()

func _is_same_team(body: Node) -> bool:
	if team == "enemy" and body.is_in_group("enemies"):
		return true
	if team == "player" and body.is_in_group("player"):
		return true
	return false

func _destroy_projectile() -> void:
	# 여기서 폭발 이펙트 등을 인스턴스화 할 수 있음
	queue_free()

# --- 핵심: 패링 함수 ---
# 플레이어의 칼(Attack Area)이 이 함수를 호출할 것임
# projectile.gd

func attempt_parry(source_pos: Vector2) -> bool:
	if not is_parryable:
		return false
	
	_reflected = true
	
	team = "player"
	
	# 1. 쏜 놈(shooter)이 아직 살아있는지 확인
	if is_instance_valid(shooter):
		_is_homing = true
		_homing_target = shooter
	
	# 일단 튕겨나가는 초기 방향은 플레이어가 바라보는 방향 or 반사각
	# (유도탄이라 초기 방향은 크게 중요하지 않지만, 멋을 위해 반대편으로 설정)
	direction = (global_position - source_pos).normalized()
	damage = ceil(damage * 1.5)
	speed *= 2.0 # 유도탄이니까 속도는 2배만 (너무 빠르면 선회하기 힘듦)
	velocity = direction * speed  # <-- 이거 꼭 있어야 날아갑니다!

	modulate = Color.CYAN

	# [핵심] 신분 세탁 (Layer & Mask 실시간 변경)
	set_collision_layer_value(7, false) 
	set_collision_layer_value(6, true) 
	set_collision_mask_value(2, false)
	set_collision_mask_value(1, false)
	set_collision_mask_value(3, true)
	set_collision_mask_value(4, true)
	
	return true
	

func _on_visible_on_screen_notifier_2d_screen_exited() -> void:
	queue_free()
