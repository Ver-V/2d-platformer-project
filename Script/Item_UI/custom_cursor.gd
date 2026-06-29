extends CanvasLayer

@onready var cursor_sprite: Sprite2D = $CursorSprite
const CURSOR_NONE = preload("res://Assets/cursor_none.png")

# 논리적 마우스 좌표가 아닌 시스템 커서 기준 누적 오프셋
var sensitivity_offset: Vector2 = Vector2.ZERO
var last_mouse_pos: Vector2 = Vector2.ZERO

func _ready():
	# 처음엔 숨김
	cursor_sprite.visible = false
	
	# 웹 브라우저 대비용: 실제 시스템 커서 이미지를 아예 투명하게 덮어씌움
	Input.set_custom_mouse_cursor(CURSOR_NONE)

func _input(event):
	# 웹 버전의 경우 클릭 시 마우스 모드가 풀리는 현상 방지
	if event is InputEventMouseButton and event.pressed:
		if cursor_sprite.visible:
			Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	# 커서가 켜져 있을 때만 감도 계산
	if cursor_sprite.visible and event is InputEventMouseMotion:
		# 실제 마우스의 이동량(relative)에 감도를 곱한 만큼 오프셋을 누적
		# 감도가 1.0이면 오프셋은 0으로 유지됨
		var sensitivity_diff = event.relative * (GameManager.mouse_sensitivity - 1.0)
		sensitivity_offset += sensitivity_diff

func _process(_delta):
	if cursor_sprite.visible:
		# OS 기준 실제 마우스 위치 가져오기 (웹 클릭 어긋남 방지)
		var base_pos = get_viewport().get_mouse_position()
		
		# 시스템 위치에 감도 오프셋을 더해 최종 가짜 커서 위치 결정
		var final_pos = base_pos + sensitivity_offset
		
		# 화면 밖으로 가두기 (clamp)
		var viewport_rect = get_viewport().get_visible_rect()
		final_pos.x = clamp(final_pos.x, 0, viewport_rect.size.x)
		final_pos.y = clamp(final_pos.y, 0, viewport_rect.size.y)
		
		cursor_sprite.global_position = final_pos

# --- 외부 호출 함수 ---

func show_cursor():
	cursor_sprite.visible = true
	
	# 초기화: 커서를 켤 때마다 오프셋을 초기화하여 현재 마우스 위치와 동기화
	sensitivity_offset = Vector2.ZERO
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	
	cursor_sprite.global_position = get_viewport().get_mouse_position()

func hide_cursor():
	cursor_sprite.visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
