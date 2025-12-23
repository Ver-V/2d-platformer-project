extends Node2D

@export var player_scene: PackedScene
@export var room_size: Vector2 = Vector2(640.0, 360.0)
@export var grid_size: Vector2i = Vector2i(12, 3)
@export var grid_origin: Vector2 = Vector2(0.0, 0.0)

@onready var spawn_point: Marker2D = $SpawnPoint
@onready var entities: Node2D = $Entities
@onready var cam: Camera2D = $Camera2D

var player: CharacterBody2D = null
var current_room: Vector2i = Vector2i(0, 0)

	
func _enter_tree() -> void:
	var vp := get_viewport()
	vp.canvas_cull_mask = 1  # 레이어1(bit0)만 보이게
	# vp.set_canvas_cull_mask_bit(0, true) 와 동일

func _ready() -> void:
	cam.make_current()

	var dbg := Polygon2D.new()
	dbg.polygon = PackedVector2Array([
		Vector2(-30, -30), Vector2(30, -30), Vector2(30, 30), Vector2(-30, 30)
	])
	dbg.color = Color(1, 0, 0, 1)
	dbg.visibility_layer = 1
	add_child(dbg)
	dbg.global_position = Vector2(0.0, 0.0)

	spawn_player()

	var start_room := room_from_pos((player as Node2D).global_position)
	snap_to_room(start_room)

func _physics_process(delta: float) -> void:
	if player == null:
		return
	var new_room := room_from_pos((player as Node2D).global_position)
	if new_room != current_room:
		snap_to_room(new_room)

func spawn_player() -> void:
	if player_scene == null:
		push_error("player_scene is not assigned.")
		return

	var inst := player_scene.instantiate()
	player = inst as CharacterBody2D
	if player == null:
		push_error("Player scene root must be CharacterBody2D.")
		return

	entities.add_child(player)
	(player as Node2D).global_position = spawn_point.global_position

	force_layer1(player)

func force_layer1(n: Node) -> void:
	if n is CanvasItem:
		var ci := n as CanvasItem
		ci.visible = true
		ci.visibility_layer = 1
		var m := ci.modulate
		m.a = 1.0
		ci.modulate = m
	for c in n.get_children():
		force_layer1(c)

func room_from_pos(p: Vector2) -> Vector2i:
	var local := p - grid_origin
	var rx := int(floor(local.x / room_size.x))
	var ry := int(floor(local.y / room_size.y))
	rx = clamp(rx, 0, grid_size.x - 1)
	ry = clamp(ry, 0, grid_size.y - 1)
	return Vector2i(rx, ry)

func room_center(room: Vector2i) -> Vector2:
	return grid_origin + Vector2((float(room.x) + 0.5) * room_size.x,
								 (float(room.y) + 0.5) * room_size.y)

func snap_to_room(room: Vector2i) -> void:
	current_room = room
	cam.global_position = room_center(room)
