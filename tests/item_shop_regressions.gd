extends SceneTree
# Run with Godot --headless --path . --script res://tests/item_shop_regressions.gd
# 실제 세이브 파일은 쓰지 않는다. 저장 데이터는 Dictionary로만 주고받는다.

var failures: int = 0

# 오토로드 (테스트 스크립트에선 오토로드 이름을 바로 못 쓴다)
func inv() -> Node: return root.get_node("Inventory")
func settings() -> Node: return root.get_node("SettingsManager")
func db() -> Node: return root.get_node("Database")

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
	await check_merchant_without_dialogue(manager)
	await check_interact_key_objects(manager)
	await check_chest_rewards(manager)
	await check_inventory_item_info(manager)
	await check_item_animation(manager)
	await check_door_lock(manager)
	await check_shortcut_door(manager)
	await check_resume_on_quit(manager, saver)
	await check_door_prompt_on_hud(manager)
	check_loot_seed(manager, saver)
	check_save_slots(manager, saver)
	check_inventory_signal(manager)
	check_settings_manager()
	check_boss_bar_centered()
	manager.reset_data()
	print("Item/shop regression checks: ", "PASS" if failures == 0 else "FAIL", " (", failures, " failures)")
	quit(0 if failures == 0 else 1)

# 랜덤 보상 시드: 같은 세이브(시드) + 같은 상자 = 같은 결과, 상자나 시드가 다르면 달라질 수 있음
func check_loot_seed(manager, saver) -> void:
	manager.reset_data()
	var LootTableScript = load("res://Script/Item_UI/LootTable.gd")
	var LootEntryScript = load("res://Script/Item_UI/LootEntry.gd")
	var table = LootTableScript.new()
	for i in 20:
		var entry = LootEntryScript.new()
		entry.gold_amount = 10
		entry.gold_max = 1000
		entry.weight = 1
		entry.item = db().get_item_by_id("health_potion") if i == 0 else null
		table.entries.append(entry)

	# 상자 하나의 결과 = (뽑힌 줄, 골드)
	var roll := func(source_id: String) -> Array:
		var rng = manager.make_loot_rng(source_id)
		var picked = table.pick(rng)
		return [table.entries.find(picked), picked.roll_gold(rng)]

	var first: Array = roll.call("chest:A")
	check(roll.call("chest:A") == first, "Same seed and chest should give the same loot")
	var differs_by_source := false
	for i in 20:
		differs_by_source = differs_by_source or roll.call("chest:B%d" % i) != first
	check(differs_by_source, "Different chests should be able to give different loot")

	# 저장 → 불러오기 해도 시드가 유지되어 같은 결과
	var data: Dictionary = JSON.parse_string(JSON.stringify(manager.get_data_for_save()))
	check(saver._is_valid_game(data), "Save with loot_seed rejected by validator")
	var saved_seed: int = manager.loot_seed
	manager.reset_data()
	manager.load_data_from_save(data)
	check(manager.loot_seed == saved_seed, "loot_seed should survive save/load")
	check(roll.call("chest:A") == first, "Reloaded save should give the same loot")

	# 새 게임마다 시드가 바뀐다 (몇 번 해서 한 번이라도 다르면 통과)
	var changed := false
	for i in 5:
		manager.reset_data()
		changed = changed or manager.loot_seed != saved_seed
	check(changed, "New game should pick a new loot seed")

	# 옛 세이브(시드 없음)도 통과하고 시드가 생긴다
	data.erase("loot_seed")
	check(saver._is_valid_game(data), "Save without loot_seed should still be valid")
	var bad := data.duplicate(true)
	bad["loot_seed"] = -1
	check(not saver._is_valid_game(bad), "Negative loot_seed accepted")
	bad["loot_seed"] = "abc"
	check(not saver._is_valid_game(bad), "Non-number loot_seed accepted")
	print("Loot seed: same save + same chest = same loot, survives save/load, new per game")

# 인벤토리가 바뀌는 모든 경로에서 inventory_changed가 나가야 UI·시야 등이 따라온다
func check_inventory_signal(manager) -> void:
	manager.reset_data()
	var count := [0]
	var on_changed := func(): count[0] += 1
	inv().inventory_changed.connect(on_changed)
	var potion = db().get_item_by_id("health_potion")
	var key = db().get_item_by_id("pink_key")

	inv().add_item(potion)
	check(count[0] == 1, "add_item should emit inventory_changed")
	var removed = inv().remove_item_at(0)
	check(removed == potion and inv().inventory[0] == null and count[0] == 2, "remove_item_at should clear the slot and emit")
	check(inv().remove_item_at(0) == null and count[0] == 2, "Removing an empty slot should do nothing")
	check(inv().remove_item_at(99) == null and count[0] == 2, "Removing out of range should do nothing")

	inv().add_item(key)
	var before: int = count[0]
	inv().consume_key_use("pink_key")
	check(count[0] == before + 1 and not inv().has_item("pink_key"), "Using up a key should remove it and emit")

	inv().add_item(potion)
	var data: Dictionary = manager.get_data_for_save()
	before = count[0]
	manager.reset_data()
	check(count[0] == before + 1, "New game should emit inventory_changed")
	manager.load_data_from_save(data)
	check(count[0] == before + 2 and inv().has_item("health_potion"), "Loading a save should emit inventory_changed")

	inv().inventory_changed.disconnect(on_changed)
	manager.reset_data()
	print("Inventory signal: add, remove, key use-up, new game and load all emit inventory_changed")

