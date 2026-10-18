extends Control
class_name DebugMenu

# 개발용 바로 가기: 스테이지마다 시작 지점·세이브 포인트·보스(가장 가까운 세이브 포인트)로 바로 간다.
# 메인 메뉴에서 F2 (디버그 빌드에서만), 또는 에디터에서 이 씬을 바로 실행 (F6).
# 저장은 전부 DEBUG_SAVE_PATH로 간다 — 진짜 세이브 슬롯은 건드리지 않는다 (메인 메뉴로 돌아가면 다시 슬롯으로).
# 스테이지 씬은 열지 않고 PackedScene.get_state()로 위치만 읽으므로, 스테이지를 고치면 목록도 따라 바뀐다.

const DEBUG_SAVE_PATH := "user://debug_save.json"
const MAIN_MENU := "res://Scenes/System/MainMenu.tscn"
const SAVE_POINT_SCENE := "res://Scenes/System/SavePoint.tscn"
const BOSS_SCENE_PREFIX := "res://Scenes/Entitites/boss_"

# [표시 이름, 씬]
const STAGES := [
	["튜토리얼", "res://Scenes/Stage/Stage_tutorial.tscn"],
	["지상", "res://Scenes/Stage/Stage_Surface.tscn"],
	["B1 (Stage_02)", "res://Scenes/Stage/Stage_02.tscn"],
	["B4 (Stage_01)", "res://Scenes/Stage/Stage_01.tscn"],
	["B8 (Stage_03)", "res://Scenes/Stage/Stage_03.tscn"],
	["늑대 보스 아레나", "res://Scenes/Debug/WolfArena.tscn"],
]

# 프리셋에서 넣을 수 있는 아이템 [표시 이름, id]
const PRESET_ITEMS := [
	["랜턴", "lantern"],
	["문지기의 반지 (엘리베이터)", "gatekeepers_ring"],
]

var _checks := {}
var _spins := {}

# 테스트가 이 스크립트를 오토로드보다 먼저 컴파일하므로 오토로드는 경로로 찾는다
static func _autoload(name: String) -> Node:
	return (Engine.get_main_loop() as SceneTree).root.get_node(name)

func _ready() -> void:
	_autoload("CustomCursor").show_cursor()
	_build_ui()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().change_scene_to_file(MAIN_MENU)

# --- 위치 읽기 ---

# 씬의 바로 가기 목록 [{label, pos}]: 시작 지점, 세이브 포인트, 보스(가장 가까운 세이브 포인트에서 시작)
static func jump_points(scene_path: String) -> Array:
	var points := []
	if not ResourceLoader.exists(scene_path):
		return points
	var state := (load(scene_path) as PackedScene).get_state()
	var saves := []
	var bosses := []
	for i in state.get_node_count():
		var name := String(state.get_node_name(i))
		var inst := state.get_node_instance(i)
		var inst_path := inst.resource_path if inst != null else ""
		if name == "SpawnPoint" and state.get_node_path(i, true) == NodePath("."):
			points.append({"label": "시작 지점", "pos": _scene_position(state, i)})
		elif inst_path == SAVE_POINT_SCENE:
			saves.append({"label": "세이브: " + name, "pos": _scene_position(state, i)})
		elif inst_path.begins_with(BOSS_SCENE_PREFIX):
			bosses.append({"name": name, "pos": _scene_position(state, i)})
	for b in bosses:
		var nearest: Variant = null
		for s in saves:
			if nearest == null or (s.pos as Vector2).distance_to(b.pos) < (nearest.pos as Vector2).distance_to(b.pos):
				nearest = s
		if nearest != null:
			points.append({"label": "보스: %s (%s)" % [b.name, nearest.label.trim_prefix("세이브: ")], "pos": nearest.pos})
	points.append_array(saves)
	return points

# 씬 파일 안 노드의 위치 (부모 위치를 더한 값). 월드맵(world_map_ui.gd)과 같은 계산
static func _scene_position(state: SceneState, idx: int) -> Vector2:
	var paths := {}
	for i in state.get_node_count():
		paths[_relative_path(state, i)] = i
	var rel := _relative_path(state, idx)
	var total := Vector2.ZERO
	while not rel.is_empty() and rel != ".":
		if paths.has(rel):
			var i: int = paths[rel]
			for p in state.get_node_property_count(i):
				if state.get_node_property_name(i, p) == &"position":
					total += state.get_node_property_value(i, p)
		var cut := rel.rfind("/")
		rel = rel.substr(0, cut) if cut >= 0 else ""
	return total

static func _relative_path(state: SceneState, idx: int) -> String:
	return String(state.get_node_path(idx)).trim_prefix("./")

# --- 이동 ---

func jump(scene_path: String, pos: Vector2) -> void:
	apply_preset(scene_path, pos, _preset())
	get_tree().change_scene_to_file(scene_path)

