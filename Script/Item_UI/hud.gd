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
const BOSS_BAR_SIZE := Vector2(260.0, 18.0)
const BOSS_BAR_TOP := 8.0

var boss_target: EnemyBase = null
var boss_bar_root: Control = null
var boss_bar_fill: ColorRect = null
var boss_bar_label: Label = null

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
	_setup_boss_health_bar()
	_setup_ui()

func _input(event):
	if event.is_action_pressed("toggle_map"):
		minimap_container.visible = !minimap_container.visible
		if minimap_container.visible:
			show_hud_temporarily()
			hide_timer.stop()
		else:
			hide_timer.start()

func _process(_delta: float) -> void:
	if boss_target == null:
		return
	if not is_instance_valid(boss_target) or boss_target.hp <= 0:
		hide_boss_health()
		return
	_update_boss_health_bar()

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
	fade_tween.tween_callback(func():
		if not _is_boss_health_visible():
			visible = false
	)

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

func show_boss_health(boss: EnemyBase) -> void:
	if boss == null or not is_instance_valid(boss):
		hide_boss_health()
		return
	
	boss_target = boss
	if boss_bar_root:
		boss_bar_root.visible = true
	visible = true
	_update_boss_health_bar()

func hide_boss_health(boss: EnemyBase = null) -> void:
	if boss != null and boss_target != boss:
		return
	
	boss_target = null
	if boss_bar_root:
		boss_bar_root.visible = false
	if ui_root.modulate.a <= 0.01 and not minimap_container.visible and (Restart_Label == null or not Restart_Label.visible):
		visible = false

func _setup_boss_health_bar() -> void:
	boss_bar_root = Control.new()
	boss_bar_root.name = "BossHealthBar"
	boss_bar_root.visible = false
	boss_bar_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	boss_bar_root.anchor_left = 0.5
	boss_bar_root.anchor_right = 0.5
	boss_bar_root.anchor_top = 0.0
	boss_bar_root.anchor_bottom = 0.0
	boss_bar_root.offset_left = -BOSS_BAR_SIZE.x * 0.5
	boss_bar_root.offset_right = BOSS_BAR_SIZE.x * 0.5
	boss_bar_root.offset_top = BOSS_BAR_TOP
	boss_bar_root.offset_bottom = BOSS_BAR_TOP + BOSS_BAR_SIZE.y
	add_child(boss_bar_root)
	
	var bg := ColorRect.new()
	bg.name = "Background"
	bg.color = Color.BLACK
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	boss_bar_root.add_child(bg)
	
	boss_bar_fill = ColorRect.new()
	boss_bar_fill.name = "Fill"
	boss_bar_fill.color = Color(0.9, 0.05, 0.05, 1.0)
	boss_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	boss_bar_fill.offset_left = 2.0
	boss_bar_fill.offset_top = 2.0
	boss_bar_fill.offset_bottom = BOSS_BAR_SIZE.y - 2.0
	boss_bar_root.add_child(boss_bar_fill)
	
	boss_bar_label = Label.new()
	boss_bar_label.name = "ValueLabel"
	boss_bar_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	boss_bar_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_bar_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	boss_bar_label.add_theme_color_override("font_color", Color.WHITE)
	boss_bar_label.add_theme_font_size_override("font_size", 8)
	boss_bar_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	boss_bar_root.add_child(boss_bar_label)

func _update_boss_health_bar() -> void:
	if boss_target == null or boss_bar_fill == null or boss_bar_label == null:
		return
	
	var max_value: int = max(1, boss_target.max_hp)
	var current_value: int = clampi(boss_target.hp, 0, max_value)
	var ratio: float = clampf(float(current_value) / float(max_value), 0.0, 1.0)
	
	boss_bar_fill.offset_right = 2.0 + (BOSS_BAR_SIZE.x - 4.0) * ratio
	boss_bar_label.text = "%d / %d" % [current_value, max_value]

func _is_boss_health_visible() -> bool:
	return boss_bar_root != null and boss_bar_root.visible
