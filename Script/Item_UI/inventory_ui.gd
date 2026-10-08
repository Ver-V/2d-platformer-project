extends CanvasLayer

@onready var grid: GridContainer = $Control/TextureRect/GridContainer
@onready var gold_label: Label = $Control/TextureRect/Panel/HBoxContainer/VBoxContainer/GoldLabel
@onready var hp_label: Label = $Control/TextureRect/Panel/HBoxContainer/VBoxContainer/HpLabel
@onready var atk_label: Label = $Control/TextureRect/Panel/HBoxContainer/VBoxContainer/AtkLabel
@onready var pd_label: Label = $Control/TextureRect/Panel/HBoxContainer/VBoxContainer/ParryDmgLabel

# 아이템 설명 패널 (상점처럼 고정 위치). 마우스를 올린 아이템, 없으면 클릭해서 고른 아이템을 보여준다
@onready var info_name_label: Label = $Control/TextureRect/ItemInfo/NameLabel
@onready var info_desc_label: Label = $Control/TextureRect/ItemInfo/DescLabel

# [새로 추가] 액션 메뉴 관련 노드 연결
@onready var action_menu: PanelContainer = $ActionMenu
@onready var btn_use: Button = $ActionMenu/VBoxContainer/BtnUse
@onready var btn_close: Button = $ActionMenu/VBoxContainer/BtnClose

var is_open: bool = false
var selected_index: int = -1 # [새로 추가] 클릭한 슬롯 번호 기억용
var hovered_index: int = -1 # 마우스가 올라가 있는 슬롯 번호

func _ready():
	var slots = grid.get_children()

	for i in range(slots.size()):
		var slot = slots[i]
		if not slot.slot_clicked.is_connected(_on_slot_clicked):
			slot.slot_clicked.connect(_on_slot_clicked.bind(i))
		slot.mouse_entered.connect(_on_slot_mouse_entered.bind(i))
		slot.mouse_exited.connect(_on_slot_mouse_exited.bind(i))

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
	atk_label.text = tr(&"INVENTORY_DAMAGE").format({"damage": GameManager.player_damage})
	pd_label.text = tr(&"INVENTORY_PARRY_MULTIPLIER").format({
		"multiplier": "%.1f" % GameManager.player_parry_damage_multifac
	})
	
	# --- 아이템 슬롯 갱신 ---
	var slots = grid.get_children()
	for i in range(slots.size()):
		if i < Inventory.inventory.size():
			slots[i].set_item(Inventory.inventory[i], i)
		else:
			slots[i].set_item(null)
	_update_item_info()

# --- 아이템 설명 패널 ---
func _item_at(index: int) -> ItemData:
	if index < 0 or index >= Inventory.inventory.size():
		return null
	return Inventory.inventory[index]

func _update_item_info() -> void:
	var item := _item_at(hovered_index)
	if item == null:
		item = _item_at(selected_index)
	if item == null:
		info_name_label.text = ""
		info_desc_label.text = ""
		return
	info_name_label.text = tr(item.name)
	info_desc_label.text = tr(item.description)

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
	
	if item != null:
		selected_index = index
		_update_item_info()
		
		# [수정 1] 마우스 좌표 대신, 클릭한 슬롯 노드의 위치를 기준으로 띄웁니다.
		# (해상도/카메라 스케일 때문에 마우스 좌표가 엉뚱한 곳을 가리키는 현상 방지)
		var clicked_slot = grid.get_child(index)
		action_menu.global_position = clicked_slot.global_position + Vector2(20, 20)
		
		# [수정 2] 팝업이 다른 UI 배경에 가려지지 않도록 Z-Index를 강제로 100으로 확 끌어올립니다.
		action_menu.z_index = 100 
		
		action_menu.show()
	else:
		action_menu.hide()
		selected_index = -1
		_update_item_info()

# --- [새로 추가] '사용' 버튼 눌렀을 때 ---
func _on_use_pressed():
	if selected_index < 0 or selected_index >= Inventory.inventory.size():
		return
	
	var item = Inventory.inventory[selected_index]
	
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
	_update_item_info()

func _on_button_pressed() -> void:
	close()
