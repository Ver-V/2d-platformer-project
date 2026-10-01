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
	GameManager.locale_changed.connect(_on_locale_changed)

# --- 상점 열고 닫기 ---
func open_shop(shop_id: String = "Stage1"): # 인자 받기
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
	_clear_item_slots()
		
	show()
	_create_item_slots() # 목록 생성
	_update_selection_ui()
	GameManager.ui_opened(self)
	
func close_shop():
	if not is_open:
		return
	is_open = false
	hide()
	GameManager.ui_closed(self)
	shop_closed.emit(bought_something)

func close_confirm_panel():
	is_confirming = false
	confirm_panel.hide()

func _clear_item_slots() -> void:
	for child in item_list.get_children():
		child.free()

func _on_locale_changed(_new_locale: String) -> void:
	if not is_open:
		return

	_clear_item_slots()
	_create_item_slots()
	_update_selection_ui()
	if is_confirming:
		_update_confirm_message()

# --- 입력 처리 ---
func _input(event):
	if not is_open: return

	if is_confirming:
		if event.is_action_pressed("ui_accept"): 
			buy_item()
			get_viewport().set_input_as_handled() # 입력 삼키기
		elif event.is_action_pressed("ui_cancel") or event.is_action_pressed("attack"):
			close_confirm_panel()
			get_viewport().set_input_as_handled() # 입력 삼키기
		return

	# 상점에 물건이 하나도 없을 때 에러 방지용 방어막
	if current_stock_list.is_empty():
		if event.is_action_pressed("ui_cancel") or event.is_action_pressed("attack"):
			close_shop()
			get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("ui_down"):
		selected_index = (selected_index + 1) % current_stock_list.size()
		_update_selection_ui()
		get_viewport().set_input_as_handled() # 입력 삼키기
		
	elif event.is_action_pressed("ui_up"):
		# hop_item_ids 잔재를 current_stock_list 로 변경!
		selected_index = (selected_index - 1 + current_stock_list.size()) % current_stock_list.size()
		_update_selection_ui()
		get_viewport().set_input_as_handled() # 입력 삼키기
		
	elif event.is_action_pressed("ui_accept"): 
		open_confirm_panel()
		get_viewport().set_input_as_handled() # 입력 삼키기
		
	elif event.is_action_pressed("ui_cancel") or event.is_action_pressed("attack"):
		close_shop()
		get_viewport().set_input_as_handled() # 입력 삼키기

# --- 아이템 목록 UI 동적 생성 ---
func _create_item_slots():
	for i in range(current_stock_list.size()):
		var item_data = current_stock_list[i]
		var item_id = item_data["id"]
		var stock = item_data["stock"] # 남은 수량
		
		var item_resource = GameManager.get_item_by_id(item_id)
		if item_resource == null: continue
			
		var slot = ColorRect.new()
		slot.custom_minimum_size = Vector2(300, 40)
		
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
		# 텍스트에 남은 stock을 함께 표시합니다!
		var stock_text := tr(&"SHOP_SOLD_OUT") if stock <= 0 else tr(&"SHOP_STOCK_REMAINING").format({
			"count": int(stock)
		})
		label.text = tr(&"SHOP_ITEM_ROW").format({
			"name": tr(item_resource.name),
			"price": item_resource.price,
			"stock": stock_text
		})
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
			GameManager.play_ui_click() # [추가] 클릭 소리
			selected_index = index
			_update_selection_ui()
			open_confirm_panel()
			
# --- 선택된 아이템 시각적 강조 및 정보 표시 ---
func _update_selection_ui():
	for i in range(item_list.get_child_count()):
		var slot = item_list.get_child(i)
		slot.color = Color(0.4, 0.4, 0.4) if i == selected_index else Color(0.1, 0.1, 0.1)
			
	if current_stock_list.is_empty(): return
	
	var item_id = current_stock_list[selected_index]["id"]
	var item_resource = GameManager.get_item_by_id(item_id)
	
	if item_resource:
		name_label.text = tr(item_resource.name)
		desc_label.text = tr(item_resource.description)
		price_label.text = "%s\n\n%s" % [
			tr(&"SHOP_MY_GOLD").format({"gold": GameManager.gold}),
			tr(&"SHOP_PRICE").format({"price": item_resource.price})
		]

# --- 구매 확인창 로직 ---
func open_confirm_panel():
	if current_stock_list.is_empty(): return
	
	is_confirming = true
	_update_confirm_message()
	confirm_panel.show()

func _update_confirm_message() -> void:
	if current_stock_list.is_empty():
		return

	var item_data = current_stock_list[selected_index]
	var item_resource = GameManager.get_item_by_id(item_data["id"])
	if item_resource == null:
		return

	var item_name := tr(item_resource.name)
	
	# 이미 품절이라면 아예 못 사게 막기!
	if item_data["stock"] <= 0:
		confirm_msg.text = "[ %s ]\n\n%s\n\n%s" % [
			item_name,
			tr(&"SHOP_OUT_OF_STOCK"),
			tr(&"SHOP_EXIT_HINT")
		]
	else:
		confirm_msg.text = "[ %s ]\n%s\n\n%s" % [
			item_name,
			tr(&"SHOP_PURCHASE_QUESTION").format({"price": item_resource.price}),
			tr(&"SHOP_PURCHASE_HINT")
		]

# --- GameManager 연동 구매 로직 ---
func buy_item():
	var item_data = current_stock_list[selected_index]

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
			# 재고 1개 감소
			item_data["stock"] -= 1 
			bought_something = true 
			
			close_confirm_panel()
			
			# UI를 지웠다가 다시 그려서 남은 수량 텍스트를 즉시 갱신
			_clear_item_slots()
			_create_item_slots()
			await get_tree().process_frame
			
			_update_selection_ui()
			
		else:
			confirm_msg.text = "%s\n\n%s" % [tr(&"SHOP_INVENTORY_FULL"), tr(&"SHOP_CANCEL_HINT")]
	else:
		confirm_msg.text = "%s\n\n%s" % [tr(&"SHOP_NOT_ENOUGH_GOLD"), tr(&"SHOP_CANCEL_HINT")]
