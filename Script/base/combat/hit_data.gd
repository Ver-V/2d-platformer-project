extends RefCounted
class_name HitData

# 타격 한 번의 정보. 공격하는 쪽(검·투사체·접촉·가시)이 만들어 HitData.deliver(대상, hit)로 넘기고,
# 맞는 쪽은 receive_hit(hit) -> Result 하나로 처리한다. 항목이 늘어도 받는 쪽 시그니처는 그대로다.

enum Result {
	IGNORED,        # 처리하지 않음 (피해 0, 이미 죽음, 비활성 방의 적, 맞을 수 없는 대상 등)
	INVULNERABLE,   # 피격 후 무적이라 막힘 — 적 투사체는 여기서 흡수된다
	EVADED,         # 회피 무적(대시 등)으로 피함 — 투사체가 통과한다
	GUARDED,        # 가드로 막음 (깎인 피해는 들어갈 수 있음, 상태이상은 막음)
	PERFECT_GUARD,  # 퍼펙트 가드 (피해 없음)
	HIT,            # 피해가 들어감
	KILLED,         # 이 타격으로 쓰러짐
}

var amount: int = 0
var knockback: Vector2 = Vector2.ZERO
var source: Node = null                      # 때린 쪽 (없을 수 있음)
var is_projectile: bool = false              # 가드는 투사체만 막는다 (의도된 동작)
var ignore_knockback_cooldown: bool = false
var invuln_time: float = -1.0                # 0 이상이면 맞은 쪽 무적시간을 이 값으로 (가시 등)
var status_effects: Array[StatusEffect] = [] # HIT일 때만 건다

func _init(p_amount: int = 0, p_knockback: Vector2 = Vector2.ZERO, p_source: Node = null) -> void:
	amount = p_amount
	knockback = p_knockback
	source = p_source

func duplicate_hit() -> HitData:
	var h := HitData.new(amount, knockback, source)
	h.is_projectile = is_projectile
	h.ignore_knockback_cooldown = ignore_knockback_cooldown
	h.invuln_time = invuln_time
	h.status_effects = status_effects.duplicate()
	return h

# 맞을 수 있는 대상(receive_hit을 가진 노드)에게 전달. 그 외 대상은 IGNORED.
# "맞을 수 있는가"를 확인하는 곳은 여기 하나뿐이다.
static func deliver(target: Node, hit: HitData) -> Result:
	if target == null or not is_instance_valid(target) or not target.has_method("receive_hit"):
		return Result.IGNORED
	return target.receive_hit(hit)

# 피해가 실제로 들어갔는가 (반격 보너스 소모·히트스탑 등)
static func landed(result: Result) -> bool:
	return result == Result.HIT or result == Result.KILLED

# 투사체가 여기서 소모되어야 하는가 (통과하지 않음)
static func blocks_projectile(result: Result) -> bool:
	return result != Result.IGNORED and result != Result.EVADED
