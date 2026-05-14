extends CanvasLayer

# UI 노드들 연결
@onready var name_label: Label = $Panel/NameLabel
@onready var text_label: RichTextLabel = $Panel/TextLabel
@onready var type_timer: Timer = $TypeTimer
@onready var panel: Panel = $Panel

@onready var left_portrait: TextureRect = $PortraitsContainer/LeftPortrait
@onready var right_portrait: TextureRect = $PortraitsContainer/RightPortrait

# 일러스트 기본 위치 저장용 변수
var left_base_y: float = 0.0
var right_base_y: float = 0.0

# [수정] 스크롤 컨테이너와 선택지 버튼을 담을 컨테이너
var scroll_container: ScrollContainer
var choice_container: VBoxContainer
	
signal dialogue_finished
signal dialogue_event

var portrait_path = "res://resources/Portraits/" # 이미지가 저장된 폴더 경로
const DIM_COLOR = Color(0.5, 0.5, 0.5, 1.0) # 어두워질 색 (회색)
const BRIGHT_COLOR = Color.WHITE            # 밝은 색 (원래 색)
const MOVE_OFFSET = 20.0 # 강조될 때 위로 올라갈 픽셀 수

var dialogue_data = {} # 전체 대화 데이터 (딕셔너리)
var current_block: Array = [] # 현재 진행 중인 대사 뭉치
var current_index: int = 0
var is_dialogue_active: bool = false
var is_typing: bool = false
var is_waiting_choice: bool = false # 선택지 대기 중인가?
var portrait_tween: Tween # 일러스트 움직임용 트윈

func _ready():
	visible = false # 평소엔 숨김
	type_timer.timeout.connect(_on_type_timer_timeout)
	
	# 일러스트 기본 위치 설정
	left_portrait.position.y += 30.0
	right_portrait.position.y += 30.0
	left_base_y = left_portrait.position.y
	right_base_y = right_portrait.position.y
	
	# [수정] 스크롤 가능한 선택지 UI 구조 생성
	scroll_container = ScrollContainer.new()
	scroll_container.name = "ChoiceScroll"
	# 선택지가 많아질 경우를 대비해 적절한 높이 설정 (패널 위쪽 공간 활용)
	scroll_container.custom_minimum_size = Vector2(500, 250)
	add_child(scroll_container)
	
	# 화면 중앙 하단에 배치하되 대화창 패널 위에 오도록 조정
	scroll_container.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	scroll_container.position.y -= 200.0 
	
	# 가로 스크롤은 끄고 세로만 허용
	scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	
	choice_container = VBoxContainer.new()
	choice_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choice_container.theme_type_variation = "VBoxContainer"
	# 버튼들 사이의 간격 조정
	choice_container.add_theme_constant_override("separation", 5)
	scroll_container.add_child(choice_container)

func _input(event):
	if not is_dialogue_active or is_waiting_choice:
		return

	# z나 x로 다음 대사 넘기기
	if event.is_action_pressed("jump") or event.is_action_pressed("attack"):
		if is_typing:
			# 타자기 치는 중이면 -> 즉시 완성 (스킵)
			text_label.visible_ratio = 1.0
			is_typing = false
			type_timer.stop()
		else:
			# 다 쳤으면 -> 다음 대사로
			show_next_line()

# --- [핵심] 외부에서 이 함수를 부르면 대화 시작 ---
func start_dialogue(json_file_path: String, start_block: String = "start"):
	if not FileAccess.file_exists(json_file_path):
		print("JSON 파일이 존재하지 않습니다: ", json_file_path)
		return
		
	# 1. 파일 읽기
	var file = FileAccess.open(json_file_path, FileAccess.READ)
	if file == null:
		print("파일을 열 수 없습니다: ", json_file_path)
		return
		
	var content = file.get_as_text()
	var json = JSON.new()
	var error = json.parse(content)
	
	if error == OK:
		var data = json.data
		if typeof(data) == TYPE_ARRAY:
			# 기존 방식 (단순 배열) 지원
			dialogue_data = {"start": data}
		else:
			# 새로운 방식 (딕셔너리 분기) 지원
			dialogue_data = data
			
		_jump_to_block(start_block)
		is_dialogue_active = true
		visible = true
		
		# 플레이어 움직임 멈추기 (GameManager 이용)
		GameManager.is_menu_open = true
	else:
		print("JSON 파일 오류!")

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
		
		# 1. 텍스트 설정
		name_label.text = line.get("name", "")
		text_label.text = line.get("text", "")
		text_label.visible_ratio = 0.0
		is_typing = true
		type_timer.start()
		
		# 2. 이미지 설정
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

		# 3. 강조 효과
		if line.has("speaker"):
			emphasis_speaker(line["speaker"])
		
		if line.has("event") and line["event"] != "":
			dialogue_event.emit(line["event"])
		
		# 4. 선택지가 있는 경우 처리
		if line.has("choices"):
			# 선택지가 있으면 타자기 효과가 끝날 때까지 기다리지 않고 즉시 표시하도록 함 (유저 편의성)
			text_label.visible_ratio = 1.0
			is_typing = false
			type_timer.stop()
			_display_choices(line["choices"])
		
		current_index += 1
	else:
		end_dialogue()

