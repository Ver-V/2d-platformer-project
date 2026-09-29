extends CanvasLayer

@onready var btn_mode: OptionButton = $OptionsUI/Panel/TabContainer/Graphics/HBox_Mode/BtnMode
@onready var btn_res: OptionButton = $OptionsUI/Panel/TabContainer/Graphics/HBox_Res/BtnRes
@onready var btn_fps: OptionButton = $OptionsUI/Panel/TabContainer/Graphics/HBox_FPS/BtnFPS
@onready var tab_container: TabContainer = $OptionsUI/Panel/TabContainer
signal close_requested

@onready var slider_master: HSlider = $OptionsUI/Panel/TabContainer/Audio/GridContainer/SliderMaster
@onready var slider_bgm: HSlider = $OptionsUI/Panel/TabContainer/Audio/GridContainer/SliderBGM
@onready var slider_sfx: HSlider = $OptionsUI/Panel/TabContainer/Audio/GridContainer/SliderSFX

@onready var slider_sens: HSlider = $"OptionsUI/Panel/TabContainer/Control and game/GridContainer/SliderSens"
@onready var lbl_sens_value: Label = $"OptionsUI/Panel/TabContainer/Control and game/GridContainer/Mouse Sensitivity"
@onready var slider_shake: HSlider = $"OptionsUI/Panel/TabContainer/Control and game/GridContainer/SliderShake"
@onready var lbl_shake_value: Label = $"OptionsUI/Panel/TabContainer/Control and game/GridContainer/ShakeValue"
@onready var btn_language: OptionButton = $"OptionsUI/Panel/TabContainer/Control and game/GridContainer/BtnLanguage"


var bus_index_master: int
var bus_index_bgm: int
var bus_index_sfx: int

# 1. 해상도 목록 (자주 쓰는 것들)
const RESOLUTIONS: Dictionary = {
	"1280 x 720": Vector2i(1280, 720),
	"1920 x 1080": Vector2i(1920, 1080),
	"2560 x 1440": Vector2i(2560, 1440),
	"3840 x 2160": Vector2i(3840, 2160)
}

# 2. 화면 모드 목록
const WINDOW_MODE_KEYS: Array[StringName] = [
	&"OPTIONS_WINDOWED",
	&"OPTIONS_FULLSCREEN",
	&"OPTIONS_BORDERLESS"
]

const LANGUAGE_CODES: Array[String] = ["en", "ko"]
const LANGUAGE_NAMES: Array[String] = ["English", "한국어"]

# 3. FPS(Hz) 목록
# Godot에서 Hz를 강제로 바꾸는 건 위험할 수 있어서(블랙스크린),
# 보통 '최대 FPS 제한'을 두는 방식으로 처리합니다.
const FPS_OPTIONS: Array[Dictionary] = [
	{"label_key": &"OPTIONS_FPS_30", "value": 30},
	{"label_key": &"OPTIONS_FPS_60", "value": 60},
	{"label_key": &"OPTIONS_FPS_144", "value": 144},
	{"label_key": &"OPTIONS_FPS_240", "value": 240},
	{"label_key": &"OPTIONS_FPS_UNLIMITED", "value": 0}
]

func _ready():
	_add_items_to_ui()
	_connect_signals()
	visibility_changed.connect(_on_visibility_changed)
	GameManager.locale_changed.connect(_on_locale_changed)
	
	# 모든 버튼 및 옵션 버튼에 클릭 소리 연결
	for btn in find_children("*", "BaseButton", true):
		btn.pressed.connect(GameManager.play_ui_click)
	for opt in find_children("*", "OptionButton", true):
		opt.item_selected.connect(func(_idx): GameManager.play_ui_click())
	
	bus_index_master = AudioServer.get_bus_index("Master")
	bus_index_bgm = AudioServer.get_bus_index("BGM")
	bus_index_sfx = AudioServer.get_bus_index("SFX")
	
	_init_audio_sliders()
	_init_game_settings()
	_init_language_ui()
	_init_graphics_ui() # 그래픽 UI 초기화 추가
	_refresh_translated_texts()
	
	slider_shake.value_changed.connect(_on_shake_changed)
	
	# 3. 슬라이더 움직임 감지 연결
	slider_master.value_changed.connect(_on_master_volume_changed)
	slider_bgm.value_changed.connect(_on_bgm_volume_changed)
	slider_sfx.value_changed.connect(_on_sfx_volume_changed)

