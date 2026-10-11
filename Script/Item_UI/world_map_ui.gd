extends CanvasLayer

# 전체 지도 (autoload: WorldMap). 쉼표 키(world_map)로 열고 닫는다 (ESC로도 닫힘).
# 지하 탑의 층들을 위에서 아래로 쌓아 그린다. 엘리베이터가 모든 층에서 같은 세로 축(화면 가운데)에 오도록
# 층마다 가로로 옮겨 그리므로, 층마다 엘리베이터 좌표·방 개수(grid_size)가 달라도 탑 모양으로 맞춰진다.
# 엘리베이터 통로선은 층과 층 사이 빈 공간에만 그린다 (통로는 화면 안쪽, 보이는 단면 뒤에 있다는 느낌).
# 그리는 것: 다녀간 방(방 단위 칸, 지형은 안 그림), 엘리베이터, 가까이 가 본 세이브 포인트·상인, 현재 위치.
# 지상층~지하 12층을 모두 순서대로 놓고, 아직 안 가 본 층(씬이 없는 층 포함)은 "???" 빈자리로 그린다.
# 다른 층의 정보는 씬을 인스턴스하지 않고 PackedScene.get_state()로 읽어 층마다 한 번만 캐시한다.
# 튜토리얼 스테이지처럼 FLOORS에 없는 씬은 지도에 나오지 않는다.

# [층 이름 번역 키, 씬 경로]. 위층부터. 아직 없는 층은 경로를 비워 둔다
const FLOORS := [
	[&"WORLD_MAP_FLOOR_GROUND", ""],
	[&"WORLD_MAP_FLOOR_B1", "res://Scenes/Stage/Stage_02.tscn"],
	[&"WORLD_MAP_FLOOR_B2", ""],
	[&"WORLD_MAP_FLOOR_B3", ""],
	[&"WORLD_MAP_FLOOR_B4", "res://Scenes/Stage/Stage_01.tscn"],
	[&"WORLD_MAP_FLOOR_B5", ""],
	[&"WORLD_MAP_FLOOR_B6", ""],
	[&"WORLD_MAP_FLOOR_B7", ""],
	[&"WORLD_MAP_FLOOR_B8", "res://Scenes/Stage/Stage_03.tscn"],
	[&"WORLD_MAP_FLOOR_B9", ""],
	[&"WORLD_MAP_FLOOR_B10", ""],
	[&"WORLD_MAP_FLOOR_B11", ""],
	[&"WORLD_MAP_FLOOR_B12", ""],
]

const ELEVATOR_SCRIPT := "res://Script/System/elevator_block.gd"
const SAVE_POINT_SCENE := "res://Scenes/System/SavePoint.tscn"
const MERCHANT_SCENE := "res://Scenes/Entitites/MerchantNPC.tscn"

# --- 모양 (직접 꾸밀 때 여기만 바꾸면 된다) ---
const MAP_SCALE := 0.06           # 월드 1px → 지도 크기 (방 640x360 → 38.4x21.6)
const FLOOR_GAP := 28.0           # 층과 층 사이 빈 공간 (통로선이 보이는 곳)
const TOP_MARGIN := 70.0
const LABEL_GAP := 10.0           # 층 이름과 층 그림 사이
const FONT_SIZE := 16
const TITLE_FONT_SIZE := 24
const SCROLL_STEP := 40.0
const COLOR_DIM := Color(0, 0, 0, 0.82)
const COLOR_ROOM := Color(0.62, 0.62, 0.66)
const COLOR_ROOM_CURRENT_FLOOR := Color(0.8, 0.8, 0.86)
const COLOR_ROOM_BORDER := Color(0.2, 0.2, 0.24)
const COLOR_CURRENT_ROOM := Color(1.0, 1.0, 1.0)
const COLOR_SHAFT := Color(0.45, 0.55, 0.85)
const COLOR_TEXT := Color.WHITE
const COLOR_TEXT_DIM := Color(0.75, 0.75, 0.8)
const UNKNOWN_ROOMS := Vector2(4, 1)  # 안 가 본 층 빈자리 크기 (방 칸 수)
const COLOR_UNKNOWN := Color(0.4, 0.4, 0.45)

