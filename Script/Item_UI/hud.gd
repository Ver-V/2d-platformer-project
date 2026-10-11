# HUD.gd
extends CanvasLayer

@onready var Restart_Label: Label = $Control/RestartLabel
@onready var heart_container: HBoxContainer = $Control/HeartContainer
@onready var hide_timer: Timer = $HideTimer
@onready var ui_root: Control = $Control
@onready var gold_label: Label = $Control/GoldLabel
@onready var interact_label: Control = $Control/InteractPrompt # 키 아이콘 + 번역 문구(HUD_INTERACT)
@onready var interact_text: Label = $Control/InteractPrompt/InteractLabel # 안내 문구 (번역 키를 그대로 넣으면 자동 번역)
@onready var save_panel: HBoxContainer = $Control/SavePanel
@onready var minimap_container = $Control/MinimapContainer
@onready var damage_vignette: ColorRect = get_node_or_null("DamageVignette") as ColorRect

const DAMAGE_VIGNETTE_SHADER := """
shader_type canvas_item;
render_mode unshaded;

uniform float strength = 0.0;

void fragment() {
	vec2 from_center = (UV - vec2(0.5)) * 2.0;
	float edge = smoothstep(0.55, 1.15, length(from_center * vec2(1.0, 0.8)));
	COLOR = vec4(0.72, 0.025, 0.035, edge * strength);
}
"""
const DAMAGE_VIGNETTE_HOLD_MS: int = 500
const DAMAGE_VIGNETTE_FADE_MS: int = 250

# 상태이상(독 등)이 걸려 있는 동안 화면 가장자리를 해당 색으로 은은하게 점멸시킨다
const STATUS_TINT_SHADER := """
shader_type canvas_item;
render_mode unshaded;

uniform float strength = 0.0;
uniform vec3 tint = vec3(0.55, 0.1, 0.8);

void fragment() {
	vec2 from_center = (UV - vec2(0.5)) * 2.0;
	float edge = smoothstep(0.5, 1.15, length(from_center * vec2(1.0, 0.8)));
	COLOR = vec4(tint, edge * strength);
}
"""
const STATUS_TINT_MAX_STRENGTH: float = 0.16
const STATUS_TINT_MIN_STRENGTH: float = 0.04
const STATUS_TINT_PERIOD_SEC: float = 1.4

var _damage_vignette_material: ShaderMaterial
var _damage_vignette_start_ms: int = -1
var _damage_vignette_strength: float = 0.0

var status_tint_rect: ColorRect
var _status_tint_material: ShaderMaterial
var _status_tints: Dictionary = {} # 상태이상 id -> Color (나중에 걸린 것이 표시됨)

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
	_setup_damage_vignette()
	_setup_status_tint()
	_setup_boss_health_bar()
	_setup_pickup_log()
	_setup_ui()

func _setup_damage_vignette() -> void:
	if damage_vignette == null:
		return
	var shader := Shader.new()
	shader.code = DAMAGE_VIGNETTE_SHADER
	_damage_vignette_material = ShaderMaterial.new()
	_damage_vignette_material.shader = shader
	damage_vignette.material = _damage_vignette_material
	damage_vignette.color = Color.WHITE
	damage_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	damage_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	damage_vignette.z_index = -1
	damage_vignette.hide()

func show_damage_vignette(current_hp: int, maximum_hp: int) -> void:
	if damage_vignette == null or _damage_vignette_material == null:
		return
	var health_ratio := clampf(float(current_hp) / float(maxi(maximum_hp, 1)), 0.0, 1.0)
	_damage_vignette_strength = lerpf(0.22, 0.12, health_ratio)
	_damage_vignette_start_ms = Time.get_ticks_msec()
	_damage_vignette_material.set_shader_parameter("strength", _damage_vignette_strength)
	damage_vignette.show()

func _update_damage_vignette() -> void:
	if _damage_vignette_start_ms < 0 or damage_vignette == null:
		return
	var elapsed_ms := Time.get_ticks_msec() - _damage_vignette_start_ms
	if elapsed_ms < DAMAGE_VIGNETTE_HOLD_MS:
		return
	if elapsed_ms >= DAMAGE_VIGNETTE_HOLD_MS + DAMAGE_VIGNETTE_FADE_MS:
		_damage_vignette_start_ms = -1
		_damage_vignette_material.set_shader_parameter("strength", 0.0)
		damage_vignette.hide()
		return
	var fade_progress := float(elapsed_ms - DAMAGE_VIGNETTE_HOLD_MS) / float(DAMAGE_VIGNETTE_FADE_MS)
	_damage_vignette_material.set_shader_parameter("strength", _damage_vignette_strength * (1.0 - fade_progress))

