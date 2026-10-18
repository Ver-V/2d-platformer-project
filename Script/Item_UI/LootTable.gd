extends Resource
class_name LootTable

# 상자·박스 등에서 쓰는 랜덤 보상 목록. 가중치 비례로 한 줄을 뽑는다.
@export var entries: Array[LootEntry] = []
# 켜면 이 목록의 스탯 포션(ItemData.is_stat_potion)은 pick_with_stat_pity 규칙으로 나온다 (기본 상자 목록).
# - 불운 보정: 스탯 포션이 안 나온 상자 하나마다 스탯 포션 확률 +STAT_PITY_STEP (남은 종류끼리 나눠 가짐)
# - 중복 방지: 이번 세트에서 이미 받은 종류는 목록의 모든 종류를 한 번씩 받을 때까지 다시 안 나온다
# - 상한: 상자에서 받는 스탯 포션은 STAT_MAX_SETS 세트까지. 그 뒤로는 스탯 포션이 안 나온다 (변이 상자·고정 배치는 별개)
@export var stat_pity: bool = false

const STAT_PITY_STEP := 0.025 # 실패 한 번마다 스탯 포션 전체 확률 + (5종이면 종류마다 0.5%)
const STAT_MAX_SETS := 2

# 목록에 든 스탯 포션 줄들
func stat_entries() -> Array[LootEntry]:
	var out: Array[LootEntry] = []
	for entry in entries:
		if entry != null and entry.weight > 0 and entry.item != null and entry.item.is_stat_potion():
			out.append(entry)
	return out

func stat_ids() -> Array[String]:
	var out: Array[String] = []
	for entry in stat_entries():
		if not out.has(entry.item.id):
			out.append(entry.item.id)
	return out

# 지금 상태에서 스탯 포션 종류별 확률 {id: 확률}. 상한에 닿았거나 남은 종류가 없으면 빈 Dictionary.
# state = {"fails": 연속 실패 수, "taken": 이번 세트에서 받은 id 목록, "drops": 지금까지 받은 수}
func stat_chances(state: Dictionary) -> Dictionary:
	var out := {}
	var ids := stat_ids()
	if not stat_pity or ids.is_empty() or int(state.get("drops", 0)) >= STAT_MAX_SETS * ids.size():
		return out
	var taken: Array = state.get("taken", [])
	var total := _total_weight()
	var remaining: Array[LootEntry] = []
	for entry in stat_entries():
		if not taken.has(entry.item.id):
			remaining.append(entry)
	if remaining.is_empty():
		return out
	var pity_each := int(state.get("fails", 0)) * STAT_PITY_STEP / remaining.size()
	for entry in remaining:
		out[entry.item.id] = float(out.get(entry.item.id, 0.0)) + float(entry.weight) / total + pity_each
	return out

# stat_pity 목록이면 위 규칙으로, 아니면 pick과 같다. state는 읽기만 한다 (상자가 실제로 열린 뒤 GameManager가 기록)
func pick_with_stat_pity(rng: RandomNumberGenerator, state: Dictionary) -> LootEntry:
	if not stat_pity or stat_entries().is_empty():
		return pick(rng)
	var chances := stat_chances(state)
	var roll := rng.randf() if rng != null else randf()
	for id in chances:
		roll -= chances[id]
		if roll < 0.0:
			for entry in stat_entries():
				if entry.item.id == id:
					return entry
	# 스탯 포션이 아니면 나머지 줄에서 가중치대로
	return _pick_from(entries.filter(func(e): return e != null and (e.item == null or not e.item.is_stat_potion())), rng)

func _total_weight() -> int:
	var total := 0
	for entry in entries:
		if entry != null and not entry.is_empty():
			total += maxi(0, entry.weight)
	return maxi(1, total)

# rng를 주면 그걸로 굴린다 (세이브 시드로 결과 고정). 없으면 전역 랜덤.
func pick(rng: RandomNumberGenerator = null) -> LootEntry:
	return _pick_from(entries, rng)

func _pick_from(list: Array, rng: RandomNumberGenerator) -> LootEntry:
	var total := 0
	for entry in list:
		if entry != null and not entry.is_empty():
			total += maxi(0, entry.weight)
	if total <= 0:
		return null
	var roll := rng.randi_range(1, total) if rng != null else randi_range(1, total)
	for entry in list:
		if entry == null or entry.is_empty() or entry.weight <= 0:
			continue
		roll -= entry.weight
		if roll <= 0:
			return entry
	return null
