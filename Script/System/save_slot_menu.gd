extends Control
class_name SaveSlotMenu

# 메인 메뉴의 세이브 슬롯 선택 화면 (코드로 구성).
# 새 게임: 모든 슬롯 선택 가능 (저장된 슬롯은 메인 메뉴가 덮어쓰기 확인)
# 불러오기: 저장된 슬롯만 선택 가능

signal slot_chosen(slot: int, has_data: bool)
signal closed

enum Mode { NEW_GAME, LOAD }

var mode: Mode = Mode.NEW_GAME
var font: Font = null # 메인 메뉴 버튼과 같은 글꼴을 넘겨받는다
var font_size: int = 16

var _title: Label
var _slot_buttons: Array[Button] = []
var _back_button: Button

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP # 뒤의 메인 메뉴 버튼이 눌리지 않게

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(420, 0)
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)

	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_font(_title)
	box.add_child(_title)

	for slot in range(1, SaveManager.SLOT_COUNT + 1):
		var button := Button.new()
		button.custom_minimum_size = Vector2(0, 64)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_apply_font(button)
		button.pressed.connect(_on_slot_pressed.bind(slot))
		box.add_child(button)
		_slot_buttons.append(button)

	_back_button = Button.new()
	_apply_font(_back_button)
	_back_button.pressed.connect(close)
	box.add_child(_back_button)

	for button in _slot_buttons + [_back_button]:
		button.pressed.connect(GameManager.play_ui_click)

	visible = false

func _apply_font(control: Control) -> void:
	if font != null:
		control.add_theme_font_override("font", font)
	control.add_theme_font_size_override("font_size", font_size)

func open(new_mode: Mode) -> void:
	mode = new_mode
	refresh()
	visible = true
	for button in _slot_buttons:
		if not button.disabled:
			button.grab_focus()
			return
	_back_button.grab_focus()

func close() -> void:
	visible = false
	closed.emit()

func refresh() -> void:
	_title.text = tr(&"SAVE_SLOT_TITLE_NEW" if mode == Mode.NEW_GAME else &"SAVE_SLOT_TITLE_LOAD")
	_back_button.text = tr(&"COMMON_BACK")
	for i in _slot_buttons.size():
		var slot := i + 1
		var summary := SaveManager.slot_summary(SaveManager.slot_path(slot))
		var button := _slot_buttons[i]
		button.text = slot_text(slot, summary)
		button.set_meta("has_data", not summary.is_empty())
		button.disabled = mode == Mode.LOAD and summary.is_empty()

func _on_slot_pressed(slot: int) -> void:
	slot_chosen.emit(slot, bool(_slot_buttons[slot - 1].get_meta("has_data", false)))

func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()

# 슬롯 버튼 글자: "슬롯 1" + (비어 있음 | 스테이지 · 골드 + 저장 시각)
static func slot_text(slot: int, summary: Dictionary) -> String:
	var slot_name := TranslationServer.translate(&"SAVE_SLOT_NAME").format({"n": slot})
	if summary.is_empty():
		return "%s\n%s" % [slot_name, TranslationServer.translate(&"SAVE_SLOT_EMPTY")]
	var info := TranslationServer.translate(&"SAVE_SLOT_INFO").format({
		"stage": stage_title(summary),
		"gold": summary.get("gold", 0),
	})
	return "%s\n%s\n%s" % [slot_name, info, saved_time_text(int(summary.get("saved_unix", 0)))]

# 저장할 때 기록한 스테이지 제목 키. 옛 세이브는 씬 파일 이름으로 추정 (Stage_02 → STAGE_02_TITLE)
static func stage_title(summary: Dictionary) -> String:
	var key := str(summary.get("stage_title_key", ""))
	if key.is_empty():
		var file := str(summary.get("scene_path", "")).get_file().get_basename()
		if file.begins_with("Stage_"):
			key = "STAGE_%s_TITLE" % file.trim_prefix("Stage_").to_upper()
	var text: String = String(TranslationServer.translate(key)) if not key.is_empty() else ""
	if text.is_empty() or text == key:
		return TranslationServer.translate(&"SAVE_SLOT_UNKNOWN_STAGE")
	return text

static func saved_time_text(unix: int) -> String:
	if unix <= 0:
		return ""
	var bias_minutes: int = int(Time.get_time_zone_from_system().get("bias", 0))
	var t := Time.get_datetime_dict_from_unix_time(unix + bias_minutes * 60)
	return "%04d-%02d-%02d %02d:%02d" % [t.year, t.month, t.day, t.hour, t.minute]