# 세이브 슬롯: 슬롯별 경로, 요약, 옛 단일 세이브 이전, 슬롯 버튼 글자.
# 실제 슬롯 파일(user://save_slot_N.json)은 건드리지 않고 테스트 전용 경로만 쓴다.
func check_save_slots(manager, saver) -> void:
	check(saver.SLOT_COUNT == 3, "There should be 3 save slots")
	var paths := {}
	for slot in range(1, 4):
		paths[saver.slot_path(slot)] = true
	check(paths.size() == 3 and not paths.has(saver.SAVE_PATH), "Each slot should have its own save file")
	manager.current_slot = 2
	check(manager.current_save_path() == saver.slot_path(2), "GameManager should save to the chosen slot")
	manager.current_slot = 1

	var legacy := "user://test_legacy_save.json"
	var target := "user://test_slot_target.json"
	saver.delete_save(legacy)
	saver.delete_save(target)
	check(saver.slot_summary(target).is_empty(), "Empty slot should have no summary")

	manager.reset_data()
	manager.gold = 345
	manager.last_scene_path = "res://Scenes/Stage/Stage_02.tscn"
	var data: Dictionary = manager.get_data_for_save()
	data["stage_title_key"] = "" # 옛 세이브처럼 제목 키 없음
	check(saver.save_game(data, legacy), "Writing the test legacy save failed")
	check(saver.migrate_legacy_save(legacy, target), "Legacy save should move to slot 1")
	check(not saver.has_save(legacy) and saver.has_save(target), "Legacy save file should be gone after moving")
	check(not saver.migrate_legacy_save(legacy, target), "Nothing left to migrate the second time")

	var summary: Dictionary = saver.slot_summary(target)
	check(summary.get("gold") == 345 and summary.get("saved_unix", 0) > 0, "Slot summary should show gold and save time")

	# 슬롯이 이미 있으면 옛 세이브로 덮어쓰지 않는다
	check(saver.save_game(data, legacy), "Writing the test legacy save failed")
	check(not saver.migrate_legacy_save(legacy, target) and saver.has_save(legacy), "Legacy save must not overwrite an existing slot")

	var SlotMenu = load("res://Script/System/save_slot_menu.gd")
	var manager_locale: String = TranslationServer.get_locale()
	for locale in ["en", "ko"]:
		settings().set_locale(locale)
		var text: String = SlotMenu.slot_text(2, summary)
		check(text.contains(TranslationServer.translate(&"STAGE_02_TITLE")) and text.contains("345"),
			"Old save without a title key should still show the stage name from its scene path (%s)" % locale)
		check(not text.contains("SAVE_SLOT_") and not text.contains("{"), "Slot text left a raw key/placeholder (%s)" % locale)
		var empty_text: String = SlotMenu.slot_text(1, {})
		check(empty_text.contains(TranslationServer.translate(&"SAVE_SLOT_EMPTY")), "Empty slot text missing (%s)" % locale)
		var unknown: String = SlotMenu.stage_title({"scene_path": "res://Scenes/Other.tscn"})
		check(unknown == TranslationServer.translate(&"SAVE_SLOT_UNKNOWN_STAGE"), "Unknown scene should show a fallback name")
	settings().set_locale(manager_locale)

	saver.delete_save(legacy)
	saver.delete_save(target)
	manager.reset_data()
	print("Save slots: 3 separate files, legacy save moves to slot 1, slot summary and labels")

func stock_of(manager, shop_id: String, item_id: String) -> int:
	for row in manager.get_shop_stock(shop_id):
		if row["item"].id == item_id:
			return row["stock"]
	return -1

# 상점 리소스(resources/shops)에 적힌 시작 재고. 재고 수치를 바꿔도 테스트가 따라가도록
func default_stock(shop_id: String, item_id: String) -> int:
	for entry in db().get_shop(shop_id).entries:
		if entry.item != null and entry.item.id == item_id:
			return entry.stock
	return -1

func check_item_database(manager) -> void:
	for id in ["health_potion", "health_flask", "Parry_increase_potion", "pink_key"]:
		var item = db().get_item_by_id(id)
		check(item != null and item.id == id, "Item not loaded from resources/items: " + id)
	check(db().get_item_by_id("no_such_item") == null, "Unknown item id should return null")
	print("Items: every .tres in resources/items is found by id")

func check_shop_stock(manager, saver) -> void:
	manager.reset_data()
	# 시작 재고는 상점 리소스 값 그대로 (숫자는 리소스에서 자유롭게 바꿀 수 있다)
	var potion1 := default_stock("Stage1", "health_potion")
	var parry1 := default_stock("Stage1", "Parry_increase_potion")
	check(potion1 >= 3, "Stage1 should start with at least 3 potions for the purchase checks below")
	check(stock_of(manager, "Stage1", "health_potion") == potion1, "Stage1 potion default stock")
	check(stock_of(manager, "Stage1", "Parry_increase_potion") == parry1, "Stage1 parry potion default stock")
	check(stock_of(manager, "Stage2", "health_potion") == default_stock("Stage2", "health_potion"), "Stage2 potion default stock")
	check(manager.get_shop_stock("NoShop").is_empty(), "Unknown shop should be empty")

	manager.record_shop_purchase("Stage1", "health_potion")
	for i in parry1 + 1: # 재고보다 한 번 더 산다
		manager.record_shop_purchase("Stage1", "Parry_increase_potion")
	check(stock_of(manager, "Stage1", "health_potion") == potion1 - 1, "Purchase did not reduce stock")
	check(stock_of(manager, "Stage1", "Parry_increase_potion") == 0, "Stock should not go below zero")

	# 저장 → JSON → 불러오기 왕복 (파일 없이)
	var data: Dictionary = manager.get_data_for_save()
	check(saver._is_valid_game(data), "Save data with shop_sold rejected by validator")
	var round_trip: Dictionary = JSON.parse_string(JSON.stringify(data))
	manager.reset_data()
	check(stock_of(manager, "Stage1", "health_potion") == potion1, "New game did not restore default stock")
	manager.load_data_from_save(round_trip)
	check(stock_of(manager, "Stage1", "health_potion") == potion1 - 1, "Loaded stock wrong after JSON round trip")
	check(stock_of(manager, "Stage2", "health_potion") == default_stock("Stage2", "health_potion"), "Untouched shop changed after load")
	manager.record_shop_purchase("Stage1", "health_potion")
	check(stock_of(manager, "Stage1", "health_potion") == potion1 - 2, "Purchase after load (float counts from JSON) failed")

	# 세이브에 없는 상점(나중에 추가된 상점)은 기본 재고로 보인다.
	var without_stage2 := round_trip.duplicate(true)
	without_stage2["shop_sold"] = {"Stage1": {"health_potion": 1}}
	manager.load_data_from_save(without_stage2)
	check(stock_of(manager, "Stage2", "health_potion") == default_stock("Stage2", "health_potion"), "Shop missing from save should use default stock")

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
		"Stage1": [{"id": "health_potion", "stock": 1}, {"id": "Parry_increase_potion", "stock": default_stock("Stage1", "Parry_increase_potion")}],
		"OldShop": [{"id": "health_potion", "stock": 0}],
	}
	check(saver._is_valid_game(legacy), "Version 2 save rejected")
	manager.load_data_from_save(JSON.parse_string(JSON.stringify(legacy)))
	check(stock_of(manager, "Stage1", "health_potion") == 1, "Legacy remaining stock not converted")
	check(stock_of(manager, "Stage1", "Parry_increase_potion") == default_stock("Stage1", "Parry_increase_potion"), "Legacy untouched item changed")
	check(stock_of(manager, "Stage2", "health_potion") == default_stock("Stage2", "health_potion"), "Shop absent from legacy save changed")
	var resaved: Dictionary = manager.get_data_for_save()
	check(resaved["save_version"] == saver.SAVE_VERSION and not resaved.has("merchant_stocks"), "Legacy save not upgraded on next save")
	print("Legacy: version 2 merchant_stocks converted to sold counts")

