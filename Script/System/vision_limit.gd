extends Node2D
class_name VisionLimit

# 플레이어 주변 원 안만 보이게 하는 시야 제한.
# 월드 공간에 그리므로 HUD·상점·인벤토리 등 CanvasLayer UI는 가려지지 않는다.
# BaseStage.vision_radius_tiles > 0 이면 스테이지가 자동으로 붙인다.

const SHADER: Shader = preload("res://resources/Shaders/vision_limit.gdshader")
const Z_INDEX: int = RenderingServer.CANVAS_ITEM_Z_MAX - 1

@export var radius_tiles: float = 4.0
@export var tile_size: float = 16.0
@export var edge_softness: float = 12.0
@export var darkness: Color = Color.BLACK
@export var center_offset: Vector2 = Vector2(0, -10) # 발밑 원점 → 몸 중앙

var target: Node2D = null
var _rect: ColorRect
var _material: ShaderMaterial

func _ready() -> void:
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
	_update()

func _process(_delta: float) -> void:
	_update()

func get_radius() -> float:
	return radius_tiles * tile_size

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
	_material.set_shader_parameter("center", eye)
	_material.set_shader_parameter("radius", get_radius())
	_material.set_shader_parameter("softness", edge_softness)
	_material.set_shader_parameter("darkness", darkness)
