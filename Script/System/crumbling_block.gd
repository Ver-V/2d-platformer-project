@tool
extends StaticBody2D
class_name CrumblingBlock

# 플레이어가 위에 올라서면 흔들리다가 무너지고, 잠시 뒤 다시 생기는 블록.
# 원점은 왼쪽 위 모서리. 타일(16px) 격자에 맞춰 놓고 width_tiles로 가로 길이를 정한다.
# independent_tiles를 켜면 노드 하나로 길게 깔아도 밟은 칸만 무너진다.
# @tool: 에디터에서도 블록 모양이 보이도록 (에디터에서는 그리기와 크기 조절만 한다)

@export_range(1, 64, 1) var width_tiles: int = 1:
	set(value):
		width_tiles = maxi(1, value)
		if is_node_ready():
			_rebuild()
@export var independent_tiles: bool = false: # true면 칸마다 따로 무너진다
	set(value):
		independent_tiles = value
		if is_node_ready():
			_rebuild()
@export var tile_size: float = 16.0
@export var crumble_delay: float = 0.8 # 밟은 뒤 무너질 때까지
@export var respawn_delay: float = 3.0 # 무너진 뒤 다시 생길 때까지
@export var shake_amount: float = 1.5
@export var texture: Texture2D: # 비워두면 임시 그림으로 그린다 (한 칸마다 반복)
	set(value):
		texture = value
		queue_redraw()

enum State { SOLID, SHAKING, BROKEN }

@onready var detector: Area2D = $Detector
@onready var detector_shape: CollisionShape2D = $Detector/CollisionShape2D

var tile_states: Array[State] = []
var _tile_owners: Array[int] = [] # 칸마다 하나씩 만든 충돌 shape owner
var _shake_offsets: Array[Vector2] = []
var _generation: int = 0 # 크기를 바꾸면 진행 중이던 무너짐/재생성을 취소하기 위한 번호

func _ready() -> void:
	set_process(false) # 흔들릴 때만 켠다
	if not Engine.is_editor_hint():
		add_to_group("object")
	_rebuild()

# 칸 수에 맞게 충돌·감지 영역·상태를 다시 만든다. 모든 칸은 멀쩡한 상태로 돌아간다.
func _rebuild() -> void:
	_generation += 1
	var size := Vector2(width_tiles * tile_size, tile_size)

	# 감지 영역: 윗면 바로 위의 얇은 띠 (아래에서 머리를 박으면 반응 없음)
	# 에디터에서 바꾸면 이 블록을 놓은 스테이지 씬에 변경이 저장되므로 실행 중에만 맞춘다.
	if not Engine.is_editor_hint():
		var top := RectangleShape2D.new()
		top.size = Vector2(size.x - 2.0, 4.0)
		detector_shape.shape = top
		detector_shape.position = Vector2(size.x * 0.5, -2.0)

	tile_states.clear()
	_shake_offsets.clear()
	for i in width_tiles:
		tile_states.append(State.SOLID)
		_shake_offsets.append(Vector2.ZERO)

	# 몸통 충돌: 노드를 늘리지 않고 칸마다 shape owner를 만든다 (에디터에서는 만들지 않는다)
	for owner_id in _tile_owners:
		remove_shape_owner(owner_id)
	_tile_owners.clear()
	if not Engine.is_editor_hint():
		for i in width_tiles:
			var owner_id := create_shape_owner(self)
			var rect := RectangleShape2D.new()
			rect.size = Vector2(tile_size, tile_size)
			shape_owner_add_shape(owner_id, rect)
			shape_owner_set_transform(owner_id, Transform2D(0.0, _tile_rect(i).get_center()))
			_tile_owners.append(owner_id)

	set_process(false)
	queue_redraw()

func _tile_rect(i: int) -> Rect2:
	return Rect2(Vector2(i * tile_size, 0.0), Vector2(tile_size, tile_size))

func is_tile_solid(i: int) -> bool:
	return tile_states[i] == State.SOLID

# 진입 신호 한 번이 아니라 매 프레임 확인한다: 점프 정점이 감지 영역 안이었다가 그대로 내려앉는 경우도 잡는다.
func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	for body in detector.get_overlapping_bodies():
		_try_step_on(body)

