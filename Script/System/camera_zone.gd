@tool
extends Node2D
class_name CameraZone

# 카메라 구역: 방 여러 개(rooms, 방 좌표 기준 사각형)를 하나로 묶는다. 플레이어가 이 안의 어느 방에 있든
# 카메라는 구역 전체의 가운데에 서고, 확대(zoom)를 바꾼다. 보스방처럼 넓게 보여야 하는 곳에 쓴다.
# 스테이지(BaseStage) 아래 아무 데나 두면 된다. 위치는 쓰지 않고 rooms만 본다 (에디터에서 그 영역을 테두리로 보여 준다).
# zoom = 0이면 구역이 화면에 꽉 차게 자동 (기본 화면 1280x720, 방 640x360이면 2x2 구역 → 1배).
# 구역 안에서 방을 옮겨 다녀도 투사체를 지우지 않는다.

@export var rooms: Rect2i = Rect2i(0, 0, 2, 2):
	set(value):
		rooms = value
		queue_redraw()
@export var zoom: float = 0.0
@export var transition_time: float = 0.4 # 들어오고 나갈 때 카메라가 옮겨 가는 시간

func contains_room(r: Vector2i) -> bool:
	return rooms.has_point(r)

# 구역의 월드 사각형 (스테이지 기준 좌표)
func world_rect(room_size: Vector2, grid_origin: Vector2) -> Rect2:
	return Rect2(grid_origin + Vector2(rooms.position) * room_size, Vector2(rooms.size) * room_size)

# 이 구역에서 쓸 카메라 확대. zoom이 0이면 viewport_size에 구역이 꽉 차게
func zoom_for(room_size: Vector2, viewport_size: Vector2) -> Vector2:
	if zoom > 0.0:
		return Vector2(zoom, zoom)
	var size := Vector2(rooms.size) * room_size
	var z := minf(viewport_size.x / size.x, viewport_size.y / size.y)
	return Vector2(z, z)

func _ready() -> void:
	if not Engine.is_editor_hint():
		visible = false

func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	# 에디터: 부모 스테이지의 방 크기로 영역을 그린다 (스테이지 원점 기준이라 이 노드 위치를 빼서 그림)
	var stage := get_parent()
	var room_size: Vector2 = stage.get("room_size") if stage != null and stage.get("room_size") != null else Vector2(640, 360)
	var origin: Vector2 = stage.get("grid_origin") if stage != null and stage.get("grid_origin") != null else Vector2.ZERO
	var rect := world_rect(room_size, origin)
	rect.position -= position
	draw_rect(rect, Color(1.0, 0.55, 0.1, 0.12))
	draw_rect(rect, Color(1.0, 0.55, 0.1, 0.9), false, 4.0)
