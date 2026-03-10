# EnemyRanged.gd
extends EnemyBase
class_name EnemyRanged

# [설정] 사거리와 쿨타임만 남김 (총알 관련 설정은 Component로 이사감)
@export_group("Ranged Behavior")
@export var shoot_interval: float = 2.0
@export var shoot_range: float = 250.0
@export var shoot_offset: Vector2 = Vector2(0, -10) # 발사 위치 보정
@export var gravity: float = 980.0

# [중요] 씬에서 ShooterComponent 노드를 자식으로 추가하고 연결해야 함!
# 이름을 "ShooterComponent"로 짓거나, 인스펙터에서 할당하세요.
@export var shooter_component: ShooterComponent

var _shoot_timer: float = 0.0
var _can_see_target: bool = true

@onready var los: RayCast2D = get_node_or_null("LineOfSight")
@onready var muzzle: Marker2D = get_node_or_null("Muzzle")

func _ready() -> void:
	super._ready()
	# 만약 인스펙터 연결 까먹었을까봐 코드로도 찾아줌
	if shooter_component == null:
		shooter_component = get_node_or_null("ShooterComponent")

func _physics_process(delta: float) -> void:
	if not _active: return
	
	# 공중에 있을 경우 중력 적용
	if not is_on_floor():
		velocity.y += gravity * delta
		
	if is_instance_valid(target) and los:
		if global_position.distance_to(target.global_position) <= shoot_range:
			los.target_position = los.to_local(target.global_position + Vector2(0, -10))
			los.force_raycast_update()
			_can_see_target = true
			if los.is_colliding():
				var collider = los.get_collider()
				if collider != target and not collider.is_in_group("player"):
					_can_see_target = false

	super._physics_process(delta)

func _process(delta: float) -> void:
	super._process(delta)
	
	if not _active: return
	
	if not is_instance_valid(target):
		target = null
		if shooter_component:
			shooter_component.reset_count()
		return

	# --- 거리 재고 쿨타임 돌리기 ---
	var dist = global_position.distance_to(target.global_position)
	
	if dist <= shoot_range:
		var can_see = _can_see_target if los else true
					
		if can_see:
			_shoot_timer -= delta
			if _shoot_timer <= 0.0:
				shoot_projectile() # 발사!
				_shoot_timer = shoot_interval
		else:
			_shoot_timer = 0.5 # 벽에 가려지면 장전 상태 유지
	else:
		_shoot_timer = 0.5 # 사거리 밖이면 장전 상태

# [다이어트 된 발사 함수]
func shoot_projectile() -> void:
	if shooter_component == null:
		print("경고: ShooterComponent가 없습니다!")
		return
		
	# Muzzle 마커가 있으면 그 위치를 사용, 없으면 offset 사용
	var spawn_pos = global_position + shoot_offset
	if muzzle:
		spawn_pos = muzzle.global_position
		
	# "야, 내 위치(보정값 포함)에서 쟤 맞춰서 쏴." (한 줄로 끝)
	shooter_component.shoot(self, target, spawn_pos)
