# Inventory.gd (autoload: Inventory)
extends Node

# 플레이어가 들고 있는 아이템. 칸(inventory)을 직접 바꾸지 말고 아래 함수를 거쳐야 inventory_changed가 나간다
# (인벤토리 UI, 랜턴 시야(VisionLimit) 등이 이 신호를 듣는다).
# 저장·불러오기·새 게임 초기화는 GameManager가 to_save / load_from_save / reset으로 부른다.
# 장비 칸: 보조 장비(accessories) 4칸, 보석(gems) 2칸. 장착 아이템(ItemData.equip_slot)은 얻을 때 칸이 비어 있으면
# 바로 장착되고, 가방(inventory)과 장비 칸 사이는 equip_from_bag / unequip으로만 옮긴다 (inventory_changed가 나간다).
# 장착 효과(시야·공격력·패링 배율·타격 상태이상)는 장착한 것만 적용된다.
# 겹치는 아이템(ItemData.max_stack > 1, 예: 체력 포션)은 한 칸에 max_stack개까지 쌓인다 (stack_counts).

signal inventory_changed

const SLOT_COUNT: int = 15
const ACCESSORY_SLOTS: int = 4
const GEM_SLOTS: int = 2

var inventory: Array[ItemData] = []
var key_uses_remaining: Array[int] = [] # inventory와 같은 인덱스의 열쇠 잔여 사용 횟수
var stack_counts: Array[int] = [] # inventory와 같은 인덱스의 개수 (빈 칸 0, 보통 아이템 1)
var accessories: Array[ItemData] = []
var gems: Array[ItemData] = []

func _init() -> void:
	inventory.resize(SLOT_COUNT)
	key_uses_remaining.resize(SLOT_COUNT)
	stack_counts.resize(SLOT_COUNT)
	accessories.resize(ACCESSORY_SLOTS)
	gems.resize(GEM_SLOTS)

const EQUIPMENT_TUTORIAL_KEY := &"TUTORIAL_EQUIPMENT" # 장비를 처음 얻었을 때 한 번 (TutorialPopup.show_once)

# 장착 아이템은 맞는 장비 칸이 비어 있으면 바로 장착, 아니면 가방으로.
# 겹치는 아이템은 같은 아이템이 든 칸에 자리가 있으면 거기에 하나 더한다
func add_item(item: ItemData) -> bool:
	if item == null:
		return false
	if _equip_into_free_slot(item):
		inventory_changed.emit()
		_on_got_item(item)
		return true
	var stack_index := _stack_slot_for(item)
	if stack_index != -1:
		stack_counts[stack_index] += 1
		inventory_changed.emit()
		_on_got_item(item)
		return true
	for i in range(inventory.size()):
		if inventory[i] == null:
			inventory[i] = item # 리소스 파일 자체를 저장
			key_uses_remaining[i] = maxi(1, item.key_uses)
			stack_counts[i] = 1
			inventory_changed.emit()
			_on_got_item(item)
			return true
	return false

func _on_got_item(item: ItemData) -> void:
	var key := item_tutorial_key(item)
	if key != &"":
		var popup := get_node_or_null("/root/TutorialPopup")
		if popup != null:
			popup.show_once(key)

# 이런 종류의 아이템을 처음 얻었을 때 띄울 도움말 (없으면 빈 키). 아이템마다가 아니라 종류마다 한 번
static func item_tutorial_key(item: ItemData) -> StringName:
	if item.equip_slot != ItemData.EquipSlot.NONE:
		return EQUIPMENT_TUTORIAL_KEY
	if item.key_uses > 0:
		return &"TUTORIAL_KEY"
	if item.flask_charges_up > 0 or item.flask_heal_up > 0:
		return &"TUTORIAL_FLASK_UPGRADE"
	if item.is_stat_potion():
		return &"TUTORIAL_STAT_POTION"
	if item.type == ItemData.ItemType.CONSUMABLE and item.heal_amount > 0 and item.id != "health_flask":
		return &"TUTORIAL_HEALING_POTION"
	return &""

