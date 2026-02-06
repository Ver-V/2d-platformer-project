extends CanvasLayer

@onready var cursor_sprite: Sprite2D = $CursorSprite

# 커서의 논리적 위치 (화면 좌표)
var cursor_pos: Vector2

# [핵심] 무한 루프 방지용 플래그
var is_warping: bool = false

func _ready():
	# 처음엔 숨김
	cursor_sprite.visible = false
	
	# 초기 위치 중앙
	var win_size = get_viewport().get_visible_rect().size
	cursor_pos = win_size / 2.0
	cursor_sprite.global_position = cursor_pos

func _input(event):
	# 커서가 켜져 있을 때만 작동
	if cursor_sprite.visible:
		if event is InputEventMouseMotion:
			
			# [중요] 내가 방금 warp_mouse로 옮긴 거라면 계산하지 말고 무시해!
			if is_warping:
				is_warping = false
				return
			
			# 1. 감도 적용 (내 손의 움직임 * 감도)
			# (relative 값이 너무 작으면 안 움직일 수 있으니 최소값 보정은 선택)
			cursor_pos += event.relative * GameManager.mouse_sensitivity
			
			# 2. 화면 밖으로 못 나가게 가두기
			var viewport_rect = get_viewport().get_visible_rect()
			cursor_pos.x = clamp(cursor_pos.x, 0, viewport_rect.size.x)
			cursor_pos.y = clamp(cursor_pos.y, 0, viewport_rect.size.y)
			
			# 3. 가짜 커서 그림 이동
			cursor_sprite.global_position = cursor_pos
			
			# 4. [핵심] 실제 마우스를 그 위치로 강제 이동
			# warp_mouse를 쓰면 다음 프레임에 또 Motion 이벤트가 발생함 -> is_warping으로 무시
			is_warping = true 
			get_viewport().warp_mouse(cursor_pos)

# --- 외부 호출 함수 ---

func show_cursor():
	cursor_sprite.visible = true
	
	# [중요] 켜질 때 모드를 'Hidden'(숨김+자유)으로 변경
	# CAPTURED 상태에서는 warp_mouse가 제대로 안 먹힐 수 있음
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	
	# 켜지는 순간 현재 마우스 위치로 동기화
	cursor_pos = get_viewport().get_mouse_position()
	cursor_sprite.global_position = cursor_pos

func hide_cursor():
	cursor_sprite.visible = false
	# 게임 플레이 중엔 다시 가두기
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