func check_shop_ui(manager) -> void:
	manager.reset_data()
	manager.gold = 1000
	var shop = root.get_node("ShopUI")
	shop.open_shop("Stage1")
	check(shop.item_list.get_child_count() == db().get_shop("Stage1").entries.size(), "Shop UI did not list Stage1 items")
	shop.selected_index = 0
	var first_item = db().get_shop("Stage1").entries[0].item
	var before := stock_of(manager, "Stage1", first_item.id)
	shop.open_confirm_panel()
	await shop.buy_item()
	check(stock_of(manager, "Stage1", first_item.id) == before - 1 and manager.gold == 1000 - first_item.price, "Buying through the shop UI failed")
	check(inv().has_item(first_item.id), "Bought item not in inventory")
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
	chest.loot_table = null # 입력 키만 검사: 랜덤 보상(기본 상자 목록은 바뀔 수 있음) 없이 골드 10만
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
	var saved_opened_art = door.opened_sprite.texture
	door.opened_sprite.texture = null # 열린 그림이 없는 문 상황
	door._update_open_state()
	check(door.opened_sprite.visible == false and door.closed_sprite.visible and door.closed_sprite.modulate != Color.WHITE,
		"Door without opened art should tint the closed sprite")
	door.opened_sprite.texture = saved_opened_art
	door.opened_sprite.texture = PlaceholderTexture2D.new()
	door._update_open_state()
	check(door.opened_sprite.visible and not door.closed_sprite.visible, "Opened door should show the opened sprite")
	var reloaded = load("res://Scenes/System/KeyDoor.tscn").instantiate()
	reloaded.persist_id = "test_door"
	var closed_art := ImageTexture.create_from_image(Image.create(16, 32, false, Image.FORMAT_RGBA8))
	var opened_art := ImageTexture.create_from_image(Image.create(16, 32, false, Image.FORMAT_RGBA8))
	reloaded.closed_texture = closed_art
	reloaded.opened_texture = opened_art
	root.add_child(reloaded)
	check(reloaded._opened, "Opened door should stay open (saved)")
	check(reloaded.closed_sprite.texture == closed_art and reloaded.opened_sprite.texture == opened_art,
		"Door inspector textures should be applied to its sprites")
	check(reloaded.opened_sprite.visible and not reloaded.closed_sprite.visible, "Saved-open door should show its opened texture")
	check(reloaded.opened_sprite.offset == Vector2(0, -16) and reloaded.opened_sprite.position == Vector2.ZERO,
		"Door textures from the inspector should sit on the node origin")
	reloaded.queue_free()

	for node in [door, chest, menu, player]:
		node.queue_free()
	await process_frame
	await process_frame
	manager.reset_data()
	print("Interact key: chest and key door open with E, not jump/up, and respect the input lock")

# 지정 아이템이 있는 상자·박스는 그것만, 없으면 LootTable 가중치대로 아이템 또는 골드.
func check_chest_rewards(manager) -> void:
	var potion = db().get_item_by_id("health_potion")
	var parry = db().get_item_by_id("Parry_increase_potion")
	var key = db().get_item_by_id("pink_key")

	# LootTable/LootEntry → ItemData → GameManager 의존이라 실행 중에 로드한다 (컴파일 시점엔 autoload가 없음)
	var LootTableScript = load("res://Script/Item_UI/LootTable.gd")
	var LootEntryScript = load("res://Script/Item_UI/LootEntry.gd")
	var table = LootTableScript.new()
	for row in [[null, 25, 6], [potion, 0, 3], [parry, 0, 1], [key, 0, 0], [null, 0, 50]]:
		var entry = LootEntryScript.new()
		entry.item = row[0]
		entry.gold_amount = row[1]
		entry.weight = row[2]
		table.entries.append(entry)
	var counts := {}
	for i in 1000:
		var picked = table.pick()
		var key_name: String = picked.item.id if picked.item != null else "gold"
		counts[key_name] = counts.get(key_name, 0) + 1
	check(not counts.has("pink_key"), "Zero-weight loot entry should never drop")
	check(counts.get("gold", 0) > counts.get("health_potion", 0) and counts.get("health_potion", 0) > counts.get("Parry_increase_potion", 0),
		"Loot entries should drop in proportion to their weights")
	check(counts.get("Parry_increase_potion", 0) > 0, "Every weighted loot entry should be able to drop")
	check(LootTableScript.new().pick() == null, "Empty loot table should give nothing")

	# 랜덤 골드: 10 ~ 100 사이 10의 배수
	var gold_entry = LootEntryScript.new()
	gold_entry.gold_amount = 10
	gold_entry.gold_max = 100
	var seen := {}
	var gold_ok := true
	for i in 500:
		var g: int = gold_entry.roll_gold()
		gold_ok = gold_ok and g >= 10 and g <= 100 and g % 10 == 0
		seen[g] = true
	check(gold_ok, "Random gold should stay within 10~100 in steps of 10")
	check(seen.has(10) and seen.has(100) and seen.size() == 10, "Random gold should be able to roll every step including both ends")
	gold_entry.gold_max = 0
	check(gold_entry.roll_gold() == 10, "Gold without a max should be fixed")
	var max_only = LootEntryScript.new()
	max_only.gold_max = 50
	check(not max_only.is_empty(), "Entry with only gold_max should not count as empty")

	var chest = load("res://Scenes/System/Chest.tscn").instantiate()
	check(chest.loot_table != null and not chest.loot_table.entries.is_empty(), "Chest should default to the default loot table")
	chest.reward_item = key
	chest.loot_table = table
	var fixed_ok := true
	for i in 20:
		var r = chest._roll_reward()
		fixed_ok = fixed_ok and r.item == key and r.gold_amount == 0
	check(fixed_ok, "Chest with a reward item should always give only that item")
	chest.reward_item = null
	var rolled = chest._roll_reward()
	check(rolled.item in [potion, parry] or rolled.gold_amount == 25, "Chest without a reward item should roll from its loot table")
	chest.loot_table = null
	check(chest._roll_reward().is_empty(), "Chest without reward item or loot table should give nothing")
	chest.free()
	print("Chest rewards: fixed item only, otherwise weighted random item/gold from LootTable")

	await check_box_drops(manager, LootTableScript, LootEntryScript, potion)

