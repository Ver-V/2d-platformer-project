extends TileMapLayer

@export var sample_offset: Vector2 = Vector2(0.0, 16.0)
@export var knockback_x: float = 200.0
@export var knockback_y: float = -160.0
@export var tick: float = 0.75

var player: Node2D = null
var _accum: float = 0.0

func _process(delta: float) -> void:
	if player == null:
		return

	if "invincible_time" in player:
		tick = float(player.invincible_time) + 0.05

	_accum += delta
	if _accum < tick:
		return

	var p: Vector2 = player.global_position + sample_offset
	var cell: Vector2i = local_to_map(to_local(p))

	var data := get_cell_tile_data(cell)
	if data == null:
		return

	var dmg: int = int(data.get_custom_data("damage"))
	if dmg <= 0:
		return

	var cell_center_local: Vector2 = map_to_local(cell) + get_tile_set().tile_size * 0.5
	var cell_center_global: Vector2 = to_global(cell_center_local)

	var dx: float = player.global_position.x - cell_center_global.x
	var dir: Vector2 = Vector2(1.0 if dx >= 0.0 else -1.0, 0.0)

	if player.has_method("apply_damage"):
		player.apply_damage(dmg)
	if player.has_method("apply_knockback"):
		player.apply_knockback(dir, knockback_x, knockback_y, false, true)
