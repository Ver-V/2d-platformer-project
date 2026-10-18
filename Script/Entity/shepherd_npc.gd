extends Interactable
class_name ShepherdNPC

# 양치기 (스테이지3): 길 잃은 새끼양(lamb_item_id) total_lambs(4)마리 찾기 퀘스트.
# interact(E)로 말을 걸면 상황에 맞는 블록을 resources/Dialogues/<locale>/shepherd.json에서 고른다:
#   intro      = 처음 말 걸 때 (부탁)
#   thanks     = 새끼양을 들고 왔을 때 / thanks_all = 이번에 다 모였을 때
#   waiting    = 안 들고 왔을 때 (아직 남음)
#   done       = 다 돌려준 뒤
# thanks 대사가 끝나면 가방의 새끼양을 모두 받고, 돌려받은 순서대로 rewards[n-1]을 준다 (n번째 새끼양의 보상.
# LootEntry의 아이템·골드를 쓰고 weight는 안 쓴다. 칸이 모자라거나 비어 있으면 그 번째는 보상 없음).
# 돌려준 수는 GameManager.quest_progress["lost_lambs"]로 저장된다. 대화 중 범위를 벗어나 대화가 끊기면 받지 않는다.
# 그림: AnimatedSprite2D에 "Idle" 애니메이션을 넣으면 그걸 재생하고, 비어 있으면 Placeholder 도형을 보여 준다. 원점 = 발밑 중앙.

const QUEST_ID := "lost_lambs"
const DIALOGUE_FILE := "res://resources/Dialogues/en/shepherd.json"

@export var lamb_item_id: String = "lost_lamb"
@export var total_lambs: int = 4
@export var rewards: Array[LootEntry] = []
@export var npc_id: String = "shepherd" # GameManager.npc_talk_counts 키 (처음 말 걸었는지)

@onready var sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D")
@onready var placeholder: CanvasItem = get_node_or_null("Placeholder")

func _ready() -> void:
	super._ready()
	add_to_group("npc")
	var has_art := sprite != null and sprite.sprite_frames != null and sprite.sprite_frames.has_animation(&"Idle")
	if sprite != null:
		sprite.visible = has_art
		if has_art:
			sprite.play(&"Idle")
	if placeholder != null:
		placeholder.visible = not has_art

func returned_count() -> int:
	return GameManager.get_quest_progress(QUEST_ID)

func carried_count() -> int:
	return Inventory.count_item(lamb_item_id)

func pick_block() -> String:
	if int(GameManager.npc_talk_counts.get(npc_id, 0)) == 0:
		return "intro"
	var carried := carried_count()
	if carried > 0:
		return "thanks_all" if returned_count() + carried >= total_lambs else "thanks"
	return "done" if returned_count() >= total_lambs else "waiting"

# 메뉴 잠금은 Interactable이 확인한다. 대화·상점 상태도 한 번 더 확인.
func _can_interact() -> bool:
	return not DialogueManager.is_dialogue_active and not ShopUI.is_open

func _on_interact() -> void:
	var block := pick_block()
	if not DialogueManager.start_dialogue(DIALOGUE_FILE, block):
		return
	await DialogueManager.dialogue_finished
	if not is_instance_valid(self) or not player_in_range:
		return # 범위를 벗어나 대화가 끊겼다
	GameManager.npc_talk_counts[npc_id] = int(GameManager.npc_talk_counts.get(npc_id, 0)) + 1
	if block.begins_with("thanks"):
		take_lambs()

# 가방의 새끼양을 모두 받고 한 마리마다 보상을 준다. 받은 수를 돌려준다
func take_lambs() -> int:
	var taken := 0
	var index := Inventory.find_item(lamb_item_id)
	while index != -1 and returned_count() < total_lambs:
		Inventory.remove_item_at(index)
		var n := returned_count() + 1
		GameManager.set_quest_progress(QUEST_ID, n)
		_give_reward(n)
		taken += 1
		index = Inventory.find_item(lamb_item_id)
	if taken > 0 and is_instance_valid(current_player) and current_player.has_method("show_popup"):
		current_player.show_popup(tr(&"SHEPHERD_LAMBS_RETURNED").format({"count": returned_count(), "total": total_lambs}), Color(0.95, 0.92, 0.8))
	return taken

func _give_reward(n: int) -> void:
	if n < 1 or n > rewards.size() or rewards[n - 1] == null:
		return
	var entry: LootEntry = rewards[n - 1]
	if entry.item != null and Inventory.add_item(entry.item):
		HUD.log_pickup_item(entry.item)
	var gold := entry.roll_gold(GameManager.make_loot_rng("shepherd:%s:%d" % [npc_id, n]))
	if gold > 0:
		GameManager.update_gold(gold)
		HUD.log_pickup_gold(gold)

# 플레이어가 멀어지면 대화창을 닫는다
func _on_player_exited(_body: Node) -> void:
	if DialogueManager.is_dialogue_active:
		DialogueManager.force_close()
