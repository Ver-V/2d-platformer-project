extends Control
class_name MinimapUI

# 미니맵 설정
const MAP_SCALE = 0.1 # 화면에 보여질 축소 비율 (1/10 크기)
var room_size: Vector2 = Vector2(640, 360)
var grid_origin: Vector2 = Vector2.ZERO
var room_draw_size: Vector2:
	get: return room_size * MAP_SCALE
var visited_rooms: Array:
	get: return GameManager.get_visited_rooms(current_scene_path)

# 색상 설정
const COLOR_BG_VISITED = Color(0.7, 0.7, 0.7, 0.8)   # 방문한 방 배경 (밝은 회색)
const COLOR_BG_CURRENT = Color(0.9, 0.9, 1.0, 0.9)   # 현재 방 배경 (밝은 푸른빛)
const COLOR_BORDER = Color(0.3, 0.3, 0.3, 1.0)       # 방 테두리
const COLOR_PLAYER = Color.GREEN                     # 플레이어 (초록)
const COLOR_ENEMY = Color.RED                        # 적 (빨강, 지금 있는 방만)
const COLOR_BOSS = Color(0.6, 0.0, 0.1)              # 보스 (진한 빨강, 큰 점 — 다녀간 방이면 계속 보인다)
const COLOR_NPC = Color.YELLOW                       # NPC (노랑)
const COLOR_SAVE = Color(0.2, 0.9, 1.0)              # 세이브 포인트 (하늘색)
const COLOR_ELEVATOR = Color(0.25, 0.4, 1.0)         # 엘리베이터 (파랑)
const COLOR_CHEST = Color(1.0, 0.6, 0.1)             # 보물 상자 (주황)
const COLOR_DOOR_CLOSED = Color(1.0, 0.2, 0.9)       # 닫힌 문 (자홍)
const COLOR_DOOR_OPEN = Color(0.75, 0.65, 1.0)       # 열린 문 (연보라)
const COLOR_DEATH_DROP = Color(0.95, 0.92, 0.8)       # 죽은 자리 금화 (뼈 색 큰 점)
const COLOR_TERRAIN = Color.BLACK                    # 지형 (검은색)
const COLOR_MARKER_OUTLINE = Color(0, 0, 0, 0.85)    # 밝은 방 배경에서도 보이도록 표시마다 검은 테두리

# 오브젝트 표시와 지형은 플레이어가 이 거리(타일 수) 안으로 가 본 것만 기록한다 — 다녀간 방 안의 숨은 공간이 미니맵으로 들키지 않게
const REVEAL_RADIUS_TILES := 5.0
const TILE_SIZE := 16.0
const REVEAL_GROUPS := ["minimap_chest", "minimap_door", "minimap_elevator", "minimap_save", "npc"]

# 범례: 미니맵 왼쪽 위에 "기호 : 뜻"을 한 줄씩 (번역 키). [키, 색, 네모인가, 반지름]
const LEGEND := [
	[&"MINIMAP_LEGEND_PLAYER", COLOR_PLAYER, false, 3.0],
	[&"MINIMAP_LEGEND_ENEMY", COLOR_ENEMY, false, 3.0],
	[&"MINIMAP_LEGEND_BOSS", COLOR_BOSS, false, 4.0],
	[&"MINIMAP_LEGEND_NPC", COLOR_NPC, false, 3.0],
	[&"MINIMAP_LEGEND_SAVE", COLOR_SAVE, true, 3.0],
	[&"MINIMAP_LEGEND_ELEVATOR", COLOR_ELEVATOR, true, 3.0],
	[&"MINIMAP_LEGEND_CHEST", COLOR_CHEST, true, 3.0],
	[&"MINIMAP_LEGEND_DOOR_CLOSED", COLOR_DOOR_CLOSED, true, 3.0],
	[&"MINIMAP_LEGEND_DOOR_OPEN", COLOR_DOOR_OPEN, true, 3.0],
	[&"MINIMAP_LEGEND_DEATH_DROP", COLOR_DEATH_DROP, false, 4.0],
]
const LEGEND_FONT_SIZE := 14
const LEGEND_LINE := 18.0
const LEGEND_PADDING := 6.0
const COLOR_LEGEND_BG = Color(0, 0, 0, 0.6)

var current_room_coords: Vector2i = Vector2i.ZERO