func _setup_status_tint() -> void:
	var shader := Shader.new()
	shader.code = STATUS_TINT_SHADER
	_status_tint_material = ShaderMaterial.new()
	_status_tint_material.shader = shader
	status_tint_rect = ColorRect.new()
	status_tint_rect.name = "StatusTint"
	status_tint_rect.material = _status_tint_material
	status_tint_rect.color = Color.WHITE
	status_tint_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_tint_rect.z_index = -1
	add_child(status_tint_rect)
	# 피격 비네트가 위에 그려지도록 그 앞에 둔다
	if damage_vignette:
		move_child(status_tint_rect, damage_vignette.get_index())
	status_tint_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	status_tint_rect.hide()

func add_status_tint(id: StringName, color: Color) -> void:
	_status_tints.erase(id) # 다시 걸리면 맨 뒤(표시 대상)로
	_status_tints[id] = color
	_refresh_status_tint()

func remove_status_tint(id: StringName) -> void:
	_status_tints.erase(id)
	_refresh_status_tint()

func clear_status_tints() -> void:
	_status_tints.clear()
	_refresh_status_tint()

func _refresh_status_tint() -> void:
	if status_tint_rect == null:
		return
	if _status_tints.is_empty():
		status_tint_rect.hide()
		return
	var c: Color = _status_tints.values().back()
	_status_tint_material.set_shader_parameter("tint", Vector3(c.r, c.g, c.b))
	status_tint_rect.show()

func _update_status_tint() -> void:
	if status_tint_rect == null or not status_tint_rect.visible:
		return
	var t := Time.get_ticks_msec() / 1000.0
	var wave := 0.5 + 0.5 * sin(t * TAU / STATUS_TINT_PERIOD_SEC)
	_status_tint_material.set_shader_parameter("strength", lerpf(STATUS_TINT_MIN_STRENGTH, STATUS_TINT_MAX_STRENGTH, wave))

func _input(event):
	if event.is_action_pressed("toggle_map"):
		minimap_container.visible = !minimap_container.visible
		if minimap_container.visible:
			show_hud_temporarily()
			hide_timer.stop()
		else:
			hide_timer.start()

func _process(_delta: float) -> void:
	_update_pickup_log()
	_update_damage_vignette()
	_update_status_tint()
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
		if not _is_boss_health_visible() and not _has_pickups():
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
		# msg = 안내 번역 키 (문: KEY_DOOR_OPEN_PROMPT 등). 비우면 기본 ": 상호작용"
		if interact_text:
			interact_text.text = msg if msg != "" else "HUD_INTERACT"
		if interact_label:
			interact_label.visible = true
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
	# HUD CanvasLayer는 2배 스케일이라 바로 붙이면 1280x720 기준 중앙(화면상 오른쪽 끝)에 간다.
	# ui_root와 같은 크기(스케일 전 화면 크기)의 틀에 넣어 중앙을 맞춘다. ui_root는 페이드되므로 따로 둔다
	var holder := Control.new()
	holder.name = "BossBarLayer"
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.anchor_right = 1.0
	holder.anchor_bottom = 1.0
	holder.offset_right = ui_root.offset_right
	holder.offset_bottom = ui_root.offset_bottom
	add_child(holder)
	holder.add_child(boss_bar_root)
	
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

# -------------------------------------------------------------------------
# 획득 목록: 인벤토리·골드로 들어온 것(상자, 박스 드롭, 필드 아이템, 코인, 보스 보상, 상점 구매)을
# 왼쪽 위(골드 아래)에 한 줄씩 띄운다. 거의 동시에 들어온 것(PICKUP_GROUP_WINDOW 안)은 한 묶음으로 같이 떠오르고,
# 연달아 줍는 골드(PICKUP_GOLD_MERGE 안)는 한 줄로 합쳐 금액만 늘린다.
# 묶음마다 마지막으로 바뀐 뒤 pickup_lifetime초가 지나면 흐려지며 사라진다. HUD가 자동으로 숨는 중에도 끝까지 보인다
# -------------------------------------------------------------------------
const PICKUP_LOG_POS := Vector2(4.0, 40.0) # 골드 표시 바로 아래 (스케일 전 HUD 좌표)
const PICKUP_FONT_SIZE := 8
const PICKUP_RISE := 6.0 # 떠오르는 거리(px)
const PICKUP_MAX_GROUPS := 5 # 이보다 많으면 오래된 묶음부터 지운다
const PICKUP_GROUP_WINDOW := 0.3 # 이 시간(초) 안에 들어온 것은 같은 묶음
const PICKUP_GOLD_MERGE := 1.5 # 이 시간(초) 안에 들어온 골드는 한 줄로 합친다
const PICKUP_FADE := 0.5
var pickup_lifetime: float = 10.0
var pickup_log: VBoxContainer
var _pickup_settings: LabelSettings
var _pickup_group: Control = null # 지금 채우는 묶음
var _pickup_group_time: float = -INF
var _pickup_gold_label: Label = null # 합치는 중인 골드 줄
var _pickup_gold_total: int = 0
var _pickup_gold_time: float = -INF

