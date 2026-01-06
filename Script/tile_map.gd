extends TileMapLayer

@export var sample_offset: Vector2 = Vector2(0.0, 16.0)
@export var knockback_x: float = 320.0
@export var knockback_y: float = -240.0
@export var tick: float = 0.5 # 데미지 주는 간격

var player: CombatBody2D = null # 타입을 CombatBody2D로 명시
var _accum: float = 0.0

func _process(delta: float) -> void:
	if player == null:
		return

	_accum += delta
	if _accum < tick:
		return

	# 플레이어가 이미 무적 상태면 연산 건너뛰기
	if player.is_invulnerable():
		return

	var p_pos: Vector2 = player.global_position + sample_offset
	var cell: Vector2i = local_to_map(to_local(p_pos))
	
	# 타일 데이터 확인
	var data := get_cell_tile_data(cell)
	if data == null:
		return

	var dmg: int = int(data.get_custom_data("damage"))
	if dmg <= 0:
		return

	# 데미지 적용 시도
	_accum = 0.0 # 틱 초기화
	
	var cell_center: Vector2 = to_global(map_to_local(cell))
	var dx: float = player.global_position.x - cell_center.x
	var knock_dir := Vector2(1.0 if dx >= 0.0 else -1.0, 0.0)
	
	# 넉백 벡터 계산
	var final_kb = Vector2(knock_dir.x * knockback_x, knockback_y)
	
	# 데미지와 넉백을 한 번에 전달
	player.apply_damage(dmg, final_kb)