func _only_entry_table(LootTableScript, LootEntryScript, item, gold: int):
	var table = LootTableScript.new()
	var entry = LootEntryScript.new()
	entry.item = item
	entry.gold_amount = gold
	table.entries.append(entry)
	return table

func _children_with_script(path: String) -> Array:
	var found := []
	for child in root.get_children():
		var sc = child.get_script()
		if sc != null and sc.resource_path == path:
			found.append(child)
	return found

func check_box_drops(manager, LootTableScript, LootEntryScript, potion) -> void:
	manager.reset_data()
	var box_scene = load("res://Scenes/System/BreakableBox.tscn")
	var default_box = box_scene.instantiate()
	check(default_box.loot_table != null, "Box should default to the default loot table")
	default_box.free()

	# 아이템 박스: 부수면 아이템이 바닥에 떨어지고, 주워야 박스가 부순 상태로 저장된다
	var box = box_scene.instantiate()
	box.persist_id = "test_box_item"
	box.loot_table = _only_entry_table(LootTableScript, LootEntryScript, potion, 0)
	root.add_child(box)
	box.receive_hit(HitData.new(box.max_hp))
	await process_frame
	var drops := _children_with_script("res://Script/Item_UI/FieldItem.gd")
	check(drops.size() == 1 and drops[0].item_resource == potion, "Broken box should drop its item on the floor")
	check(not manager.collected_items.has("box:test_box_item"), "Box should come back if its dropped item was not picked up")
	if drops.size() == 1:
		drops[0].id = "box:test_box_item" # 이미 같은 값이어야 함
		manager.add_collected_item(drops[0].id) # 줍기 = FieldItem이 id를 기록
		drops[0].queue_free()
	var again = box_scene.instantiate()
	again.persist_id = "test_box_item"
	root.add_child(again)
	await process_frame
	check(not is_instance_valid(again) or again.is_queued_for_deletion(), "Box whose drop was picked up should stay broken")

	# 골드 박스: 코인을 뿌리고 바로 부순 상태로 저장
	var gold_box = box_scene.instantiate()
	gold_box.persist_id = "test_box_gold"
	gold_box.loot_table = _only_entry_table(LootTableScript, LootEntryScript, null, 120)
	root.add_child(gold_box)
	gold_box.receive_hit(HitData.new(gold_box.max_hp))
	await process_frame
	var coins := _children_with_script("res://Script/Item_UI/coin.gd")
	var coin_total := 0
	for c in coins:
		coin_total += c.gold_amount
	check(coin_total == 120 and coins.size() == 3, "Gold box should scatter coins worth its gold amount")
	check(manager.collected_items.has("box:test_box_gold"), "Gold-only box should be saved as broken right away")

	# 체력 단계별 그림: 100% → [0], 75% 이하 → [1], 50% 이하 → [2], 25% 이하 → [3]
	var staged = box_scene.instantiate()
	check(staged.damage_textures.size() == 4, "Box scene should have 4 damage-stage textures")
	staged.persist_id = "test_box_stages"
	root.add_child(staged)
	staged.max_hp = 100
	var expected := {100: 0, 76: 0, 75: 1, 51: 1, 50: 2, 26: 2, 25: 3, 1: 3}
	var stages_ok := true
	for hp_value in expected:
		staged.hp = hp_value
		staged._update_damage_texture()
		stages_ok = stages_ok and staged.damage_stage() == expected[hp_value] 			and staged.sprite.texture == staged.damage_textures[expected[hp_value]]
	check(stages_ok, "Box damage texture should follow the 100/75/50/25% thresholds")
	staged.hp = 100
	staged.receive_hit(HitData.new(30))
	check(staged.sprite.texture == staged.damage_textures[1], "Hitting a box should switch to the damaged texture")
	staged.free()

	# 지정 아이템 박스는 랜덤 목록을 무시
	var fixed_box = box_scene.instantiate()
	fixed_box.reward_item = potion
	fixed_box.loot_table = _only_entry_table(LootTableScript, LootEntryScript, null, 50)
	var r = fixed_box._roll_reward()
	check(r.item == potion and r.gold_amount == 0, "Box with a reward item should drop only that item")
	fixed_box.free()

	await create_timer(0.8).timeout # 코인 튀어오르기 트윈(0.7초)이 끝난 뒤 지워야 트윈이 남지 않는다
	for node in coins + _children_with_script("res://Script/Item_UI/FieldItem.gd"):
		node.queue_free()
	await process_frame
	manager.reset_data()
	print("Box drops: item on the floor (saved when picked up), gold as coins, fixed item overrides loot table")

