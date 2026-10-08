# SettingsManager.gd (autoload: SettingsManager)
extends Node

# 옵션 설정: 볼륨, 화면 모드·해상도, 언어, 마우스 감도, 화면 흔들림.
# 세이브(진행 상태)와 별개인 설정 파일에 저장한다 (SaveManager.save_settings / load_settings).
# 언어가 바뀌면 locale_changed가 나간다 — 번역 문구를 직접 그리는 UI가 듣는다.

signal locale_changed(new_locale: String)

var mouse_sensitivity: float = 1.0
var screenshake_intensity: float = 0.5
var locale: String = "en"
var display_mode: int = 0 # 0: 창 모드, 1: 전체 화면, 2: 테두리 없는 창
var windowed_resolution: Vector2i = Vector2i(1280, 720)

func _ready() -> void:
	display_mode = _detect_display_mode()
	if display_mode == 0:
		var current_size := DisplayServer.window_get_size()
		if current_size.x > 0 and current_size.y > 0:
			windowed_resolution = current_size
	load_settings()

# path는 테스트용 (기본: 실제 설정 파일)
func save_settings(path: String = SaveManager.SETTINGS_PATH) -> bool:
	var data = {
		"master_vol": get_audio_volume(&"Master"),
		"bgm_vol": get_audio_volume(&"BGM"),
		"sfx_vol": get_audio_volume(&"SFX"),
		"mouse_sens": mouse_sensitivity,
		"screen_shake": screenshake_intensity,
		"display_mode": display_mode,
		"resolution_x": windowed_resolution.x,
		"resolution_y": windowed_resolution.y,
		"fps_limit": Engine.max_fps,
		"locale": locale
	}
	return SaveManager.save_settings(data, path)

func get_audio_volume(bus_name: StringName) -> float:
	var bus_index := AudioServer.get_bus_index(bus_name)
	if bus_index < 0:
		push_error("Audio bus is missing: " + str(bus_name))
		return 1.0
	if AudioServer.is_bus_mute(bus_index):
		return 0.0
	return clampf(AudioServer.get_bus_volume_linear(bus_index), 0.0, 1.0)

func set_audio_volume(bus_name: StringName, value: float) -> void:
	var bus_index := AudioServer.get_bus_index(bus_name)
	if bus_index < 0:
		push_error("Audio bus is missing: " + str(bus_name))
		return
	var level := clampf(value, 0.0, 1.0)
	AudioServer.set_bus_mute(bus_index, level <= 0.0)
	if level > 0.0:
		AudioServer.set_bus_volume_linear(bus_index, level)

func load_settings(path: String = SaveManager.SETTINGS_PATH) -> void:
	var data = SaveManager.load_settings(path)
	set_locale(str(data.get("locale", SaveManager.DEFAULT_LOCALE)))
	if data.size() == 1 and data.has("locale"):
		return
	
	# 오디오 적용
	set_audio_volume(&"Master", float(data.get("master_vol", 1.0)))
	set_audio_volume(&"BGM", float(data.get("bgm_vol", 1.0)))
	set_audio_volume(&"SFX", float(data.get("sfx_vol", 1.0)))
	
	# 게임플레이 설정
	mouse_sensitivity = clampf(float(data.get("mouse_sens", 1.0)), 0.5, 2.0)
	screenshake_intensity = data.get("screen_shake", 0.5)
	
	# 이전 버전의 설정 파일도 읽되, 새 파일에는 선택한 화면 모드를 직접 기록한다.
	display_mode = clampi(int(data.get("display_mode", _legacy_display_mode(data))), 0, 2)
	windowed_resolution = Vector2i(
		maxi(1280, int(data.get("resolution_x", 1280))),
		maxi(720, int(data.get("resolution_y", 720)))
	)
	if not is_windowed_resolution_supported(windowed_resolution):
		windowed_resolution = Vector2i(1280, 720)
	Engine.max_fps = maxi(0, int(data.get("fps_limit", 60)))
	call_deferred("apply_display_mode")

func _detect_display_mode() -> int:
	var mode := DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
		return 1
	if mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		return 2 if bool(ProjectSettings.get_setting("display/window/size/borderless", false)) else 1
	return 2 if DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_BORDERLESS) else 0

func _legacy_display_mode(data: Dictionary) -> int:
	var mode := int(data.get("window_mode", DisplayServer.WINDOW_MODE_WINDOWED))
	if mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
		return 1
	if bool(data.get("borderless", false)):
		return 2
	return 1 if mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN else 0

func set_locale(new_locale: String) -> void:
	var normalized := new_locale.to_lower().get_slice("_", 0).get_slice("-", 0)
	if normalized not in ["en", "ko"]:
		normalized = SaveManager.DEFAULT_LOCALE

	var did_change := locale != normalized
	locale = normalized
	TranslationServer.set_locale(locale)
	if did_change:
		locale_changed.emit(locale)

func apply_display_mode() -> void:
	match display_mode:
		0:
			if not is_windowed_resolution_supported(windowed_resolution):
				windowed_resolution = Vector2i(1280, 720)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			DisplayServer.window_set_size(windowed_resolution)
			center_window()
		1:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		2:
			var screen_id := DisplayServer.window_get_current_screen()
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
			DisplayServer.window_set_size(DisplayServer.screen_get_size(screen_id))
			DisplayServer.window_set_position(DisplayServer.screen_get_position(screen_id))

func is_windowed_resolution_supported(size: Vector2i) -> bool:
	var screen_id := DisplayServer.window_get_current_screen()
	var usable_size := DisplayServer.screen_get_usable_rect(screen_id).size
	if usable_size.x <= 0 or usable_size.y <= 0:
		return true # 헤드리스 환경에는 화면 크기 정보가 없다.
	return size.x <= usable_size.x and size.y <= usable_size.y

func center_window() -> void:
	var screen_id := DisplayServer.window_get_current_screen()
	var screen_rect := DisplayServer.screen_get_usable_rect(screen_id)
	var window_size := DisplayServer.window_get_size()
	DisplayServer.window_set_position(screen_rect.position + (screen_rect.size - window_size) / 2)
