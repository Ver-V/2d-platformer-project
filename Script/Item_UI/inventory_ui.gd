extends CanvasLayer

@onready var grid: GridContainer = $Control/TextureRect/GridContainer
@onready var gold_label: Label = $Control/TextureRect/Panel/HBoxContainer/VBoxContainer/GoldLabel
@onready var hp_label: Label = $Control/TextureRect/Panel/HBoxContainer/VBoxContainer/HpLabel
@onready var atk_label: Label = $Control/TextureRect/Panel/HBoxContainer/VBoxContainer/AtkLabel
@onready var pd_label: Label = $Control/TextureRect/Panel/HBoxContainer/VBoxContainer/ParryDmgLabel

# 아이템 설명 패널 (상점처럼 고정 위치). 마우스를 올린 아이템, 없으면 클릭해서 고른 아이템을 보여준다
@onready var info_name_label: Label = $Control/TextureRect/ItemInfo/NameLabel
@onready var info_desc_label: RichTextLabel = $Control/TextureRect/ItemInfo/DescLabel
# 정보창 장착 효과 줄 색: 능력치가 오르면 파랑, 내리면 빨강
const EFFECT_BUFF_COLOR := Color("4da6ff")
const EFFECT_DEBUFF_COLOR := Color("ff4d4d")

# [새로 추가] 액션 메뉴 관련 노드 연결
@onready var action_menu: PanelContainer = $ActionMenu
@onready var btn_use: Button = $ActionMenu/VBoxContainer/BtnUse
@onready var btn_close: Button = $ActionMenu/VBoxContainer/BtnClose

var is_open: bool = false
var selected_index: int = -1 # [새로 추가] 클릭한 슬롯 번호 기억용
var hovered_index: int = -1 # 마우스가 올라가 있는 슬롯 번호
# 장비 칸 (보조 장비 4, 보석 2): 씬의 %AccessorySlots / %GemSlots 아래 Slot들 (순서 = 칸 번호).
# 위치·크기·테두리는 씬에서 바꾸면 된다. 선택·마우스 위치는 [종류, 칸 번호], 없으면 [-1, -1]
@onready var accessory_slots: Array = %AccessorySlots.get_children()
@onready var gem_slots: Array = %GemSlots.get_children()
var selected_equip: Array = [-1, -1]
var hovered_equip: Array = [-1, -1]

func _ready():
	var slots = grid.get_children()

	for i in range(slots.size()):
		var slot = slots[i]
		if not slot.slot_clicked.is_connected(_on_slot_clicked):
			slot.slot_clicked.connect(_on_slot_clicked.bind(i))
		slot.mouse_entered.connect(_on_slot_mouse_entered.bind(i))
		slot.mouse_exited.connect(_on_slot_mouse_exited.bind(i))

	_build_equipment_slots()

	btn_use.pressed.connect(GameManager.play_ui_click)
	btn_use.pressed.connect(_on_use_pressed)
	btn_close.pressed.connect(GameManager.play_ui_click)
	btn_close.pressed.connect(_on_close_pressed)

	# [실시간 스탯 반영을 위한 신호 연결 (메모리 누수 방지를 위해 메서드로 연결)]
	GameManager.gold_changed.connect(_on_gold_changed)
	GameManager.hp_changed.connect(_on_hp_changed)
	GameManager.stats_changed.connect(_on_stats_changed)
	SettingsManager.locale_changed.connect(_on_locale_changed)
	Inventory.inventory_changed.connect(_on_inventory_changed)

	action_menu.hide()
	close()

func _on_gold_changed(_amount: int) -> void:
	if is_open: update_ui()

func _on_hp_changed(_cur: int, _max: int) -> void:
	if is_open: update_ui()

func _on_inventory_changed() -> void:
	if is_open: update_ui()

func _on_stats_changed() -> void:
	if is_open: update_ui()

func _on_locale_changed(_new_locale: String) -> void:
	if is_open:
		update_ui()


func _input(event):
	if event.is_action_pressed("inventory"):
		get_viewport().set_input_as_handled()
		if is_open:
			close()
		else:
			open()
	elif event.is_action_pressed("ui_cancel"):
		if is_open:
			close()
			get_viewport().set_input_as_handled()

func open():
	if is_open or GameManager.is_menu_open:
		return
	visible = true
	is_open = true
	selected_index = -1 # 열 때 선택 초기화
	hovered_index = -1
	selected_equip = [-1, -1]
	hovered_equip = [-1, -1]
	action_menu.hide()  # 열 때 팝업 무조건 숨김

	update_ui()
	GameManager.ui_opened(self)

