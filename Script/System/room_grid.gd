@tool
extends Node2D

@export var room_size: Vector2 = Vector2(640.0, 360.0)
@export var rooms: Vector2i = Vector2i(12, 3)
@export var origin: Vector2 = Vector2.ZERO
@export var line_color: Color = Color(1.0, 0.6, 0.0, 1.0) # 주황
@export var line_width: float = 2.0

func _enter_tree() -> void:
	if Engine.is_editor_hint():
		process_mode = Node.PROCESS_MODE_ALWAYS
		set_process(true)
		queue_redraw()

func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		queue_redraw()

func _draw() -> void:
	if not Engine.is_editor_hint():
		return
		
	var total_w: float = float(rooms.x) * room_size.x
	var total_h: float = float(rooms.y) * room_size.y

	for x in range(rooms.x + 1):
		var px: float = origin.x + float(x) * room_size.x
		draw_line(Vector2(px, origin.y), Vector2(px, origin.y + total_h), line_color, line_width)

	for y in range(rooms.y + 1):
		var py: float = origin.y + float(y) * room_size.y
		draw_line(Vector2(origin.x, py), Vector2(origin.x + total_w, py), line_color, line_width)
