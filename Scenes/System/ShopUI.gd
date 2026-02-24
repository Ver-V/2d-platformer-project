extends CanvasLayer

@onready var item_list = $MainPanel/HBox/ItemList
@onready var name_label = $MainPanel/HBox/InfoPanel/NameLabel
@onready var desc_label = $MainPanel/HBox/InfoPanel/DescLabel
@onready var price_label = $MainPanel/HBox/InfoPanel/PriceLabel
@onready var confirm_panel = $ConfirmPanel
@onready var confirm_msg = $ConfirmPanel/MsgLabel

signal shop_closed(bought_something: bool)

var bought_something: bool = false

var shop_item_ids: Array[String] = ["health_potion"]

var selected_index: int = 0
var is_open: bool = false
var is_confirming: bool = false

func _ready():
	hide()
	confirm_panel.hide()
	_create_item_slots()

# --- 1. 상점 열고 닫기 ---
func open_shop():
	bought_something = false
	is_open = true
	is_confirming = false
	selected_index = 0
	confirm_panel.hide()
	show()
	_update_selection_ui()
	GameManager.ui_opened()

func close_shop():
	is_open = false
	hide()
	shop_closed.emit(bought_something)
	GameManager.ui_closed()

func close_confirm_panel():
	is_confirming = false
	confirm_panel.hide()

# --- 2. 입력 처리 ---
func _input(event):
	if not is_open: return

	if is_confirming:
		if event.is_action_pressed("interact"):
			buy_item()
		elif event.is_action_pressed("ui_cancel"):
			close_confirm_panel()
		return

	if event.is_action_pressed("ui_down"):
		selected_index = (selected_index + 1) % shop_item_ids.size()
		_update_selection_ui()
	elif event.is_action_pressed("ui_up"):
		selected_index = (selected_index - 1 + shop_item_ids.size()) % shop_item_ids.size()
		_update_selection_ui()
	elif event.is_action_pressed("interact"):
		open_confirm_panel()
	elif event.is_action_pressed("ui_cancel"):
		close_shop()

# --- 3. 아이템 목록 UI 동적 생성 ---
func _create_item_slots():
	for i in range(shop_item_ids.size()):
		var item_id = shop_item_ids[i]
		
		# GameManager의 도감에서 실제 리소스(.tres) 가져오기
		var item_resource = GameManager.get_item_by_id(item_id)
		
		if item_resource == null:
			print("에러: 데이터를 찾을 수 없음 -> ", item_id)
			continue # 데이터가 없으면 슬롯 생성을 건너뜀
			
		var slot = ColorRect.new()
		slot.custom_minimum_size = Vector2(250, 40)
		
		var hbox = HBoxContainer.new()
		hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
		hbox.alignment = BoxContainer.ALIGNMENT_CENTER
		hbox.add_theme_constant_override("separation", 15)
		slot.add_child(hbox)
		
		var icon_rect = TextureRect.new()
		if item_resource.icon != null:
			icon_rect.texture = item_resource.icon
		icon_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.custom_minimum_size = Vector2(30, 30)
		hbox.add_child(icon_rect)
		
		var label = Label.new()
		# 리소스에서 name과 price를 직접 가져옴!
		label.text = item_resource.name + "   [" + str(item_resource.price) + "G]"
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		hbox.add_child(label)
		
		slot.mouse_entered.connect(_on_slot_mouse_entered.bind(i))
		slot.gui_input.connect(_on_slot_gui_input.bind(i))
		
		item_list.add_child(slot)

func _on_slot_mouse_entered(index: int):
	if not is_confirming:
		selected_index = index
		_update_selection_ui()

# --- 마우스 클릭 처리 ---
func _on_slot_gui_input(event: InputEvent, index: int):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if not is_confirming:
			selected_index = index
			_update_selection_ui()
			open_confirm_panel()
			
# --- 5. 선택된 아이템 시각적 강조 및 정보 표시 ---
func _update_selection_ui():
	for i in range(item_list.get_child_count()):
		var slot = item_list.get_child(i)
		if i == selected_index:
			slot.color = Color(0.4, 0.4, 0.4)
		else:
			slot.color = Color(0.1, 0.1, 0.1)
			
	var item_id = shop_item_ids[selected_index]
	var item_resource = GameManager.get_item_by_id(item_id)
	
	if item_resource:
		name_label.text = item_resource.name
		desc_label.text = item_resource.description # 리소스의 description 가져오기!
		price_label.text = "보유 골드: " + str(GameManager.gold) + " G\n\n가격: " + str(item_resource.price) + " G"

# --- 6. 구매 확인창 로직 ---
func open_confirm_panel():
	is_confirming = true
	var item_id = shop_item_ids[selected_index]
	var item_resource = GameManager.get_item_by_id(item_id)
	
	confirm_msg.text = "[ " + item_resource.name + " ]\n" + str(item_resource.price) + "G 에 구매하시겠습니까?\n\n(E 키: 구매 확정 / ESC: 취소)"
	confirm_panel.show()

# --- [핵심] GameManager 연동 구매 로직 ---
func buy_item():
	var item_id = shop_item_ids[selected_index]
	var item_resource = GameManager.get_item_by_id(item_id)
	
	if item_resource == null: return
	
	var price = item_resource.price

	if GameManager.gold >= price:
		var is_added = GameManager.add_item(item_resource)
		
		if is_added:
			GameManager.update_gold(-price)
			print(item_resource.name + " 구매 완료!")
			_update_selection_ui() 
			close_confirm_panel()
			bought_something = true # 상인 대사 변경을 위한 변수
		else:
			confirm_msg.text = "인벤토리가 가득 찼습니다!\n\n(ESC: 취소)"
	else:
		confirm_msg.text = "골드가 부족합니다!\n\n(ESC: 취소)"
