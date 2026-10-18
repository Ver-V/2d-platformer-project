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

@export_group("Reward Reveal")
# reward_item 상자: 열면 시간이 멈추고 카메라가 상자로 당겨진 뒤, 아이템이 상자 위로 튀어나온다 (주워야 가방에 들어감).
# 끄면 예전처럼 바로 가방에 넣는다
@export var reveal_reward_item: bool = true
@export var reveal_freeze_time: float = 1.5 # 시간 멈춤 + 확대 시간 (실제 시간)
@export var reveal_zoom: float = 1.6 # 지금 카메라 확대에 곱한다
@export var reveal_hold_time: float = 0.4 # 아이템이 나온 뒤 확대를 유지하는 시간
@export var reveal_return_time: float = 0.4 # 카메라가 방으로 돌아가는 시간
@export var item_pop_height: float = 28.0 # 아이템이 멈추는 높이 (상자 바닥 기준, 위로 px)
@export var item_scale: float = 0.5 # 상자에서 나온 아이템 그림 크기 (필드 아이템 기본 크기 대비)
@export var reveal_sound: AudioStream # 아이템이 튀어나올 때 효과음 (비우면 무음)

@export_group("Sprite")
@export var closed_texture: Texture2D
@export var opened_texture: Texture2D
@export var locked_texture: Texture2D # 잠긴 상자 전용 그림. 비워두면 closed_texture 사용

@onready var sprite: Sprite2D = $Sprite2D
@onready var open_sound: AudioStreamPlayer2D = $OpenSound

var _opened: bool = false
var _busy: bool = false # 잠긴 상자의 자물쇠 연출·대사 중
var lock_overlay: LockOverlay # 잠긴 상자에만 만든다. 그림은 열쇠 아이템(item_key)의 lock_sprite_frames (문과 같은 자물쇠)

const FIELD_ITEM_SCENE: PackedScene = preload("res://Scenes/Item/field_item.tscn")
const ITEM_POP_TIME := 0.3

var _revealing: bool = false
var _spawned_item: Node2D = null

const VANISH_DELAY := 3.0 # 연 뒤 이만큼 있다가
const VANISH_FADE := 0.5 # 이 시간 동안 흐려지며 사라진다
const LOCK_SHOW_TIME := 0.8 # 대사 없이 "열쇠가 필요해"만 뜰 때 자물쇠를 보여주는 시간

func _ready() -> void:
	super()
	add_to_group("minimap_chest")
	_opened = GameManager.collected_items.has(_save_id())
	if _opened:
		if _uses_reveal() and not GameManager.collected_items.has(_item_save_id()):
			# 열어 두고 아이템을 안 주운 상자: 열린 채로 아이템을 다시 띄워 둔다 (주우면 사라짐)
			_update_visual()
			call_deferred("_spawn_reward_item", false)
			return
		queue_free() # 이미 연 상자는 다시 나오지 않는다
		return
	if locked:
		lock_overlay = LockOverlay.new()
		add_child(lock_overlay)
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
	var picked: LootEntry = loot_table.pick_with_stat_pity(rng, GameManager.stat_loot) if loot_table != null else null
	return picked if picked != null else LootEntry.new()

# 열린 상자는 안내를 띄우지 않고 상호작용도 받지 않는다.
func _show_prompt() -> void:
	if not _opened:
		super()

func _can_interact() -> bool:
	return not _opened and not _busy and current_player is Player

func _on_interact() -> void:
	var player := current_player as Player
	var rng := GameManager.make_loot_rng(_save_id()) # 같은 세이브에서는 같은 상자 = 같은 결과
	var reward := _roll_reward(rng)
	if locked:
		_busy = true
		var unlocked: bool = await _try_unlock(player, reward)
		_busy = false
		if not unlocked or not is_instance_valid(player):
			return
	if _uses_reveal():
		_open_with_reveal(reward, rng)
		return
	if reward.item != null and not Inventory.add_item(reward.item):
		player.show_status("full")
		return

	var gold := reward_gold + reward.roll_gold(rng)
	if gold > 0:
		GameManager.update_gold(gold)
	# 획득 목록(HUD 왼쪽 위): 골드, 아이템 순으로 한 묶음
	HUD.log_pickup_gold(gold)
	HUD.log_pickup_item(reward.item)
	if reward_item == null:
		GameManager.record_chest_loot(loot_table, reward.item) # 스탯 포션 불운 보정·중복 방지 기록
	_opened = true
	GameManager.add_collected_item(_save_id())
	_hide_prompt()
	_update_visual()
	open_sound.play()
	_vanish_after_open()

