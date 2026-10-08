extends Area2D
class_name Hurtbox

# 맞는 판정 영역. 검·투사체·적 접촉은 몸(CollisionShape)이 아니라 이 영역에 닿아야 들어간다.
# 받은 타격은 receiver(기본: 부모)의 receive_hit으로 넘긴다.
# 레이어는 씬에서 정한다: 플레이어 = 9 (player_hurtbox), 적·상자 = 10 (enemy_hurtbox). 감지는 하지 않는다(mask 0).

@export var receiver_path: NodePath # 비우면 부모

var receiver: Node

func _ready() -> void:
	receiver = get_node(receiver_path) if not receiver_path.is_empty() else get_parent()
	monitoring = false # 맞는 쪽은 감지할 필요가 없다 (공격 쪽 Area가 감지)

func receive_hit(hit: HitData) -> HitData.Result:
	return HitData.deliver(receiver, hit)

# 죽음·비활성 때 끄기 (물리 콜백 중에도 안전하도록 deferred)
func set_enabled(enabled: bool) -> void:
	set_deferred("monitorable", enabled)
