extends SceneTree
# Run with Godot --headless --path . --script res://tests/item_shop_regressions.gd
# 실제 세이브 파일은 쓰지 않는다. 저장 데이터는 Dictionary로만 주고받는다.

var failures: int = 0

func _initialize() -> void:
	call_deferred("run_checks")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func run_checks() -> void:
	var manager = root.get_node("GameManager")
	var saver = root.get_node("SaveManager")
	check_item_database(manager)
	check_shop_stock(manager, saver)
	check_legacy_save(manager, saver)
	await check_shop_ui(manager)
	await check_merchant_input_lock(manager)
	await check_interact_key_objects(manager)
	manager.reset_data()
	print("Item/shop regression checks: ", "PASS" if failures == 0 else "FAIL", " (", failures, " failures)")
	quit(0 if failures == 0 else 1)

func stock_of(manager, shop_id: String, item_id: String) -> int:
	for row in manager.get_shop_stock(shop_id):
		if row["item"].id == item_id:
			return row["stock"]
	return -1

func check_item_database(manager) -> void:
	for id in ["health_potion", "health_flask", "Parry_increase_potion", "pink_key"]:
		var item = manager.get_item_by_id(id)
		check(item != null and item.id == id, "Item not loaded from resources/items: " + id)
	check(manager.get_item_by_id("no_such_item") == null, "Unknown item id should return null")
	print("Items: every .tres in resources/items is found by id")

func check_shop_stock(manager, saver) -> void:
	manager.reset_data()
	check(stock_of(manager, "Stage1", "health_potion") == 3, "Stage1 potion default stock")
	check(stock_of(manager, "Stage1", "Parry_increase_potion") == 1, "Stage1 parry potion default stock")
	check(stock_of(manager, "Stage2", "health_potion") == 5, "Stage2 potion default stock")
	check(manager.get_shop_stock("NoShop").is_empty(), "Unknown shop should be empty")

	manager.record_shop_purchase("Stage1", "health_potion")
	manager.record_shop_purchase("Stage1", "Parry_increase_potion")
	manager.record_shop_purchase("Stage1", "Parry_increase_potion")
	check(stock_of(manager, "Stage1", "health_potion") == 2, "Purchase did not reduce stock")
	check(stock_of(manager, "Stage1", "Parry_increase_potion") == 0, "Stock should not go below zero")

	# 저장 → JSON → 불러오기 왕복 (파일 없이)
	var data: Dictionary = manager.get_data_for_save()
	check(saver._is_valid_game(data), "Save data with shop_sold rejected by validator")
	var round_trip: Dictionary = JSON.parse_string(JSON.stringify(data))
	manager.reset_data()
	check(stock_of(manager, "Stage1", "health_potion") == 3, "New game did not restore default stock")
	manager.load_data_from_save(round_trip)
	check(stock_of(manager, "Stage1", "health_potion") == 2, "Loaded stock wrong after JSON round trip")
	check(stock_of(manager, "Stage2", "health_potion") == 5, "Untouched shop changed after load")
	manager.record_shop_purchase("Stage1", "health_potion")
	check(stock_of(manager, "Stage1", "health_potion") == 1, "Purchase after load (float counts from JSON) failed")

	# 세이브에 없는 상점(나중에 추가된 상점)은 기본 재고로 보인다.
	var without_stage2 := round_trip.duplicate(true)
	without_stage2["shop_sold"] = {"Stage1": {"health_potion": 1}}
	manager.load_data_from_save(without_stage2)
	check(stock_of(manager, "Stage2", "health_potion") == 5, "Shop missing from save should use default stock")

	var bad := round_trip.duplicate(true)
	bad["shop_sold"] = {"Stage1": {"health_potion": -1}}
	check(not saver._is_valid_game(bad), "Negative sold count accepted")
	print("Shops: default stock, purchases, save round trip and shops added after a save checked")

func check_legacy_save(manager, saver) -> void:
	manager.reset_data()
	var legacy: Dictionary = manager.get_data_for_save()
	legacy.erase("shop_sold")
	legacy["save_version"] = 2
	legacy["merchant_stocks"] = {
		"Stage1": [{"id": "health_potion", "stock": 1}, {"id": "Parry_increase_potion", "stock": 1}],
		"OldShop": [{"id": "health_potion", "stock": 0}],
	}
	check(saver._is_valid_game(legacy), "Version 2 save rejected")
	manager.load_data_from_save(JSON.parse_string(JSON.stringify(legacy)))
	check(stock_of(manager, "Stage1", "health_potion") == 1, "Legacy remaining stock not converted")
	check(stock_of(manager, "Stage1", "Parry_increase_potion") == 1, "Legacy untouched item changed")
	check(stock_of(manager, "Stage2", "health_potion") == 5, "Shop absent from legacy save changed")
	var resaved: Dictionary = manager.get_data_for_save()
	check(resaved["save_version"] == saver.SAVE_VERSION and not resaved.has("merchant_stocks"), "Legacy save not upgraded on next save")
	print("Legacy: version 2 merchant_stocks converted to sold counts")

