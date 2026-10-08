# Inventory.gd (autoload: Inventory)
extends Node

# 플레이어가 들고 있는 아이템. 칸(inventory)을 직접 바꾸지 말고 아래 함수를 거쳐야 inventory_changed가 나간다
# (인벤토리 UI, 랜턴 시야(VisionLimit) 등이 이 신호를 듣는다).
# 저장·불러오기·새 게임 초기화는 GameManager가 to_save / load_from_save / reset으로 부른다.
# 나중에 장비 칸(무기)·패시브 칸이 생기면 여기에 같은 방식으로 추가한다.

signal inventory_changed

const SLOT_COUNT: int = 15

var inventory: Array[ItemData] = []
var key_uses_remaining: Array[int] = [] # inventory와 같은 인덱스의 열쇠 잔여 사용 횟수

func _init() -> void:
	inventory.resize(SLOT_COUNT)
	key_uses_remaining.resize(SLOT_COUNT)

func add_item(item: ItemData) -> bool:
	for i in range(inventory.size()):
		if inventory[i] == null:
			inventory[i] = item # 리소스 파일 자체를 저장
			key_uses_remaining[i] = maxi(1, item.key_uses)
			inventory_changed.emit()
			return true
	return false

# 해당 칸을 비운다 (사용·버리기). 비운 아이템을 돌려준다. 빈 칸·범위 밖이면 null.
func remove_item_at(index: int) -> ItemData:
	if index < 0 or index >= inventory.size() or inventory[index] == null:
		return null
	var item := inventory[index]
	inventory[index] = null
	key_uses_remaining[index] = 0
	inventory_changed.emit()
	return item

func has_item(item_id: String) -> bool:
	return find_item(item_id) != -1

# 그 아이템이 든 첫 칸의 번호. 없으면 -1.
func find_item(item_id: String) -> int:
	if item_id.is_empty():
		return -1
	for i in range(inventory.size()):
		if inventory[i] != null and inventory[i].id == item_id:
			return i
	return -1

# 갖고 있는 아이템 중 가장 큰 시야 보너스 (랜턴 등). 겹쳐서 더하지 않는다.
func get_vision_bonus_tiles() -> float:
	var bonus := 0.0
	for item in inventory:
		if item != null:
			bonus = maxf(bonus, item.vision_bonus_tiles)
	return bonus

func get_key_uses_for_slot(index: int) -> int:
	if index < 0 or index >= inventory.size() or inventory[index] == null:
		return 0
	return key_uses_remaining[index]

# 한 번 사용한 뒤 이 열쇠의 남은 횟수. 열쇠가 없으면 -1.
func consume_key_use(item_id: String) -> int:
	var i := find_item(item_id)
	if i == -1:
		return -1
	if key_uses_remaining[i] <= 0:
		key_uses_remaining[i] = maxi(1, inventory[i].key_uses)
	key_uses_remaining[i] -= 1
	var remaining := key_uses_remaining[i]
	if remaining == 0:
		remove_item_at(i)
	else:
		inventory_changed.emit() # 남은 횟수 표시 갱신
	return remaining

# --- 저장 (GameManager가 부름) ---
# 칸마다 null 또는 {"id", "key_uses"}
func to_save() -> Array:
	var out: Array = []
	for i in range(inventory.size()):
		var item := inventory[i]
		out.append(null if item == null else {"id": item.id, "key_uses": key_uses_remaining[i]})
	return out

func load_from_save(slots: Array) -> void:
	inventory.fill(null)
	key_uses_remaining.fill(0)
	for i in range(mini(slots.size(), inventory.size())):
		var slot = slots[i]
		if typeof(slot) == TYPE_DICTIONARY and slot.has("id"):
			inventory[i] = Database.get_item_by_id(slot["id"])
			if inventory[i] != null:
				key_uses_remaining[i] = maxi(1, int(slot.get("key_uses", inventory[i].key_uses)))
	inventory_changed.emit()

func reset() -> void:
	inventory.fill(null)
	key_uses_remaining.fill(0)
	inventory_changed.emit()