func _try_step_on(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	# 위로 점프하며 스치는 경우는 무시 (떨어지거나 서 있을 때만)
	if body is CharacterBody2D and body.velocity.y < 0.0:
		return
	var touched := _tiles_under(body)
	if touched.is_empty():
		return
	# 한 덩어리 모드: 어느 칸을 밟든 전부 같이 무너진다
	var candidates: Array = touched if independent_tiles else range(width_tiles)
	var group: Array[int] = []
	for i in candidates:
		if tile_states[i] == State.SOLID:
			group.append(i)
	if independent_tiles:
		if not group.is_empty():
			_crumble(group)
	elif group.size() == width_tiles:
		_crumble(group)

# 몸의 충돌 모양이 가로로 걸쳐 있는 칸 번호들
func _tiles_under(body: Node) -> Array[int]:
	var left := INF
	var right := -INF
	for child in body.get_children():
		var col := child as CollisionShape2D
		if col == null or col.disabled or col.shape == null:
			continue
		var rect := col.shape.get_rect()
		var a := to_local(col.global_transform * rect.position)
		var b := to_local(col.global_transform * rect.end)
		left = minf(left, minf(a.x, b.x))
		right = maxf(right, maxf(a.x, b.x))
	if left == INF and body is Node2D:
		left = to_local(body.global_position).x
		right = left
	var result: Array[int] = []
	if right < 0.0 or left > width_tiles * tile_size:
		return result
	# 옆 칸 경계에 1px 닿은 정도는 밟은 것으로 치지 않는다
	var first := clampi(int(floor((left + 1.0) / tile_size)), 0, width_tiles - 1)
	var last := clampi(int(floor((right - 1.0) / tile_size)), 0, width_tiles - 1)
	for i in range(first, last + 1):
		result.append(i)
	return result

func _crumble(group: Array[int]) -> void:
	var gen := _generation
	for i in group:
		tile_states[i] = State.SHAKING
	set_process(true)
	await Wait.seconds(self, crumble_delay)
	if gen != _generation or not is_inside_tree():
		return
	for i in group:
		tile_states[i] = State.BROKEN
		_shake_offsets[i] = Vector2.ZERO
		shape_owner_set_disabled(_tile_owners[i], true)
	_update_shaking()
	queue_redraw()

	await Wait.seconds(self, respawn_delay)
	if gen != _generation or not is_inside_tree():
		return
	# 그 자리에 무언가 끼어 있으면 비켜날 때까지 기다린다 (플레이어가 블록 안에 갇히지 않게)
	while _is_occupied(group):
		await Wait.seconds(self, 0.2)
		if gen != _generation or not is_inside_tree():
			return
	for i in group:
		tile_states[i] = State.SOLID
		shape_owner_set_disabled(_tile_owners[i], false)
	queue_redraw()

# 흔들리는 칸이 있을 때만 켜진다
func _process(_delta: float) -> void:
	for i in width_tiles:
		if tile_states[i] == State.SHAKING:
			_shake_offsets[i] = Vector2(randf_range(-shake_amount, shake_amount), 0.0)
	queue_redraw()
	_update_shaking()

func _update_shaking() -> void:
	set_process(tile_states.has(State.SHAKING))

func _is_occupied(group: Array[int]) -> bool:
	var space := get_world_2d().direct_space_state
	var query := PhysicsShapeQueryParameters2D.new()
	query.collision_mask = 2 | 4 | 8 # Player, Enemies, Bosses
	query.exclude = [get_rid()]
	var rect := RectangleShape2D.new()
	rect.size = Vector2(tile_size, tile_size)
	query.shape = rect
	for i in group:
		query.transform = global_transform * Transform2D(0.0, _tile_rect(i).get_center())
		if not space.intersect_shape(query, 1).is_empty():
			return true
	return false

func _draw() -> void:
	for i in width_tiles:
		if i < tile_states.size() and tile_states[i] == State.BROKEN:
			continue
		var cell := _tile_rect(i)
		if i < _shake_offsets.size():
			cell.position += _shake_offsets[i]
		if texture != null:
			draw_texture_rect(texture, cell, false)
		else:
			draw_rect(cell, Color(0.45, 0.33, 0.22))
			draw_rect(cell.grow(-1.0), Color(0.6, 0.45, 0.3))
			# 금 간 표시
			var c := cell.position
			draw_line(c + Vector2(4, 2), c + Vector2(8, 8), Color(0.3, 0.2, 0.12), 1.0)
			draw_line(c + Vector2(8, 8), c + Vector2(6, 14), Color(0.3, 0.2, 0.12), 1.0)
			draw_line(c + Vector2(8, 8), c + Vector2(13, 10), Color(0.3, 0.2, 0.12), 1.0)