# 잠긴 상자: 열쇠가 없으면 자물쇠("locked") + 대사, 있으면 열쇠를 한 번 쓰고 자물쇠가 풀리는("unlock") 걸 보여준다.
# 가방이 가득 차 보상을 못 받으면 열쇠를 쓰지 않는다. 열렸으면 true
func _try_unlock(player: Player, reward: LootEntry) -> bool:
	var frames := _lock_frames()
	lock_overlay.show_lock(frames, &"locked")
	if not Inventory.has_item(item_key):
		if DialogueManager.has_dialogue_file(dialogue_file) and DialogueManager.start_dialogue(dialogue_file, block_without_item):
			await DialogueManager.dialogue_finished
		else:
			player.show_popup(tr(&"KEY_REQUIRED"), Color.YELLOW)
			await Wait.seconds(self, LOCK_SHOW_TIME)
		lock_overlay.hide_lock()
		return false
	if reward.item != null and not Inventory.has_room_for(reward.item):
		lock_overlay.hide_lock()
		player.show_status("full")
		return false
	if Inventory.consume_key_use(item_key) < 0:
		lock_overlay.hide_lock()
		return false
	await lock_overlay.play_unlock(frames)
	lock_overlay.hide_lock() # "unlock" 그림이 없으면 play_unlock이 "locked"를 치우지 않는다
	locked = false
	return true

func _lock_frames() -> SpriteFrames:
	var key_item := Database.get_item_by_id(item_key)
	return key_item.lock_sprite_frames if key_item != null else null

# --- reward_item 상자 연출 ---
func _uses_reveal() -> bool:
	return reveal_reward_item and reward_item != null

# 아이템의 획득 기록 id (상자 열림 기록과 따로: 열어 두고 안 주운 채로 나가면 다음에 아이템만 다시 나온다)
func _item_save_id() -> String:
	return _save_id().replace("chest:", "chest_item:")

func _open_with_reveal(reward: LootEntry, rng: RandomNumberGenerator) -> void:
	_revealing = true
	_opened = true
	GameManager.add_collected_item(_save_id()) # 골드를 두 번 받지 않게 열린 건 바로 기록
	var gold := reward_gold + reward.roll_gold(rng)
	if gold > 0:
		GameManager.update_gold(gold)
		HUD.log_pickup_gold(gold)
	_hide_prompt()
	_update_visual()
	open_sound.play()
	GameManager.ui_opened(self, false) # 연출 동안 조작 잠금
	GameManager.apply_hitstop(0.0, reveal_freeze_time) # 시간 멈춤 (풀어 주는 건 GameManager 쪽 타이머)
	var stage := get_tree().current_scene
	var has_cam := stage != null and stage.has_method("focus_camera")
	if has_cam:
		stage.focus_camera(global_position + Vector2(0, -item_pop_height * 0.5), reveal_zoom, reveal_freeze_time)
	await Wait.real_seconds(self, reveal_freeze_time)
	_spawn_reward_item(true)
	await Wait.real_seconds(self, ITEM_POP_TIME + reveal_hold_time)
	if has_cam and is_instance_valid(stage):
		stage.release_camera_focus(reveal_return_time)
	_end_reveal()

func _end_reveal() -> void:
	if _revealing:
		_revealing = false
		GameManager.ui_closed(self)

func _exit_tree() -> void:
	_end_reveal() # 연출 중에 사라져도 조작 잠금이 남지 않게

# 상자 위로 아이템을 띄운다. 주우면(FieldItem이 사라지면) 상자도 흐려지며 사라진다
func _spawn_reward_item(pop: bool) -> void:
	var item := FIELD_ITEM_SCENE.instantiate() as Node2D
	item.id = _item_save_id()
	item.item_resource = reward_item
	var target := position + Vector2(0, -item_pop_height)
	get_parent().add_child(item)
	item.tree_exiting.connect(_on_reward_item_taken)
	_spawned_item = item
	if not pop:
		item.position = target
		item.scale = Vector2.ONE * item_scale
		return
	_play_reveal_sound()
	# 뾱: 상자 입구에서 작게 튀어나와 살짝 넘쳤다가 제자리
	item.position = position + Vector2(0, -6)
	item.scale = Vector2.ONE * item_scale * 0.2
	item.get_node("CollisionShape2D").set_deferred("disabled", true) # 다 나오기 전엔 줍지 않는다
	var tween := item.create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(item, "position", target, ITEM_POP_TIME)
	tween.tween_property(item, "scale", Vector2.ONE * item_scale, ITEM_POP_TIME)
	tween.chain().tween_callback(func(): item.get_node("CollisionShape2D").set_deferred("disabled", false))

func _play_reveal_sound() -> void:
	if reveal_sound == null:
		return
	var player := AudioStreamPlayer2D.new()
	player.stream = reveal_sound
	player.bus = &"SFX"
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()

func _on_reward_item_taken() -> void:
	if not is_inside_tree() or is_queued_for_deletion():
		return # 씬이 통째로 닫히는 중
	if GameManager.collected_items.has(_item_save_id()):
		_vanish_after_open()

# 연 상자는 잠시 열린 모습을 보여준 뒤 흐려지며 사라진다 (열림 기록은 세이브에 남아 다시 나오지 않음)
func _vanish_after_open() -> void:
	await Wait.seconds(self, VANISH_DELAY)
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, VANISH_FADE)
	tween.tween_callback(queue_free)
