extends Interactable
class_name Chest

@export var locked: bool = false
@export var item_key: String = "pink_key"
@export_file("*.json") var dialogue_file: String = "res://resources/Dialogues/en/chest_key_example.json"
@export var block_without_item: String = "without_item"
@export var reward_item: ItemData
@export var reward_gold: int = 0
@export var persist_id: String = ""

@onready var closed_visual: CanvasItem = $ClosedVisual
@onready var opened_visual: CanvasItem = $OpenedVisual
@onready var keyhole: CanvasItem = $ClosedVisual/Keyhole
@onready var open_sound: AudioStreamPlayer2D = $OpenSound

var _opened: bool = false

func _ready() -> void:
	super()
	add_to_group("object")
	_opened = GameManager.collected_items.has(_save_id())
	_update_visual()

func _save_id() -> String:
	if not persist_id.is_empty():
		return "chest:" + persist_id
	var scene := get_tree().current_scene
	var scene_path := scene.scene_file_path if scene != null else ""
	return "chest:%s:%s" % [scene_path, get_path()]

func _update_visual() -> void:
	closed_visual.visible = not _opened
	opened_visual.visible = _opened
	keyhole.visible = locked
	if _opened:
		set_deferred("monitoring", false)

# 열린 상자는 안내를 띄우지 않고 상호작용도 받지 않는다.
func _show_prompt() -> void:
	if not _opened:
		super()

func _can_interact() -> bool:
	return not _opened and current_player is Player

func _on_interact() -> void:
	var player := current_player as Player
	if locked and not GameManager.has_item(item_key):
		if DialogueManager.has_dialogue_file(dialogue_file):
			DialogueManager.start_dialogue(dialogue_file, block_without_item)
		else:
			player.show_popup(tr(&"KEY_REQUIRED"), Color.YELLOW)
		return
	if reward_item != null and not GameManager.add_item(reward_item):
		player.show_status("full")
		return

	if reward_gold > 0:
		GameManager.update_gold(reward_gold)
	_opened = true
	GameManager.add_collected_item(_save_id())
	_hide_prompt()
	_update_visual()
	open_sound.play()
