extends CanvasLayer

@onready var panel: PanelContainer = $Control/PanelContainer
@onready var label: Label = $Control/PanelContainer/MarginContainer/Label
@onready var anim: AnimationPlayer = get_node_or_null("AnimationPlayer")

var is_active: bool = false

func _ready() -> void:
	visible = false
	panel.scale = Vector2.ZERO

func display(text: String, pause: bool = true) -> void:
	if is_active: return
	
	is_active = true
	label.text = text
	visible = true
	
	if pause:
		get_tree().paused = true
	
	# 애니메이션 실행 (팝업 연출)
	if anim and anim.has_animation("show"):
		anim.play("show")
	else:
		panel.scale = Vector2.ONE

func _input(event: InputEvent) -> void:
	if not is_active: return
	
	# 아무 키나 누르거나 공격/점프 키를 누르면 닫기
	if event.is_action_pressed("attack") or event.is_action_pressed("jump") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		hide_popup()

func hide_popup() -> void:
	is_active = false
	if get_tree().paused:
		get_tree().paused = false
	
	if anim and anim.has_animation("hide"):
		anim.play("hide")
		await anim.animation_finished
	
	visible = false
	panel.scale = Vector2.ZERO
