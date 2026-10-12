@tool
extends StaticBody2D
class_name CrumblingBlock

# 플레이어가 위에 올라서면 흔들리다가 무너지고, 잠시 뒤 다시 생기는 한 칸(16px) 블록.
# 원점은 왼쪽 위 모서리. 몸통 충돌(CollisionShape2D)·그림(Sprite2D)·밟기 감지(Detector)가 씬에 들어 있어
# 에디터에서 보이는 그대로 작동한다. 긴 발판은 블록을 한 칸씩 이어 붙인다:
# 가로로 맞붙은 블록끼리는 한 덩어리라서 한 칸을 밟으면 이어진 블록이 전부 같이 무너진다 (crumble_alone이면 따로).
# @tool: 그림이 비어 있을 때 에디터에서도 임시 그림이 보이도록

@export var crumble_delay: float = 0.8 # 밟은 뒤 무너질 때까지
@export var respawn_delay: float = 3.0 # 무너진 뒤 다시 생길 때까지
@export var shake_amount: float = 1.5
@export var crumble_alone: bool = false # 켜면 옆에 붙은 블록과 묶이지 않고 혼자 무너진다
@export var texture: Texture2D: # 넣으면 Sprite2D 그림으로 쓴다. Sprite2D에 직접 넣어도 된다. 둘 다 비우면 임시 그림
	set(value):
		texture = value
		if is_node_ready():
			_apply_texture()

enum State { SOLID, SHAKING, BROKEN }
const TILE_SIZE := 16.0
const GROUP := &"crumbling_blocks"

@onready var body_shape: CollisionShape2D = $CollisionShape2D
@onready var sprite: Sprite2D = $Sprite2D
@onready var detector: Area2D = $Detector

var state: State = State.SOLID
var _shake_offset: Vector2 = Vector2.ZERO
var _generation: int = 0 # 노드가 나갔다 들어오면 진행 중이던 무너짐/재생성을 취소하기 위한 번호

func _ready() -> void:
	set_process(false) # 흔들릴 때만 켠다
	_apply_texture()
	if not Engine.is_editor_hint():
		add_to_group(GROUP)

func _apply_texture() -> void:
	if texture != null:
		sprite.texture = texture
	queue_redraw()

# 진입 신호 한 번이 아니라 매 프레임 확인한다: 점프 정점이 감지 영역 안이었다가 그대로 내려앉는 경우도 잡는다.
func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint() or state != State.SOLID:
		return
	for body in detector.get_overlapping_bodies():
		_try_step_on(body)

func _try_step_on(body: Node) -> void:
	if state != State.SOLID or not body.is_in_group("player"):
		return
	# 위로 점프하며 스치는 경우는 무시 (떨어지거나 서 있을 때만)
	if body is CharacterBody2D and body.velocity.y < 0.0:
		return
	for block in linked_blocks():
		if block.state == State.SOLID:
			block._crumble()

# 이 블록과 가로로 맞붙어 이어진 블록들 (자신 포함). crumble_alone인 블록은 묶음에 끼지 않는다
func linked_blocks() -> Array[CrumblingBlock]:
	var result: Array[CrumblingBlock] = [self]
	if crumble_alone or not is_inside_tree():
		return result
	var others: Array[CrumblingBlock] = []
	for node in get_tree().get_nodes_in_group(GROUP):
		var block := node as CrumblingBlock
		if block != null and block != self and not block.crumble_alone:
			others.append(block)
	var i := 0
	while i < result.size():
		var here := result[i].global_position
		for block in others:
			if result.has(block):
				continue
			var d := block.global_position - here
			if absf(d.y) < 1.0 and absf(absf(d.x) - TILE_SIZE) < 1.0:
				result.append(block)
		i += 1
	return result

func _crumble() -> void:
	var gen := _generation
	state = State.SHAKING
	set_process(true)
	await Wait.seconds(self, crumble_delay)
	if gen != _generation or not is_inside_tree():
		return
	state = State.BROKEN
	set_process(false)
	_set_shake(Vector2.ZERO)
	sprite.visible = false
	body_shape.set_deferred("disabled", true)
	queue_redraw()

	await Wait.seconds(self, respawn_delay)
	if gen != _generation or not is_inside_tree():
		return
	# 그 자리에 무언가 끼어 있으면 비켜날 때까지 기다린다 (플레이어가 블록 안에 갇히지 않게)
	while _is_occupied():
		await Wait.seconds(self, 0.2)
		if gen != _generation or not is_inside_tree():
			return
	state = State.SOLID
	sprite.visible = true
	body_shape.set_deferred("disabled", false)
	queue_redraw()

func _exit_tree() -> void:
	_generation += 1

# 흔들리는 동안만 켜진다
func _process(_delta: float) -> void:
	_set_shake(Vector2(randf_range(-shake_amount, shake_amount), 0.0))

func _set_shake(offset: Vector2) -> void:
	_shake_offset = offset
	sprite.position = offset
	queue_redraw()

func _is_occupied() -> bool:
	var query := PhysicsShapeQueryParameters2D.new()
	query.collision_mask = 2 | 4 | 8 # Player, Enemies, Bosses
	query.exclude = [get_rid()]
	var rect := RectangleShape2D.new()
	rect.size = Vector2(TILE_SIZE, TILE_SIZE)
	query.shape = rect
	query.transform = global_transform * Transform2D(0.0, Vector2(TILE_SIZE, TILE_SIZE) * 0.5)
	return not get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()

# Sprite2D에 그림이 없을 때만 임시 그림을 그린다
func _draw() -> void:
	if state == State.BROKEN or (sprite != null and sprite.texture != null):
		return
	var cell := Rect2(_shake_offset, Vector2(TILE_SIZE, TILE_SIZE))
	draw_rect(cell, Color(0.45, 0.33, 0.22))
	draw_rect(cell.grow(-1.0), Color(0.6, 0.45, 0.3))
	# 금 간 표시
	var c := cell.position
	draw_line(c + Vector2(4, 2), c + Vector2(8, 8), Color(0.3, 0.2, 0.12), 1.0)
	draw_line(c + Vector2(8, 8), c + Vector2(6, 14), Color(0.3, 0.2, 0.12), 1.0)
	draw_line(c + Vector2(8, 8), c + Vector2(13, 10), Color(0.3, 0.2, 0.12), 1.0)
