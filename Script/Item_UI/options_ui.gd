extends Control

@onready var btn_mode: OptionButton = $Panel/TabContainer/Graphics/HBox_Mode/BtnMode
@onready var btn_res: OptionButton = $Panel/TabContainer/Graphics/HBox_Res/BtnRes
@onready var btn_fps: OptionButton = $Panel/TabContainer/Graphics/HBox_FPS/BtnFPS
@onready var tab_container: TabContainer = $Panel/TabContainer
signal close_requested

@onready var slider_master: HSlider = $Panel/TabContainer/Audio/GridContainer/SliderMaster
@onready var slider_bgm: HSlider = $Panel/TabContainer/Audio/GridContainer/SliderBGM
@onready var slider_sfx: HSlider = $Panel/TabContainer/Audio/GridContainer/SliderSFX

@onready var slider_sens: HSlider = $"Panel/TabContainer/Control and game/GridContainer/SliderSens"
@onready var lbl_sens_value: Label = $"Panel/TabContainer/Control and game/GridContainer/Mouse Sensitivity"
@onready var btn_gore: CheckButton = $"Panel/TabContainer/Control and game/BtnGore"
@onready var slider_shake: HSlider = $"Panel/TabContainer/Control and game/GridContainer/SliderShake"
@onready var lbl_shake_value: Label = $"Panel/TabContainer/Control and game/GridContainer/ShakeValue"


var bus_index_master: int
var bus_index_bgm: int
var bus_index_sfx: int

# 1. 해상도 목록 (자주 쓰는 것들)
const RESOLUTIONS: Dictionary = {
	"640 x 360": Vector2i(640,360),
	"1280 x 720": Vector2i(1280, 720),
	"1920 x 1080": Vector2i(1920, 1080),
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
	visibility_changed.connect(_on_visibility_changed)
	
	bus_index_master = AudioServer.get_bus_index("Master")
	bus_index_bgm = AudioServer.get_bus_index("BGM")
	bus_index_sfx = AudioServer.get_bus_index("SFX")
	
	_init_audio_sliders()
	_init_game_settings()
	
	slider_shake.value_changed.connect(_on_shake_changed)
	
	# 3. 슬라이더 움직임 감지 연결
	slider_master.value_changed.connect(_on_master_volume_changed)
	slider_bgm.value_changed.connect(_on_bgm_volume_changed)
	slider_sfx.value_changed.connect(_on_sfx_volume_changed)
	
	
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
	var key = btn_res.get_item_text(index)
	var target_size = RESOLUTIONS[key]

	var current_mode = DisplayServer.window_get_mode()
	
	if current_mode == DisplayServer.WINDOW_MODE_FULLSCREEN or current_mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		print("전체 화면 상태라 해상도 크기를 변경하지 않습니다. (모니터 크기 유지)")
		return

	DisplayServer.window_set_size(target_size)
	_center_window()
	
	print("해상도 변경됨: ", target_size)

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
	close_requested.emit()
	# 혹은 설정을 파일에 저장하는 로직 호출 (SaveSettings)

func _on_visibility_changed():
	# 만약 내가 지금 '보이는 상태(true)'가 되었다면?
	if visible:
		# 탭을 0번(첫 번째 탭)으로 강제 설정
		tab_container.current_tab = 0

func _on_exit_button_pressed() -> void:
	visible = false
	close_requested.emit()

# --- [기능 1: 마우스 감도] ---
func _on_sens_changed(value: float):
	GameManager.mouse_sensitivity = value
	_update_sens_label(value)

func _update_sens_label(value: float):
	# 0.5 -> "50%" 처럼 보기 좋게 변환
	lbl_sens_value.text = "Mouse Sensitivity: " + str(int(value * 100)) + "%"

# --- [기능 2: 유혈 표현] ---
func _on_gore_toggled(toggled_on: bool):
	GameManager.enable_gore = toggled_on
	
func _init_game_settings():
	# 1. 마우스 감도 초기화 (저장된 값 불러오기)
	slider_sens.value = GameManager.mouse_sensitivity
	_update_sens_label(GameManager.mouse_sensitivity)
	
	slider_shake.value = GameManager.screenshake_intensity
	_update_shake_label(GameManager.screenshake_intensity)
	
	# 2. 유혈 표현 초기화
	btn_gore.button_pressed = GameManager.enable_gore
	
	# 3. 연결
	slider_sens.value_changed.connect(_on_sens_changed)
	btn_gore.toggled.connect(_on_gore_toggled)
	
	
func _init_audio_sliders():
	# 현재 오디오 서버의 실제 볼륨(db)을 가져와서 -> 슬라이더 값(0~1)으로 변환
	slider_master.value = db_to_linear(AudioServer.get_bus_volume_db(bus_index_master))
	slider_bgm.value = db_to_linear(AudioServer.get_bus_volume_db(bus_index_bgm))
	slider_sfx.value = db_to_linear(AudioServer.get_bus_volume_db(bus_index_sfx))
	
func _on_master_volume_changed(value: float):
	AudioServer.set_bus_volume_db(bus_index_master, linear_to_db(value))

func _on_bgm_volume_changed(value: float):
	AudioServer.set_bus_volume_db(bus_index_bgm, linear_to_db(value))

func _on_sfx_volume_changed(value: float):
	AudioServer.set_bus_volume_db(bus_index_sfx, linear_to_db(value))
	
func _on_shake_changed(value: float):
	GameManager.screenshake_intensity = value
	_update_shake_label(value)

func _update_shake_label(value: float):
	lbl_shake_value.text = "Shake Value: " + str(int(value * 100)) + "%"