func close():
	var was_open := is_open
	visible = false
	is_open = false
	action_menu.hide() # 닫을 때 팝업도 같이 닫기
	if was_open:
		GameManager.ui_closed(self)

func _exit_tree() -> void:
	if is_open:
		GameManager.ui_closed(self)

func update_ui():
	# --- 정보 갱신 ---
	gold_label.text = tr(&"INVENTORY_GOLD").format({"gold": GameManager.gold})
	hp_label.text = tr(&"INVENTORY_HP").format({
		"current": GameManager.player_current_hp,
		"maximum": GameManager.player_max_hp
	})
	# 장착한 장비 보너스까지 더한 실제 값
	atk_label.text = tr(&"INVENTORY_DAMAGE").format({"damage": GameManager.player_damage + Inventory.get_equipped_attack_bonus()})
	pd_label.text = tr(&"INVENTORY_PARRY_MULTIPLIER").format({
		"multiplier": "%.1f" % (GameManager.player_parry_damage_multifac + Inventory.get_equipped_parry_bonus())
	})

	# --- 아이템 슬롯 갱신 ---
	var slots = grid.get_children()
	for i in range(slots.size()):
		if i < Inventory.inventory.size():
			slots[i].set_item(Inventory.inventory[i], i)
		else:
			slots[i].set_item(null)
	for i in accessory_slots.size():
		accessory_slots[i].set_item(Inventory.accessories[i] if i < Inventory.accessories.size() else null)
	for i in gem_slots.size():
		gem_slots[i].set_item(Inventory.gems[i] if i < Inventory.gems.size() else null)
	_update_item_info()

# --- 아이템 설명 패널 ---
func _item_at(index: int) -> ItemData:
	if index < 0 or index >= Inventory.inventory.size():
		return null
	return Inventory.inventory[index]

func _equip_at(where: Array) -> ItemData:
	var slots: Array = Inventory.equipment_for(where[0]) if where[0] >= 0 else []
	return slots[where[1]] if where[1] >= 0 and where[1] < slots.size() else null

func _update_item_info() -> void:
	var item := _item_at(hovered_index)
	if item == null:
		item = _equip_at(hovered_equip)
	if item == null:
		item = _item_at(selected_index)
	if item == null:
		item = _equip_at(selected_equip)
	if item == null:
		info_name_label.text = ""
		info_desc_label.text = ""
		return
	info_name_label.text = tr(item.name)
	# 장착 효과는 이름 바로 아래, 설명보다 먼저 한 줄씩 (BBCode로 색칠 — 번역 문구의 "["는 이스케이프)
	var lines := PackedStringArray()
	for effect in item.effect_lines():
		var color: Color = EFFECT_BUFF_COLOR if effect["buff"] else EFFECT_DEBUFF_COLOR
		lines.append("[color=#%s]%s[/color]" % [color.to_html(false), _escape_bbcode(effect["text"])])
	lines.append(_escape_bbcode(tr(item.description)))
	info_desc_label.text = "
".join(lines)

static func _escape_bbcode(text: String) -> String:
	return text.replace("[", "[lb]")

func _on_slot_mouse_entered(index: int) -> void:
	hovered_index = index
	_update_item_info()

func _on_slot_mouse_exited(index: int) -> void:
	if hovered_index == index:
		hovered_index = -1
		_update_item_info()

# --- [수정됨] 슬롯 클릭 시 팝업 띄우기 ---
func _on_slot_clicked(index):
	if index >= Inventory.inventory.size(): return

	var item = Inventory.inventory[index]
	selected_equip = [-1, -1]

	if item != null:
		selected_index = index
		_update_item_info()
		# 장착 아이템이면 "장착", 아니면 "사용"
		btn_use.text = "INVENTORY_EQUIP" if item.equip_slot != ItemData.EquipSlot.NONE else "INVENTORY_USE"
		_show_action_menu(grid.get_child(index))
	else:
		action_menu.hide()
		selected_index = -1
		_update_item_info()

# 마우스 좌표 대신 클릭한 칸 위치에 띄운다 (해상도·스케일 차이로 엉뚱한 곳에 뜨지 않게).
# 다른 UI 배경에 가려지지 않도록 z_index를 올린다
func _show_action_menu(slot: Control) -> void:
	action_menu.global_position = slot.global_position + Vector2(20, 20)
	action_menu.z_index = 100
	action_menu.show()