# 인벤토리: 툴팁 대신 고정 설명 패널. 올린 아이템 → 없으면 클릭한 아이템 → 없으면 비움
func check_inventory_item_info(manager) -> void:
	manager.reset_data()
	var potion = db().get_item_by_id("health_potion")
	var key = db().get_item_by_id("pink_key")
	inv().add_item(potion)
	inv().add_item(key)
	var ui = load("res://Scenes/System/InventoryUI.tscn").instantiate()
	root.add_child(ui)
	await process_frame
	ui.open()
	check(ui.info_name_label.text == "" and ui.info_desc_label.text == "", "Inventory info should start empty")
	ui._on_slot_mouse_entered(0)
	check(ui.info_name_label.text == TranslationServer.translate(potion.name) and ui.info_desc_label.text == TranslationServer.translate(potion.description),
		"Hovering an item should show its name and description")
	ui._on_slot_clicked(1)
	ui._on_slot_mouse_exited(0)
	check(ui.info_name_label.text == TranslationServer.translate(key.name), "Leaving the hovered slot should fall back to the clicked item")
	ui._on_slot_mouse_entered(5)
	check(ui.info_name_label.text == TranslationServer.translate(key.name), "Hovering an empty slot should keep the clicked item")
	ui._on_close_pressed()
	ui._on_slot_mouse_exited(5)
	check(ui.info_name_label.text == "", "Closing the action menu with nothing hovered should clear the info")
	check(ui.grid.get_child(0).tooltip_text == "", "Slots should no longer use the default tooltip")
	ui.close()
	ui.queue_free()
	await process_frame
	manager.reset_data()
	print("Inventory info: fixed panel shows hovered, then clicked item; no default tooltip")

# 애니메이션 아이템: 필드에선 Sprite2D 자식 AnimatedSprite2D로 재생, 슬롯에선 프레임이 바뀌고 둥둥 뜬다. 없는 아이템은 icon 그대로.
func check_item_animation(manager) -> void:
	manager.reset_data()
	var key = db().get_item_by_id("red_lighted_silver_key")
	var potion = db().get_item_by_id("health_potion")
	check(key != null and key.has_animation() and key.anim_frames.get_frame_count(key.anim_name) == 18, "Red-lit silver key should have an 18-frame animation")
	check(not db().get_item_by_id("pink_key").has_animation(), "Pink key should stay a still icon")
	check(key.get_frame_at(0.0) != key.get_frame_at(0.15), "Animated item frame should change over time")
	check(potion.get_frame_at(1.0) == potion.icon, "Item without animation should use its icon")

	var field = load("res://Scenes/Item/field_item.tscn").instantiate()
	field.id = "test:anim_key"
	field.item_resource = key
	root.add_child(field)
	await process_frame
	var anim = field.get_node_or_null("Sprite2D/ItemAnim")
	check(anim is AnimatedSprite2D and anim.is_playing() and field.get_node("Sprite2D").texture == null, "Field item should play the item animation instead of the icon")
	field.queue_free()

	inv().add_item(key)
	inv().add_item(potion)
	var ui = load("res://Scenes/System/InventoryUI.tscn").instantiate()
	root.add_child(ui)
	await process_frame
	ui.open()
	var key_slot = ui.grid.get_child(0)
	var potion_slot = ui.grid.get_child(1)
	var top_before = key_slot.icon.offset_top
	var frame_before = key_slot.icon.texture
	key_slot._process(0.15)
	check(key_slot.icon.texture != frame_before, "Inventory slot should advance the item animation")
	check(key_slot.icon.offset_top != top_before, "Inventory slot icon should bob")
	check(not potion_slot.is_processing() and potion_slot.icon.texture == potion.icon, "Slot without animation should keep the icon still")
	ui.close()
	ui.queue_free()
	await process_frame
	manager.reset_data()
	print("Item animation: field and inventory play anim_frames, others keep the icon")

# HUD는 2배 스케일 CanvasLayer — 보스 체력바가 실제 화면(1280x720) 가운데 위에 와야 한다
func check_boss_bar_centered() -> void:
	var hud = root.get_node("HUD")
	var r: Rect2 = hud.boss_bar_root.get_global_rect()
	var center: float = (r.position.x + r.size.x * 0.5) * hud.scale.x
	check(is_equal_approx(center, root.get_visible_rect().size.x * 0.5), "Boss health bar should be centered on screen, got x=%s" % center)
	print("Boss bar: centered on the scaled HUD")

