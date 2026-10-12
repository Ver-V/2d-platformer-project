extends Node2D
class_name VisionLimit

# 플레이어 주변 원 안만 보이게 하는 시야 제한.
# 월드 공간에 그리므로 HUD·상점·인벤토리 등 CanvasLayer UI는 가려지지 않는다.
# BaseStage.vision_radius_tiles > 0 이면 스테이지가 자동으로 붙인다.
# LIGHT_GROUP 노드(켜진 횃불 등: get_light_center() / get_light_radius())의 원 안도 밝힌다 — 화면 근처 MAX_LIGHTS개까지.

const SHADER: Shader = preload("res://resources/Shaders/vision_limit.gdshader")
const Z_INDEX: int = RenderingServer.CANVAS_ITEM_Z_MAX - 1

@export var radius_tiles: float = 4.0
@export var tile_size: float = 16.0
@export var edge_softness: float = 12.0
@export var darkness: Color = Color.BLACK
@export var center_offset: Vector2 = Vector2(0, -10) # 발밑 원점 → 몸 중앙
@export var radius_change_speed: float = 48.0 # 랜턴을 얻거나 잃을 때 반지름이 바뀌는 속도 (px/초)

var target: Node2D = null
var _rect: ColorRect
var _material: ShaderMaterial
var _shown_radius: float = -1.0 # 실제로 그리는 반지름. 목표값(get_radius)을 부드럽게 따라간다
var _bonus_tiles: float = 0.0 # 갖고 있는 아이템의 시야 보너스 (인벤토리가 바뀔 때만 다시 계산)
var _eye: Vector2 = Vector2.ZERO # 빛의 중심 (플레이어 몸 중앙)

const GROUP := &"vision_limit"
const LIGHT_GROUP := &"vision_light"
const MAX_LIGHTS := 16 # vision_limit.gdshader의 배열 크기와 같아야 한다

var _light_centers := PackedVector2Array()
var _light_radii := PackedFloat32Array()

func _ready() -> void:
	add_to_group(GROUP)
	# Inventory를 이름으로 직접 쓰지 않는다 — 테스트 스크립트가 autoload보다 먼저 이 클래스를 컴파일함
	var inventory := get_node_or_null("/root/Inventory")
	if inventory != null:
		inventory.inventory_changed.connect(_on_inventory_changed)
		_on_inventory_changed()
	# 맨 위 한 칸(Z_MAX)은 어둠 위에 보여야 하는 것(GlowEyes 등)용으로 비워둔다
	z_index = Z_INDEX
	z_as_relative = false
	process_priority = 100 # 플레이어·카메라가 움직인 뒤에 따라간다
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_rect = ColorRect.new()
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.material = _material
	add_child(_rect)
	_shown_radius = get_radius() # 시작할 때는 바로 맞춘다 (랜턴을 갖고 입장해도 넓어지는 연출 없이)
	_update()

func _process(delta: float) -> void:
	_shown_radius = move_toward(_shown_radius, get_radius(), radius_change_speed * delta)
	_update()

func _on_inventory_changed() -> void:
	_bonus_tiles = get_node("/root/Inventory").get_vision_bonus_tiles()

# 목표 반지름(px): 기본 반지름 + 갖고 있는 아이템의 시야 보너스(랜턴 등)
func get_radius() -> float:
	return (radius_tiles + _bonus_tiles) * tile_size

# 이 위치가 빛 안에 있는가 (지금 그려지는 반지름 기준). 어둠 위에 그리는 몹 체력바가 빛 밖에서는 숨는 데 쓴다
func is_lit(world_pos: Vector2) -> bool:
	if world_pos.distance_to(_eye) <= _shown_radius:
		return true
	for i in _light_centers.size():
		if world_pos.distance_to(_light_centers[i]) <= _light_radii[i]:
			return true
	return false

func _update() -> void:
	if not is_instance_valid(target):
		target = get_tree().get_first_node_in_group("player") as Node2D

	# 화면 전체를 덮도록 카메라 중심에 맞춘다 (줌·흔들림 여유분 포함)
	var view := get_viewport()
	var cam := view.get_camera_2d()
	var view_size := view.get_visible_rect().size
	var cover := view_size
	var center := global_position
	if cam != null:
		cover = view_size / cam.zoom
		center = cam.get_screen_center_position()
	cover *= 1.5
	_rect.size = cover
	_rect.global_position = center - cover * 0.5

	var eye := target.global_position + center_offset if is_instance_valid(target) else center
	_eye = eye
	_material.set_shader_parameter("center", eye)
	_material.set_shader_parameter("radius", _shown_radius)
	_material.set_shader_parameter("softness", edge_softness)
	_material.set_shader_parameter("darkness", darkness)
	_update_lights(Rect2(_rect.global_position, cover))

# 화면(cover)에 걸치는 빛만 가까운 순으로 MAX_LIGHTS개 골라 셰이더에 넘긴다
func _update_lights(view_rect: Rect2) -> void:
	var found: Array = []
	for node in get_tree().get_nodes_in_group(LIGHT_GROUP):
		var r: float = node.get_light_radius()
		if r <= 0.0:
			continue
		var c: Vector2 = node.get_light_center()
		if view_rect.grow(r).has_point(c):
			found.append([c.distance_squared_to(view_rect.get_center()), c, r])
	if found.size() > MAX_LIGHTS:
		found.sort_custom(func(a, b): return a[0] < b[0])
		found.resize(MAX_LIGHTS)
	_light_centers.resize(found.size())
	_light_radii.resize(found.size())
	for i in found.size():
		_light_centers[i] = found[i][1]
		_light_radii[i] = found[i][2]
	# 셰이더 배열은 크기가 고정이라 남는 칸을 채워서 넘긴다
	var centers := _light_centers.duplicate()
	var radii := _light_radii.duplicate()
	centers.resize(MAX_LIGHTS)
	radii.resize(MAX_LIGHTS)
	_material.set_shader_parameter("light_count", found.size())
	_material.set_shader_parameter("light_centers", centers)
	_material.set_shader_parameter("light_radii", radii)