var is_open: bool = false
var _floor_cache: Dictionary = {} # 씬 경로 → 층 정보 (read_floor_info)
var _scroll: float = 0.0
var _canvas: Control

func _ready() -> void:
	layer = 90 # HUD·대화창보다 위
	process_mode = Node.PROCESS_MODE_ALWAYS
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_map)
	add_child(_canvas)
	visible = false

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("world_map"):
		if is_open:
			close()
		elif can_open():
			open()
		get_viewport().set_input_as_handled()
	elif is_open:
		if event.is_action_pressed("ui_cancel"):
			close()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("ui_up") or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP):
			_scroll += SCROLL_STEP
			_canvas.queue_redraw()
		elif event.is_action_pressed("ui_down") or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			_scroll -= SCROLL_STEP
			_canvas.queue_redraw()

# 다른 창(인벤토리·대화·상점·일시정지 등)이 열려 있으면 열지 않는다. 플레이어가 있는 게임 화면에서만
func can_open() -> bool:
	return GameManager.active_ui_count == 0 and get_tree().get_first_node_in_group("player") != null

func open() -> void:
	is_open = true
	visible = true
	GameManager.ui_opened(self, false)
	_scroll = 0.0
	_scroll_to_current_floor()
	_canvas.queue_redraw()

func close() -> void:
	is_open = false
	visible = false
	GameManager.ui_closed(self)

func _process(_delta: float) -> void:
	if is_open:
		_canvas.queue_redraw()

# --- 층 정보 (씬 파일에서 읽기) ---

# {grid_size, room_size, grid_origin, title_key, elevator (Vector2 또는 null), markers: [{kind, pos, key}]}
func floor_info(scene_path: String) -> Dictionary:
	if not _floor_cache.has(scene_path):
		_floor_cache[scene_path] = read_floor_info(scene_path)
	return _floor_cache[scene_path]

static func read_floor_info(scene_path: String) -> Dictionary:
	var info := {
		"grid_size": Vector2i(12, 3), "room_size": Vector2(640, 360), "grid_origin": Vector2.ZERO,
		"title_key": &"", "elevator": null, "markers": [],
	}
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		return info
	var packed := load(scene_path) as PackedScene
	if packed == null:
		return info
	var state := packed.get_state()
	# 루트(BaseStage)의 설정: 씬에 적힌 값, 없으면 스크립트 기본값
	for p in state.get_node_property_count(0):
		var value: Variant = state.get_node_property_value(0, p)
		match state.get_node_property_name(0, p):
			&"script":
				var script := value as Script
				if script != null:
					for key in ["grid_size", "room_size", "grid_origin"]:
						var default_value: Variant = script.get_property_default_value(key)
						if default_value != null:
							info[key] = default_value
	for p in state.get_node_property_count(0):
		var name := state.get_node_property_name(0, p)
		if name in [&"grid_size", &"room_size", &"grid_origin"]:
			info[String(name)] = state.get_node_property_value(0, p)
		elif name == &"stage_title_key":
			info["title_key"] = state.get_node_property_value(0, p)
	# 엘리베이터·세이브 포인트·상인 위치 (부모 노드 위치를 더한 씬 기준 좌표)
	for i in range(1, state.get_node_count()):
		var kind := ""
		var instance := state.get_node_instance(i)
		if instance != null and instance.resource_path == SAVE_POINT_SCENE:
			kind = "save"
		elif instance != null and instance.resource_path == MERCHANT_SCENE:
			kind = "npc"
		else:
			for p in state.get_node_property_count(i):
				if state.get_node_property_name(i, p) == &"script":
					var script := state.get_node_property_value(i, p) as Script
					if script != null and script.resource_path == ELEVATOR_SCRIPT:
						kind = "elevator"
		if kind.is_empty():
			continue
		var pos := _scene_position(state, i)
		if kind == "elevator":
			if info["elevator"] == null:
				info["elevator"] = pos
		else:
			info["markers"].append({"kind": kind, "pos": pos, "key": "path:" + _relative_path(state, i)})
	return info

