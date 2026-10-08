@tool
extends Node2D
class_name KeyDoor

# 원점 = 문 바닥 중앙 (상자와 같은 규칙). 에디터에서도 그림이 실제 게임과 같은 자리에 보이도록 @tool

@export var locked: bool = true
@export var item_key: String = "pink_key"
@export_file("*.json") var dialogue_file: String = "res://resources/Dialogues/en/item_conditional_example.json"
@export var block_without_item: String = "without_item" # 열쇠가 없을 때 (자물쇠와 함께)
@export var block_ask_open: String = "ask_open" # 열쇠가 있을 때 "문을 열겠습니까?" 예/아니오 블록
@export var unlock_event: String = "door_unlock" # ask_open 블록에서 '예' 선택지의 "event" 값
@export var block_key_spent: String = "key_spent"
@export var block_key_kept: String = "key_kept"
@export var open_sound: AudioStream
@export var destination_marker: Marker2D # 비워두면 이동 없이 문만 열린다.
@export var persist_id: String = ""

@export_group("Sprite")
# 배치한 문마다 인스펙터에서 바로 그림을 바꾸는 용도. 넣으면 ClosedSprite/OpenedSprite에 적용되고,
# 문 바닥 중앙이 노드 원점(y=0)에 오도록 자동 정렬된다. 비워두면 자식 Sprite2D 설정 그대로.
@export var closed_texture: Texture2D:
	set(value):
		closed_texture = value
		if Engine.is_editor_hint() and is_node_ready():
			_apply_texture(get_node_or_null("ClosedSprite") as Sprite2D, value)
@export var opened_texture: Texture2D: # 이것도 자식도 비어 있으면 닫힌 그림을 초록빛으로 칠해 열린 걸 구분한다
	set(value):
		opened_texture = value
		if Engine.is_editor_hint() and is_node_ready():
			_apply_texture(get_node_or_null("OpenedSprite") as Sprite2D, value)

@onready var trigger: Area2D = $Trigger
# 문은 배경 오브젝트라 기본 씬엔 몸으로 막는 Blocker가 없다. 필요한 문만 Blocker(StaticBody2D)를 추가하면 닫혀 있는 동안 막는다.
@onready var blocker_shape: CollisionShape2D = get_node_or_null("Blocker/CollisionShape2D") as CollisionShape2D
# 닫힌 문 / 열린 문 그림. 열린 문 그림이 비어 있으면 닫힌 그림을 초록빛으로 칠해 구분한다
@onready var closed_sprite: Sprite2D = get_node_or_null("ClosedSprite") as Sprite2D
@onready var opened_sprite: Sprite2D = get_node_or_null("OpenedSprite") as Sprite2D
@onready var prompt_label: Label = get_node_or_null("PromptLabel") as Label
# 잠긴 문을 열려고 할 때 화면 중앙에 뜨는 자물쇠 연출. 그림은 열쇠 아이템(item_key)의 lock_sprite_frames
var lock_overlay: LockOverlay

var _opened: bool = false
var _busy: bool = false
var _player: Player = null
const TELEPORT_COOLDOWN_MS: int = 500

func _ready() -> void:
	if Engine.is_editor_hint():
		_apply_texture(closed_sprite, closed_texture)
		_apply_texture(opened_sprite, opened_texture)
		return
	add_to_group("object")
	lock_overlay = LockOverlay.new()
	add_child(lock_overlay)
	trigger.body_entered.connect(_on_body_entered)
	trigger.body_exited.connect(_on_body_exited)
	SettingsManager.locale_changed.connect(_on_locale_changed)
	_opened = GameManager.collected_items.has(_save_id())
	_apply_texture(closed_sprite, closed_texture)
	_apply_texture(opened_sprite, opened_texture)
	_update_open_state()
	if prompt_label != null:
		prompt_label.hide()

func _apply_texture(target: Sprite2D, tex: Texture2D) -> void:
	if target == null or tex == null:
		return
	target.texture = tex
	target.centered = true
	target.position = Vector2.ZERO
	target.offset = Vector2(0, -tex.get_size().y * 0.5)

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
	if not _busy:
		_hide_lock()
	_hide_prompt()

func _on_locale_changed(_new_locale: String) -> void:
	if is_instance_valid(_player):
		_show_prompt()