# 같은 아이템이 들어 있고 아직 더 쌓을 수 있는 칸. 없으면(겹치지 않는 아이템 포함) -1
func _stack_slot_for(item: ItemData) -> int:
	if item.max_stack <= 1:
		return -1
	for i in range(inventory.size()):
		if inventory[i] != null and inventory[i].id == item.id and stack_counts[i] < item.max_stack:
			return i
	return -1

# 해당 칸에서 하나를 뺀다 (사용·버리기). 겹친 칸은 개수만 줄고, 마지막 하나면 칸이 빈다.
# 뺀 아이템을 돌려준다. 빈 칸·범위 밖이면 null.
func remove_item_at(index: int) -> ItemData:
	if index < 0 or index >= inventory.size() or inventory[index] == null:
		return null
	var item := inventory[index]
	stack_counts[index] -= 1
	if stack_counts[index] <= 0:
		_clear_slot(index)
	inventory_changed.emit()
	return item

func _clear_slot(index: int) -> void:
	inventory[index] = null
	key_uses_remaining[index] = 0
	stack_counts[index] = 0

# 칸에 든 개수 (빈 칸 0)
func get_count_at(index: int) -> int:
	if index < 0 or index >= inventory.size() or inventory[index] == null:
		return 0
	return stack_counts[index]

# 가방에 든 그 아이템의 총 개수 (겹친 칸 포함)
func count_item(item_id: String) -> int:
	var total := 0
	for i in range(inventory.size()):
		if inventory[i] != null and inventory[i].id == item_id:
			total += stack_counts[i]
	return total

# 가방이나 장비 칸에 있으면 true
func has_item(item_id: String) -> bool:
	if find_item(item_id) != -1:
		return true
	return equipped_items().any(func(item): return item.id == item_id)

# 그 아이템이 든 첫 칸의 번호. 없으면 -1.
func find_item(item_id: String) -> int:
	if item_id.is_empty():
		return -1
	for i in range(inventory.size()):
		if inventory[i] != null and inventory[i].id == item_id:
			return i
	return -1

# --- 장비 칸 ---
func equipment_for(kind: ItemData.EquipSlot) -> Array[ItemData]:
	match kind:
		ItemData.EquipSlot.ACCESSORY:
			return accessories
		ItemData.EquipSlot.GEM:
			return gems
	return []

func equipped_items() -> Array[ItemData]:
	var out: Array[ItemData] = []
	for item in accessories + gems:
		if item != null:
			out.append(item)
	return out

# add_item이 성공할지 미리 본다 (넣지는 않음). 열쇠를 쓰기 전에 보상 자리가 있는지 확인할 때
func has_room_for(item: ItemData) -> bool:
	if item == null:
		return false
	return equipment_for(item.equip_slot).has(null) or inventory.has(null) or _stack_slot_for(item) != -1

func _equip_into_free_slot(item: ItemData) -> bool:
	var slots := equipment_for(item.equip_slot)
	for i in slots.size():
		if slots[i] == null:
			slots[i] = item
			return true
	return false

# 가방 칸의 아이템을 맞는 장비 칸(빈 칸)에 장착. 장착할 수 없는 아이템이거나 칸이 가득 차면 false
func equip_from_bag(index: int) -> bool:
	if index < 0 or index >= inventory.size() or inventory[index] == null:
		return false
	var item := inventory[index]
	if not _equip_into_free_slot(item):
		return false
	_clear_slot(index)
	inventory_changed.emit()
	return true

# 장비 칸의 아이템을 가방 빈 칸으로. 가방이 가득 차면 false
func unequip(kind: ItemData.EquipSlot, slot_index: int) -> bool:
	var slots := equipment_for(kind)
	if slot_index < 0 or slot_index >= slots.size() or slots[slot_index] == null:
		return false
	var bag_index := inventory.find(null)
	if bag_index == -1:
		return false
	inventory[bag_index] = slots[slot_index]
	key_uses_remaining[bag_index] = maxi(1, slots[slot_index].key_uses)
	stack_counts[bag_index] = 1
	slots[slot_index] = null
	inventory_changed.emit()
	return true

