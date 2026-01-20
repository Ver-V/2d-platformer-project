extends CanvasLayer

@onready var grid: GridContainer = $Control/TextureRect/GridContainer
# [경로 확인 필수] 본인 씬 트리에 맞춰서 수정하세요
@onready var gold_label: Label = $Control/TextureRect/Panel/HBoxContainer/VBoxContainer/GoldLabel
@onready var hp_label: Label = $Control/TextureRect/Panel/HBoxContainer/VBoxContainer/HpLabel
@onready var atk_label: Label = $Control/TextureRect/Panel/HBoxContainer/VBoxContainer/AtkLabel
@onready var pd_label: Label = $Control/TextureRect/Panel/HBoxContainer/VBoxContainer/ParryDmgLabel

var is_open: bool = false

func _ready():
	var slots = grid.get_children()
	
	for i in range(slots.size()):
		var slot = slots[i]
		
		# 슬롯의 'slot_clicked' 신호를 내 함수 '_on_slot_clicked'에 연결
		# .bind(i)는 "이게 몇 번째(i) 슬롯인지" 정보를 함께 넘겨주는 기능입니다.
		if not slot.slot_clicked.is_connected(_on_slot_clicked):
			slot.slot_clicked.connect(_on_slot_clicked.bind(i))
	
	close()
	
func _process(_float) -> void:
	update_ui()

func _input(event):
	# 인풋 맵에 등록한 "inventory" 키가 눌렸을 때
	if event.is_action_pressed("inventory"):
		if is_open:
			close()
		else:
			open()

func open():
	visible = true
	is_open = true
	
	update_ui() # 켜면서 데이터 갱신
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
func close():
	visible = false
	is_open = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

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

# 슬롯 클릭 연결 함수 (Slot 씬에서 시그널 연결이 필요할 수 있음)
func _on_slot_clicked(index):
	print("클릭된 슬롯 번호: ", index) # 확인용
	
	if index >= GameManager.inventory.size(): return

	var item = GameManager.inventory[index]
	if item != null:
		var player = get_tree().get_first_node_in_group("player")
		
		# 아이템 사용 (ItemData에 use 함수가 있다고 가정)
		# 만약 item이 Dictionary라면 스크립트를 로드해서 함수를 부르는 등 별도 처리가 필요할 수 있음
		if player and item.has_method("use"):
			item.use(player)
			GameManager.inventory[index] = null # 사용 후 삭제
			update_ui()



func _on_button_pressed() -> void:
	close()
