extends Area2D
class_name DialogueBlock

@export_file("*.json")
var dialogue_file: String = ""

@export var persist_id: StringName = &""

var _has_triggered: bool = false
var _is_playing_dialogue: bool = false

func _ready() -> void:
	add_to_group("dialogue_blocks")
	if _restore_completed_state():
		return

	DialogueManager.dialogue_event.connect(_on_dialogue_event)
	body_entered.connect(_on_body_entered)

func get_persist_id() -> StringName:
	return persist_id if persist_id != &"" else StringName(str(get_path()))
	
func _on_dialogue_event(event_name : String) -> void:
	if _is_playing_dialogue and event_name == "block_fall":
		_record_completion()
		queue_free()

func _restore_completed_state() -> bool:
	if not GameManager.triggered_dialogues.has(get_persist_id()):
		return false
	_has_triggered = true
	queue_free()
	return true

func _record_completion() -> void:
	var block_id := get_persist_id()
	if not GameManager.triggered_dialogues.has(block_id):
		GameManager.triggered_dialogues.append(block_id)
	
func _on_body_entered(body: Node2D) -> void :
	if not _has_triggered and body is Player:
		_has_triggered = true # 중복 실행 방지용 플래그만 세움
		
		if DialogueManager.has_dialogue_file(dialogue_file):
			if DialogueManager.is_dialogue_active:
				await DialogueManager.dialogue_finished
			
			_is_playing_dialogue = true
			if not DialogueManager.start_dialogue(dialogue_file):
				_is_playing_dialogue = false
				_has_triggered = false
				return
			
			# 대화가 끝날 때까지 기다림
			await DialogueManager.dialogue_finished
			
			# 대화가 완전히 끝난 후 GM에 기록하고 자신을 삭제
			_is_playing_dialogue = false
			_record_completion()
			queue_free()
		else:
			_has_triggered = false
			
