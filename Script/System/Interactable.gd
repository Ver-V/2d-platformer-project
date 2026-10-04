# Interactable.gd
extends Area2D
class_name Interactable

# 플레이어가 범위 안에서 interact 키(E)를 누르면 반응하는 오브젝트의 공통 부모.
# 자식은 _on_interact()를 덮어쓰고, 필요하면 _can_interact() / _show_prompt() /
# _on_player_entered() / _on_player_exited() / _on_other_input()을 덮어쓴다.

# HUD에 보낼 안내 종류 ("" = 일반 상호작용, "save_mode" = 저장/휴식 패널)
var interact_msg: String = ""

var player_in_range: bool = false
var current_player: Node2D = null

func _ready() -> void:
	# 씬(.tscn)에서 이미 연결해 둔 경우 중복 연결하지 않는다.
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		player_in_range = true
		current_player = body as Node2D
		_show_prompt()
		_on_player_entered(body)

func _on_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		player_in_range = false
		current_player = null
		_hide_prompt()
		_on_player_exited(body)

func _input(event: InputEvent) -> void:
	if not player_in_range:
		return
	# 일시정지 메뉴·인벤토리·대화·상점 등 UI가 열려 있으면 무시한다.
	if GameManager.is_menu_open or not _can_interact():
		return
	if event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		_on_interact()
	else:
		_on_other_input(event)

func _show_prompt() -> void:
	GameManager.interact_msg_requested.emit(interact_msg)

func _hide_prompt() -> void:
	GameManager.interact_msg_hidden.emit()

# --- 자식이 덮어쓰는 함수들 ---
func _can_interact() -> bool:
	return true

func _on_interact() -> void:
	pass

func _on_other_input(_event: InputEvent) -> void:
	pass

func _on_player_entered(_body: Node) -> void:
	pass

func _on_player_exited(_body: Node) -> void:
	pass
