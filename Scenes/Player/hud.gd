# HUD.gd
extends CanvasLayer

# 방금 만든 '그릇' (HBoxContainer)
@onready var heart_container: HBoxContainer = $HeartContainer

# 라벨들 경로
@onready var gold_label: Label = $Control/GoldLabel
@onready var interact_label: Label = $Control/InteractLabel

# 개별 하트 씬 (Control 노드로 된 파일)
var heart_scene: PackedScene = preload("res://Scenes/Player/HeartIcon.tscn")
const HP_PER_HEART = 20

func _ready() -> void:
	GameManager.hp_changed.connect(_on_hp_changed)
	GameManager.gold_changed.connect(_on_gold_changed)
	GameManager.interact_msg_requested.connect(_on_interact_msg)
	GameManager.interact_msg_hidden.connect(_on_interact_hide)
	
	call_deferred("_setup_ui")
	
	visible = false

func _setup_ui() -> void:
	draw_hearts(GameManager.player_current_hp, GameManager.player_max_hp)
	_on_gold_changed(GameManager.gold)
	if interact_label: interact_label.visible = false

func _on_hp_changed(current: int, max_hp: int) -> void:
	draw_hearts(current, max_hp)

func draw_hearts(current_hp: int, max_hp: int) -> void:
	var total_hearts = ceili(float(max_hp) / HP_PER_HEART)
	
	# 그릇 비우고 다시 채우기
	if heart_container.get_child_count() != total_hearts:
		for child in heart_container.get_children():
			child.queue_free()
		
		for i in range(total_hearts):
			var heart = heart_scene.instantiate()
			heart_container.add_child(heart) # 상자 안에 하트 넣기
	
	# 하트 상태 업데이트
	var hearts = heart_container.get_children()
	for i in range(hearts.size()):
		var heart_range_start = i * HP_PER_HEART
		var heart_value = clampi(current_hp - heart_range_start, 0, HP_PER_HEART)
		hearts[i].update_visual(heart_value)

# ... (골드, 상호작용 함수들은 기존 그대로) ...
func _on_gold_changed(amount: int) -> void:
	if gold_label: gold_label.text = " %d" % amount

func _on_interact_msg(msg: String) -> void:
	interact_label.visible = true

func _on_interact_hide() -> void:
	if interact_label: interact_label.visible = false