# 씬 루트 기준 노드 경로 ("Entities/MerchantNPC") — MinimapUI.map_object_key의 경로 키와 같은 형식
static func _relative_path(state: SceneState, idx: int) -> String:
	var path := String(state.get_node_path(idx))
	return path.trim_prefix("./")

# 노드와 조상들의 position을 더한다 (중간에 Node2D가 아닌 그룹 노드는 0으로 친다)
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

# --- 배치 계산 ---

# 지도에 그릴 층: FLOORS 전부, 위층부터. 한 번이라도 들어가 본 층만 info가 있고 나머지는 known = false ("???")
# [{label, scene, known, info, rect, offset}]
func map_floors() -> Array:
	var result := []
	for row in FLOORS:
		var scene: String = row[1]
		var known := not scene.is_empty() and not GameManager.get_visited_rooms(scene).is_empty()
		result.append({"label": row[0], "scene": scene, "known": known, "info": floor_info(scene) if known else {}})
	return result

# 층에 엘리베이터 축이 있는가 (모르는 층은 축이 지나간다고 본다 — 통로선이 끊기지 않게)
static func has_shaft(f: Dictionary) -> bool:
	return not f["known"] or f["info"]["elevator"] != null

# 층마다 지도 위 원점(월드 좌표 → 지도 좌표 변환용)과 차지하는 사각형을 정한다.
# 가로: 엘리베이터가 axis_x에 오도록 (없으면 층 가운데). 세로: 위층부터 차례로 쌓는다
static func layout_floors(floors: Array, axis_x: float, top: float) -> Array:
	var y := top
	for f in floors:
		if not f["known"]: # 빈자리: 축 가운데에 놓는다
			var unknown_size := UNKNOWN_ROOMS * Vector2(640, 360) * MAP_SCALE
			f["rect"] = Rect2(Vector2(axis_x - unknown_size.x * 0.5, y), unknown_size)
			f["offset"] = f["rect"].position
			y += unknown_size.y + FLOOR_GAP
			continue
		var info: Dictionary = f["info"]
		var size: Vector2 = Vector2(info["grid_size"]) * info["room_size"] * MAP_SCALE
		var origin_world: Vector2 = info["grid_origin"]
		var anchor_world: Vector2 = info["elevator"] if info["elevator"] != null else origin_world + Vector2(info["grid_size"]) * info["room_size"] * 0.5
		var x_left := axis_x - (anchor_world.x - origin_world.x) * MAP_SCALE
		f["rect"] = Rect2(Vector2(x_left, y), size)
		# 월드 좌표 p → 지도 좌표: offset + (p - grid_origin) * MAP_SCALE
		f["offset"] = Vector2(x_left, y)
		y += size.y + FLOOR_GAP
	return floors

func _scroll_to_current_floor() -> void:
	var current := _current_scene_path()
	var floors := layout_floors(map_floors(), 0.0, TOP_MARGIN)
	var view_h := _canvas.get_viewport_rect().size.y
	for f in floors:
		if f["scene"] == current:
			var r: Rect2 = f["rect"]
			_scroll = minf(0.0, view_h * 0.5 - (r.position.y + r.size.y * 0.5))
			return

func _current_scene_path() -> String:
	var scene := get_tree().current_scene
	return scene.scene_file_path if scene != null else ""

# --- 그리기 ---

func _draw_map() -> void:
	var view := _canvas.get_viewport_rect().size
	_canvas.draw_rect(Rect2(Vector2.ZERO, view), COLOR_DIM)
	var font := _canvas.get_theme_default_font()
	_canvas.draw_string(font, Vector2(24, 40), tr(&"WORLD_MAP_TITLE"), HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_FONT_SIZE, COLOR_TEXT)
	var hint := tr(&"WORLD_MAP_CLOSE_HINT")
	_canvas.draw_string(font, Vector2(view.x - 24 - font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x, 40), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, COLOR_TEXT_DIM)

	var axis_x := view.x * 0.5
	var floors := layout_floors(map_floors(), axis_x, TOP_MARGIN + _scroll)
	var current := _current_scene_path()

	# 층 사이 통로선 (위아래 층 모두 엘리베이터가 있을 때, 빈 공간에만)
	for i in range(floors.size() - 1):
		var upper: Dictionary = floors[i]
		var lower: Dictionary = floors[i + 1]
		if not has_shaft(upper) or not has_shaft(lower):
			continue
		var y0: float = upper["rect"].end.y
		var y1: float = lower["rect"].position.y
		_canvas.draw_line(Vector2(axis_x, y0), Vector2(axis_x, y1), COLOR_SHAFT, 3.0)

	for f in floors:
		if f["known"]:
			_draw_floor(f, f["scene"] == current, font)
		else:
			_draw_unknown_floor(f, font)

