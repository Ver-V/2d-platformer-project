extends Resource
class_name LootEntry

# 랜덤 보상 한 줄: 아이템 또는 골드, 그리고 가중치 (가중치가 클수록 자주 나옴, 0이면 안 나옴)
# item과 골드를 둘 다 넣으면 둘 다 준다.
@export var item: ItemData
@export var gold_amount: int = 0 # 골드 (gold_max를 쓰면 최소값)
@export var gold_max: int = 0 # gold_amount보다 크면 gold_amount ~ gold_max 사이 랜덤
@export var gold_step: int = 10 # 랜덤 골드의 단위 (10이면 10, 20, 30 ... 처럼 10의 배수로만)
@export_range(0, 100, 1, "or_greater") var weight: int = 1 # 백분율 아님: 이 숫자 ÷ 전체 가중치 합 = 확률

func is_empty() -> bool:
	return item == null and gold_amount <= 0 and gold_max <= 0

# 실제로 줄 골드. 범위가 없으면 gold_amount 그대로. rng를 주면 그걸로 굴린다.
func roll_gold(rng: RandomNumberGenerator = null) -> int:
	if gold_max <= gold_amount:
		return maxi(0, gold_amount)
	var step := maxi(1, gold_step)
	var low := ceili(float(maxi(0, gold_amount)) / step)
	var high := floori(float(gold_max) / step)
	if high < low:
		return maxi(0, gold_amount)
	return (rng.randi_range(low, high) if rng != null else randi_range(low, high)) * step