# 지형 데이터를 담아둘 변수들
var room_terrain_points: Dictionary = {}
var valid_rooms: Array = []
var current_scene_path: String = ""

# RoomGrid 데이터 저장용
var map_origin_room: Vector2i = Vector2i(-9999, -9999)
var map_size_rooms: Vector2i = Vector2i(0, 0)

# 지형 기록(안개): BaseStage에서만 쓴다. 맵 전체를 TILE_SIZE 칸으로 나눈 크기
var fog_enabled: bool = false
var fog_size: Vector2i = Vector2i.ZERO
var _last_fog_cell: Vector2i = Vector2i(-99999, -99999)

func _ready():
	# UI가 다른 것들 위에 잘 보이도록 설정
	z_index = 50

func _process(_delta):
	var current_scene = get_tree().current_scene
	if current_scene and current_scene.scene_file_path != current_scene_path:
		_init_map_data(current_scene)
		current_scene_path = current_scene.scene_file_path
		
	# 플레이어 위치를 기반으로 현재 방 좌표 계산
	var player = get_tree().get_first_node_in_group("player")
	if player:
		var pos = player.global_position
		current_room_coords = _room_from_world(pos)
		
		# 방문 기록에 없으면 추가 (새로운 방 발견!)
		if current_scene is BaseStage:
			current_room_coords = current_scene.room_from_pos(pos)
			GameManager.visit_room(current_scene_path, current_room_coords)
		_record_nearby_objects(current_scene, pos)
		if fog_enabled:
			_reveal_terrain_around(pos)
	
	# 화면이 계속 갱신되도록 다시 그리기 요청
	queue_redraw()

# 전체 타일맵을 뒤져서 어느 방에 지형이 있는지(valid_rooms) 파악하고 점 찍을 위치를 저장합니다.
func _init_map_data(scene_node: Node):
	room_terrain_points.clear()
	valid_rooms.clear()
	
	# 게임 진행에 쓰는 BaseStage 좌표계를 그대로 사용한다.
	room_size = Vector2(640, 360)
	grid_origin = Vector2.ZERO
	var room_grid = scene_node.get_node_or_null("RoomGrid")
	fog_enabled = false
	_last_fog_cell = Vector2i(-99999, -99999)
	if scene_node is BaseStage:
		room_size = scene_node.room_size
		grid_origin = scene_node.grid_origin
		map_origin_room = Vector2i.ZERO
		map_size_rooms = scene_node.grid_size
		fog_enabled = true
		fog_size = Vector2i(ceili(map_size_rooms.x * room_size.x / TILE_SIZE), ceili(map_size_rooms.y * room_size.y / TILE_SIZE))
	elif room_grid:
		grid_origin = room_grid.origin
		room_size = room_grid.room_size
		var counts = room_grid.get("rooms")
		map_origin_room = Vector2i.ZERO
		map_size_rooms = counts if counts != null else Vector2i(999, 999)
	else:
		map_origin_room = Vector2i(-9999, -9999)
		map_size_rooms = Vector2i(99999, 99999)
	
	var tilemaps = _get_all_tilemap_layers(scene_node)
	for tm in tilemaps:
		if tm is TileMapLayer:
			for cell in tm.get_used_cells():
				var local_pos = tm.map_to_local(cell)
				var global_pos = tm.to_global(local_pos)
				_add_terrain_point(global_pos)
		elif tm is TileMap: # Godot 4.2 이하 버전 호환용
			for i in range(tm.get_layers_count()):
				for cell in tm.get_used_cells(i):
					var local_pos = tm.map_to_local(cell)
					var global_pos = tm.to_global(local_pos)
					_add_terrain_point(global_pos)

# 재귀적으로 씬 안의 모든 타일맵을 찾아내는 함수 (가시밭길 Hazard는 제외)
func _get_all_tilemap_layers(node: Node) -> Array:
	var result = []
	if (node is TileMapLayer or node is TileMap) and "Hazard" not in node.name and not _is_water_layer(node):
		result.append(node)
	for child in node.get_children():
		result.append_array(_get_all_tilemap_layers(child))
	return result

# 물 타일맵(커스텀 데이터 "water")은 지형이 아니다
func _is_water_layer(node: Node) -> bool:
	return node.get("tile_set") != null and node.tile_set.get_custom_data_layer_by_name("water") != -1

