extends Interactable
class_name Chest

@export var locked: bool = false
@export var item_key: String = "pink_key"
@export_file("*.json") var dialogue_file: String = "res://resources/Dialogues/en/no_chest_key.json"
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

const VANISH_DELAY := 3.0 # 연 뒤 이만큼 있다가
const VANISH_FADE := 0.5 # 이 시간 동안 흐려지며 사라진다

func _ready() -> void:
	super()
	add_to_group("minimap_chest")
	_opened = GameManager.collected_items.has(_save_id())
	if _opened:
		queue_free() # 이미 연 상자는 다시 나오지 않는다
		return
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
	# 원점 = 상자 바닥 중앙. 그림의 투명 여백은 빼고 실제로 그려진 맨 아래 픽셀을 바닥에 붙인다
	if sprite.texture != null:
		sprite.centered = true
		sprite.offset = Vector2(0, -(visible_bottom(sprite.texture) - sprite.texture.get_size().y * 0.5))
	if _opened:
		set_deferred("monitoring", false)

# 그림에서 투명하지 않은 맨 아래 줄 바로 아래 y (텍스처 픽셀 기준). 그림마다 한 번만 계산
static var _bottom_cache := {}
static func visible_bottom(tex: Texture2D) -> float:
	if not _bottom_cache.has(tex):
		var bottom := tex.get_size().y
		var img := tex.get_image()
		if img != null and not img.is_empty():
			if img.is_compressed():
				img.decompress()
			var used := img.get_used_rect()
			if used.size.y > 0:
				bottom = used.end.y
		_bottom_cache[tex] = bottom
	return _bottom_cache[tex]

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
	# 획득 목록(HUD 왼쪽 위): 골드, 아이템 순으로 한 묶음
	HUD.log_pickup_gold(gold)
	HUD.log_pickup_item(reward.item)
	_opened = true
	GameManager.add_collected_item(_save_id())
	_hide_prompt()
	_update_visual()
	open_sound.play()
	_vanish_after_open()

# 연 상자는 잠시 열린 모습을 보여준 뒤 흐려지며 사라진다 (열림 기록은 세이브에 남아 다시 나오지 않음)
func _vanish_after_open() -> void:
	await Wait.seconds(self, VANISH_DELAY)
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, VANISH_FADE)
	tween.tween_callback(queue_free)