func _display_choices(choices: Array):
	is_waiting_choice = true
	_clear_choices()
	scroll_container.visible = true
	
	var first_focus_btn = null
	
	for i in range(choices.size()):
		var c = choices[i]
		var btn = Button.new()
		btn.text = c["text"]
		
		# [추가] 조건 체크 로직
		var can_select = true
		if c.has("condition"):
			can_select = _check_condition(c["condition"])
		
		if not can_select:
			btn.disabled = true
			# 비활성화된 버튼은 회색으로 강조
			btn.modulate = Color(0.5, 0.5, 0.5, 1.0)
			if c.has("fail_text"):
				btn.text += " (" + str(c["fail_text"]) + ")"
		
		btn.pressed.connect(_on_choice_selected.bind(c))
		choice_container.add_child(btn)
		
		# 선택 가능한 첫 번째 버튼에 포커스 (키보드/패드 조작용)
		if can_select and first_focus_btn == null:
			first_focus_btn = btn

	if first_focus_btn:
		first_focus_btn.grab_focus()

# [추가] GameManager와 연동하여 선택지 조건을 확인하는 핵심 함수
func _check_condition(cond: Dictionary) -> bool:
	var type = cond.get("type", "")
	var val = cond.get("value") # ID나 수치 등
	
	match type:
		"gold":
			return GameManager.gold >= int(val)
		"hp":
			return GameManager.player_current_hp >= int(val)
		"boss_defeated":
			return GameManager.defeated_bosses.get(str(val), false)
		"has_item":
			# 인벤토리에 해당 ID의 아이템이 있는지 체크
			for item in GameManager.inventory:
				if item != null and item.id == str(val):
					return true
			return false
	return true

func _on_choice_selected(choice_data: Dictionary):
	_clear_choices()
	if choice_data.has("next"):
		_jump_to_block(choice_data["next"])
	else:
		end_dialogue()

func _clear_choices():
	scroll_container.visible = false
	for child in choice_container.get_children():
		child.queue_free()

func emphasis_speaker(speaker_side: String):
	if portrait_tween:
		portrait_tween.kill()
	portrait_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	if speaker_side == "left":
		portrait_tween.tween_property(left_portrait, "modulate", BRIGHT_COLOR, 0.3)
		portrait_tween.tween_property(left_portrait, "position:y", left_base_y - MOVE_OFFSET, 0.3)
		portrait_tween.tween_property(right_portrait, "modulate", DIM_COLOR, 0.3)
		portrait_tween.tween_property(right_portrait, "position:y", right_base_y, 0.3)
	elif speaker_side == "right":
		portrait_tween.tween_property(right_portrait, "modulate", BRIGHT_COLOR, 0.3)
		portrait_tween.tween_property(right_portrait, "position:y", right_base_y - MOVE_OFFSET, 0.3)
		portrait_tween.tween_property(left_portrait, "modulate", DIM_COLOR, 0.3)
		portrait_tween.tween_property(left_portrait, "position:y", left_base_y, 0.3)
		
func _on_type_timer_timeout():
	text_label.visible_ratio += 0.05
	if text_label.visible_ratio >= 1.0:
		is_typing = false
		type_timer.stop()

func end_dialogue():
	if portrait_tween:
		portrait_tween.kill()
	is_dialogue_active = false
	visible = false
	GameManager.is_menu_open = false
	left_portrait.visible = false
	right_portrait.visible = false
	_clear_choices()
	dialogue_finished.emit()

func force_close():
	if is_dialogue_active:
		if portrait_tween:
			portrait_tween.kill()
		is_dialogue_active = false
		visible = false
		GameManager.is_menu_open = false
		left_portrait.visible = false
		right_portrait.visible = false
		type_timer.stop()
		_clear_choices()
		dialogue_finished.emit()
