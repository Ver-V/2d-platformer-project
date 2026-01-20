# EnemyRanged.gd
extends EnemyBase
class_name EnemyRanged

# [설정] 사거리와 쿨타임만 남김 (총알 관련 설정은 Component로 이사감)
@export_group("Ranged Behavior")
@export var shoot_interval: float = 2.0
@export var shoot_range: float = 250.0
@export var shoot_offset: Vector2 = Vector2(0, -10) # 발사 위치 보정

# [중요] 씬에서 ShooterComponent 노드를 자식으로 추가하고 연결해야 함!
# 이름을 "ShooterComponent"로 짓거나, 인스펙터에서 할당하세요.
@export var shooter_component: ShooterComponent

var _shoot_timer: float = 0.0

func _ready() -> void:
	super._ready()
	# 만약 인스펙터 연결 까먹었을까봐 코드로도 찾아줌
	if shooter_component == null:
		shooter_component = get_node_or_null("ShooterComponent")

func _process(delta: float) -> void:
	super._process(delta)
	
	if not _active: return
	
	if target == null:
		if shooter_component:
			shooter_component.reset_count()
		var players = get_tree().get_nodes_in_group("player")
		if players.size() > 0: target = players[0]
		return

	# --- 거리 재고 쿨타임 돌리기 ---
	var dist = global_position.distance_to(target.global_position)
	
	if dist <= shoot_range:
		_shoot_timer -= delta
		if _shoot_timer <= 0.0:
			shoot_projectile() # 발사!
			_shoot_timer = shoot_interval
	else:
		_shoot_timer = 0.5 # 사거리 밖이면 장전 상태

# [다이어트 된 발사 함수]
func shoot_projectile() -> void:
	if shooter_component == null:
		print("경고: ShooterComponent가 없습니다!")
		return
		
	# "야, 내 위치(보정값 포함)에서 쟤 맞춰서 쏴." (한 줄로 끝)
	shooter_component.shoot(self, target, global_position + shoot_offset)
