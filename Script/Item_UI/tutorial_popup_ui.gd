extends CanvasLayer

@onready var panel: PanelContainer = $Control/PanelContainer
@onready var label: Label = $Control/PanelContainer/MarginContainer/Label
@onready var anim: AnimationPlayer = get_node_or_null("AnimationPlayer")

var is_active: bool = false
var _is_closing: bool = false
var _paused_by_popup: bool = false
var _registered_ui: bool = false
var _current_text_key: StringName = &""
var _pending_popups: Array[Dictionary] = []

func _ready() -> void:
	visible = false
	panel.scale = Vector2.ZERO
	panel.resized.connect(_update_panel_pivot)
	_update_panel_pivot()
	GameManager.locale_changed.connect(_on_locale_changed)

func _update_panel_pivot() -> void:
	panel.pivot_offset = panel.size * 0.5

func display(text_key: StringName, pause: bool = true) -> bool:
	if text_key == &"":
		return false
	if is_active:
		_pending_popups.append({"text_key": text_key, "pause": pause})
	else:
		_show_popup(text_key, pause)
	return true

func _show_popup(text_key: StringName, pause: bool) -> void:
	is_active = true
	_is_closing = false
	_current_text_key = text_key
	label.text = tr(text_key)
	visible = true
	
	if pause:
		if not _registered_ui:
			GameManager.ui_opened(self, false)
			_registered_ui = true
		if not get_tree().paused:
			_paused_by_popup = true
			get_tree().paused = true
	else:
		_release_pause()
	
	# 애니메이션 실행 (팝업 연출)
	if anim and anim.has_animation("show"):
		anim.play("show")
	else:
		panel.scale = Vector2.ONE
		panel.modulate.a = 1.0

func _on_locale_changed(_locale: String) -> void:
	if is_active:
		label.text = tr(_current_text_key)

func _input(event: InputEvent) -> void:
	if not is_active: return
	
	# 아무 키나 누르거나 공격/점프 키를 누르면 닫기
	if event.is_action_pressed("attack") or event.is_action_pressed("jump") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if not _is_closing and not event.is_echo():
			hide_popup()

func hide_popup() -> void:
	if not is_active or _is_closing:
		return
	_is_closing = true
	
	if anim and anim.has_animation("hide"):
		anim.play("hide")
		await anim.animation_finished
	
	visible = false
	panel.scale = Vector2.ZERO
	if not _pending_popups.is_empty():
		var next_popup: Dictionary = _pending_popups.pop_front()
		_show_popup(next_popup["text_key"], next_popup["pause"])
	else:
		is_active = false
		_is_closing = false
		_current_text_key = &""
		_release_pause()

func _release_pause() -> void:
	if _paused_by_popup:
		get_tree().paused = false
		_paused_by_popup = false
	if _registered_ui:
		GameManager.ui_closed(self)
		_registered_ui = false