# 안 가 본 층: 회색 테두리 빈자리에 "???", 왼쪽에 층 이름
func _draw_unknown_floor(f: Dictionary, font: Font) -> void:
	var rect: Rect2 = f["rect"]
	_canvas.draw_rect(rect, COLOR_UNKNOWN, false, 1.0)
	var q := "???"
	var q_size := font.get_string_size(q, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
	_canvas.draw_string(font, rect.get_center() + Vector2(-q_size.x * 0.5, FONT_SIZE * 0.35), q, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, COLOR_UNKNOWN)
	var label := tr(f["label"])
	var label_w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	_canvas.draw_string(font, Vector2(rect.position.x - LABEL_GAP - label_w, rect.position.y + FONT_SIZE), label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, COLOR_UNKNOWN)

func _draw_floor(f: Dictionary, is_current: bool, font: Font) -> void:
	var info: Dictionary = f["info"]
	var room_px: Vector2 = info["room_size"] * MAP_SCALE
	var offset: Vector2 = f["offset"]
	var visited: Array = GameManager.get_visited_rooms(f["scene"])
	for room in visited:
		var r := Rect2(offset + Vector2(room) * room_px, room_px)
		_canvas.draw_rect(r, COLOR_ROOM_CURRENT_FLOOR if is_current else COLOR_ROOM)
		_canvas.draw_rect(r, COLOR_ROOM_BORDER, false, 1.0)

	# 층 이름: 층 그림 왼쪽 위
	var label := tr(f["label"])
	if info["title_key"] != &"":
		label += "  " + tr(info["title_key"])
	var rect: Rect2 = f["rect"]
	var label_w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	_canvas.draw_string(font, Vector2(rect.position.x - LABEL_GAP - label_w, rect.position.y + FONT_SIZE), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, COLOR_TEXT if is_current else COLOR_TEXT_DIM)

	var origin: Vector2 = info["grid_origin"]
	var to_map := func(world: Vector2) -> Vector2: return offset + (world - origin) * MAP_SCALE
	if info["elevator"] != null:
		_draw_marker(to_map.call(info["elevator"]), MinimapUI.COLOR_ELEVATOR, true, 3.0)
	for m in info["markers"]:
		if not GameManager.has_seen_map_object(f["scene"], m["key"]):
			continue
		var color: Color = MinimapUI.COLOR_SAVE if m["kind"] == "save" else MinimapUI.COLOR_NPC
		_draw_marker(to_map.call(m["pos"]), color, m["kind"] == "save", 3.0)

	if is_current:
		var player := get_tree().get_first_node_in_group("player") as Node2D
		if player != null:
			var room := Vector2i(((player.global_position - origin) / info["room_size"]).floor())
			_canvas.draw_rect(Rect2(offset + Vector2(room) * room_px, room_px), COLOR_CURRENT_ROOM, false, 2.0)
			_draw_marker(to_map.call(player.global_position), MinimapUI.COLOR_PLAYER, false, 4.0)

func _draw_marker(pos: Vector2, color: Color, square: bool, radius: float) -> void:
	if square:
		var r := Rect2(pos - Vector2(radius, radius), Vector2(radius, radius) * 2.0)
		_canvas.draw_rect(r.grow(1.0), MinimapUI.COLOR_MARKER_OUTLINE)
		_canvas.draw_rect(r, color)
	else:
		_canvas.draw_circle(pos, radius + 1.0, MinimapUI.COLOR_MARKER_OUTLINE)
		_canvas.draw_circle(pos, radius, color)
