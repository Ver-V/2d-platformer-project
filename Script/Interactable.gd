# Interactable.gd
extends Area2D
class_name Interactable

# [삭제] prompt_message 변수는 이제 필요 없습니다. HUD에 있는걸 그대로 쓸 거니까요.
# @export var prompt_message: String = "E: 상호작용" 

var player_in_range: bool = false

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		player_in_range = true
		# [수정] 텍스트 없이 "켜줘!" 신호만 보냅니다. 
		# (GameManager의 신호가 인자를 받도록 되어있어도, 빈 문자열 ""을 보내면 됩니다)
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
	print("상호작용 실행됨!")
	# 상자 열기 등의 로직...
