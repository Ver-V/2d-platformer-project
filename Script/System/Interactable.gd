# Interactable.gd
extends Area2D
class_name Interactable


var player_in_range: bool = false

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		player_in_range = true
		# 켜줘! 신호만 보냅니다. 
		GameManager.interact_msg_requested.emit("") 

func _on_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		player_in_range = false
		# "꺼줘!" 신호
		GameManager.interact_msg_hidden.emit()

func _input(event: InputEvent) -> void:
	if not player_in_range: return
	
	if event.is_action_pressed("interact"):
		_on_interact()

func _on_interact() -> void:
	return
