extends CanvasLayer

@onready var grid: GridContainer = $Control/TextureRect/GridContainer
@onready var gold_label: Label = $Control/TextureRect/Panel/HBoxContainer/VBoxContainer/GoldLabel
@onready var hp_label: Label = $Control/TextureRect/Panel/HBoxContainer/VBoxContainer/HpLabel
@onready var atk_label: Label = $Control/TextureRect/Panel/HBoxContainer/VBoxContainer/AtkLabel
@onready var pd_label: Label = $Control/TextureRect/Panel/HBoxContainer/VBoxContainer/ParryDmgLabel

# [새로 추가] 액션 메뉴 관련 노드 연결
@onready var action_menu: PanelContainer = $ActionMenu
@onready var btn_use: Button = $ActionMenu/VBoxContainer/BtnUse
@onready var btn_close: Button = $ActionMenu/VBoxContainer/BtnClose

var is_open: bool = false
var selected_index: int = -1 # [새로 추가] 클릭한 슬롯 번호 기억용

func _ready():
	var slots = grid.get_children()
	
	for i in range(slots.size()):
		var slot = slots[i]
		if not slot.slot_clicked.is_connected(_on_slot_clicked):
			slot.slot_clicked.connect(_on_slot_clicked.bind(i))
	
	# [새로 추가] 팝업 버튼 시그널 연결 및 숨기기
	btn_use.pressed.connect(_on_use_pressed)
	btn_close.pressed.connect(_on_close_pressed)
	action_menu.hide()
	
	close()
	
func _process(_float) -> void:
	if is_open:
		update_ui()

func _input(event):
	if event.is_action_pressed("inventory"):
		if is_open:
			close()
		else:
			open()

func open():
	visible = true
	is_open = true
	selected_index = -1 # 열 때 선택 초기화
	action_menu.hide()  # 열 때 팝업 무조건 숨김
	
	update_ui()
	CustomCursor.show_cursor()
	
func close():
	visible = false
	is_open = false
	action_menu.hide() # 닫을 때 팝업도 같이 닫기
	CustomCursor.hide_cursor()

func update_ui():
	# --- 정보 갱신 ---
	gold_label.text = "Gold : " + str(GameManager.gold)
	hp_label.text = "HP: %d / %d" % [GameManager.player_current_hp, GameManager.player_max_hp]
	atk_label.text = "Dmg : " + str(GameManager.player_damage)
	pd_label.text = "Parry dmg Mult: x %.1f" % GameManager.player_parry_damage_multifac
	
	# --- 아이템 슬롯 갱신 ---
	var slots = grid.get_children()
	for i in range(slots.size()):
		if i < GameManager.inventory.size():
			slots[i].set_item(GameManager.inventory[i])
		else:
			slots[i].set_item(null)

# --- [수정됨] 슬롯 클릭 시 팝업 띄우기 ---
func _on_slot_clicked(index):
	print("클릭된 슬롯 번호: ", index)
	
	if index >= GameManager.inventory.size(): return

	var item = GameManager.inventory[index]
	
	# 디버그용: 아이템이 정말 들어있는지 콘솔에 출력해 봅니다.
	print("슬롯에 있는 아이템 데이터: ", item) 
	
	if item != null:
		selected_index = index
		
		# [수정 1] 마우스 좌표 대신, 클릭한 슬롯 노드의 위치를 기준으로 띄웁니다.
		# (해상도/카메라 스케일 때문에 마우스 좌표가 엉뚱한 곳을 가리키는 현상 방지)
		var clicked_slot = grid.get_child(index)
		action_menu.global_position = clicked_slot.global_position + Vector2(20, 20)
		
		# [수정 2] 팝업이 다른 UI 배경에 가려지지 않도록 Z-Index를 강제로 100으로 확 끌어올립니다.
		action_menu.z_index = 100 
		
		action_menu.show()
	else:
		action_menu.hide()

# --- [새로 추가] '사용' 버튼 눌렀을 때 ---
func _on_use_pressed():
	if selected_index == -1: return
	
	var item = GameManager.inventory[selected_index]
	var player = get_tree().get_first_node_in_group("player")
	
	# 기존에 _on_slot_clicked에 있던 로직을 이쪽으로 이사시켰습니다.
	if player and item.has_method("use"):
		item.use(player)
		GameManager.inventory[selected_index] = null # 사용 후 삭제
		update_ui()
	
	# 사용 완료 후 팝업 닫기 및 선택 초기화
	action_menu.hide()
	selected_index = -1

# --- [새로 추가] '닫기' 버튼 눌렀을 때 ---
func _on_close_pressed():
	action_menu.hide()
	selected_index = -1

func _on_button_pressed() -> void:
	close()
