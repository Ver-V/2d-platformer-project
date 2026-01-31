extends Control

@onready var btn_mode: OptionButton = $Panel/TabContainer/Graphics/HBox_Mode/BtnMode
@onready var btn_res: OptionButton = $Panel/TabContainer/Graphics/HBox_Res/BtnRes
@onready var btn_fps: OptionButton = $Panel/TabContainer/Graphics/HBox_FPS/BtnFPS

# 1. 해상도 목록 (자주 쓰는 것들)
const RESOLUTIONS: Dictionary = {
	"640 x 360": Vector2i(640,360),
	"1280 x 720": Vector2i(1280, 720),
	"2560 x 1440": Vector2i(2560, 1440),
	"3840 x 2160": Vector2i(3840, 2160)
}

# 2. 화면 모드 목록
const WINDOW_MODES: Array = [
	"Windowed",
	"Fullscreen",
	"Borderless"
]

# 3. FPS(Hz) 목록
# Godot에서 Hz를 강제로 바꾸는 건 위험할 수 있어서(블랙스크린),
# 보통 '최대 FPS 제한'을 두는 방식으로 처리합니다.
const FPS_LIMITS: Dictionary = {
	"30 FPS": 30,
	"60 FPS": 60,
	"144 FPS": 144,
	"240 FPS": 240,
	"무제한": 0 # 0은 제한 없음
}

func _ready():
	_add_items_to_ui()
	_connect_signals()

func _add_items_to_ui():
	# 1. 화면 모드 추가
	for mode in WINDOW_MODES:
		btn_mode.add_item(mode)
	
	# 2. 해상도 추가
	for res_name in RESOLUTIONS.keys():
		btn_res.add_item(res_name)
		
	# 3. FPS 추가
	for fps_name in FPS_LIMITS.keys():
		btn_fps.add_item(fps_name)

func _connect_signals():
	# 옵션을 선택했을 때 실행될 함수 연결
	btn_mode.item_selected.connect(_on_mode_selected)
	btn_res.item_selected.connect(_on_resolution_selected)
	btn_fps.item_selected.connect(_on_fps_selected)

# --- 기능 구현 ---

func _on_mode_selected(index: int):
	match index:
		0: # 창 모드
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
		1: # 전체 화면
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
		2: # 테두리 없는 창 모드
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	
	print("화면 모드 변경됨: ", index)

func _on_resolution_selected(index: int):
	# 선택된 텍스트 가져오기
	var key = btn_res.get_item_text(index)
	var _res_size = RESOLUTIONS[key]
	
	# 해상도 적용
	DisplayServer.window_set_size(size)
	
	# 창 모드일 때만 화면 중앙으로 이동 (전체화면일 땐 의미 없음)
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED:
		_center_window()
		
	print("해상도 변경됨: ", size)

func _on_fps_selected(index: int):
	var key = btn_fps.get_item_text(index)
	var limit = FPS_LIMITS[key]
	
	# 엔진의 최대 FPS 설정
	Engine.max_fps = limit
	print("FPS 제한 변경됨: ", limit)

# 창을 모니터 정중앙으로 옮기는 헬퍼 함수
func _center_window():
	var screen_id = DisplayServer.window_get_current_screen()
	var screen_size = DisplayServer.screen_get_size(screen_id)
	var window_size = DisplayServer.window_get_size()
	var center_pos = (screen_size - window_size) / 2
	DisplayServer.window_set_position(center_pos)

# (옵션) 닫기 버튼용
func _on_close_button_pressed():
	visible = false
	# 혹은 설정을 파일에 저장하는 로직 호출 (SaveSettings)
