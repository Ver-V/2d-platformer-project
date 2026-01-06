extends Area2D
class_name Projectile

@export_group("Stats")
@export var speed: float = 300.0
@export var damage: int = 1
@export var life_time: float = 10.0

@export_group("Parry")
@export var is_parryable: bool = false         # 이 옵션을 켜면 패링 가능
@export var parried_speed_mult: float = 1.5    # 반사되면 속도 1.5배
@export var parried_color: Color = Color(0.925, 0.473, 0.857, 1.0) # 반사시 색상 변경

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
	
	# 벽이나 바닥에 닿으면 사라짐 (Body Entered)
	body_entered.connect(_on_body_entered)
	
	# Area(플레이어 히트박스 등)와의 충돌은 Player나 Enemy쪽에서 처리하거나
	# 여기서 area_entered로 처리할 수도 있지만, 보통 투사체는 '몸'에 닿는 걸 체크함.

func _physics_process(delta: float) -> void:
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
func attempt_parry(source_pos: Vector2) -> bool:
	# 1. 패링 불가능한 경우:
	if not is_parryable:
		# 아무것도 하지 않고 false 반환.
		# queue_free()도 없고, 데미지 로직도 없으니
		# 플레이어의 칼(Area)과 이 탄환(Area)은 서로 그냥 겹치고 지나감.
		return false
	
	# 2. 패링 성공 로직:
	team = "player"
	
	# 방향 반사
	var new_dir = (global_position - source_pos).normalized()
	velocity = new_dir * speed * parried_speed_mult
	rotation = new_dir.angle() # 회전도 맞춰주면 좋음
	
	# 비주얼 변경
	modulate = parried_color
	scale *= 1.0
	
	# [중요] 레이어 변경! 
	# 이제 이 탄환은 '플레이어 투사체'가 되어 적을 때릴 수 있게 됨.
	# Enemy Projectile(7) -> Player Projectile(6)
	collision_layer = 1 << 5 # 비트 연산: 6번 레이어 (1 << 5는 2^5 = 32)
	
	# 마스크 변경 (이제 적을 맞춰야 함)
	# World(1) + Enemy(3) + Boss(4)
	collision_mask = (1 << 0) | (1 << 2) | (1 << 3)
	
	return true
	

func _on_visible_on_screen_notifier_2d_screen_exited() -> void:
	queue_free()
