extends DialogueBlock
class_name ItemConditionalDialogueBlock

@export_group("Item Condition")
@export var required_item_id: String = ""
@export var finish_without_item: bool = false

@export_group("Dialogue Blocks")
@export var block_with_item: String = "with_item"
@export var block_without_item: String = "without_item"


func _ready() -> void:
	add_to_group("dialogue_blocks")

	if _restore_completed_state():
		return

	body_entered.connect(_on_conditional_body_entered)


func _on_conditional_body_entered(body: Node2D) -> void:
	if _has_triggered or not body is Player:
		return

	_has_triggered = true

	if DialogueManager.is_dialogue_active:
		await DialogueManager.dialogue_finished

	if not DialogueManager.has_dialogue_file(dialogue_file):
		push_warning("ItemConditionalDialogueBlock: Dialogue file is missing: " + dialogue_file)
		_has_triggered = false
		return

	var has_item := _has_required_item()
	var start_block := block_with_item if has_item else block_without_item
	if not DialogueManager.start_dialogue(dialogue_file, start_block):
		_has_triggered = false
		return
	await DialogueManager.dialogue_finished

	# Keep the block active when the item is missing, so the player can
	# return after obtaining the item and trigger the with_item block.
	if not has_item and not finish_without_item:
		_has_triggered = false
		return

	_record_completion()

	queue_free()


func _has_required_item() -> bool:
	if required_item_id.strip_edges().is_empty():
		push_warning("ItemConditionalDialogueBlock: Required Item Id is empty.")
		return false

	for item: ItemData in Inventory.inventory:
		if item != null and item.id == required_item_id:
			return true

	return false