# 지름길 문: A는 B를 한 번 쓰기 전엔 잠김. B를 쓰면 A로 이동하며 개방(세이브 기록), 그 뒤로 A→B도 된다.
# 다른 씬의 짝으로 갈 때는 도착 정보를 남기고, 다음 스테이지가 플레이어를 그 문 앞에 소환한다.
func check_shortcut_door(manager) -> void:
	manager.reset_data()
	var door_scene = load("res://Scenes/System/ShortcutDoor.tscn")
	var player = load("res://Scenes/Entitites/Player.tscn").instantiate()
	root.add_child(player)
	player.set_physics_process(false)
	var a = door_scene.instantiate()
	a.link_id = "test_link"
	a.side = 0
	a.position = Vector2(100, 0)
	var b = door_scene.instantiate()
	b.link_id = "test_link"
	b.side = 1
	b.position = Vector2(900, 0)
	root.add_child(a)
	root.add_child(b)
	player.global_position = a.arrival_position()

	a._try_use_door(player)
	await process_frame
	check(not a.is_unlocked() and player.global_position.is_equal_approx(a.arrival_position()), "Shortcut A should stay locked before B is used")

	player.global_position = b.arrival_position()
	b._try_use_door(player)
	await process_frame
	check(a.is_unlocked() and b.is_unlocked() and manager.collected_items.has("shortcut:test_link"), "Using B should unlock the shortcut and save it")
	check(player.global_position.is_equal_approx(a.arrival_position()), "Using B should move the player to A")

	player.set_meta("key_door_teleport_until", 0)
	a._try_use_door(player)
	await process_frame
	check(player.global_position.is_equal_approx(b.arrival_position()), "After unlocking, A should take the player to B")

	var a_again = door_scene.instantiate()
	a_again.link_id = "test_link"
	root.add_child(a_again)
	check(a_again.is_unlocked(), "An unlocked shortcut should stay open when the scene is loaded again")
	# 문 원점 = 바닥 중앙 (기본 그림도, 바꾼 그림도). 플레이어 원점(발끝)이 그 바닥 1px 위에 도착
	check(is_equal_approx(b.arrival_position().y - b.global_position.y, -1.0), "Shortcut arrival should be at the default door art's bottom")
	var art_bottom: float = b.closed_sprite.to_global(Vector2(0, b.closed_sprite.get_rect().end.y)).y
	check(is_equal_approx(art_bottom, b.global_position.y), "Door art should stand on the node origin (bottom center), like in the editor")
	b.closed_texture = ImageTexture.create_from_image(Image.create(16, 40, false, Image.FORMAT_RGBA8))
	b._apply_texture(b.closed_sprite, b.closed_texture)
	check(is_equal_approx(b.arrival_position().y - b.global_position.y, -1.0), "Shortcut arrival should follow a replaced door art's bottom")
	b.partner_scene = "res://Scenes/Stage/Stage_02.tscn"
	check(b._partner_in_other_scene(), "A partner_scene different from the current scene should travel across scenes")
	for n in [a, b, a_again, player]:
		n.queue_free()
	await process_frame

	# 다른 씬에서 온 경우: 스테이지가 도착 문(link_id + side) 앞에 플레이어를 소환하고 도착 정보를 지운다
	var stage = load("res://Scenes/Stage/Stage_02.tscn").instantiate()
	var arrival_door = door_scene.instantiate()
	arrival_door.link_id = "test_cross"
	arrival_door.side = 1
	arrival_door.position = Vector2(777, 333)
	stage.get_node("Entities").add_child(arrival_door)
	manager.pending_shortcut_arrival = {"link_id": "test_cross", "side": 1}
	root.add_child(stage) # 스폰은 스테이지 _ready에서 바로 일어난다 (프레임을 넘기면 중력으로 떨어짐)
	check(stage.player != null and stage.player.global_position.is_equal_approx(arrival_door.arrival_position()),
		"Arriving through a shortcut should spawn the player at the partner door")
	check(manager.pending_shortcut_arrival.is_empty(), "Shortcut arrival info should be cleared after spawning")
	stage.queue_free()
	await process_frame
	manager.reset_data()
	print("Shortcut door: A locked until B used, unlock saved, both ways after, cross-scene arrival")

# 이어 하기 저장: 나갈 때 지금 상태 그대로 + 마지막 안전한 땅 위치. 전투 중이면 위치 없이(세이브 포인트에서).
# 불러오면 그 씬·그 자리에서 시작하고 한 번 쓰면 지운다. 죽어서 부활할 땐 쓰지 않는다.
func check_resume_on_quit(manager, saver) -> void:
	const TEST_SAVE := "user://test_resume_save.json"
	manager.reset_data()
	manager.save_path_override = TEST_SAVE
	var stage = load("res://Scenes/Stage/Stage_03.tscn").instantiate()
	root.add_child(stage)
	current_scene = stage
	for i in 30:
		await physics_frame
	var player = stage.player
	check(player.has_safe_position and player.last_safe_position.is_equal_approx(player.global_position),
		"Standing on normal ground should record a safe position")
	player.hp = 37
	manager.update_hp(37)
	manager.mutation_epoch = 2
	manager.add_defeated_mob("M-resume")
	var safe: Vector2 = player.last_safe_position
	check(manager.save_on_quit(), "Quitting in a stage should save")
	var data: Dictionary = saver.load_game(TEST_SAVE)
	check(saver._is_valid_game(data) and data.get("current_hp") == 37 and data.get("defeated_mobs", []).has("M-resume") and data.get("mutation_epoch") == 2,
		"Quit save should keep HP, kills and mutation epoch as they are (not a rest)")
	check(data.get("resume", {}).get("scene") == stage.scene_file_path, "Quit save should remember the scene")

	# 몹이 쫓는 중이면 위치는 남기지 않는다
	var mob = load("res://Scenes/Entitites/slime_1.tscn").instantiate()
	mob.mutation_enabled = false
	mob.position = player.global_position + Vector2(40, -10)
	stage.get_node("Entities").add_child(mob)
	stage.register_spawned_enemy(mob)
	await process_frame
	mob.target = player
	check(stage.is_player_in_combat() and stage.get_resume_position() == null, "A chasing mob should count as combat")
	manager.save_on_quit()
	check(saver.load_game(TEST_SAVE).get("resume", {}).is_empty(), "Quitting during combat should not keep the position")
	mob.target = null
	mob.queue_free()
	await process_frame
	manager.save_on_quit()

	# 불러오면 그 자리에서 시작, 한 번 쓰면 지운다
	stage.queue_free()
	await process_frame
	manager.reset_data()
	manager.save_path_override = TEST_SAVE
	check(manager.load_game() and manager.get_continue_scene_path() == "res://Scenes/Stage/Stage_03.tscn", "Continue should go to the quit scene")
	stage = load(manager.get_continue_scene_path()).instantiate()
	root.add_child(stage)
	current_scene = stage
	check(stage.player.global_position.is_equal_approx(safe) and stage.player.hp == 37, "Continue should start at the quit position with the same HP")
	check(manager.resume_scene_path.is_empty(), "The resume point should be used only once")
	stage.queue_free()
	await process_frame

	# 죽었거나 메뉴(스테이지 밖)에서는 저장하지 않는다
	manager.reset_data()
	manager.save_path_override = TEST_SAVE
	current_scene = null
	check(not manager.save_on_quit(), "Quitting outside a stage should not save")
	var bad: Dictionary = data.duplicate(true)
	bad["resume"] = {"scene": 3}
	check(not saver._is_valid_game(bad), "Broken resume data should be rejected")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE + ".bak"))
	manager.save_path_override = ""
	manager.reset_data()
	print("Resume: quit saves state as is + safe position, not during combat, used once on continue")

