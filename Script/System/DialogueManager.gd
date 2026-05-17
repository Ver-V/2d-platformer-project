extends CanvasLayer

# UI 노드들 연결
@onready var name_label: Label = $Panel/NameLabel
@onready var text_label: RichTextLabel = $Panel/TextLabel
@onready var type_timer: Timer = $TypeTimer
@onready var panel: Panel = $Panel

@onready var left_portrait: TextureRect = $PortraitsContainer/LeftPortrait
@onready var right_portrait: TextureRect = $PortraitsContainer/RightPortrait

var left_base_y: float = 0.0
var right_base_y: float = 0.0

var scroll_container: ScrollContainer
var choice_container: VBoxContainer
var choice_bg: PanelContainer 
	
signal dialogue_finished
signal dialogue_event

var portrait_path = "res://resources/Portraits/"
const DIM_COLOR = Color(0.5, 0.5, 0.5, 1.0)
const BRIGHT_COLOR = Color.WHITE
const MOVE_OFFSET = 20.0

var dialogue_data = {}
var current_block: Array = []
var current_index: int = 0
var is_dialogue_active: bool = false
var is_typing: bool = false
var is_waiting_choice: bool = false
var portrait_tween: Tween

func _ready():
	visible = false
	type_timer.timeout.connect(_on_type_timer_timeout)
	
	left_portrait.position.y += 30.0
	right_portrait.position.y += 30.0
	left_base_y = left_portrait.position.y
	right_base_y = right_portrait.position.y
	
	# [수정] 선택지 UI 생성 및 스타일 부여
	choice_bg = PanelContainer.new()
	choice_bg.name = "ChoiceUI"
	add_child(choice_bg)
	
	# 배경을 검게 만들어 확실히 보이게 함
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.8) # 80% 불투명 검정
	style.set_border_width_all(2)
	style.border_color = Color(1, 1, 1, 0.5) # 흰색 테두리
	choice_bg.add_theme_stylebox_override("panel", style)
	
	# 위치 설정: 640x360 해상도 기준으로 절대 좌표 사용 (확실하게 화면 중앙 위쪽)
	# 높이를 280으로 늘려서 선택지 12개가 들어갈 수 있도록 공간 확보 (넘치면 자동 스크롤됨)
	choice_bg.position = Vector2(120, 20)
	choice_bg.size = Vector2(400, 280)
	choice_bg.visible = false
	
	scroll_container = ScrollContainer.new()
	scroll_container.size = Vector2(380, 260)
	scroll_container.position = Vector2(10, 10) # 패널 내부 여백
	scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	choice_bg.add_child(scroll_container)
	
	choice_container = VBoxContainer.new()
	choice_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choice_container.add_theme_constant_override("separation", 10)
	scroll_container.add_child(choice_container)
	
	print("[DialogueManager] ChoiceUI 노드가 생성되었습니다.")

func _input(event):
	if not is_dialogue_active or is_waiting_choice:
		return

	if event.is_action_pressed("jump") or event.is_action_pressed("attack"):
		get_viewport().set_input_as_handled()
		if is_typing:
			text_label.visible_ratio = 1.0
			is_typing = false
			type_timer.stop()
		else:
			show_next_line()

func start_dialogue(json_file_path: String, start_block: String = "start"):
	print("[DialogueManager] Loading dialogue: ", json_file_path)
	if not FileAccess.file_exists(json_file_path):
		print("[DialogueManager] Error: File not found at ", json_file_path)
		return
	var file = FileAccess.open(json_file_path, FileAccess.READ)
	var content = file.get_as_text()
	var json = JSON.new()
	var error = json.parse(content)
	if error == OK:
		var data = json.data
		dialogue_data = data if typeof(data) == TYPE_DICTIONARY else {"start": data}
		is_dialogue_active = true
		visible = true
		GameManager.is_menu_open = true
		_jump_to_block(start_block)
	else:
		print("[DialogueManager] JSON Parse Error: ", json.get_error_message(), " at line ", json.get_error_line())