func _init_graphics_ui():
	# 1. 화면 모드 초기값 설정
	var current_mode = DisplayServer.window_get_mode()
	var is_borderless = DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_BORDERLESS)
	
	if current_mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
		btn_mode.selected = 1
	elif is_borderless:
		btn_mode.selected = 2
	else:
		btn_mode.selected = 0
		
	# 2. 해상도 초기값 설정
	var current_res = DisplayServer.window_get_size()
	var res_found = false
	for i in range(btn_res.item_count):
		var res_name = btn_res.get_item_text(i)
		if RESOLUTIONS.has(res_name) and RESOLUTIONS[res_name] == current_res:
			btn_res.selected = i
			res_found = true
			break
	if not res_found:
		# 목록에 없는 해상도면 가장 가까운 것이나 기본값 표시 (여기서는 선택 해제 또는 기본값)
		pass

	# 3. FPS 초기값 설정
	var current_fps = Engine.max_fps
	for i in range(FPS_OPTIONS.size()):
		if int(FPS_OPTIONS[i]["value"]) == current_fps:
			btn_fps.selected = i
			break
	
	
func _add_items_to_ui():
	# 1. 화면 모드 추가
	for mode_key in WINDOW_MODE_KEYS:
		btn_mode.add_item(tr(mode_key))
	
	# 2. 해상도 추가
	for res_name in RESOLUTIONS.keys():
		btn_res.add_item(res_name)
		
	# 3. FPS 추가
	for option in FPS_OPTIONS:
		btn_fps.add_item(tr(option["label_key"]))

	for language_name in LANGUAGE_NAMES:
		btn_language.add_item(language_name)

func _connect_signals():
	# 옵션을 선택했을 때 실행될 함수 연결
	btn_mode.item_selected.connect(_on_mode_selected)
	btn_res.item_selected.connect(_on_resolution_selected)
	btn_fps.item_selected.connect(_on_fps_selected)
	btn_language.item_selected.connect(_on_language_selected)

func _init_language_ui() -> void:
	var current_locale := GameManager.locale
	var selected_index := LANGUAGE_CODES.find(current_locale)
	btn_language.select(selected_index if selected_index >= 0 else 0)

func _on_language_selected(index: int) -> void:
	if index < 0 or index >= LANGUAGE_CODES.size():
		return

	GameManager.set_locale(LANGUAGE_CODES[index])
	GameManager.save_settings()

func _on_locale_changed(_new_locale: String) -> void:
	_refresh_translated_texts()

func _refresh_translated_texts() -> void:
	for i in range(WINDOW_MODE_KEYS.size()):
		btn_mode.set_item_text(i, tr(WINDOW_MODE_KEYS[i]))

	for i in range(FPS_OPTIONS.size()):
		btn_fps.set_item_text(i, tr(FPS_OPTIONS[i]["label_key"]))

	tab_container.set_tab_title(0, tr(&"OPTIONS_TAB_GRAPHICS"))
	tab_container.set_tab_title(1, tr(&"OPTIONS_TAB_AUDIO"))
	tab_container.set_tab_title(2, tr(&"OPTIONS_TAB_CONTROLS"))
	_update_sens_label(slider_sens.value)
	_update_shake_label(slider_shake.value)

# --- 기능 구현 ---

func _on_mode_selected(index: int):
	match index:
		0: # Windowed
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
		1: # Fullscreen
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		2: # Borderless Window
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
			# 테두리 없는 창의 경우 현재 모니터 크기로 자동 맞춤
			var screen_id = DisplayServer.window_get_current_screen()
			var screen_size = DisplayServer.screen_get_size(screen_id)
			DisplayServer.window_set_size(screen_size)
			DisplayServer.window_set_position(DisplayServer.screen_get_position(screen_id))
	
	GameManager.save_settings()
	print("Display mode changed: ", index)