# 문 안내는 플레이어 머리 위가 아니라 HUD 하단 상호작용 안내로 뜬다 (방 위쪽에서도 화면 밖으로 안 나감)
func check_door_prompt_on_hud(manager) -> void:
	manager.reset_data()
	var stage = load("res://Scenes/Stage/Stage_03.tscn").instantiate()
	root.add_child(stage)
	current_scene = stage
	var hud = root.get_node("HUD")
	var shown := []
	var on_show := func(msg): shown.append(msg)
	var on_hide := func(): shown.append("<hidden>")
	manager.interact_msg_requested.connect(on_show)
	manager.interact_msg_hidden.connect(on_hide)
	var door = load("res://Scenes/System/KeyDoor.tscn").instantiate()
	door.locked = false
	door.persist_id = "test_prompt_door"
	stage.get_node("Entities").add_child(door)
	door._on_body_entered(stage.player)
	check(shown == ["KEY_DOOR_OPEN_PROMPT"], "Door prompt should go to the HUD interact prompt, got %s" % str(shown))
	check(hud.interact_label.visible and hud.interact_text.text == "KEY_DOOR_OPEN_PROMPT", "HUD should show the door's prompt text")
	door._on_body_exited(stage.player)
	check(shown.back() == "<hidden>" and not hud.interact_label.visible, "Leaving the door should hide the HUD prompt")
	hud._on_interact_msg("")
	check(hud.interact_text.text == "HUD_INTERACT", "Other interactables should get the default prompt back")
	hud._on_interact_hide()

	# 머리 위 팝업(show_popup)도 카메라 화면 안에 붙는다: 방 맨 위·맨 왼쪽에서 띄워도 화면 밖으로 안 나감
	var player = stage.player
	player.set_physics_process(false)
	await process_frame # 카메라가 방 중앙으로 옮겨진 뒤
	var cam: Camera2D = player.get_viewport().get_camera_2d()
	var half: Vector2 = player.get_viewport_rect().size / cam.zoom * 0.5
	var view := Rect2(cam.get_screen_center_position() - half, half * 2.0)
	player.global_position = view.position + Vector2(2, 10) # 화면 왼쪽 위 구석
	player.show_popup("A long popup message near the corner")
	await process_frame
	var label: Label = player.status_label
	check(view.encloses(label.get_global_rect()), "Popup should stay inside the camera view (%s in %s)" % [label.get_global_rect(), view])
	player.global_position = view.get_center()
	await process_frame
	var r: Rect2 = label.get_global_rect()
	check(is_equal_approx(r.get_center().x, player.global_position.x) and r.end.y < player.global_position.y,
		"Popup should be centered above the player when there is room")
	manager.interact_msg_requested.disconnect(on_show)
	manager.interact_msg_hidden.disconnect(on_hide)
	stage.queue_free()
	await process_frame
	manager.reset_data()
	print("Door prompt: shown on the HUD, hidden on leave, default text restored for others")

# 대사 파일이 없는 상인(Stage2 상인)은 E를 누르면 바로 자기 상점을 연다
func check_merchant_without_dialogue(manager) -> void:
	manager.reset_data()
	# 상호작용 물체는 배치만 해도 플레이어(레이어 2)를 감지해야 한다 (스테이지에서 따로 바꾸지 않아도)
	for scene_path in ["res://Scenes/Entitites/MerchantNPC.tscn", "res://Scenes/System/Chest.tscn", "res://Scenes/System/SavePoint.tscn"]:
		var obj = load(scene_path).instantiate()
		check(obj.get_collision_mask_value(2), "%s should detect the player (collision mask 2) by default" % scene_path)
		obj.free()
	var shop = root.get_node("ShopUI")
	var dialogue = root.get_node("DialogueManager")
	var merchant = load("res://Scenes/Entitites/MerchantNPC.tscn").instantiate()
	merchant.location_name = "Stage2"
	root.add_child(merchant)
	merchant.player_in_range = true
	check(not dialogue.has_dialogue_file("res://resources/Dialogues/en/merchant_Stage2_0.json"), "This check assumes the Stage2 merchant has no dialogue yet")
	merchant._on_interact()
	await process_frame
	check(shop.is_open and shop.current_shop_id == "Stage2", "A merchant without dialogue should open its shop directly")
	check(manager.get_shop_stock("Stage2").any(func(row): return row["item"].id == "lantern"), "Stage2 shop should sell the lantern")
	shop.close_shop()
	merchant.queue_free()
	await process_frame
	manager.reset_data()
	print("Merchant without dialogue: opens its shop directly")

func _end_dialogue_and_wait(dialogue) -> void:
	if dialogue.is_dialogue_active:
		dialogue.end_dialogue()
	await process_frame
	await process_frame