func _room_from_world(world_pos: Vector2) -> Vector2i:
	var relative_pos := world_pos - grid_origin
	return Vector2i(floor(relative_pos.x / room_size.x), floor(relative_pos.y / room_size.y))

func _add_terrain_point(global_pos: Vector2):
	var room_coords = _room_from_world(global_pos)
	
	# [핵심] RoomGrid 범위 바깥으로 삐져나온 타일은 미니맵 방으로 취급하지 않음!
	if map_origin_room.x != -9999:
		if room_coords.x < map_origin_room.x or room_coords.x >= map_origin_room.x + map_size_rooms.x:
			return
		if room_coords.y < map_origin_room.y or room_coords.y >= map_origin_room.y + map_size_rooms.y:
			return
			
	if not room_terrain_points.has(room_coords):
		room_terrain_points[room_coords] = []
		valid_rooms.append(room_coords)
	room_terrain_points[room_coords].append(global_pos)

func _draw():
	var player = get_tree().get_first_node_in_group("player")
	if not player: return

	var center_offset = size / 2.0
	var current_room_origin = grid_origin + Vector2(current_room_coords) * room_size
	
	# 0. 아직 방문하지 않았지만 갈 수 있는 인접한 방(새까맣게 표시)
	var adjacent_unvisited = []
	for v_room in visited_rooms:
		# 현재 방문한 방의 상하좌우 검사
		var neighbors = [v_room + Vector2i(1, 0), v_room + Vector2i(-1, 0), v_room + Vector2i(0, 1), v_room + Vector2i(0, -1)]
		for n in neighbors:
			# 실제로 타일이 존재하는 유효한 방(valid_rooms)이면서, 아직 방문하지 않았다면? -> 까맣게 그릴 대상!
			if valid_rooms.has(n) and not visited_rooms.has(n) and not adjacent_unvisited.has(n):
				adjacent_unvisited.append(n)
				
	for room in adjacent_unvisited:
		var diff = room - current_room_coords
		var draw_pos = center_offset + Vector2(diff) * room_draw_size
		var rect = Rect2(draw_pos, room_draw_size)
		# 까만색으로 칠하기
		draw_rect(rect, Color(0, 0, 0, 0.95)) 
		draw_rect(rect, COLOR_BORDER, false, 1.0) 
	
	# 1. 방문했던 모든 방의 뼈대(배경과 테두리) 및 지형 그리기
	for room in visited_rooms:
		var is_current = (room == current_room_coords)
		
		var diff = room - current_room_coords
		var draw_pos = center_offset + Vector2(diff) * room_draw_size
		var rect = Rect2(draw_pos, room_draw_size)
		
		# 배경
		draw_rect(rect, COLOR_BG_CURRENT if is_current else COLOR_BG_VISITED)
		# 테두리
		draw_rect(rect, COLOR_BORDER, false, 2.0)
		
		# 지형(검은 점) 그리기
		if room_terrain_points.has(room):
			var fog := current_fog() if fog_enabled else {}
			for t_pos in room_terrain_points[room]:
				if fog_enabled and not GameManager.is_tile_seen(fog, tile_cell(t_pos)):
					continue
				var t_draw_pos = center_offset + (t_pos - current_room_origin) * MAP_SCALE
				# 타일 한 칸마다 작은 사각형 점을 찍음 (크기 2.0으로 상향)
				draw_rect(Rect2(t_draw_pos, Vector2(2.0, 2.0)), COLOR_TERRAIN)

	# 2. 방 내부의 요소들 그리기 — 오브젝트는 네모, 사람·몹은 동그라미. 다녀간 방에 있는 것만 보인다
	_draw_entities_as_dots("minimap_chest", COLOR_CHEST, center_offset, current_room_origin, false, true)
	_draw_entities_as_dots("minimap_door", COLOR_DOOR_CLOSED, center_offset, current_room_origin, false, true)
	_draw_entities_as_dots("minimap_elevator", COLOR_ELEVATOR, center_offset, current_room_origin, false, true)
	_draw_entities_as_dots("minimap_save", COLOR_SAVE, center_offset, current_room_origin, false, true)
	_draw_entities_as_dots("npc", COLOR_NPC, center_offset, current_room_origin, false)
	_draw_entities_as_dots("enemies", COLOR_ENEMY, center_offset, current_room_origin, true)
	_draw_entities_as_dots("bosses", COLOR_BOSS, center_offset, current_room_origin, false, false, 5.0)
	_draw_entities_as_dots(DeathDrop.MINIMAP_GROUP, COLOR_DEATH_DROP, center_offset, current_room_origin, false, false, 4.0)
	_draw_death_tooltip(center_offset, current_room_origin)

	# 3. 플레이어(초록 점) 그리기
	var p_draw_pos = center_offset + (player.global_position - current_room_origin) * MAP_SCALE
	draw_circle(p_draw_pos, 4.0, COLOR_PLAYER)

	# 4. 범례
	_draw_legend()

