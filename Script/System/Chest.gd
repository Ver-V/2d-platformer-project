extends Interactable
class_name Chest

@export var locked: bool = false
@export var item_key: String = "pink_key"
@export_file("*.json") var dialogue_file: String = "res://resources/Dialogues/en/chest_key_example.json"
@export var block_without_item: String = "without_item"
@export var reward_item: ItemData # 지정하면 항상 이 아이템. 비워두면 loot_table에서 랜덤
@export var loot_table: LootTable = preload("res://resources/loot/default_chest.tres") # 아이템/골드 랜덤 목록. 비우면 reward_gold만
@export var reward_gold: int = 0
@export var persist_id: String = ""

@export_group("Sprite")
@export var closed_texture: Texture2D
@export var opened_texture: Texture2D
@export var locked_texture: Texture2D # 잠긴 상자 전용 그림. 비워두면 closed_texture 사용

@onready var sprite: Sprite2D = $Sprite2D
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
	var tex := closed_texture
	if _opened:
		tex = opened_texture
	elif locked and locked_texture != null:
		tex = locked_texture
	if tex != null:
		sprite.texture = tex
	# 원점 = 상자 바닥 중앙. 그림 크기가 달라도 바닥에 붙게 맞춘다
	if sprite.texture != null:
		sprite.centered = true
		sprite.offset = Vector2(0, -sprite.texture.get_size().y * 0.5)
	if _opened:
		set_deferred("monitoring", false)

# 지정 아이템이 있으면 그것, 없으면 랜덤 목록에서 한 줄(아이템 또는 골드)을 뽑는다.
# rng를 주면 그걸로 뽑는다 (세이브 시드로 결과 고정). 아무것도 없으면 빈 LootEntry.
func _roll_reward(rng: RandomNumberGenerator = null) -> LootEntry:
	if reward_item != null:
		var fixed := LootEntry.new()
		fixed.item = reward_item
		return fixed
	var picked: LootEntry = loot_table.pick(rng) if loot_table != null else null
	return picked if picked != null else LootEntry.new()

# 열린 상자는 안내를 띄우지 않고 상호작용도 받지 않는다.
func _show_prompt() -> void:
	if not _opened:
		super()

func _can_interact() -> bool:
	return not _opened and current_player is Player

func _on_interact() -> void:
	var player := current_player as Player
	if locked and not Inventory.has_item(item_key):
		if DialogueManager.has_dialogue_file(dialogue_file):
			DialogueManager.start_dialogue(dialogue_file, block_without_item)
		else:
			player.show_popup(tr(&"KEY_REQUIRED"), Color.YELLOW)
		return
	var rng := GameManager.make_loot_rng(_save_id()) # 같은 세이브에서는 같은 상자 = 같은 결과
	var reward := _roll_reward(rng)
	if reward.item != null and not Inventory.add_item(reward.item):
		player.show_status("full")
		return

	var gold := reward_gold + reward.roll_gold(rng)
	if gold > 0:
		GameManager.update_gold(gold)
	_opened = true
	GameManager.add_collected_item(_save_id())
	_hide_prompt()
	_update_visual()
	open_sound.play()
