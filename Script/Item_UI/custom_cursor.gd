extends CanvasLayer

@onready var cursor_sprite: Sprite2D = $CursorSprite
const CURSOR_NONE = preload("res://Assets/cursor_none.png")

# 실제 클릭 위치와 커서 그림이 항상 같은 위치를 가리키게 한다.
var cursor_position: Vector2 = Vector2.ZERO
var _last_raw_position: Vector2 = Vector2.ZERO

func _ready():
	# 처음엔 숨김
	cursor_sprite.visible = false
	
	# 웹 브라우저 대비용: 실제 시스템 커서 이미지를 아예 투명하게 덮어씌움
	Input.set_custom_mouse_cursor(CURSOR_NONE)

func _input(event: InputEvent) -> void:
	# 웹 버전의 경우 클릭 시 마우스 모드가 풀리는 현상 방지
	if event is InputEventMouseButton and event.pressed:
		if cursor_sprite.visible:
			Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	if not cursor_sprite.visible:
		return

	if event is InputEventMouseMotion:
		var raw_position: Vector2 = event.position
		var raw_movement: Vector2 = raw_position - _last_raw_position
		var sensitivity := GameManager.mouse_sensitivity
		var viewport_size := get_viewport().get_visible_rect().size
		cursor_position += raw_movement * sensitivity
		cursor_position = cursor_position.clamp(Vector2.ZERO, viewport_size)
		_last_raw_position = raw_position

		# 실제 OS 포인터도 이동시켜 GUI의 호버·드래그·클릭 좌표를 맞춘다.
		# Web에서는 warp_mouse가 지원되지 않아 기본 커서 속도를 사용한다.
		if OS.has_feature("web"):
			cursor_position = raw_position
		elif cursor_position.distance_to(raw_position) > 0.5:
			get_viewport().warp_mouse(cursor_position)
			_last_raw_position = cursor_position

		event.position = cursor_position
		event.global_position = cursor_position
		event.relative = raw_movement * sensitivity
		event.velocity *= sensitivity
	elif event is InputEventMouseButton:
		event.position = cursor_position
		event.global_position = cursor_position

func _process(_delta):
	if cursor_sprite.visible:
		cursor_sprite.global_position = cursor_position

# --- 외부 호출 함수 ---

func show_cursor():
	cursor_sprite.visible = true
	
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	cursor_position = get_viewport().get_mouse_position()
	_last_raw_position = cursor_position
	cursor_sprite.global_position = cursor_position

func hide_cursor():
	cursor_sprite.visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
