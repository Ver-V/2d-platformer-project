extends Area2D
class_name DialogueBlock

@export_file("*.json")
var dialogue_file: String = ""

var _has_triggered: bool = false

func _ready() -> void:
	DialogueManager.dialogue_event.connect(_on_dialogue_event)
	body_entered.connect(_on_body_entered)
	
func _on_dialogue_event(event_name : String) -> void:
	if _has_triggered and event_name == "block_fall":
		queue_free()
	
func _on_body_entered(body: Node2D) -> void :
	if not _has_triggered and body is Player:
		_has_triggered = true
		if dialogue_file != "":
			if DialogueManager.is_dialogue_active:
				await DialogueManager.dialogue_finished
			DialogueManager.start_dialogue(dialogue_file)
			