# 새 게임 상태에서 프리셋을 적용하고, 도착 지점을 체크포인트로 삼는다 (죽으면 여기서 다시 시작)
static func apply_preset(scene_path: String, pos: Vector2, preset: Dictionary) -> void:
	var gm: Node = _autoload("GameManager")
	var inv: Node = _autoload("Inventory")
	gm.reset_data()
	gm.save_path_override = DEBUG_SAVE_PATH
	gm.has_checkpoint = true
	gm.last_scene_path = scene_path
	gm.last_checkpoint_pos = pos
	gm.heavy_attack_unlocked = preset.get("heavy_attack", false)
	gm.double_jump_unlocked = preset.get("double_jump", false)
	gm.player_damage = int(preset.get("damage", gm.player_damage))
	gm.flask_max_charges = int(preset.get("flasks", gm.flask_max_charges))
	gm.flask_current_charges = gm.flask_max_charges
	gm.gold = int(preset.get("gold", 0))
	gm.mutation_epoch = 0 # 보름달
	gm.moon_passage_open = preset.get("full_moon", false)
	gm.moon_changed.emit()
	if not preset.get("wolf_intro", false):
		gm.talked_bosses["B-wolfarena"] = true # 아레나 늑대의 persist_id
	for id in preset.get("items", []):
		var item = _autoload("Database").get_item_by_id(id)
		if item != null:
			inv.add_item(item)
	gm.seen_tutorials.append_array(preset.get("skip_tutorials", []))

func _preset() -> Dictionary:
	var items := []
	for row in PRESET_ITEMS:
		if _checks[row[1]].button_pressed:
			items.append(row[1])
	var preset := {
		"heavy_attack": _checks["heavy_attack"].button_pressed,
		"double_jump": _checks["double_jump"].button_pressed,
		"full_moon": _checks["full_moon"].button_pressed,
		"wolf_intro": _checks["wolf_intro"].button_pressed,
		"damage": int(_spins["damage"].value),
		"flasks": int(_spins["flasks"].value),
		"gold": int(_spins["gold"].value),
		"items": items,
	}
	if _checks["skip_tutorials"].button_pressed:
		preset["skip_tutorials"] = _all_tutorial_keys()
	return preset

static func _all_tutorial_keys() -> Array:
	var keys := []
	var csv := FileAccess.open("res://resources/i18n/ui.csv", FileAccess.READ)
	if csv == null:
		return keys
	while not csv.eof_reached():
		var key := csv.get_csv_line()[0]
		if key.begins_with("TUTORIAL_"):
			keys.append(key)
	return keys

# --- 화면 ---

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.08, 0.1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var root := HBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 24
	root.offset_top = 24
	root.offset_right = -24
	root.offset_bottom = -24
	root.add_theme_constant_override("separation", 32)
	add_child(root)

	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 340
	root.add_child(left)
	_title(left, "디버그 바로 가기  (ESC: 메인 메뉴)")
	_note(left, "저장은 %s에만 됩니다." % DEBUG_SAVE_PATH)
	_title(left, "프리셋")
	_check(left, "heavy_attack", "강공격 해금", false)
	_check(left, "double_jump", "더블 점프 해금", false)
	_check(left, "full_moon", "해치 열림 + 보름달", false)
	_check(left, "wolf_intro", "늑대 인트로 보기", false)
	_check(left, "skip_tutorials", "도움말 팝업 끄기", true)
	for row in PRESET_ITEMS:
		_check(left, row[1], row[0], false)
	_spin(left, "damage", "공격력", 10, 1, 200)
	_spin(left, "flasks", "플라스크 횟수", 1, 0, 10)
	_spin(left, "gold", "골드", 0, 0, 99999)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for stage in STAGES:
		_title(list, stage[0])
		var points := jump_points(stage[1])
		if points.is_empty():
			_note(list, "(씬이 없거나 위치를 못 찾음)")
		for p in points:
			var btn := Button.new()
			btn.text = "  %s   %s" % [p.label, str(Vector2i(p.pos))]
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			btn.pressed.connect(jump.bind(stage[1], p.pos))
			list.add_child(btn)

func _title(parent: Node, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 20)
	parent.add_child(l)

func _note(parent: Node, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.modulate = Color(0.7, 0.7, 0.7)
	parent.add_child(l)

func _check(parent: Node, key: String, text: String, on: bool) -> void:
	var c := CheckBox.new()
	c.text = text
	c.button_pressed = on
	parent.add_child(c)
	_checks[key] = c

func _spin(parent: Node, key: String, text: String, value: float, lo: float, hi: float) -> void:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = text
	l.custom_minimum_size.x = 140
	row.add_child(l)
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.value = value
	row.add_child(s)
	parent.add_child(row)
	_spins[key] = s
