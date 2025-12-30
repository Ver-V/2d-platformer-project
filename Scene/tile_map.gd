extends TileMapLayer

@export var player_path: NodePath
@export var sample_offset: Vector2 = Vector2(0.0, 10.0)

var _accum: float = 0.0

func _process(delta: float) -> void:
	if player_path == NodePath():
		return

	var player := get_node(player_path)
	if player == null:
		return

	var tick := 0.5
	if "invincible_time" in player:
		tick = float(player.invincible_time) + 0.05

	_accum += delta
	if _accum < tick:
		return

	var p: Vector2 = player.global_position + sample_offset
	var cell: Vector2i = local_to_map(to_local(p))

	var data := get_cell_tile_data(cell)
	if data == null:
		print("NO TILE", cell, "p=", p, "local=", to_local(p))
		return

	var dmg := int(data.get_custom_data("damage"))
	print("HIT", cell, "dmg=", dmg)

	if player.has_method("apply_damage"):
		player.apply_damage(dmg)
		_accum = 0.0