func _setup_pickup_log() -> void:
	var holder := Control.new() # ui_root와 같은 크기의 틀 (페이드되는 ui_root 밖에 둔다)
	holder.name = "PickupLayer"
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.anchor_right = 1.0
	holder.anchor_bottom = 1.0
	holder.offset_right = ui_root.offset_right
	holder.offset_bottom = ui_root.offset_bottom
	add_child(holder)
	pickup_log = VBoxContainer.new()
	pickup_log.name = "PickupLog"
	pickup_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pickup_log.position = PICKUP_LOG_POS
	pickup_log.add_theme_constant_override("separation", 2)
	holder.add_child(pickup_log)
	_pickup_settings = LabelSettings.new()
	_pickup_settings.font = interact_text.label_settings.font if interact_text and interact_text.label_settings else null
	_pickup_settings.font_size = PICKUP_FONT_SIZE
	_pickup_settings.outline_size = 3
	_pickup_settings.outline_color = Color.BLACK

func _has_pickups() -> bool:
	return pickup_log != null and pickup_log.get_child_count() > 0

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

func log_pickup_gold(amount: int) -> void:
	if amount <= 0 or pickup_log == null:
		return
	var now := _now()
	if is_instance_valid(_pickup_gold_label) and now - _pickup_gold_time < PICKUP_GOLD_MERGE:
		_pickup_gold_total += amount
		_pickup_gold_label.text = tr(&"PICKUP_GOLD") % _pickup_gold_total
		_pickup_gold_time = now
		_touch_group(_pickup_gold_label.get_parent().get_parent())
		return
	_pickup_gold_total = amount
	_pickup_gold_time = now
	_pickup_gold_label = _add_pickup_line(tr(&"PICKUP_GOLD") % amount)

func log_pickup_item(item: ItemData) -> void:
	if item == null:
		return
	_add_pickup_line(tr(&"PICKUP_ITEM") % tr(item.name))

# 이미 번역된 문구들을 새 묶음으로 띄운다
func show_pickups(lines: Array) -> void:
	_pickup_group_time = -INF
	for line in lines:
		_add_pickup_line(str(line))

func _add_pickup_line(text: String) -> Label:
	if pickup_log == null:
		return null
	show_hud_temporarily()
	visible = true
	var now := _now()
	if not is_instance_valid(_pickup_group) or _pickup_group.get_meta("fading", false) or now - _pickup_group_time >= PICKUP_GROUP_WINDOW:
		_pickup_group = _new_pickup_group()
	_pickup_group_time = now
	var label := Label.new()
	label.text = text
	label.label_settings = _pickup_settings
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED # 이미 번역된 문구
	_pickup_group.get_child(0).add_child(label)
	_touch_group(_pickup_group)
	return label

func _new_pickup_group() -> Control:
	while pickup_log.get_child_count() >= PICKUP_MAX_GROUPS:
		var oldest := pickup_log.get_child(0)
		pickup_log.remove_child(oldest)
		oldest.queue_free()
	var group := MarginContainer.new()
	group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 0)
	group.add_child(column)
	pickup_log.add_child(group)
	# 아래에서 살짝 떠오르며 나타난다
	group.modulate.a = 0.0
	group.add_theme_constant_override("margin_top", int(PICKUP_RISE))
	var tween := group.create_tween().set_parallel(true)
	tween.tween_property(group, "modulate:a", 1.0, 0.25)
	tween.tween_method(func(v: float): group.add_theme_constant_override("margin_top", int(v)), PICKUP_RISE, 0.0, 0.25)
	return group

# 묶음의 사라질 시각을 지금부터 pickup_lifetime 뒤로 미룬다
func _touch_group(group: Node) -> void:
	if is_instance_valid(group) and not group.get_meta("fading", false):
		group.set_meta("expire_at", _now() + pickup_lifetime)

func _update_pickup_log() -> void:
	if pickup_log == null:
		return
	var now := _now()
	for group in pickup_log.get_children():
		if group.get_meta("fading", false) or now < float(group.get_meta("expire_at", INF)):
			continue
		group.set_meta("fading", true)
		var tween := group.create_tween()
		tween.tween_property(group, "modulate:a", 0.0, PICKUP_FADE)
		tween.tween_callback(_remove_pickup_group.bind(group))

func _remove_pickup_group(group: Control) -> void:
	if is_instance_valid(group) and group.get_parent() == pickup_log:
		pickup_log.remove_child(group)
		group.queue_free()
	# 마지막 묶음이 사라졌고 HUD도 이미 흐려져 있으면 숨긴다
	if not _has_pickups() and ui_root.modulate.a <= 0.01 and not _is_boss_health_visible():
		visible = false

func _is_boss_health_visible() -> bool:
	return boss_bar_root != null and boss_bar_root.visible
