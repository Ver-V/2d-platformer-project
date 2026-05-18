extends CanvasLayer

@onready var item_list = $MainPanel/HBox/ItemList
@onready var name_label = $MainPanel/HBox/InfoPanel/NameLabel
@onready var desc_label = $MainPanel/HBox/InfoPanel/DescLabel
@onready var price_label = $MainPanel/HBox/InfoPanel/PriceLabel
@onready var confirm_panel = $ConfirmPanel
@onready var confirm_msg = $ConfirmPanel/MsgLabel

signal shop_closed(bought_something: bool)

var bought_something: bool = false

var current_shop_id: String = "" # 현재 말 건 상인의 이름
var current_stock_list: Array = [] # 현재 띄울 아이템 목록 참조용

var selected_index: int = 0
var is_open: bool = false
var is_confirming: bool = false

func _ready():
	hide()
	confirm_panel.hide()
	_create_item_slots()

# --- 1. 상점 열고 닫기 ---
func open_shop(shop_id: String = "Stage1"): # [수정] 인자 받기
	current_shop_id = shop_id
	
	# GameManager의 장부에 이 상인 데이터가 있는지 확인
	if GameManager.merchant_stocks.has(shop_id):
		current_stock_list = GameManager.merchant_stocks[shop_id]
	else:
		current_stock_list = [] # 데이터 없으면 빈 상점
		
	bought_something = false
	is_open = true
	is_confirming = false
	selected_index = 0
	confirm_panel.hide()
	
	# [추가] UI를 그리기 전에 기존에 있던 아이템 목록을 싹 지워줍니다.
	for child in item_list.get_children():
		child.queue_free()
		
	show()
	_create_item_slots() # 목록 생성
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
		if event.is_action_pressed("ui_accept"): 
			buy_item()
			get_viewport().set_input_as_handled() # [추가] 입력 삼키기
		elif event.is_action_pressed("ui_cancel") or event.is_action_pressed("attack"):
			close_confirm_panel()
			get_viewport().set_input_as_handled() # [추가] 입력 삼키기
		return

	# [추가] 상점에 물건이 하나도 없을 때 에러 방지용 방어막
	if current_stock_list.is_empty():
		if event.is_action_pressed("ui_cancel") or event.is_action_pressed("attack"):
			close_shop()
			get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("ui_down"):
		selected_index = (selected_index + 1) % current_stock_list.size()
		_update_selection_ui()
		get_viewport().set_input_as_handled() # [추가] 입력 삼키기
		
	elif event.is_action_pressed("ui_up"):
		# ⭐ [수정] shop_item_ids 잔재를 current_stock_list 로 변경!
		selected_index = (selected_index - 1 + current_stock_list.size()) % current_stock_list.size()
		_update_selection_ui()
		get_viewport().set_input_as_handled() # [추가] 입력 삼키기
		
	elif event.is_action_pressed("ui_accept"): 
		open_confirm_panel()
		get_viewport().set_input_as_handled() # [추가] 입력 삼키기
		
	elif event.is_action_pressed("ui_cancel") or event.is_action_pressed("attack"):
		close_shop()
		get_viewport().set_input_as_handled() # [추가] 입력 삼키기

# --- 3. 아이템 목록 UI 동적 생성 ---
func _create_item_slots():
	for i in range(current_stock_list.size()):
		var item_data = current_stock_list[i]
		var item_id = item_data["id"]
		var stock = item_data["stock"] # 남은 수량
		
		var item_resource = GameManager.get_item_by_id(item_id)
		if item_resource == null: continue
			
		var slot = ColorRect.new()
		slot.custom_minimum_size = Vector2(300, 40) # 글자가 길어지니 너비를 살짝 늘림
		
		var hbox = HBoxContainer.new()
		hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
		hbox.alignment = BoxContainer.ALIGNMENT_CENTER
		hbox.add_theme_constant_override("separation", 15)
		slot.add_child(hbox)
		
		var icon_rect = TextureRect.new()
		if "icon" in item_resource and item_resource.icon != null:
			icon_rect.texture = item_resource.icon
		icon_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.custom_minimum_size = Vector2(30, 30)
		hbox.add_child(icon_rect)
		
		var label = Label.new()
		# [핵심] 텍스트에 남은 수량(stock)을 함께 표시합니다!
		var stock_text = "Sold out" if stock <= 0 else str(stock) + " remain"
		label.text = item_resource.name + " [" + str(item_resource.price) + "G] - " + stock_text
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
		slot.color = Color(0.4, 0.4, 0.4) if i == selected_index else Color(0.1, 0.1, 0.1)
			
	if current_stock_list.is_empty(): return
	
	var item_id = current_stock_list[selected_index]["id"]
	var item_resource = GameManager.get_item_by_id(item_id)
	
	if item_resource:
		name_label.text = item_resource.name
		desc_label.text = item_resource.description
		price_label.text = "My Gold: " + str(GameManager.gold) + " G\n\nPrice: " + str(item_resource.price) + " G"

# --- 6. 구매 확인창 로직 ---
func open_confirm_panel():
	if current_stock_list.is_empty(): return
	
	is_confirming = true
	var item_data = current_stock_list[selected_index]
	var item_resource = GameManager.get_item_by_id(item_data["id"])
	
	# [핵심 방어막] 이미 품절이라면 아예 못 사게 막기!
	if item_data["stock"] <= 0:
		confirm_msg.text = "[ " + item_resource.name + " ]\n\nOut of stock.\n\n(ESC : Exit)"
	else:
		confirm_msg.text = "[ " + item_resource.name + " ]\n" + str(item_resource.price) + "Gold to purchase this item?\n\n(Enter : purchase / ESC: Cancel)"
	
	confirm_panel.show()

# --- [핵심] GameManager 연동 구매 로직 ---
func buy_item():
	var item_data = current_stock_list[selected_index]
	
	# 품절 상태에서 엔터 눌렀을 땐 그냥 확인창만 닫아줌
	if item_data["stock"] <= 0:
		close_confirm_panel()
		return
		
	var item_resource = GameManager.get_item_by_id(item_data["id"])
	if item_resource == null: return
	
	var price = item_resource.price

	if GameManager.gold >= price:
		var is_added = GameManager.add_item(item_resource)
		
		if is_added:
			GameManager.update_gold(-price)
			# [핵심] 재고 1개 감소!!
			item_data["stock"] -= 1 
			bought_something = true 
			
			close_confirm_panel()
			
			# UI를 지웠다가 다시 그려서 남은 수량 텍스트를 즉시 갱신합니다.
			for child in item_list.get_children():
				child.queue_free()
			_create_item_slots()
			await get_tree().process_frame
			
			_update_selection_ui()
			
		else:
			confirm_msg.text = "Inventory is full.\n\n(ESC: Cancel)"
	else:
		confirm_msg.text = "Not enough Gold!\n\n(ESC: Cancel)"