# 해골 표시에 마우스를 올리면 사인과 남은 금화 (미니맵을 연 동안 커서가 보인다)
const DEATH_HOVER_RADIUS := 7.0
func _draw_death_tooltip(center_offset: Vector2, current_room_origin: Vector2) -> void:
	var drop := hovered_death_drop(get_local_mouse_position(), center_offset, current_room_origin)
	if drop == null:
		return
	var text := death_tooltip_text(drop)
	var font := get_theme_default_font()
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, LEGEND_FONT_SIZE)
	var at := center_offset + (drop.global_position - current_room_origin) * MAP_SCALE + Vector2(8, -8 - text_size.y)
	at.x = clampf(at.x, 2.0, maxf(2.0, size.x - text_size.x - 8.0))
	at.y = clampf(at.y, 2.0, maxf(2.0, size.y - text_size.y - 6.0))
	var box := Rect2(at - Vector2(3, 2), text_size + Vector2(6, 4))
	draw_rect(box, Color(0, 0, 0, 0.85))
	draw_rect(box, COLOR_DEATH_DROP, false, 1.0)
	draw_string(font, at + Vector2(0, font.get_ascent(LEGEND_FONT_SIZE)), text, HORIZONTAL_ALIGNMENT_LEFT, -1, LEGEND_FONT_SIZE, Color.WHITE)

# local_mouse(미니맵 안 좌표) 근처의 해골 더미. 다녀간 방에 있는 것만
func hovered_death_drop(local_mouse: Vector2, center_offset: Vector2, current_room_origin: Vector2) -> Node2D:
	var best: Node2D = null
	var best_d := DEATH_HOVER_RADIUS
	for node in get_tree().get_nodes_in_group(DeathDrop.MINIMAP_GROUP):
		if not node is Node2D or node.is_queued_for_deletion() or not visited_rooms.has(_room_from_world(node.global_position)):
			continue
		var d := local_mouse.distance_to(center_offset + (node.global_position - current_room_origin) * MAP_SCALE)
		if d <= best_d:
			best = node
			best_d = d
	return best

static func death_tooltip_text(drop: Node) -> String:
	return TranslationServer.translate(&"MINIMAP_DEATH_TOOLTIP").format({
		"cause": DeathCause.describe(str(drop.get("cause"))), "gold": int(drop.get("gold")),
	})

func _draw_legend() -> void:
	var font := get_theme_default_font()
	var labels: Array[String] = []
	var width := 0.0
	for row in LEGEND:
		var text := ": " + tr(row[0])
		labels.append(text)
		width = maxf(width, font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, LEGEND_FONT_SIZE).x)
	var box := Rect2(Vector2.ZERO, Vector2(LEGEND_PADDING * 3.0 + 10.0 + width, LEGEND_PADDING * 2.0 + LEGEND_LINE * LEGEND.size()))
	draw_rect(box, COLOR_LEGEND_BG)
	for i in LEGEND.size():
		var row: Array = LEGEND[i]
		var mid := Vector2(LEGEND_PADDING + 5.0, LEGEND_PADDING + LEGEND_LINE * (i + 0.5))
		_draw_marker(mid, row[1], row[2], row[3])
		var baseline := mid.y + font.get_ascent(LEGEND_FONT_SIZE) * 0.5 - 1.0
		draw_string(font, Vector2(LEGEND_PADDING * 2.0 + 10.0, baseline), labels[i], HORIZONTAL_ALIGNMENT_LEFT, -1, LEGEND_FONT_SIZE, Color.WHITE)

