extends Node2D
class_name KeyDoor

@export var locked: bool = true
@export var item_key: String = "pink_key"
@export_file("*.json") var dialogue_file: String = "res://resources/Dialogues/en/item_conditional_example.json"
@export var block_without_item: String = "without_item"
@export var block_key_spent: String = "key_spent"
@export var block_key_kept: String = "key_kept"
@export var open_sound: AudioStream
@export var destination_marker: Marker2D # 비워두면 이동 없이 문만 열린다.
@export var persist_id: String = ""

@onready var trigger: Area2D = $Trigger
@onready var blocker_shape: CollisionShape2D = $Blocker/CollisionShape2D
@onready var closed_visual: CanvasItem = get_node_or_null("ClosedVisual") as CanvasItem
@onready var legacy_visual: CanvasItem = get_node_or_null("Visual") as CanvasItem
@onready var opened_visual: CanvasItem = get_node_or_null("OpenedVisual") as CanvasItem
@onready var prompt_label: Label = get_node_or_null("PromptLabel") as Label

var _opened: bool = false
var _busy: bool = false
var _player: Player = null
const TELEPORT_COOLDOWN_MS: int = 500

func _ready() -> void:
	add_to_group("object")
	trigger.body_entered.connect(_on_body_entered)
	trigger.body_exited.connect(_on_body_exited)
	GameManager.locale_changed.connect(_on_locale_changed)
	_opened = GameManager.collected_items.has(_save_id())
	_update_open_state()
	if prompt_label != null:
		prompt_label.hide()

func _save_id() -> String:
	if not persist_id.is_empty():
		return "door:" + persist_id
	var scene := get_tree().current_scene
	var scene_path := scene.scene_file_path if scene != null else ""
	return "door:%s:%s" % [scene_path, get_path()]

func _on_body_entered(body: Node2D) -> void:
	if not body is Player:
		return
	_player = body as Player
	_show_prompt()

func _on_body_exited(body: Node2D) -> void:
	if body != _player:
		return
	_player = null
	if prompt_label != null:
		prompt_label.hide()

func _on_locale_changed(_new_locale: String) -> void:
	if is_instance_valid(_player):
		_show_prompt()

func _show_prompt() -> void:
	if not is_instance_valid(_player):
		return
	var message := tr(&"KEY_DOOR_ENTER_PROMPT") if _opened else tr(&"KEY_DOOR_OPEN_PROMPT")
	if prompt_label != null:
		prompt_label.text = message
		prompt_label.show()
	else:
		_player.show_popup(message, Color.YELLOW)

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact") or (event is InputEventKey and event.echo):
		return
	if _busy or not is_instance_valid(_player) or GameManager.is_menu_open:
		return
	if int(_player.get_meta("key_door_teleport_until", 0)) > Time.get_ticks_msec():
		return
	get_viewport().set_input_as_handled()
	_try_use_door(_player)

func _try_use_door(body: Player) -> void:
	if _opened:
		call_deferred("_teleport_player", body)
		return
	_busy = true
	if prompt_label != null:
		prompt_label.hide()
	if DialogueManager.is_dialogue_active:
		await DialogueManager.dialogue_finished
		if not is_instance_valid(body) or body != _player:
			_busy = false
			return

	var has_key := not locked or GameManager.has_item(item_key)
	if not has_key:
		if DialogueManager.has_dialogue_file(dialogue_file):
			DialogueManager.start_dialogue(dialogue_file, block_without_item)
			await DialogueManager.dialogue_finished
			_show_prompt()
		else:
			body.show_popup(tr(&"KEY_REQUIRED"), Color.YELLOW)
			if prompt_label != null:
				_show_prompt()
		_busy = false
		return

	var remaining_uses := -1
	if locked:
		remaining_uses = GameManager.consume_key_use(item_key)
		if remaining_uses < 0:
			_busy = false
			return
	_open()
	if locked and DialogueManager.has_dialogue_file(dialogue_file):
		var dialogue_block := block_key_spent if remaining_uses == 0 else block_key_kept
		DialogueManager.start_dialogue(dialogue_file, dialogue_block)
		await DialogueManager.dialogue_finished
	_busy = false
	_show_prompt()
	if is_instance_valid(body) and body == _player:
		call_deferred("_teleport_player", body)

func _open() -> void:
	_opened = true
	GameManager.add_collected_item(_save_id())
	_update_open_state()
	_play_open_sound()

func _update_open_state() -> void:
	blocker_shape.set_deferred("disabled", _opened)
	var closed := closed_visual if closed_visual != null else legacy_visual
	if opened_visual != null:
		opened_visual.visible = _opened
		if closed != null:
			closed.visible = not _opened
	elif closed != null:
		# 열린 그림이 없을 때도 문이 사라지지 않도록 임시 색으로 구분한다.
		closed.modulate = Color(0.65, 1.0, 0.65) if _opened else Color.WHITE

func _teleport_player(body: Node2D) -> void:
	if not is_instance_valid(body) or not is_instance_valid(destination_marker):
		return
	if int(body.get_meta("key_door_teleport_until", 0)) > Time.get_ticks_msec():
		return
	body.set_meta("key_door_teleport_until", Time.get_ticks_msec() + TELEPORT_COOLDOWN_MS)
	if body is CharacterBody2D:
		body.velocity = Vector2.ZERO
	body.global_position = destination_marker.global_position

func _play_open_sound() -> void:
	# 씬에 OpenSound 노드를 두거나, 인스펙터에서 open_sound 리소스를 지정할 수 있다.
	var sound := get_node_or_null("OpenSound") as AudioStreamPlayer2D
	if sound == null:
		if open_sound == null:
			return
		sound = AudioStreamPlayer2D.new()
		sound.stream = open_sound
		sound.bus = &"SFX"
		get_tree().root.add_child(sound)
		sound.global_position = global_position
	else:
		if open_sound != null:
			sound.stream = open_sound
		sound.reparent(get_tree().root, true)
	if sound.stream != null:
		sound.finished.connect(sound.queue_free)
		sound.play()
	else:
		sound.queue_free()
