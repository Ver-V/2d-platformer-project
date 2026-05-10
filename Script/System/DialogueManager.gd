extends CanvasLayer

# UI 노드들 연결
@onready var name_label: Label = $Panel/NameLabel
@onready var text_label: RichTextLabel = $Panel/TextLabel
@onready var type_timer: Timer = $TypeTimer
@onready var panel: Panel = $Panel

@onready var left_portrait: TextureRect = $PortraitsContainer/LeftPortrait
@onready var right_portrait: TextureRect = $PortraitsContainer/RightPortrait

var left_base_y: float = 50.0 # 예시 값: 실제 씬의 LeftPortrait Y좌표
var right_base_y: float = 50.0 # 예시 값: 실제 씬의 RightPortrait Y좌표
	
signal dialogue_finished
signal dialogue_event

var portrait_path = "res://resources/Portraits/" # 이미지가 저장된 폴더 경로
const DIM_COLOR = Color(0.5, 0.5, 0.5, 1.0) # 어두워질 색 (회색)
const BRIGHT_COLOR = Color.WHITE            # 밝은 색 (원래 색)
const MOVE_OFFSET = 20.0 # 강조될 때 위로 올라갈 픽셀 수

var dialogue_queue: Array = []
var current_index: int = 0
var is_dialogue_active: bool = false
var is_typing: bool = false
var portrait_tween: Tween # 일러스트 움직임용 트윈

func _ready():
	visible = false # 평소엔 숨김
	type_timer.timeout.connect(_on_type_timer_timeout)
	
	# 일러스트가 위로 강조될 때 위가 잘리지 않도록 기본 위치를 낮춤
	left_portrait.position.y += 30.0
	right_portrait.position.y += 30.0
	
	left_base_y = left_portrait.position.y
	right_base_y = right_portrait.position.y

func _input(event):
	if not is_dialogue_active:
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
func start_dialogue(json_file_path: String):
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
		dialogue_queue = json.data # 대본 로드 완료!
		current_index = 0
		is_dialogue_active = true
		visible = true
		
		# 플레이어 움직임 멈추기 (GameManager 이용)
		GameManager.is_menu_open = true
		
		# 첫 대사 출력
		show_next_line()
	else:
		print("JSON 파일 오류!")

func show_next_line():
	if current_index < dialogue_queue.size():
		var line = dialogue_queue[current_index]
		
		# 1. 텍스트 설정 (기존 동일)
		name_label.text = line["name"]
		text_label.text = line["text"]
		text_label.visible_ratio = 0.0
		is_typing = true
		type_timer.start()
		
		# 2. 이미지 파일 불러오기 및 설정
		# (빈 문자열이면 이미지를 숨길 수도 있습니다)
		if line.has("left_image") and line["left_image"] != "":
			left_portrait.texture = load(portrait_path + line["left_image"] + ".png")
			left_portrait.visible = true
		if line.has("right_image") and line["right_image"] != "":
			right_portrait.texture = load(portrait_path + line["right_image"] + ".png")
			right_portrait.visible = true

		# 3. [⭐강조 효과] 말하는 쪽 하이라이트!
		emphasis_speaker(line["speaker"])
		
		if line.has("event") and line["event"] != "":
			dialogue_event.emit(line["event"])
		
		current_index += 1
	else:
		end_dialogue()

func emphasis_speaker(speaker_side: String):
	# 기존에 진행 중이던 트윈이 있으면 취소
	if portrait_tween:
		portrait_tween.kill()
	portrait_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	if speaker_side == "left":
		# [왼쪽 강조] 밝게, 위로 올라감
		portrait_tween.tween_property(left_portrait, "modulate", BRIGHT_COLOR, 0.3)
		portrait_tween.tween_property(left_portrait, "position:y", left_base_y - MOVE_OFFSET, 0.3)
		
		# [오른쪽 어둠] 어둡게, 원래 위치로 내려감
		portrait_tween.tween_property(right_portrait, "modulate", DIM_COLOR, 0.3)
		portrait_tween.tween_property(right_portrait, "position:y", right_base_y, 0.3)
		
	elif speaker_side == "right":
		# [오른쪽 강조] 밝게, 위로 올라감
		portrait_tween.tween_property(right_portrait, "modulate", BRIGHT_COLOR, 0.3)
		portrait_tween.tween_property(right_portrait, "position:y", right_base_y - MOVE_OFFSET, 0.3)
		
		# [왼쪽 어둠] 어둡게, 원래 위치로 내려감
		portrait_tween.tween_property(left_portrait, "modulate", DIM_COLOR, 0.3)
		portrait_tween.tween_property(left_portrait, "position:y", left_base_y, 0.3)
		
func _on_type_timer_timeout():
	# 글자 하나씩 보이게 하기
	text_label.visible_ratio += 0.05 # 속도 조절 가능
	
	if text_label.visible_ratio >= 1.0:
		is_typing = false
		type_timer.stop()

# 대화가 끝까지 정상적으로 진행되었을 때
func end_dialogue():
	if portrait_tween:
		portrait_tween.kill()
	is_dialogue_active = false
	visible = false
	GameManager.is_menu_open = false
	# 대화 끝나면 일러스트도 숨기기
	left_portrait.visible = false
	right_portrait.visible = false
	dialogue_finished.emit()

# 외부 요인(멀어짐 등)으로 인해 강제로 창을 닫아야 할 때
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
		dialogue_finished.emit()
