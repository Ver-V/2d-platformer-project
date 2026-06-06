# HUD.gd
extends CanvasLayer

@onready var Restart_Label: Label = $Control/RestartLabel
@onready var heart_container: HBoxContainer = $Control/HeartContainer
@onready var hide_timer: Timer = $HideTimer
@onready var ui_root: Control = $Control
@onready var gold_label: Label = $Control/GoldLabel
@onready var interact_label: Label = $Control/InteractLabel
@onready var save_panel: HBoxContainer = $Control/SavePanel
@onready var minimap_container = $Control/MinimapContainer

var fade_tween: Tween
var heart_scene: PackedScene = preload("res://Scenes/System/HeartIcon.tscn")
const HP_PER_HEART = 20

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
	_setup_ui()

func _input(event):
	if event.is_action_pressed("toggle_map"):
		minimap_container.visible = !minimap_container.visible
		if minimap_container.visible:
			show_hud_temporarily()
			hide_timer.stop()
		else:
			hide_timer.start()

func show_death_screen() -> void:
	if Restart_Label:
		Restart_Label.show()
	visible = true
	ui_root.modulate.a = 1.0
	hide_timer.stop()

	# [추가] 화면을 어둡게 만드는 이펙트 (동적 생성)
	var darken_rect = ColorRect.new()
	darken_rect.color = Color(0, 0, 0, 0) # 처음엔 투명하게
	darken_rect.set_anchors_preset(Control.PRESET_FULL_RECT) # 전체 화면 덮기
	darken_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	darken_rect.name = "DeathDarkenRect"
	add_child(darken_rect)

	# z_index를 높여서 다른 UI 위로 올라오게 함 (Restart Label 보다는 아래일 수 있음)
	darken_rect.z_index = -1

	# 트윈으로 서서히 어두워지는 애니메이션 (4초 동안)
	var tween = create_tween()
	tween.tween_property(darken_rect, "color:a", 0.7, 3.0).set_trans(Tween.TRANS_QUAD)

func hide_death_screen() -> void:
	if Restart_Label:
		Restart_Label.hide()

	# 어두워진 이펙트 제거
	var darken_rect = get_node_or_null("DeathDarkenRect")
	if darken_rect:
		darken_rect.queue_free()

func show_hud_temporarily():
	# 메인 메뉴 등 BaseStage가 없는 씬에서는 표시하지 않음
	if not get_tree().current_scene is BaseStage:
		visible = false
		return

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
	show_hud_temporarily()

func draw_hearts(current_hp: int, max_hp: int) -> void:
	var total_hearts = ceili(float(max_hp) / HP_PER_HEART)

	if heart_container.get_child_count() != total_hearts:
		for child in heart_container.get_children():
			heart_container.remove_child(child)
			child.queue_free()
		
		for i in range(total_hearts):
			var heart = heart_scene.instantiate()
			heart_container.add_child(heart)
	
	var hearts = heart_container.get_children()
	for i in range(hearts.size()):
		var heart_range_start = i * HP_PER_HEART
		var heart_value = clampi(current_hp - heart_range_start, 0, HP_PER_HEART)
		hearts[i].update_visual(heart_value)

func _on_gold_changed(amount: int) -> void:
	if gold_label: gold_label.text = " %d" % amount
	show_hud_temporarily()

func _on_interact_msg(msg: String) -> void:
	if not get_tree().current_scene is BaseStage: return
	
	visible = true
	ui_root.modulate.a = 1.0
	
	if fade_tween and fade_tween.is_valid():
		fade_tween.kill()
	hide_timer.stop()
	
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