# --- 장비 칸 ---
func _build_equipment_slots() -> void:
	if accessory_slots.size() != Inventory.ACCESSORY_SLOTS or gem_slots.size() != Inventory.GEM_SLOTS:
		push_warning("InventoryUI: 장비 칸 수가 Inventory와 다릅니다 (보조 %d/%d, 보석 %d/%d)" % [
			accessory_slots.size(), Inventory.ACCESSORY_SLOTS, gem_slots.size(), Inventory.GEM_SLOTS])
	for i in accessory_slots.size():
		_connect_equip_slot(accessory_slots[i], ItemData.EquipSlot.ACCESSORY, i)
	for i in gem_slots.size():
		_connect_equip_slot(gem_slots[i], ItemData.EquipSlot.GEM, i)

func _connect_equip_slot(slot: Control, kind: ItemData.EquipSlot, index: int) -> void:
	slot.slot_clicked.connect(_on_equip_slot_clicked.bind(kind, index))
	slot.mouse_entered.connect(func(): hovered_equip = [kind, index]; _update_item_info())
	slot.mouse_exited.connect(func():
		if hovered_equip == [kind, index]:
			hovered_equip = [-1, -1]
			_update_item_info())

func _on_equip_slot_clicked(kind: ItemData.EquipSlot, index: int) -> void:
	selected_index = -1
	if _equip_at([kind, index]) == null:
		selected_equip = [-1, -1]
		action_menu.hide()
		_update_item_info()
		return
	selected_equip = [kind, index]
	_update_item_info()
	btn_use.text = "INVENTORY_UNEQUIP"
	var slots := accessory_slots if kind == ItemData.EquipSlot.ACCESSORY else gem_slots
	_show_action_menu(slots[index])

func _popup_on_player(key: StringName) -> void:
	var player = get_tree().get_first_node_in_group("player")
	if player != null and player.has_method("show_popup"):
		player.show_popup(tr(key), Color.ORANGE)

# --- [새로 추가] '사용' 버튼 눌렀을 때 (장착 아이템이면 장착, 장비 칸이면 해제) ---
func _on_use_pressed():
	if _equip_at(selected_equip) != null:
		if not Inventory.unequip(selected_equip[0], selected_equip[1]):
			_popup_on_player(&"STATUS_INVENTORY_FULL") # 가방이 가득 참
		selected_equip = [-1, -1]
		action_menu.hide()
		update_ui()
		return
	if selected_index < 0 or selected_index >= Inventory.inventory.size():
		return

	var item = Inventory.inventory[selected_index]
	if item != null and item.equip_slot != ItemData.EquipSlot.NONE:
		if not Inventory.equip_from_bag(selected_index):
			_popup_on_player(&"INVENTORY_EQUIP_FULL")
		action_menu.hide()
		selected_index = -1
		update_ui()
		return

	# [추가됨] 빈 슬롯 예외 처리 (크래시 방지)
	if item == null:
		action_menu.hide()
		selected_index = -1
		return

	var player = get_tree().get_first_node_in_group("player")

	# [1] 플라스크(특수 소모품) 예외 처리
	if item.id == "health_flask":
		if GameManager.has_method("use_flask"):
			var success = GameManager.use_flask()
			if success:
				update_ui()
		else:
			push_error("GameManager에 use_flask 함수가 구현되지 않았습니다.")

		# 플라스크는 사용 후 절대 삭제하지 않음
		action_menu.hide()
		selected_index = -1
		_update_item_info()
		return

	# [2] 일반 아이템 타입별 처리
	match item.type:
		ItemData.ItemType.CONSUMABLE:
			# 일반 소모품(포션 등)은 사용 후 삭제
			item.use(player)
			Inventory.remove_item_at(selected_index)
			DebugLog.info("%s를 사용하고 소모했습니다." % item.name)

		ItemData.ItemType.EQUIPMENT:
			# 장비템은 사용(장착)해도 삭제하지 않음
			item.use(player)
			DebugLog.info("%s를 장착/해제했습니다." % item.name)

		_:
			# 잡동사니 등은 그냥 use만 실행 (보통 아무 일 없음)
			item.use(player)

	# 공통 마무리: 메뉴 닫기 및 UI 업데이트
	action_menu.hide()
	selected_index = -1
	update_ui()

# --- [새로 추가] '닫기' 버튼 눌렀을 때 ---
func _on_close_pressed():
	action_menu.hide()
	selected_index = -1
	selected_equip = [-1, -1]
	_update_item_info()

func _on_button_pressed() -> void:
	close()
