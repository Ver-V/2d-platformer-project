extends Resource
class_name LootTable

# 상자·박스 등에서 쓰는 랜덤 보상 목록. 가중치 비례로 한 줄을 뽑는다.
@export var entries: Array[LootEntry] = []

func pick() -> LootEntry:
	var total := 0
	for entry in entries:
		if entry != null and not entry.is_empty():
			total += maxi(0, entry.weight)
	if total <= 0:
		return null
	var roll := randi_range(1, total)
	for entry in entries:
		if entry == null or entry.is_empty() or entry.weight <= 0:
			continue
		roll -= entry.weight
		if roll <= 0:
			return entry
	return null
