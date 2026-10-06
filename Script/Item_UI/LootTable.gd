extends Resource
class_name LootTable

# 상자·박스 등에서 쓰는 랜덤 보상 목록. 가중치 비례로 한 줄을 뽑는다.
@export var entries: Array[LootEntry] = []

# rng를 주면 그걸로 굴린다 (세이브 시드로 결과 고정). 없으면 전역 랜덤.
func pick(rng: RandomNumberGenerator = null) -> LootEntry:
	var total := 0
	for entry in entries:
		if entry != null and not entry.is_empty():
			total += maxi(0, entry.weight)
	if total <= 0:
		return null
	var roll := rng.randi_range(1, total) if rng != null else randi_range(1, total)
	for entry in entries:
		if entry == null or entry.is_empty() or entry.weight <= 0:
			continue
		roll -= entry.weight
		if roll <= 0:
			return entry
	return null
