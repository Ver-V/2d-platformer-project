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

# 3. 렌더링 FPS 상한 목록 (모니터 주사율 변경과는 별개)
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
	SettingsManager.locale_changed.connect(_on_locale_changed)
	
	# 모든 버튼 및 옵션 버튼에 클릭 소리 연결
	for btn in find_children("*", "BaseButton", true):
		btn.pressed.connect(GameManager.play_ui_click)
	for opt in find_children("*", "OptionButton", true):
		opt.item_selected.connect(func(_idx): GameManager.play_ui_click())
	
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
	# 전체 화면에서는 Godot이 borderless 플래그도 켜므로 선택 상태를 따로 보관한다.
	btn_mode.select(SettingsManager.display_mode)
	btn_res.disabled = SettingsManager.display_mode != 0
		
	# 전체 화면에서도 마지막 창 모드 해상도를 표시한다.
	var res_found = false
	for i in range(btn_res.item_count):
		var res_name = btn_res.get_item_text(i)
		btn_res.set_item_disabled(i, not SettingsManager.is_windowed_resolution_supported(RESOLUTIONS[res_name]))
		if RESOLUTIONS.has(res_name) and RESOLUTIONS[res_name] == SettingsManager.windowed_resolution:
			btn_res.select(i)
			res_found = true
	if not res_found:
		btn_res.select(-1)

	# 3. FPS 초기값 설정
	var current_fps = Engine.max_fps
	btn_fps.select(-1)
	for i in range(FPS_OPTIONS.size()):
		if int(FPS_OPTIONS[i]["value"]) == current_fps:
			btn_fps.select(i)
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
	var current_locale := SettingsManager.locale
	var selected_index := LANGUAGE_CODES.find(current_locale)
	btn_language.select(selected_index if selected_index >= 0 else 0)

func _on_language_selected(index: int) -> void:
	if index < 0 or index >= LANGUAGE_CODES.size():
		return

	SettingsManager.set_locale(LANGUAGE_CODES[index])
	SettingsManager.save_settings()

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
	if index < 0 or index >= WINDOW_MODE_KEYS.size():
		return
	SettingsManager.display_mode = index
	SettingsManager.apply_display_mode()
	_init_graphics_ui()
	SettingsManager.save_settings()
	DebugLog.info(str("Display mode changed: ", index))

func _on_resolution_selected(index: int):
	if index < 0 or index >= btn_res.item_count or SettingsManager.display_mode != 0:
		_init_graphics_ui()
		return
	var key = btn_res.get_item_text(index)
	if not RESOLUTIONS.has(key):
		_init_graphics_ui()
		return
	var target_size: Vector2i = RESOLUTIONS[key]
	if not SettingsManager.is_windowed_resolution_supported(target_size):
		_init_graphics_ui()
		return

	SettingsManager.windowed_resolution = target_size
	DisplayServer.window_set_size(target_size)
	SettingsManager.center_window()
	await get_tree().process_frame
	if not is_inside_tree() or SettingsManager.display_mode != 0:
		return
	var applied_size := DisplayServer.window_get_size()
	if applied_size.x > 0 and applied_size.y > 0:
		SettingsManager.windowed_resolution = applied_size
	_init_graphics_ui()
	SettingsManager.save_settings()
	DebugLog.info(str("Resolution changed: ", SettingsManager.windowed_resolution))

func _on_fps_selected(index: int):
	if index < 0 or index >= FPS_OPTIONS.size():
		return
	var limit: int = int(FPS_OPTIONS[index]["value"])
	
	# 엔진의 최대 FPS 설정
	Engine.max_fps = limit
	_init_graphics_ui()
	SettingsManager.save_settings()
	DebugLog.info(str("FPS limit changed: ", limit))

# (옵션) 닫기 버튼용
func _on_close_button_pressed():
	close_requested.emit()

func _on_visibility_changed():
	# 만약 내가 지금 '보이는 상태(true)'가 되었다면?
	if visible:
		# 탭을 0번(첫 번째 탭)으로 강제 설정
		tab_container.current_tab = 0
		_init_audio_sliders()
		_init_graphics_ui()

func _on_exit_button_pressed() -> void:
	close_requested.emit()

# --- [기능 1: 마우스 감도] ---
func _on_sens_changed(value: float):
	SettingsManager.mouse_sensitivity = value
	_update_sens_label(value)
	SettingsManager.save_settings()

func _update_sens_label(value: float):
	# 0.5 -> "50%" 처럼 보기 좋게 변환
	lbl_sens_value.text = tr(&"OPTIONS_MOUSE_SENSITIVITY_VALUE").format({
		"percent": int(value * 100)
	})

func _init_game_settings():
	# 1. 마우스 감도 초기화 (저장된 값 불러오기)
	slider_sens.set_value_no_signal(SettingsManager.mouse_sensitivity)
	_update_sens_label(SettingsManager.mouse_sensitivity)
	
	slider_shake.set_value_no_signal(SettingsManager.screenshake_intensity)
	_update_shake_label(SettingsManager.screenshake_intensity)
	
	# 2. 연결
	slider_sens.value_changed.connect(_on_sens_changed)
	
	
func _init_audio_sliders():
	# 음소거된 버스는 실제 볼륨 값과 무관하게 0%로 표시한다.
	slider_master.set_value_no_signal(SettingsManager.get_audio_volume(&"Master"))
	slider_bgm.set_value_no_signal(SettingsManager.get_audio_volume(&"BGM"))
	slider_sfx.set_value_no_signal(SettingsManager.get_audio_volume(&"SFX"))
	
func _on_master_volume_changed(value: float):
	SettingsManager.set_audio_volume(&"Master", value)
	SettingsManager.save_settings()

func _on_bgm_volume_changed(value: float):
	SettingsManager.set_audio_volume(&"BGM", value)
	SettingsManager.save_settings()

func _on_sfx_volume_changed(value: float):
	SettingsManager.set_audio_volume(&"SFX", value)
	SettingsManager.save_settings()
	
func _on_shake_changed(value: float):
	SettingsManager.screenshake_intensity = value
	_update_shake_label(value)
	SettingsManager.save_settings()

func _update_shake_label(value: float):
	lbl_shake_value.text = tr(&"OPTIONS_SHAKE_VALUE").format({
		"percent": int(value * 100)
	})