func _on_resolution_selected(index: int):
	var key = btn_res.get_item_text(index)
	var target_size = RESOLUTIONS[key]

	var current_mode = DisplayServer.window_get_mode()
	var is_borderless = DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_BORDERLESS)
	
	if current_mode == DisplayServer.WINDOW_MODE_FULLSCREEN or current_mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN or is_borderless:
		print("Fullscreen or Borderless: Resolution change ignored or handled by OS/Scaling.")
		return

	DisplayServer.window_set_size(target_size)
	_center_window()
	
	GameManager.save_settings()
	print("Resolution changed: ", target_size)

func _on_fps_selected(index: int):
	if index < 0 or index >= FPS_OPTIONS.size():
		return
	var limit: int = int(FPS_OPTIONS[index]["value"])
	
	# 엔진의 최대 FPS 설정
	Engine.max_fps = limit
	GameManager.save_settings()
	print("FPS limit changed: ", limit)

# 창을 현재 모니터 정중앙으로 옮기는 헬퍼 함수 (다중 모니터 대응)
func _center_window():
	var screen_id = DisplayServer.window_get_current_screen()
	var screen_rect = DisplayServer.screen_get_usable_rect(screen_id)
	var window_size = DisplayServer.window_get_size()
	
	# screen_rect.position을 더해줘야 해당 모니터의 시작 위치를 기준으로 계산됨
	var center_pos = screen_rect.position + (screen_rect.size - window_size) / 2
	DisplayServer.window_set_position(center_pos)

# (옵션) 닫기 버튼용
func _on_close_button_pressed():
	close_requested.emit()

func _on_visibility_changed():
	# 만약 내가 지금 '보이는 상태(true)'가 되었다면?
	if visible:
		# 탭을 0번(첫 번째 탭)으로 강제 설정
		tab_container.current_tab = 0

func _on_exit_button_pressed() -> void:
	close_requested.emit()

# --- [기능 1: 마우스 감도] ---
func _on_sens_changed(value: float):
	GameManager.mouse_sensitivity = value
	_update_sens_label(value)
	GameManager.save_settings()

func _update_sens_label(value: float):
	# 0.5 -> "50%" 처럼 보기 좋게 변환
	lbl_sens_value.text = tr(&"OPTIONS_MOUSE_SENSITIVITY_VALUE").format({
		"percent": int(value * 100)
	})

func _init_game_settings():
	# 1. 마우스 감도 초기화 (저장된 값 불러오기)
	slider_sens.value = GameManager.mouse_sensitivity
	_update_sens_label(GameManager.mouse_sensitivity)
	
	slider_shake.value = GameManager.screenshake_intensity
	_update_shake_label(GameManager.screenshake_intensity)
	
	# 2. 연결
	slider_sens.value_changed.connect(_on_sens_changed)
	
	
func _init_audio_sliders():
	# 현재 오디오 서버의 실제 볼륨(db)을 가져와서 -> 슬라이더 값(0~1)으로 변환
	slider_master.value = db_to_linear(AudioServer.get_bus_volume_db(bus_index_master))
	slider_bgm.value = db_to_linear(AudioServer.get_bus_volume_db(bus_index_bgm))
	slider_sfx.value = db_to_linear(AudioServer.get_bus_volume_db(bus_index_sfx))
	
func _on_master_volume_changed(value: float):
	AudioServer.set_bus_volume_db(bus_index_master, linear_to_db(value))
	GameManager.save_settings()

func _on_bgm_volume_changed(value: float):
	AudioServer.set_bus_volume_db(bus_index_bgm, linear_to_db(value))
	GameManager.save_settings()

func _on_sfx_volume_changed(value: float):
	AudioServer.set_bus_volume_db(bus_index_sfx, linear_to_db(value))
	GameManager.save_settings()
	
func _on_shake_changed(value: float):
	GameManager.screenshake_intensity = value
	_update_shake_label(value)
	GameManager.save_settings()

func _update_shake_label(value: float):
	lbl_shake_value.text = tr(&"OPTIONS_SHAKE_VALUE").format({
		"percent": int(value * 100)
	})