# 잠긴 문: 열쇠 없으면 그 열쇠의 자물쇠 + "맞는 열쇠가 없어" 대사.
# 열쇠 있으면 자물쇠 + "문을 열겠습니까?" → 예를 골라야 "unlock" 재생 후 열림, 아니오면 그대로.
func check_door_lock(manager) -> void:
	manager.reset_data()
	var dialogue = root.get_node("DialogueManager")
	var key = db().get_item_by_id("pink_key")
	var old_frames = key.lock_sprite_frames
	var frames := SpriteFrames.new()
	var tex := ImageTexture.create_from_image(Image.create(8, 8, false, Image.FORMAT_RGBA8))
	frames.add_animation(&"locked")
	frames.add_frame(&"locked", tex)
	frames.add_animation(&"unlock")
	frames.set_animation_loop(&"unlock", false)
	frames.set_animation_speed(&"unlock", 10.0)
	for i in 3:
		frames.add_frame(&"unlock", tex) # 0.3초
	key.lock_sprite_frames = frames

	var player = load("res://Scenes/Entitites/Player.tscn").instantiate()
	root.add_child(player)
	player.set_physics_process(false)
	var door = load("res://Scenes/System/KeyDoor.tscn").instantiate()
	door.persist_id = "test_locked_door"
	root.add_child(door)
	door._on_body_entered(player)

	# 1) 열쇠 없음
	door._try_use_door(player)
	await process_frame
	check(dialogue.is_dialogue_active and door.lock_overlay.is_showing() and door.lock_overlay.sprite.sprite_frames == frames \
		and door.lock_overlay.sprite.animation == &"locked", "No key: the key's lock and the no-key line should show")
	await create_timer(0.3).timeout
	var overlay = door.lock_overlay
	var center: Vector2 = overlay.get_viewport().get_visible_rect().size * 0.5
	check(overlay.layer > 20 and overlay.layer < 1100, "Lock overlay should sit above the HUD and below the dialogue box")
	check(overlay.sprite.position.is_equal_approx(center) and is_equal_approx(overlay.dim.color.a, overlay.dim_alpha),
		"Lock should appear at the screen center with the surroundings dimmed")
	await _end_dialogue_and_wait(dialogue)
	check(not door._opened and not door.lock_overlay.is_showing() and not door._busy, "No key: door stays shut and the lock goes away after the line")

	# 2) 열쇠 있음 → 아니오
	inv().add_item(key)
	door._try_use_door(player)
	await process_frame
	check(dialogue.is_dialogue_active and door.lock_overlay.is_showing() and door.lock_overlay.sprite.animation == &"locked",
		"With key: the lock and the open question should show")
	dialogue._on_choice_selected({"text": "No"})
	await process_frame
	await process_frame
	check(not door._opened and not door.lock_overlay.is_showing() and inv().has_item("pink_key"), "Choosing No should keep the door shut and the key")

	# 3) 열쇠 있음 → 예
	door._try_use_door(player)
	await process_frame
	dialogue._on_choice_selected({"text": "Yes", "event": "door_unlock"})
	await process_frame
	await process_frame
	check(door.lock_overlay.is_showing() and door.lock_overlay.sprite.animation == &"unlock" and not door._opened,
		"Choosing Yes should play the unlock animation before the door opens")
	await create_timer(0.7).timeout
	check(door._opened and not door.lock_overlay.is_showing() and not inv().has_item("pink_key"),
		"After unlocking the door should be open and the single-use key spent")
	await create_timer(0.3).timeout
	check(not door.lock_overlay.visible and is_equal_approx(door.lock_overlay.dim.color.a, 0.0), "Dim and lock should fade out after unlocking")
	await _end_dialogue_and_wait(dialogue) # key_spent 대사

	# 같은 열쇠를 쓰는 다른 문은 같은 자물쇠
	var other = load("res://Scenes/System/KeyDoor.tscn").instantiate()
	other.persist_id = "test_locked_door_2"
	root.add_child(other)
	other._on_body_entered(player)
	other._try_use_door(player)
	await process_frame
	check(other.lock_overlay.sprite.sprite_frames == frames, "Doors using the same key should show the same lock")
	await _end_dialogue_and_wait(dialogue)

	# 질문 대사가 없는 잠긴 문은 묻지 않고 풀린다
	inv().add_item(key)
	var silent = load("res://Scenes/System/KeyDoor.tscn").instantiate()
	silent.persist_id = "test_silent_door"
	silent.dialogue_file = ""
	root.add_child(silent)
	silent._on_body_entered(player)
	silent._try_use_door(player)
	await create_timer(0.6).timeout
	check(silent._opened and not dialogue.is_dialogue_active, "Locked door without dialogue should unlock without asking")

	# 잠기지 않은 문은 자물쇠·질문 없이 바로 열린다
	var plain = load("res://Scenes/System/KeyDoor.tscn").instantiate()
	plain.locked = false
	plain.persist_id = "test_plain_door"
	root.add_child(plain)
	plain._on_body_entered(player)
	await plain._try_use_door(player)
	check(plain._opened and not plain.lock_overlay.is_showing() and not dialogue.is_dialogue_active, "Unlocked door should open right away")

	key.lock_sprite_frames = old_frames
	for node in [door, other, silent, plain, player]:
		node.queue_free()
	await process_frame
	manager.reset_data()
	print("Door lock: no-key lock + line, Yes/No question, unlock animation then open, same key same lock, plain doors open")

# 설정은 SettingsManager가 저장·불러오기 한다 (실제 설정 파일 대신 테스트 경로)
func check_settings_manager() -> void:
	var sm := settings()
	var path := "user://test_settings_manager.json"
	var before := {"locale": sm.locale, "sens": sm.mouse_sensitivity, "shake": sm.screenshake_intensity, "sfx": sm.get_audio_volume(&"SFX")}
	var heard: Array = []
	var on_locale := func(l): heard.append(l)
	sm.locale_changed.connect(on_locale)
	sm.set_locale("ko" if sm.locale != "ko" else "en")
	check(heard.size() == 1, "SettingsManager.set_locale should emit locale_changed")
	sm.locale_changed.disconnect(on_locale)

	sm.mouse_sensitivity = 1.7
	sm.screenshake_intensity = 0.2
	sm.set_audio_volume(&"SFX", 0.4)
	var saved_locale: String = sm.locale
	check(sm.save_settings(path), "settings should save to the test path")
	sm.mouse_sensitivity = 1.0
	sm.screenshake_intensity = 0.5
	sm.set_audio_volume(&"SFX", 1.0)
	sm.set_locale(before.locale)
	sm.load_settings(path)
	check(is_equal_approx(sm.mouse_sensitivity, 1.7), "mouse sensitivity should survive a settings round trip")
	check(is_equal_approx(sm.screenshake_intensity, 0.2), "screen shake should survive a settings round trip")
	check(absf(sm.get_audio_volume(&"SFX") - 0.4) < 0.01, "SFX volume should survive a settings round trip")
	check(sm.locale == saved_locale, "locale should survive a settings round trip")

	# 원래대로 (실제 설정 파일은 쓰지 않음)
	sm.mouse_sensitivity = before.sens
	sm.screenshake_intensity = before.shake
	sm.set_audio_volume(&"SFX", before.sfx)
	sm.set_locale(before.locale)
	for suffix in ["", ".tmp", ".bak"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
