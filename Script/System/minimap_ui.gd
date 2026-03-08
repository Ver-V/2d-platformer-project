extends Control

# 미니맵 설정
const ROOM_SIZE = Vector2(640, 360) # room_grid.gd와 동일한 기준
const MAP_SCALE = 0.1 # 화면에 보여질 축소 비율 (1/10 크기)
const ROOM_DRAW_SIZE = ROOM_SIZE * MAP_SCALE

# 색상 설정
const COLOR_BG_VISITED = Color(0.7, 0.7, 0.7, 0.8)   # 방문한 방 배경 (밝은 회색)
const COLOR_BG_CURRENT = Color(0.9, 0.9, 1.0, 0.9)   # 현재 방 배경 (밝은 푸른빛)
const COLOR_BORDER = Color(0.3, 0.3, 0.3, 1.0)       # 방 테두리
const COLOR_PLAYER = Color.GREEN                     # 플레이어 (초록)
const COLOR_ENEMY = Color.RED                        # 적 (빨강)
const COLOR_NPC = Color.YELLOW                       # NPC (노랑)
const COLOR_OBJECT = Color.HOT_PINK                  # 상자/중요 오브젝트 (분홍)
const COLOR_TERRAIN = Color.BLACK                    # 지형 (검은색)

var current_room_coords: Vector2i = Vector2i.ZERO

# 지형 데이터를 담아둘 변수들
var room_terrain_points: Dictionary = {}
var valid_rooms: Array = []
var map_initialized: bool = false
var current_scene_path: String = ""

# RoomGrid 데이터 저장용
var map_origin_room: Vector2i = Vector2i(-9999, -9999)
var map_size_rooms: Vector2i = Vector2i(0, 0)

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
		current_room_coords = Vector2i(floor(pos.x / ROOM_SIZE.x), floor(pos.y / ROOM_SIZE.y))
		
		# 방문 기록에 없으면 추가 (새로운 방 발견!)
		if not GameManager.visited_rooms.has(current_room_coords):
			GameManager.visited_rooms.append(current_room_coords)
	
	# 화면이 계속 갱신되도록 다시 그리기 요청
	queue_redraw()

# 전체 타일맵을 뒤져서 어느 방에 지형이 있는지(valid_rooms) 파악하고 점 찍을 위치를 저장합니다.
func _init_map_data(scene_node: Node):
	room_terrain_points.clear()
	valid_rooms.clear()
	
	# RoomGrid 노드 찾아서 맵 경계선 설정
	var room_grid = scene_node.get_node_or_null("RoomGrid")
	if room_grid:
		var grid_origin = room_grid.get("origin")
		if grid_origin == null: grid_origin = Vector2.ZERO
		var counts = room_grid.get("rooms")
		
		map_origin_room = Vector2i(floor(grid_origin.x / ROOM_SIZE.x), floor(grid_origin.y / ROOM_SIZE.y))
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
	if (node is TileMapLayer or node is TileMap) and "Hazard" not in node.name:
		result.append(node)
	for child in node.get_children():
		result.append_array(_get_all_tilemap_layers(child))
	return result

func _add_terrain_point(global_pos: Vector2):
	var room_coords = Vector2i(floor(global_pos.x / ROOM_SIZE.x), floor(global_pos.y / ROOM_SIZE.y))
	
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
	var current_room_origin = Vector2(current_room_coords) * ROOM_SIZE
	
	# 0. 아직 방문하지 않았지만 갈 수 있는 인접한 방(새까맣게 표시)
	var adjacent_unvisited = []
	for v_room in GameManager.visited_rooms:
		# 현재 방문한 방의 상하좌우 검사
		var neighbors = [v_room + Vector2i(1, 0), v_room + Vector2i(-1, 0), v_room + Vector2i(0, 1), v_room + Vector2i(0, -1)]
		for n in neighbors:
			# 실제로 타일이 존재하는 유효한 방(valid_rooms)이면서, 아직 방문하지 않았다면? -> 까맣게 그릴 대상!
			if valid_rooms.has(n) and not GameManager.visited_rooms.has(n) and not adjacent_unvisited.has(n):
				adjacent_unvisited.append(n)
				
	for room in adjacent_unvisited:
		var diff = room - current_room_coords
		var draw_pos = center_offset + Vector2(diff) * ROOM_DRAW_SIZE
		var rect = Rect2(draw_pos, ROOM_DRAW_SIZE)
		# 까만색으로 칠하기
		draw_rect(rect, Color(0, 0, 0, 0.95)) 
		draw_rect(rect, COLOR_BORDER, false, 1.0) 
	
	# 1. 방문했던 모든 방의 뼈대(배경과 테두리) 및 지형 그리기
	for room in GameManager.visited_rooms:
		var is_current = (room == current_room_coords)
		
		var diff = room - current_room_coords
		var draw_pos = center_offset + Vector2(diff) * ROOM_DRAW_SIZE
		var rect = Rect2(draw_pos, ROOM_DRAW_SIZE)
		
		# 배경
		draw_rect(rect, COLOR_BG_CURRENT if is_current else COLOR_BG_VISITED)
		# 테두리
		draw_rect(rect, COLOR_BORDER, false, 2.0)
		
		# 지형(검은 점) 그리기
		if room_terrain_points.has(room):
			for t_pos in room_terrain_points[room]:
				var t_draw_pos = center_offset + (t_pos - current_room_origin) * MAP_SCALE
				# 타일 한 칸마다 작은 사각형 점을 찍음 (크기 2.0으로 상향)
				draw_rect(Rect2(t_draw_pos, Vector2(2.0, 2.0)), COLOR_TERRAIN)

	# 2. 방 내부의 요소들(점) 그리기
	_draw_entities_as_dots("npc", COLOR_NPC, center_offset, current_room_origin, false)
	_draw_entities_as_dots("chest", COLOR_OBJECT, center_offset, current_room_origin, false)
	_draw_entities_as_dots("object", COLOR_OBJECT, center_offset, current_room_origin, false)
	_draw_entities_as_dots("enemies", COLOR_ENEMY, center_offset, current_room_origin, true)

	# 3. 플레이어(초록 점) 그리기
	var p_draw_pos = center_offset + (player.global_position - current_room_origin) * MAP_SCALE
	draw_circle(p_draw_pos, 4.0, COLOR_PLAYER)

# 특정 그룹의 노드들을 미니맵에 점으로 찍어주는 도우미 함수
func _draw_entities_as_dots(group_name: String, color: Color, center_offset: Vector2, current_room_origin: Vector2, only_current_room: bool):
	var nodes = get_tree().get_nodes_in_group(group_name)
	for node in nodes:
		if not node is Node2D: continue
		
		var pos = node.global_position
		var room_coords = Vector2i(floor(pos.x / ROOM_SIZE.x), floor(pos.y / ROOM_SIZE.y))
		
		if not GameManager.visited_rooms.has(room_coords): continue
		if only_current_room and room_coords != current_room_coords: continue
		
		var draw_pos = center_offset + (pos - current_room_origin) * MAP_SCALE
		draw_circle(draw_pos, 3.0, color)
