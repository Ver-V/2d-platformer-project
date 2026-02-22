extends CanvasLayer

@onready var item_list = $MainPanel/HBox/ItemList
@onready var name_label = $MainPanel/HBox/InfoPanel/NameLabel
@onready var desc_label = $MainPanel/HBox/InfoPanel/DescLabel
@onready var price_label = $MainPanel/HBox/InfoPanel/PriceLabel
@onready var confirm_panel = $ConfirmPanel
@onready var confirm_msg = $ConfirmPanel/MsgLabel

# [수정됨] GameManager의 item_database와 연동하기 위해 "id" 항목을 추가했습니다.
# (나중에 이 부분도 리소스나 JSON으로 빼면 관리가 더 편해집니다.)
var shop_items = [
	{"id": "health_potion", "name": "체력 포션", "price": 50, "desc": "체력을 40 회복합니다."},
	# 아래는 예시입니다. GameManager의 item_database에 ID와 리소스 경로를 추가해야 작동합니다.
	# {"id": "iron_sword", "name": "철검", "price": 300, "desc": "공격력이 소폭 상승하는 기본 검입니다."}, 
	# {"id": "rabbit_slippers", "name": "토끼 슬리퍼", "price": 500, "desc": "이동 속도가 증가합니다."}
]

var selected_index: int = 0
var is_open: bool = false
var is_confirming: bool = false

func _ready():
	hide()
	confirm_panel.hide()
	_create_item_slots()

# --- 1. 상점 열고 닫기 ---
func open_shop():
	is_open = true
	is_confirming = false
	selected_index = 0
	confirm_panel.hide()
	show()
	_update_selection_ui()
	
	get_tree().paused = true
	# CustomCursor.show_cursor() # 만든 커서 스크립트 호출

func close_shop():
	is_open = false
	hide()
	get_tree().paused = false
	# CustomCursor.hide_cursor()

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
		selected_index = (selected_index + 1) % shop_items.size()
		_update_selection_ui()
	elif event.is_action_pressed("ui_up"):
		selected_index = (selected_index - 1 + shop_items.size()) % shop_items.size()
		_update_selection_ui()
	elif event.is_action_pressed("interact"):
		open_confirm_panel()
	elif event.is_action_pressed("ui_cancel"):
		close_shop()

# --- 3. 아이템 목록 UI 동적 생성 ---
func _create_item_slots():
	for i in range(shop_items.size()):
		var item = shop_items[i]
		
		var slot = ColorRect.new()
		slot.custom_minimum_size = Vector2(250, 40)
		
		var label = Label.new()
		label.text = item["name"] + "   [" + str(item["price"]) + "G]"
		label.set_anchors_preset(Control.PRESET_FULL_RECT)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slot.add_child(label)
		
		slot.mouse_entered.connect(_on_slot_mouse_entered.bind(i))
		slot.gui_input.connect(_on_slot_gui_input.bind(i))
		
		item_list.add_child(slot)

# --- 4. 마우스 이벤트 연결 ---
func _on_slot_mouse_entered(index: int):
	if not is_confirming:
		selected_index = index
		_update_selection_ui()

func _on_slot_gui_input(event: InputEvent, index: int):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if not is_confirming:
			selected_index = index
			_update_selection_ui()
			open_confirm_panel()

# --- 5. 선택된 아이템 시각적 강조 ---
func _update_selection_ui():
	for i in range(item_list.get_child_count()):
		var slot = item_list.get_child(i)
		if i == selected_index:
			slot.color = Color(0.4, 0.4, 0.4)
		else:
			slot.color = Color(0.1, 0.1, 0.1)
			
	var item = shop_items[selected_index]
	name_label.text = item["name"]
	desc_label.text = item["desc"]
	price_label.text = "보유 골드: " + str(GameManager.gold) + " G\n\n가격: " + str(item["price"]) + " G"

# --- 6. 구매 확인창 로직 ---
func open_confirm_panel():
	is_confirming = true
	var item = shop_items[selected_index]
	confirm_msg.text = "[ " + item["name"] + " ]\n" + str(item["price"]) + "G 에 구매하시겠습니까?\n\n(E 키: 구매 확정 / ESC: 취소)"
	confirm_panel.show()

func close_confirm_panel():
	is_confirming = false
	confirm_panel.hide()

# --- [핵심] GameManager 연동 구매 로직 ---
func buy_item():
	var item_info = shop_items[selected_index]
	var price = item_info["price"]
	var item_id = item_info["id"]

	# 1. 골드 확인
	if GameManager.gold >= price:
		
		# 2. 아이템 데이터 가져오기
		var item_resource = GameManager.get_item_by_id(item_id)
		
		if item_resource != null:
			# 3. 인벤토리에 아이템 추가 시도
			var is_added = GameManager.add_item(item_resource)
			
			if is_added:
				# 4. 구매 성공: 골드 차감 (-금액)
				GameManager.update_gold(-price)
				print(item_info["name"] + " 구매 완료!")
				
				# 구매 성공 후 골드 UI 갱신을 위해 선택 UI 한번 더 업데이트
				_update_selection_ui() 
				close_confirm_panel()
			else:
				# 인벤토리 꽉 참
				confirm_msg.text = "인벤토리가 가득 찼습니다!\n\n(ESC: 취소)"
		else:
			push_error("GameManager에 존재하지 않는 아이템 ID입니다: " + item_id)
			confirm_msg.text = "아이템 데이터를 불러올 수 없습니다.\n\n(ESC: 취소)"
	else:
		# 골드 부족
		confirm_msg.text = "골드가 부족합니다!\n\n(ESC: 취소)"