# 장착한 것 중 가장 큰 시야 보너스 (랜턴 등). 겹쳐서 더하지 않는다.
func get_vision_bonus_tiles() -> float:
	var bonus := 0.0
	for item in equipped_items():
		bonus = maxf(bonus, item.vision_bonus_tiles)
	return bonus

func get_equipped_attack_bonus() -> int:
	var total := 0
	for item in equipped_items():
		total += item.attack_damage
	return total

func get_equipped_attack_speed_bonus() -> float:
	var total := 0.0
	for item in equipped_items():
		total += item.attack_speed_bonus
	return total

# 가방에 든 것은 치지 않는다 (엘리베이터 탑승 허가처럼 "장착 중"이어야 하는 효과용)
func is_equipped(item_id: String) -> bool:
	return equipped_items().any(func(item): return item.id == item_id)

func get_equipped_parry_bonus() -> float:
	var total := 0.0
	for item in equipped_items():
		total += item.parrymul
	return total

# 장착한 보석 등이 검 타격에 거는 상태이상 (확률은 여기서 굴린다)
func roll_equipped_hit_statuses() -> Array[StatusEffect]:
	var out: Array[StatusEffect] = []
	for item in equipped_items():
		if item.hit_status != null and randf() < item.hit_status_chance:
			out.append(item.hit_status)
	return out

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
# 칸마다 null 또는 {"id", "key_uses", "count"}
func to_save() -> Array:
	var out: Array = []
	for i in range(inventory.size()):
		var item := inventory[i]
		out.append(null if item == null else {"id": item.id, "key_uses": key_uses_remaining[i], "count": stack_counts[i]})
	return out

# 가방과 장비 칸을 한 번에 불러온다 (inventory_changed는 한 번만).
# equipment가 없으면(장비 칸이 없던 옛 세이브) 가방의 장착 아이템(랜턴 등)을 빈 장비 칸에 장착한다
func load_from_save(slots: Array, equipment: Variant = null) -> void:
	inventory.fill(null)
	key_uses_remaining.fill(0)
	stack_counts.fill(0)
	accessories.fill(null)
	gems.fill(null)
	for i in range(mini(slots.size(), inventory.size())):
		var slot = slots[i]
		if typeof(slot) == TYPE_DICTIONARY and slot.has("id"):
			inventory[i] = Database.get_item_by_id(slot["id"])
			if inventory[i] != null:
				key_uses_remaining[i] = maxi(1, int(slot.get("key_uses", inventory[i].key_uses)))
				stack_counts[i] = clampi(int(slot.get("count", 1)), 1, maxi(1, inventory[i].max_stack)) # count 없는 옛 세이브 = 1
	if equipment is Dictionary:
		for pair in [[accessories, equipment.get("accessories", [])], [gems, equipment.get("gems", [])]]:
			var equip_slots: Array[ItemData] = pair[0]
			var ids: Array = pair[1]
			for i in mini(ids.size(), equip_slots.size()):
				if ids[i] is String:
					equip_slots[i] = Database.get_item_by_id(ids[i])
	else:
		for i in inventory.size():
			if inventory[i] != null and inventory[i].equip_slot != ItemData.EquipSlot.NONE and _equip_into_free_slot(inventory[i]):
				_clear_slot(i)
	inventory_changed.emit()

func reset() -> void:
	inventory.fill(null)
	key_uses_remaining.fill(0)
	stack_counts.fill(0)
	accessories.fill(null)
	gems.fill(null)
	inventory_changed.emit()

# 장비 칸 저장: {"accessories": [id 또는 null, ...], "gems": [...]}
func equipment_to_save() -> Dictionary:
	return {
		"accessories": accessories.map(func(item): return null if item == null else item.id),
		"gems": gems.map(func(item): return null if item == null else item.id),
	}

