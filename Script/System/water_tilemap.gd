extends TileMapLayer
class_name WaterTileMap

# 물 타일맵: 타일셋 커스텀 데이터 "water"가 true인 칸이 물이다 (충돌 없음, 반투명으로 플레이어 위에 그린다).
# 플레이어는 몸 가운데가 물 칸 안에 있으면 수영 상태가 된다 (Player._update_water).

const GROUP := &"water_layers"

func _ready() -> void:
	add_to_group(GROUP)

func has_water_at(global_pos: Vector2) -> bool:
	var data := get_cell_tile_data(local_to_map(to_local(global_pos)))
	return data != null and data.get_custom_data("water") == true

# 씬에 있는 모든 물 타일맵 중 하나라도 그 자리가 물이면 true
static func is_water_at(tree: SceneTree, global_pos: Vector2) -> bool:
	for layer in tree.get_nodes_in_group(GROUP):
		if layer.has_water_at(global_pos):
			return true
	return false