# 미니맵 기호 하나 (검은 테두리 + 색). 지도와 범례가 같이 쓴다
func _draw_marker(pos: Vector2, color: Color, square: bool, radius: float) -> void:
	if square:
		var r := Rect2(pos - Vector2(radius, radius), Vector2(radius, radius) * 2.0)
		draw_rect(r.grow(1.0), COLOR_MARKER_OUTLINE)
		draw_rect(r, color)
	else:
		draw_circle(pos, radius + 1.0, COLOR_MARKER_OUTLINE)
		draw_circle(pos, radius, color)

# 지금 씬의 지형 기록. 지형 기록이 없던 옛 세이브면 다녀간 방은 전부 본 걸로 채운다
func current_fog() -> Dictionary:
	var fog: Dictionary = GameManager.map_fog(current_scene_path, fog_size.x, fog_size.y)
	if GameManager.take_fog_from_rooms(current_scene_path):
		var cells_per_room := Vector2i(roundi(room_size.x / TILE_SIZE), roundi(room_size.y / TILE_SIZE))
		for room in visited_rooms:
			for y in cells_per_room.y:
				for x in cells_per_room.x:
					GameManager.reveal_tile(fog, Vector2i(room.x * cells_per_room.x + x, room.y * cells_per_room.y + y))
	return fog

func tile_cell(world_pos: Vector2) -> Vector2i:
	var rel := world_pos - grid_origin
	return Vector2i(floori(rel.x / TILE_SIZE), floori(rel.y / TILE_SIZE))

# 플레이어 칸이 바뀔 때마다 주변 REVEAL_RADIUS_TILES 안의 칸을 지형 기록에 남긴다
func _reveal_terrain_around(player_pos: Vector2) -> void:
	var center := tile_cell(player_pos)
	if center == _last_fog_cell:
		return
	_last_fog_cell = center
	var fog := current_fog()
	var r := int(REVEAL_RADIUS_TILES)
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dy * dy <= r * r:
				GameManager.reveal_tile(fog, center + Vector2i(dx, dy))

# 플레이어 주변 REVEAL_RADIUS_TILES 안의 오브젝트를 "본 것"으로 기록한다 (세이브에 남는다)
func _record_nearby_objects(stage: Node, player_pos: Vector2) -> void:
	var radius := REVEAL_RADIUS_TILES * TILE_SIZE
	for group_name in REVEAL_GROUPS:
		for node in get_tree().get_nodes_in_group(group_name):
			if node is Node2D and node.global_position.distance_to(player_pos) <= radius:
				GameManager.see_map_object(current_scene_path, map_object_key(stage, node))

# 오브젝트를 세이브에서 가리키는 키: persist_id가 있으면 그것, 없으면 스테이지 기준 노드 경로
static func map_object_key(stage: Node, node: Node) -> String:
	if "persist_id" in node and str(node.persist_id) != "":
		return "id:" + str(node.persist_id)
	return "path:" + str(stage.get_path_to(node)) if stage != null else "path:" + str(node.get_path())

# 특정 그룹의 노드들을 미니맵에 점으로 찍어주는 도우미 함수
func _draw_entities_as_dots(group_name: String, color: Color, center_offset: Vector2, current_room_origin: Vector2, only_current_room: bool, square := false, radius := 3.0):
	var nodes = get_tree().get_nodes_in_group(group_name)
	for node in nodes:
		if not node is Node2D: continue
		if node.is_queued_for_deletion(): continue
		if "hp" in node and node.hp <= 0: continue # 쓰러진 몹·보스는 지운다
		
		var pos = node.global_position
		var room_coords = _room_from_world(pos)
		
		if not visited_rooms.has(room_coords): continue
		if only_current_room and room_coords != current_room_coords: continue
		if group_name in REVEAL_GROUPS and not GameManager.has_seen_map_object(current_scene_path, map_object_key(get_tree().current_scene, node)): continue
		
		var draw_pos = center_offset + (pos - current_room_origin) * MAP_SCALE
		_draw_marker(draw_pos, marker_color(node, color), square, radius)

# 같은 그룹이라도 상태에 따라 색이 다른 표시 (문: 닫힘 / 열림)
static func marker_color(node: Node, default_color: Color) -> Color:
	if node.has_method("is_open"):
		return COLOR_DOOR_OPEN if node.is_open() else COLOR_DOOR_CLOSED
	return default_color
