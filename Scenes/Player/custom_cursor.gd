extends CanvasLayer

@onready var cursor_sprite: Sprite2D = $Sprite2D

# 커서의 현재 위치 (직접 계산해야 함)
var cursor_pos: Vector2 = Vector2.ZERO

func _ready():
	# 1. 게임 켜자마자 시스템 마우스 숨기고 가두기
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	
	# 2. 커서 초기 위치를 화면 중앙으로
	var viewport_size = get_viewport().get_visible_rect().size
	cursor_pos = viewport_size / 2.0
	cursor_sprite.position = cursor_pos
	
	# 처음엔 보이게 시작 (메인 메뉴니까)
	show_cursor()

func _input(event):
	# 마우스가 움직일 때
	if event is InputEventMouseMotion:
		# 커서 이미지가 보일 때만 움직임 계산 (최적화)
		if cursor_sprite.visible:
			# [핵심] 이동 거리 * 감도
			cursor_pos += event.relative * GameManager.mouse_sensitivity
			
			# 화면 밖으로 못 나가게 막기 (Clamp)
			var viewport_rect = get_viewport().get_visible_rect()
			cursor_pos.x = clamp(cursor_pos.x, 0, viewport_rect.size.x)
			cursor_pos.y = clamp(cursor_pos.y, 0, viewport_rect.size.y)
			
			# 실제 이미지 위치 업데이트
			cursor_sprite.position = cursor_pos

# --- 외부에서 부를 함수들 ---

# 메뉴/인벤토리 열 때: "커서 보여줘!"
func show_cursor():
	cursor_sprite.visible = true
	# 필요하다면 시스템 마우스 모드 재확인
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

# 게임 플레이(전투) 들어갈 때: "커서 숨겨줘!"
func hide_cursor():
	cursor_sprite.visible = false

# (선택사항) 커서 위치를 강제로 옮길 때 (예: 창 열 때 중앙 정렬)
func center_cursor():
	var viewport_size = get_viewport().get_visible_rect().size
	cursor_pos = viewport_size / 2.0
	cursor_sprite.position = cursor_pos
