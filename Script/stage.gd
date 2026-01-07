extends Node2D

@export var player_scene: PackedScene
@export var room_size: Vector2 = Vector2(640.0, 360.0)
@export var grid_size: Vector2i = Vector2i(12, 3)
@export var grid_origin: Vector2 = Vector2(0.0, 0.0)

@export var reset_enemies_on_room_enter: bool = true
@export var deactivate_enemies_outside_room: bool = true

@export var clear_projectiles_on_room_change: bool = true
@export var clear_projectiles_outside_current_room: bool = true

@onready var spawn_point: Marker2D = $SpawnPoint as Marker2D
@onready var entities: Node2D = $Entities as Node2D
@onready var cam: Camera2D = $Camera2D as Camera2D

var player: Player = null
var current_room: Vector2i = Vector2i(-1, -1)

var killed_ids: Dictionary = {}

func _ready() -> void:
	cam.make_current()

	spawn_player()
	register_enemies()
	assign_persist_ids_by_formula()

	if player == null:
		return

	if not player.died.is_connected(_on_player_died):
		player.died.connect(_on_player_died)

	snap_to_room(room_from_pos(player.global_position), true)

func _on_player_died() -> void:
	restart_stage()

func restart_stage() -> void:
	get_tree().reload_current_scene()

func _physics_process(_delta: float) -> void:
	if player == null:
		return

	var r: Vector2i = room_from_pos(player.global_position)
	if r != current_room:
		snap_to_room(r, false)

func spawn_player() -> void:
	if player_scene == null:
		push_error("player_scene is not assigned.")
		return

	var inst: Node = player_scene.instantiate()
	var p: Player = inst as Player
	if p == null:
		push_error("Player scene root must be Player (CharacterBody2D with Player.gd).")
		return

	entities.add_child(p)
	p.global_position = spawn_point.global_position
	player = p

func snap_to_room(r: Vector2i, is_initial: bool) -> void:
	current_room = r
	cam.global_position = room_center(r)

	if not is_initial:
		if clear_projectiles_on_room_change:
			clear_projectiles(true)
		elif clear_projectiles_outside_current_room:
			clear_projectiles(false)
	else:
		if clear_projectiles_outside_current_room:
			clear_projectiles(false)

	apply_room_rules(r)

func apply_room_rules(r: Vector2i) -> void:
	var nodes: Array = get_tree().get_nodes_in_group("enemies")
	for n in nodes:
		var e: EnemyBase = n as EnemyBase
		if e == null:
			continue

		var id: StringName = e.get_persist_id()
		if killed_ids.has(id):
			e.queue_free()
			continue

		var eroom: Vector2i = room_from_pos(e.home_position)

		if eroom == r:
			if reset_enemies_on_room_enter:
				e.reset_to_home(true)
			e.set_active(true)
		else:
			if deactivate_enemies_outside_room:
				e.reset_to_home(false) # 공중 정지 방지 (위치/속도 정리)
				e.set_active(false)


func clear_projectiles(clear_all: bool) -> void:
	var nodes: Array = get_tree().get_nodes_in_group("projectiles")
	for n in nodes:
		var p: Node2D = n as Node2D
		if p == null:
			continue

		if clear_all:
			p.queue_free()
		else:
			var pr: Vector2i = room_from_pos(p.global_position)
			if pr != current_room:
				p.queue_free()

func register_enemies() -> void:
	var nodes: Array = get_tree().get_nodes_in_group("enemies")
	for n in nodes:
		var e: EnemyBase = n as EnemyBase
		if e == null:
			continue
		if not e.died.is_connected(_on_enemy_died):
			e.died.connect(_on_enemy_died)

func _on_enemy_died(e: EnemyBase) -> void:
	killed_ids[e.get_persist_id()] = true

func assign_persist_ids_by_formula() -> void:
	var nodes: Array = get_tree().get_nodes_in_group("enemies")

	var per_room: Dictionary = {}
	for n in nodes:
		var e: EnemyBase = n as EnemyBase
		if e == null:
			continue
		var rid: int = room_id_from_pos(e.home_position)

		if not per_room.has(rid):
			per_room[rid] = []
		var arr: Array = per_room[rid] as Array
		arr.append(e)
		per_room[rid] = arr

	var total_rooms: int = grid_size.x * grid_size.y
	var rid2: int = 1
	while rid2 <= total_rooms:
		if per_room.has(rid2):
			var arr2: Array = per_room[rid2] as Array
			arr2.sort_custom(Callable(self, "_sort_enemy_home"))

			var i: int = 0
			while i < arr2.size():
				var e2: EnemyBase = arr2[i] as EnemyBase
				if e2 != null and e2.persist_id == &"":
					var idx: int = i + 1
					var s: String = "R%02d_E%02d" % [rid2, idx]
					e2.persist_id = StringName(s)
				i += 1
		rid2 += 1

func _sort_enemy_home(a: Variant, b: Variant) -> bool:
	var ea: EnemyBase = a as EnemyBase
	var eb: EnemyBase = b as EnemyBase
	if ea == null and eb == null:
		return false
	if ea == null:
		return true
	if eb == null:
		return false

	var ay: float = ea.home_position.y
	var by: float = eb.home_position.y
	if ay == by:
		return ea.home_position.x < eb.home_position.x
	return ay < by

func room_from_pos(p: Vector2) -> Vector2i:
	var local: Vector2 = p - grid_origin
	var rx: int = clampi(int(floor(local.x / room_size.x)), 0, grid_size.x - 1)
	var ry: int = clampi(int(floor(local.y / room_size.y)), 0, grid_size.y - 1)
	return Vector2i(rx, ry)

func room_center(r: Vector2i) -> Vector2:
	return grid_origin + Vector2((float(r.x) + 0.5) * room_size.x,
								 (float(r.y) + 0.5) * room_size.y)

func room_id_from_xy(x: int, y: int) -> int:
	return y * grid_size.x + x + 1

func room_id_from_pos(p: Vector2) -> int:
	var r: Vector2i = room_from_pos(p)
	return room_id_from_xy(r.x, r.y)