func _jump_to_block(block_name: String):
	if dialogue_data.has(block_name):
		current_block = dialogue_data[block_name]
		current_index = 0
		is_waiting_choice = false
		_clear_choices()
		show_next_line()
	else:
		end_dialogue()

func show_next_line():
	if current_index < current_block.size():
		var line = current_block[current_index]
		name_label.text = line.get("name", "")
		text_label.text = line.get("text", "")
		text_label.visible_ratio = 0.0
		is_typing = true
		type_timer.start()
		
		_update_portraits(line)
		
		if line.has("speaker"): emphasis_speaker(line["speaker"])
		if line.has("event") and line["event"] != "": dialogue_event.emit(line["event"])
		
		if line.has("choices"):
			text_label.visible_ratio = 1.0
			is_typing = false
			type_timer.stop()
			_display_choices(line["choices"])
		
		current_index += 1
	else:
		end_dialogue()

func _update_portraits(line: Dictionary):
	if line.has("left_image") and line["left_image"] != "":
		left_portrait.texture = load(portrait_path + line["left_image"] + ".png")
		left_portrait.visible = true
	else:
		left_portrait.visible = false
	if line.has("right_image") and line["right_image"] != "":
		right_portrait.texture = load(portrait_path + line["right_image"] + ".png")
		right_portrait.visible = true
	else:
		right_portrait.visible = false

func _display_choices(choices: Array):
	is_waiting_choice = true
	_clear_choices()
	choice_bg.visible = true
	
	var first_btn = null
	for c in choices:
		var btn = Button.new()
		btn.text = c["text"]
		if c.has("condition") and not _check_condition(c["condition"]):
			btn.disabled = true
			if c.has("fail_text"): btn.text += " (" + str(c["fail_text"]) + ")"
		
		btn.pressed.connect(_on_choice_selected.bind(c))
		choice_container.add_child(btn)
		if not btn.disabled and first_btn == null: first_btn = btn

	if first_btn:
		# 선택지가 나타날 때까지 0.2초 대기 후 포커스
		get_tree().create_timer(0.2).timeout.connect(first_btn.grab_focus)

func _check_condition(cond: Dictionary) -> bool:
	match cond.get("type", ""):
		"gold": return GameManager.gold >= int(cond.get("value", 0))
		"hp": return GameManager.player_current_hp >= int(cond.get("value", 0))
		"boss_defeated": return GameManager.defeated_bosses.get(str(cond.get("value")), false)
		"has_item":
			for item in GameManager.inventory:
				if item != null and item.id == str(cond.get("value")): return true
			return false
	return true

func _on_choice_selected(choice_data: Dictionary):
	_clear_choices()
	if choice_data.has("next"): _jump_to_block(choice_data["next"])
	else: end_dialogue()

func _clear_choices():
	choice_bg.visible = false
	for child in choice_container.get_children():
		child.queue_free()

func emphasis_speaker(side: String):
	if portrait_tween: portrait_tween.kill()
	portrait_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var left_mod = BRIGHT_COLOR if side == "left" else DIM_COLOR
	var right_mod = BRIGHT_COLOR if side == "right" else DIM_COLOR
	portrait_tween.tween_property(left_portrait, "modulate", left_mod, 0.3)
	portrait_tween.tween_property(left_portrait, "position:y", left_base_y - (MOVE_OFFSET if side == "left" else 0), 0.3)
	portrait_tween.tween_property(right_portrait, "modulate", right_mod, 0.3)
	portrait_tween.tween_property(right_portrait, "position:y", right_base_y - (MOVE_OFFSET if side == "right" else 0), 0.3)

func _on_type_timer_timeout():
	text_label.visible_ratio += 0.05
	if text_label.visible_ratio >= 1.0:
		is_typing = false
		type_timer.stop()

func end_dialogue():
	if portrait_tween: portrait_tween.kill()
	visible = false
	left_portrait.visible = false
	right_portrait.visible = false
	_clear_choices()
	
	await get_tree().process_frame
	is_dialogue_active = false
	GameManager.is_menu_open = false
	dialogue_finished.emit()

func force_close():
	if is_dialogue_active:
		end_dialogue()
