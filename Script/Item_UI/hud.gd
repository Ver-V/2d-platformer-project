# HUD.gd
extends CanvasLayer

@onready var Restart_Label: Label = $Control/RestartLabel
# 방금 만든 '그릇' (HBoxContainer)
@onready var heart_container: HBoxContainer = $Control/HeartContainer
@onready var hide_timer: Timer = $HideTimer
@onready var ui_root: Control = $Control
# 라벨들 경로
@onready var gold_label: Label = $Control/GoldLabel
@onready var interact_label: Label = $Control/InteractLabel
@onready var save_panel: HBoxContainer = $Control/SavePanel
@onready var minimap_container = $Control/MinimapContainer

var fade_tween: Tween
# 개별 하트 씬 (Control 노드로 된 파일)
var heart_scene: PackedScene = preload("res://Scenes/System/HeartIcon.tscn")
const HP_PER_HEART = 20

func _input(event):
	if event.is_action_pressed("toggle_map"):
		minimap_container.visible = !minimap_container.visible
		if minimap_container.visible:
			show_hud_temporarily()
			hide_timer.stop()
		else:
			hide_timer.start()
		
func _ready() -> void:
	GameManager.hp_changed.connect(_on_hp_changed)
	GameManager.gold_changed.connect(_on_gold_changed)
	GameManager.interact_msg_requested.connect(_on_interact_msg)
	GameManager.interact_msg_hidden.connect(_on_interact_hide)
	
	if Restart_Label:
		Restart_Label.hide()
		
	minimap_container.visible = false
	
	ui_root.modulate.a = 0.0
	visible = false
	
	hide_timer.timeout.connect(_on_hide_timer_timeout)
	
	call_deferred("_setup_ui")
	
	visible = false

func show_death_screen() -> void:
	if Restart_Label:
		Restart_Label.show()
		
	visible = true
	ui_root.modulate.a = 1.0
	hide_timer.stop()
	
func hide_death_screen() -> void:
	if Restart_Label:
		Restart_Label.hide()
		
		
func show_hud_temporarily():
	visible = true
	ui_root.modulate.a = 1.0
	
	if fade_tween and fade_tween.is_valid():
		fade_tween.kill()
	
	if not minimap_container.visible:
		hide_timer.start()

func _on_hide_timer_timeout():
	if minimap_container.visible:
		return
		
	fade_tween = create_tween()

	fade_tween.tween_property(ui_root, "modulate:a", 0.0, 1.5)

	fade_tween.tween_callback(func(): visible = false)

func _setup_ui() -> void:
	draw_hearts(GameManager.player_current_hp, GameManager.player_max_hp)
	_on_gold_changed(GameManager.gold)
	if interact_label: interact_label.visible = false
	if save_panel: save_panel.visible = false
	
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
	show_hud_temporarily()

func _on_interact_msg(msg: String) -> void:
	visible = true
	ui_root.modulate.a = 1.0
	
	if fade_tween and fade_tween.is_valid():
		fade_tween.kill()
	hide_timer.stop()     # 타이머 정지
	
	if msg == "save_mode":
		if save_panel: save_panel.visible = true
		if interact_label: interact_label.visible = false
	
	else:
		if interact_label: interact_label.visible = true
		if save_panel: save_panel.visible = false

func _on_interact_hide() -> void:
	if interact_label: interact_label.visible = false
	if save_panel: save_panel.visible = false
	
	hide_timer.start()
