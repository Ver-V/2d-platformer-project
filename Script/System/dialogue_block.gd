extends Area2D
class_name DialogueBlock

@export_file("*.json")
var dialogue_file: String = ""

@export var persist_id: StringName = &""

var _has_triggered: bool = false

func _ready() -> void:
	# [추가] 이미 실행된 적이 있다면 바로 비활성화
	var pid = get_persist_id()
	if GameManager.triggered_dialogues.has(pid):
		_has_triggered = true
		# 만약 블록이 떨어지거나 사라지는 연출이 있는 경우를 위해 
		# 즉시 제거하기보다는 로직만 막아둡니다.
		# 필요하다면 queue_free()를 쓸 수도 있습니다.
		return

	DialogueManager.dialogue_event.connect(_on_dialogue_event)
	body_entered.connect(_on_body_entered)

func get_persist_id() -> StringName:
	return persist_id if persist_id != &"" else StringName(str(get_path()))
	
func _on_dialogue_event(event_name : String) -> void:
	if _has_triggered and event_name == "block_fall":
		queue_free()
	
func _on_body_entered(body: Node2D) -> void :
	if not _has_triggered and body is Player:
		_has_triggered = true # 중복 실행 방지용 플래그만 세움
		
		if dialogue_file != "":
			if DialogueManager.is_dialogue_active:
				await DialogueManager.dialogue_finished
			
			DialogueManager.start_dialogue(dialogue_file)
			
			# 대화가 끝날 때까지 기다림
			await DialogueManager.dialogue_finished
			
			# 대화가 완전히 끝난 후 GM에 기록하고 자신을 삭제
			GameManager.triggered_dialogues.append(get_persist_id())
			queue_free()
			