func check_shop_ui(manager) -> void:
	manager.reset_data()
	manager.gold = 1000
	var shop = root.get_node("ShopUI")
	shop.open_shop("Stage1")
	check(shop.item_list.get_child_count() == 2, "Shop UI did not list Stage1 items")
	shop.selected_index = 0
	shop.open_confirm_panel()
	await shop.buy_item()
	check(stock_of(manager, "Stage1", "health_potion") == 2 and manager.gold == 850, "Buying through the shop UI failed")
	check(manager.has_item("health_potion"), "Bought item not in inventory")
	shop.close_shop()
	await process_frame
	print("Shop UI: lists stock from resources and records purchases")

func check_merchant_input_lock(manager) -> void:
	manager.reset_data()
	var dialogue = root.get_node("DialogueManager")
	var shop = root.get_node("ShopUI")
	var merchant = load("res://Scenes/Entitites/MerchantNPC.tscn").instantiate()
	merchant.location_name = "Stage1"
	root.add_child(merchant)
	merchant.player_in_range = true
	var interact := InputEventAction.new()
	interact.action = "interact"
	interact.pressed = true

	# 일시정지 메뉴 같은 다른 UI가 열려 있으면 상인 대화가 시작되면 안 된다
	var other_ui := Node.new()
	root.add_child(other_ui)
	manager.ui_opened(other_ui)
	merchant._input(interact)
	check(not dialogue.is_dialogue_active and not shop.is_open, "Merchant opened while another UI held the input lock")
	manager.ui_closed(other_ui)

	merchant._input(interact)
	check(dialogue.is_dialogue_active, "Merchant did not start dialogue with no UI open")
	merchant.player_in_range = false # 대화가 끝나도 상점은 열지 않게
	dialogue.force_close()
	await process_frame

	other_ui.queue_free()
	merchant.queue_free()
	await process_frame
	manager.reset_data()
	print("Merchant: interaction ignored while another UI is open")

func press(node: Node, action: StringName, handler: String = "_input") -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	node.call(handler, event)

# 상자·열쇠 문도 상인·세이브 포인트와 같은 interact 키(E)로 열린다.
func check_interact_key_objects(manager) -> void:
	manager.reset_data()
	var player = load("res://Scenes/Entitites/Player.tscn").instantiate()
	root.add_child(player)
	player.set_physics_process(false)

	var chest = load("res://Scenes/System/Chest.tscn").instantiate()
	chest.persist_id = "test_chest"
	chest.reward_gold = 10
	root.add_child(chest)
	chest._on_body_entered(player)
	var gold_before: int = manager.gold
	press(chest, &"jump")
	check(not chest._opened, "Chest opened with the jump key")
	var menu := Node.new()
	root.add_child(menu)
	manager.ui_opened(menu, false)
	press(chest, &"interact")
	check(not chest._opened, "Chest opened while a menu held the input lock")
	manager.ui_closed(menu)
	press(chest, &"interact")
	check(chest._opened and manager.gold == gold_before + 10, "Chest did not open with the interact key")
	press(chest, &"interact")
	check(manager.gold == gold_before + 10, "Opened chest gave its reward twice")

	var door = load("res://Scenes/System/KeyDoor.tscn").instantiate()
	door.locked = false
	door.persist_id = "test_door"
	root.add_child(door)
	door._on_body_entered(player)
	press(door, &"ui_up", "_unhandled_input")
	check(not door._opened, "Door opened with the up key")
	manager.ui_opened(menu, false)
	press(door, &"interact", "_unhandled_input")
	check(not door._opened, "Door opened while a menu held the input lock")
	manager.ui_closed(menu)
	press(door, &"interact", "_unhandled_input")
	check(door._opened, "Door did not open with the interact key")

	for node in [door, chest, menu, player]:
		node.queue_free()
	await process_frame
	await process_frame
	manager.reset_data()
	print("Interact key: chest and key door open with E, not jump/up, and respect the input lock")