# 안내는 상자·상인처럼 HUD 하단의 상호작용 안내([E] : 문 열기)로 띄운다 (화면 밖으로 나가지 않게).
# 문에 PromptLabel 자식을 두면 그 라벨을 대신 쓴다
func _show_prompt() -> void:
	if not is_instance_valid(_player):
		return
	var message_key := "KEY_DOOR_ENTER_PROMPT" if _opened else "KEY_DOOR_OPEN_PROMPT"
	if prompt_label != null:
		prompt_label.text = tr(message_key)
		prompt_label.show()
	else:
		GameManager.interact_msg_requested.emit(message_key)

func _hide_prompt() -> void:
	if prompt_label != null:
		prompt_label.hide()
	else:
		GameManager.interact_msg_hidden.emit()

func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
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
	_hide_prompt()
	if DialogueManager.is_dialogue_active:
		await DialogueManager.dialogue_finished
		if not is_instance_valid(body) or body != _player:
			_busy = false
			return

	# 잠기지 않은 문은 바로 열린다
	if not locked:
		_open()
		_busy = false
		_show_prompt()
		if is_instance_valid(body) and body == _player:
			call_deferred("_teleport_player", body)
		return

	# 열쇠가 없으면: 자물쇠를 띄우고 "맞는 열쇠가 없어" 대사
	_show_lock(&"locked")
	if not Inventory.has_item(item_key):
		if await _run_dialogue(block_without_item):
			_hide_lock()
		else:
			body.show_popup(tr(&"KEY_REQUIRED"), Color.YELLOW)
		_busy = false
		_show_prompt()
		if not is_instance_valid(_player): # 대사 중에 문 앞을 떠났으면 자물쇠도 치운다
			_hide_lock()
		return

	# 열쇠가 있으면: "문을 열겠습니까?" 예를 골라야 자물쇠가 풀리고 문이 열린다
	if not await _ask_open():
		_hide_lock()
		_busy = false
		_show_prompt()
		return

	var remaining_uses := Inventory.consume_key_use(item_key)
	if remaining_uses < 0:
		_hide_lock()
		_busy = false
		return
	await _play_unlock() # 자물쇠가 풀리는 걸 보여준 뒤 문이 열린다
	_open()
	await _run_dialogue(block_key_spent if remaining_uses == 0 else block_key_kept)
	_busy = false
	_show_prompt()
	if is_instance_valid(body) and body == _player:
		call_deferred("_teleport_player", body)

func _open() -> void:
	_opened = true
	GameManager.add_collected_item(_save_id())
	_update_open_state()
	_play_open_sound()

# 대사 블록을 재생하고 끝날 때까지 기다린다. 파일·블록이 없어 시작하지 못하면 false
func _run_dialogue(block: String) -> bool:
	if block.is_empty() or not DialogueManager.has_dialogue_file(dialogue_file):
		return false
	if not DialogueManager.start_dialogue(dialogue_file, block):
		return false
	await DialogueManager.dialogue_finished
	return true

# "문을 열겠습니까?" 블록에서 unlock_event 선택지를 골랐으면 true.
# 질문 블록이 없으면 묻지 않고 연다 (대사 없는 문).
func _ask_open() -> bool:
	var chosen := [false]
	var on_event := func(event_name: String) -> void:
		if event_name == unlock_event:
			chosen[0] = true
	DialogueManager.dialogue_event.connect(on_event)
	var asked: bool = await _run_dialogue(block_ask_open)
	DialogueManager.dialogue_event.disconnect(on_event)
	return chosen[0] or not asked

# --- 자물쇠 ---

func _lock_frames() -> SpriteFrames:
	var key_item := Database.get_item_by_id(item_key)
	return key_item.lock_sprite_frames if key_item != null else null

func _show_lock(anim_name: StringName) -> bool:
	return lock_overlay.show_lock(_lock_frames(), anim_name)

func _hide_lock() -> void:
	lock_overlay.hide_lock()

# 풀리는 애니메이션 한 번 재생이 끝날 때까지 기다린다 (자물쇠 그림이 없으면 바로 넘어감)
func _play_unlock() -> void:
	await lock_overlay.play_unlock(_lock_frames())

func _update_open_state() -> void:
	if blocker_shape != null:
		blocker_shape.set_deferred("disabled", _opened)
	var has_opened_art := opened_sprite != null and opened_sprite.texture != null
	if opened_sprite != null:
		opened_sprite.visible = _opened and has_opened_art
	if closed_sprite != null:
		closed_sprite.visible = not (_opened and has_opened_art)
		closed_sprite.modulate = Color(0.65, 1.0, 0.65) if _opened and not has_opened_art else Color.WHITE

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
