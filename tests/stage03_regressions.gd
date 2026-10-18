extends SceneTree
# Run with Godot --headless --path . --script res://tests/stage03_regressions.gd
# 스테이지 3 기믹: 양털 트램펄린(떨어진 높이만큼 1:1 튕김(최소 점프 한 번, 최대 마지막 땅 + 점프 + 더블 점프)·공중 점프 충전·물속 제외), 양털 벽(랜턴으로만 태움, 저장),
# 졸음 상태이상(게이지·잠듦·조작 막힘·Zzz 말풍선·세이브), 양 잡몹(박치기/울음 선택, 울음 범위 안에서만 졸음),
# 새끼양 찾기(아이템·양치기 대사 블록·반환·보상·저장). 저장 파일은 건드리지 않는다.

var failures: int = 0
var fixture: Node2D

# 오토로드 (테스트 스크립트에선 오토로드 이름을 바로 못 쓴다)
func gm() -> Node: return root.get_node("GameManager")
func inv() -> Node: return root.get_node("Inventory")
func db() -> Node: return root.get_node("Database")

func _initialize() -> void:
	call_deferred("run_checks")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func run_checks() -> void:
	fixture = Node2D.new()
	root.add_child(fixture)
	current_scene = fixture
	check_bounce_speed()
	await check_bounce()
	await check_water_exit_double_jump()
	await check_wool_wall()
	await check_drowsy()
	await check_sheep()
	await check_lost_lambs()
	await check_first_time_tutorials()
	fixture.queue_free()
	await process_frame
	print("Stage03 regression checks: ", "PASS" if failures == 0 else "FAIL", " (", failures, " failures)")
	quit(0 if failures == 0 else 1)

const BOUNCE_SCENE := "res://Scenes/System/WoolBounce.tscn"
const WALL_SCENE := "res://Scenes/System/WoolWall.tscn"

func check_bounce_speed() -> void:
	var pad: WoolBounce = load(BOUNCE_SCENE).instantiate()
	pad.width_tiles = 3
	fixture.add_child(pad)
	var cs := pad.get_node("CollisionShape2D") as CollisionShape2D
	check(cs.shape.get_rect().size == Vector2(48, 16) and cs.position == Vector2(0, -8), "Trampoline collision should follow width_tiles, one tile tall above the origin")
	pad.free()
	# 플레이어와 같은 방식으로 적분했을 때 정확히 height만큼 솟는다 (첫 프레임은 중력 없이, 그다음은 중력을 먼저 빼고 이동)
	var g := 980.0
	for dt in [1.0 / 60.0, 1.0 / 144.0]:
		for h in [16.0, 62.5, 125.0]:
			var v: float = WoolBounce.launch_speed(g, h, dt)
			var rise: float = v * dt
			while true:
				v -= g * dt
				if v <= 0.0:
					break
				rise += v * dt
			check(absf(rise - h) <= 1.5, "launch_speed should rise %.1fpx at dt %.4f (rose %.2f)" % [h, dt, rise])

func make_player(pos: Vector2) -> Node:
	var player = load("res://Scenes/Entitites/Player.tscn").instantiate()
	fixture.add_child(player)
	player.global_position = pos
	player._menu_exit_cooldown = 0.0
	return player

# 떨어뜨려서 트램펄린에 닿은 뒤 위로 솟기 시작하는 프레임까지 기다린다. 솟기 시작하면 true
func drop_until_bounce(player) -> bool:
	for i in 120:
		await physics_frame
		if player.velocity.y < -1.0:
			return true
	return false

# 튕겨 오른 뒤 최고점의 y
func rise_peak(player) -> float:
	var peak: float = player.global_position.y
	for i in 120:
		await physics_frame
		peak = minf(peak, player.global_position.y)
		if player.velocity.y >= 0.0:
			break
	return peak

# drop만큼 위에서 떨어뜨려 트램펄린에 튕긴 뒤 솟은 높이(트램펄린 윗면 기준). ground_y가 있으면 마지막 땅을 그 높이로 둔다.
# 떨어지는 중에 점프 키를 눌러 내려앉을 때까지 누르고 있다가, 튕겨 오르기 시작하면 뗀다 (점프 컷이 없어야 한다)
func bounce_case(pad: WoolBounce, drop: float, ground_y: float = INF) -> float:
	var top := pad.global_position.y - WoolBounce.TILE
	var player = make_player(Vector2(pad.global_position.x, top - drop))
	for i in 3:
		await physics_frame
	# 새로 만든 플레이어는 첫 프레임에 바닥 판정이 남아 코요테 시간·공중 점프가 생긴다 (그때 누르면 점프가 나간다)
	player._coyote_timer = 0.0
	player._air_jump_available = false
	if is_finite(ground_y):
		player._ground_y = ground_y
	Input.action_press("jump")
	var bounced: bool = await drop_until_bounce(player)
	var rose := -1.0
	check(bounced, "Landing on a trampoline should bounce the player up (drop %d)" % drop)
	if bounced:
		check(player._air_jump_available and player._coyote_timer <= 0.0 and player._jump_buffer_timer <= 0.0,
			"A bounce should refill the air jump and leave no coyote/buffered ground jump")
		check(player.current_state == player.State.JUMP, "A bounce should put the player in the jump state")
		await physics_frame
		Input.action_release("jump")
		rose = top - await rise_peak(player)
	Input.action_release("jump")
	player.queue_free()
	for i in 3: # 뗀 입력이 다음 플레이어로 넘어가지 않게
		await physics_frame
	return rose

func check_bounce() -> void:
	gm().double_jump_unlocked = true
	var pad: WoolBounce = load(BOUNCE_SCENE).instantiate()
	fixture.add_child(pad)
	pad.global_position = Vector2(8000, 3000)
	var top := pad.global_position.y - WoolBounce.TILE
	var probe = make_player(Vector2(-9000, 0))
	await physics_frame
	await physics_frame
	var g: float = probe.get_gravity().y
	var jump_speed: float = absf(probe.jumpforce)
	probe.queue_free()
	var dt := 1.0 / Engine.physics_ticks_per_second
	var jump_h := WoolBounce.rise_height(g, jump_speed, dt, true)
	var ceiling := jump_h + WoolBounce.rise_height(g, jump_speed, dt, false)
	check(jump_h > 50.0 and ceiling > jump_h * 1.8, "Jump heights look wrong (jump %.1f, jump + air jump %.1f)" % [jump_h, ceiling])

	# 점프 한 번보다 높이 떨어지면 그 높이로 1:1 (마지막 땅 = 떨어진 곳이라 상한에 안 걸린다)
	for drop in [jump_h + 15.0, ceiling - 10.0]:
		var rose := await bounce_case(pad, drop)
		check(absf(rose - drop) <= 2.0, "A bounce should return to the drop height %.1f (rose %.1f)" % [drop, rose])
	# 점프 한 번보다 낮게 떨어지면 점프 한 번만큼
	var low := await bounce_case(pad, 20.0)
	check(absf(low - jump_h) <= 2.0, "A short drop should bounce one jump high %.1f (rose %.1f)" % [jump_h, low])
	# 튕김 → 더블 점프로 마지막 땅보다 높이 올라갔다 떨어져도 땅 + 점프 + 더블 점프 높이까지만
	var capped := await bounce_case(pad, ceiling + 60.0, top)
	check(absf(capped - ceiling) <= 2.0, "A bounce should not go above the last ground's jump + air jump height %.1f (rose %.1f)" % [ceiling, capped])

	# 위에 서 있기만 해도 점프 한 번만큼 튕긴다
	var player = make_player(Vector2(pad.global_position.x, top - 1.0))
	var stand_peak := top
	for i in 90:
		await physics_frame
		stand_peak = minf(stand_peak, player.global_position.y)
	check(absf((top - stand_peak) - jump_h) <= 2.0, "Standing on a trampoline should bounce one jump high (rose %.1f)" % (top - stand_peak))
	player.queue_free()
	for i in 3:
		await physics_frame

	# 튕겨 오르는 중에 한 번 더 누르면 더블 점프 (한 번뿐)
	player = make_player(Vector2(pad.global_position.x, top - 40.0))
	await drop_until_bounce(player)
	await physics_frame
	await process_frame
	Input.action_press("jump")
	player._process_movement(1.0 / 60.0)
	Input.action_release("jump")
	check(not player._air_jump_available and player.velocity.y < player.jumpforce * 0.9, "After a bounce one air jump should remain")
	player.queue_free()
	await process_frame

	# 물속에선 튕기지 않는다
	player = make_player(Vector2(pad.global_position.x, top - 40.0))
	player.velocity = Vector2(0, 100)
	player.set_physics_process(false)
	for i in 120:
		player.velocity.y = 100
		player.move_and_slide()
		if player.is_on_floor() and player._floor_bouncer() == pad:
			break
	player._air_peak_y = top - 40.0
	player.in_water = true
	check(player.is_on_floor() and player._floor_bouncer() == pad and not player._try_bounce() and player.velocity.y >= 0.0,
		"The trampoline should not bounce in water")
	player.in_water = false

	gm().double_jump_unlocked = false
	player.queue_free()
	pad.queue_free()
	await process_frame
	print("Trampoline: returns to the drop height 1:1 (no jump cut), at least one jump, capped at last ground + jump + air jump, refills one air jump, none in water")

# 물속에선 더블 점프 대신 헤엄치고, 물 밖으로 솟아오른 뒤에는 공중에서 더블 점프를 쓸 수 있다
func check_water_exit_double_jump() -> void:
	gm().double_jump_unlocked = true
	var player = make_player(Vector2(-8000, 3000))
	player.set_physics_process(false)
	player.in_water = true
	player.velocity = Vector2(0, 30)
	player._air_jump_available = true
	Input.action_press("jump")
	player._process_movement(1.0 / 60.0)
	Input.action_release("jump")
	check(player._air_jump_available, "Double jump should not be spent in water")
	await process_frame
	await process_frame
	player.in_water = false # 수면을 벗어남 (바닥·코요테 없음)
	player._coyote_timer = 0.0
	player.velocity = Vector2(0, -60)
	Input.action_press("jump")
	player._process_movement(1.0 / 60.0)
	Input.action_release("jump")
	check(not player._air_jump_available and player.velocity.y < player.jumpforce * 0.9, "Double jump should work right after leaving the water")
	gm().double_jump_unlocked = false
	player.queue_free()
	await process_frame
	print("Water: no double jump while swimming, available after leaving the surface")

func check_wool_wall() -> void:
	var probe = load(WALL_SCENE).instantiate()
	check(PersistIdAssigner.prefix_for(probe) == "F", "Wool walls should get F- persist ids")
	probe.free()

	var wall = load(WALL_SCENE).instantiate()
	wall.persist_id = "F-wooltest"
	wall.width_tiles = 2
	wall.height_tiles = 4
	fixture.add_child(wall)
	var body_cs := wall.get_node("Body/CollisionShape2D") as CollisionShape2D
	var range_cs := wall.get_node("CollisionShape2D") as CollisionShape2D
	check(body_cs.shape.get_rect().size == Vector2(32, 64) and body_cs.position == Vector2(0, -32), "Wool wall body should follow its tile size above the origin")
	check(range_cs.shape.get_rect().size.x > 32.0, "Interact range should reach past the wall's sides")

	# 칼로는 안 베인다
	var hit := HitData.new()
	hit.amount = 10
	check(HitData.deliver(wall, hit) == HitData.Result.GUARDED and not wall.burning, "Sword hits should not cut the wool wall")

	# 랜턴 없이 E: 안 탄다
	wall._on_interact()
	check(not wall.burning, "Wool wall should not burn without the lantern equipped")

	# 랜턴을 장착하고 E: 타기 시작하고 저장 기록이 남는다. 다 타면 사라진다
	inv().add_item(db().get_item_by_id("lantern"))
	wall._on_interact()
	check(wall.burning and gm().collected_items.has("wool:F-wooltest"), "Wool wall should burn with the lantern and record it for saving")
	check(not wall._can_interact() and HitData.deliver(wall, hit) == HitData.Result.IGNORED, "A burning wall should ignore interact and hits")
	wall._process(wall.burn_time + 0.1)
	check(wall.is_queued_for_deletion(), "Wool wall should disappear once burnt")
	await process_frame

	# 저장된 기록이 있으면 다시 들어왔을 때 없다
	var again = load(WALL_SCENE).instantiate()
	again.persist_id = "F-wooltest"
	fixture.add_child(again)
	check(again.is_queued_for_deletion(), "A saved burnt wall should not come back")
	await process_frame

	gm().collected_items.erase("wool:F-wooltest")
	inv().reset()
	print("Wool wall: sword can't cut, burns only with the lantern, saved as wool:<id>")

func make_floor(pos: Vector2, width: float = 400.0) -> StaticBody2D:
	var floor_body := StaticBody2D.new()
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(width, 16)
	shape.shape = rect
	floor_body.add_child(shape)
	fixture.add_child(floor_body)
	floor_body.global_position = pos
	return floor_body

const DROWSY := "res://resources/status_effects/drowsy.tres"

func check_drowsy() -> void:
	var template = load(DROWSY)
	check(template is DrowsyEffect and template.id == &"drowsy" and is_equal_approx(template.buildup_per_sec, 20.0)
		and is_equal_approx(template.threshold, 100.0) and is_equal_approx(template.sleep_time, 5.0), "Drowsy: 20/s, sleeps at 100 for 5s")

	var floor_body := make_floor(Vector2(12000, 3008))
	var player = make_player(Vector2(12000, 2990))
	for i in 10:
		await physics_frame
	var effect := player.apply_status_effect(template) as DrowsyEffect
	check(effect != null and effect != template, "Drowsy should be applied as a per-target copy")
	for i in 4:
		effect.expose(1.0)
	check(is_equal_approx(effect.buildup, 80.0) and not effect.is_asleep() and not player.is_asleep(), "4s of bleating should fill 80 without sleeping")
	check(is_equal_approx(effect.get_progress(), 0.8) and effect.is_bar_warning(), "Drowsy bar should show the buildup and warn near the top")
	effect.expose(1.0)
	check(effect.is_asleep() and player.is_asleep() and not effect.is_bar_warning(), "Reaching 100 should put the player to sleep")
	effect.expose(1.0)
	check(is_equal_approx(effect.sleep_left, effect.sleep_time), "Bleating should not add to the sleep while asleep")

	# 자는 동안 조작이 안 먹는다
	player._menu_exit_cooldown = 0.0
	Input.action_press("jump")
	Input.action_press("attack")
	var moved_up := false
	for i in 10:
		await physics_frame
		moved_up = moved_up or player.velocity.y < -1.0
	Input.action_release("jump")
	Input.action_release("attack")
	check(not moved_up and player.current_state != player.State.ATTACK and player.current_state != player.State.CHARGE, "A sleeping player should ignore jump and attack")
	await process_frame
	check(player.visuals.is_sleep_bubble_visible(), "A Zzz bubble should show above a sleeping player")
	await create_timer(0.8).timeout
	check(player.visuals.get_sleep_pose() >= 1.0 and absf(absf(player.sprite.rotation) - PI * 0.5) < 0.01, "A sleeping player should lie down (rotate 90 degrees)")

	# 세이브: 잠든 상태·남은 시간 그대로
	var restored := StatusEffect.from_save(effect.to_save()) as DrowsyEffect
	check(restored != null and restored.is_asleep() and absf(restored.sleep_left - effect.sleep_left) < 0.001 and is_equal_approx(restored.buildup, effect.buildup),
		"Drowsy should survive a save round trip")

	# 5초 뒤 깨어나 사라진다
	effect.advance(effect.sleep_time + 0.1)
	check(not effect.is_asleep() and effect.buildup <= 0.0 and not player.is_asleep(), "The player should wake up after the sleep time")
	await physics_frame
	await physics_frame
	await process_frame
	check(not player.get_status_effects().has(&"drowsy") and not player.visuals.is_sleep_bubble_visible(), "Waking up should remove drowsy and the bubble")
	await create_timer(0.3).timeout
	check(player.visuals.get_sleep_pose() <= 0.0 and is_zero_approx(player.sprite.rotation), "A player who woke up should stand back up")

	# 자는 중에 맞으면 깬다. 상태이상 피해(독 틱 등)로는 깨지 않는다
	var e3 := player.apply_status_effect(template) as DrowsyEffect
	e3.expose(5.0)
	check(player.is_asleep(), "Drowsy should put the player to sleep again")
	player.apply_status_damage(1)
	check(player.is_asleep(), "Status damage should not wake the player")
	player.reset_combat_state() # i-frames 없이 맞게
	player.get_status_effects().apply(template).expose(5.0)
	var hit := HitData.new(5, Vector2(100, -50), null)
	var result: int = HitData.deliver(player, hit)
	check(HitData.landed(result) and not player.is_asleep(), "Getting hit should wake the player (result %d)" % result)
	player.get_status_effects().clear_all()

	# 울음을 안 들으면 decay_delay 뒤부터 줄어든다
	var e2 := player.apply_status_effect(template) as DrowsyEffect
	e2.expose(1.0)
	e2.advance(0.5)
	check(is_equal_approx(e2.buildup, 20.0), "Drowsy should not decay right after hearing a bleat")
	e2.advance(1.0)
	check(e2.buildup < 20.0, "Drowsy should decay once the bleating stops")
	player.get_status_effects().clear_all()

	player.queue_free()
	floor_body.queue_free()
	await process_frame
	print("Drowsy: 20/s buildup, sleeps 5s at 100 with input locked, a Zzz bubble and lying down, a hit wakes (status damage does not), decays when quiet, saved")

const SHEEP_SCENE := "res://Scenes/Entitites/sheep.tscn"

func check_sheep() -> void:
	var floor_body := make_floor(Vector2(16000, 3008), 800.0)
	var sheep = load(SHEEP_SCENE).instantiate()
	sheep.mutation_enabled = false
	sheep.bleat_time = 30.0
	fixture.add_child(sheep)
	sheep.global_position = Vector2(16000, 2990)
	sheep.set_active(true)
	var bleat_cs := sheep.get_node("BleatArea/CollisionShape2D") as CollisionShape2D
	check(sheep.bleat_area.collision_mask == 2 and bleat_cs.shape is CircleShape2D, "Sheep should have a BleatArea that senses the player")
	check(is_equal_approx(sheep.charge_chance, 0.75), "Sheep should charge 75% of the time")

	sheep._decide(0.5)
	check(sheep.mode == sheep.Mode.CHARGE and not sheep.wants_hold_position(), "A roll under 75% should charge")
	sheep._end_mode()
	sheep._decide(0.9)
	check(sheep.is_bleating() and sheep.wants_hold_position(), "A roll over 75% should bleat in place")
	sheep.play_move_animation(true)
	check(sheep.sprite.animation == &"bleat", "A bleating sheep should play its bleat animation")

	# 범위 안의 플레이어만 졸음이 찬다 (1초 ≈ 20)
	var radius: float = bleat_cs.shape.radius
	var near = make_player(sheep.global_position + Vector2(radius * 0.5, 0))
	var far = make_player(sheep.global_position + Vector2(radius + 60.0, 0))
	for i in 5:
		await physics_frame
	near.get_status_effects().clear_all()
	far.get_status_effects().clear_all()
	for i in Engine.physics_ticks_per_second:
		await physics_frame
	var nd := near.get_status_effects().get_effect(&"drowsy") as DrowsyEffect
	check(nd != null and nd.buildup > 14.0 and nd.buildup < 26.0, "A player in the bleat range should gain about 20 drowsy per second (got %s)" % (nd.buildup if nd else -1.0))
	check(not far.get_status_effects().has(&"drowsy"), "A player outside the bleat range should not get drowsy")

	# 방이 비활성화되면 울음을 멈춘다
	sheep.set_active(false)
	check(sheep.mode == sheep.Mode.NONE, "An inactive sheep should stop bleating")

	for n in [near, far, sheep, floor_body]:
		n.queue_free()
	await process_frame
	print("Sheep: 75% charge / 25% bleat, bleat range applies drowsy only inside, stops when inactive")

const SHEPHERD_SCENE := "res://Scenes/Entitites/ShepherdNPC.tscn"

func lamb_count() -> int:
	var n := 0
	for item in inv().inventory:
		if item != null and item.id == "lost_lamb":
			n += 1
	return n

func check_lost_lambs() -> void:
	var lamb = db().get_item_by_id("lost_lamb")
	check(lamb != null and lamb.type == 0 and lamb.icon != null, "Lost lamb should be a plain item with an icon")
	var field = load("res://Scenes/Item/LostLamb.tscn").instantiate()
	check(field.item_resource != null and field.item_resource.id == "lost_lamb", "LostLamb.tscn should be a field item carrying the lamb")
	field.free()
	for lang in ["en", "ko"]:
		var path := "res://resources/Dialogues/%s/shepherd.json" % lang
		var data = JSON.parse_string(FileAccess.get_file_as_string(path))
		check(data is Dictionary and ["intro", "waiting", "thanks", "thanks_all", "done"].all(func(b): return data.has(b) and data[b] is Array and not data[b].is_empty()),
			"%s should have every shepherd block" % path)

	var g := gm()
	var gold_before: int = g.gold
	inv().reset()
	g.npc_talk_counts.erase("shepherd")
	g.quest_progress.clear()
	var npc = load(SHEPHERD_SCENE).instantiate()
	fixture.add_child(npc)
	check(npc.total_lambs == 4 and npc.rewards.size() == 4, "The shepherd should want 4 lambs with a reward for each")

	check(npc.pick_block() == "intro", "First talk should be the intro")
	g.npc_talk_counts["shepherd"] = 1
	check(npc.pick_block() == "waiting", "Without lambs the shepherd should wait")

	inv().add_item(lamb)
	inv().add_item(lamb)
	check(npc.pick_block() == "thanks", "Bringing lambs should thank")
	check(npc.take_lambs() == 2 and lamb_count() == 0 and g.get_quest_progress("lost_lambs") == 2, "The shepherd should take every carried lamb")
	check(g.gold == gold_before + 100, "Lambs 1 and 2 should give 50 gold each (gold %d)" % (g.gold - gold_before))

	inv().add_item(lamb)
	npc.take_lambs()
	check(inv().has_item("health_potion") and g.get_quest_progress("lost_lambs") == 3, "Lamb 3 should give a health potion")

	inv().add_item(lamb)
	check(npc.pick_block() == "thanks_all", "Bringing the last lamb should use the final thanks")
	npc.take_lambs()
	check(g.get_quest_progress("lost_lambs") == 4 and g.gold == gold_before + 300 and npc.pick_block() == "done", "Lamb 4 should give 200 gold and finish the quest")
	check(inv().has_item("old_ornate_key"), "Lamb 4 should also give the ornate key to the wolf's den")
	inv().add_item(lamb)
	check(npc.take_lambs() == 0 and lamb_count() == 1, "Extra lambs past the total should not be taken")

	# 저장: quest_progress
	var saver = root.get_node("SaveManager")
	var data: Dictionary = g.get_data_for_save()
	check(data.get("quest_progress", {}).get("lost_lambs") == 4 and saver._is_valid_game(data), "Quest progress should be saved and valid")
	var bad := data.duplicate(true)
	bad["quest_progress"] = {"lost_lambs": -1}
	check(not saver._is_valid_game(bad), "Negative quest progress should be rejected")
	bad["quest_progress"] = {"lost_lambs": "4"}
	check(not saver._is_valid_game(bad), "Non-number quest progress should be rejected")
	var parsed = JSON.parse_string(JSON.stringify(data)) # 실제 세이브처럼 숫자가 float로 돌아온다
	g.quest_progress.clear()
	g.load_data_from_save(parsed)
	check(g.get_quest_progress("lost_lambs") == 4, "Quest progress should load back")

	npc.free()
	# 숨겨진 문: 양치기의 열쇠로 한 번 연다
	var door = load("res://Scenes/System/WolfDenDoor.tscn").instantiate()
	var key = db().get_item_by_id(door.item_key)
	check(door.item_key == "old_ornate_key" and key != null and key.key_uses == 1, "The wolf den door should open with the shepherd's key (one use)")
	for lang in ["en", "ko"]:
		var path: String = door.dialogue_file.replace("/en/", "/%s/" % lang)
		var dd = JSON.parse_string(FileAccess.get_file_as_string(path))
		check(dd is Dictionary and ["without_item", "ask_open", "key_spent"].all(func(b): return dd.has(b)), "%s should have the door blocks" % path)
		var ask: Array = dd.get("ask_open", [{}])[0].get("choices", [])
		check(ask.any(func(c): return c.get("event", "") == door.unlock_event), "%s ask_open should have the unlock choice" % path)
	door.free()
	g.quest_progress.clear()
	g.npc_talk_counts.erase("shepherd")
	g.gold = gold_before
	inv().reset()
	print("Lost lambs: item + field scene, shepherd blocks intro/waiting/thanks/thanks_all/done, takes all, per-lamb rewards (4th = den key), saved; den door uses that key")

# --- 처음 한 번 도움말 (TutorialPopup.show_once) ---
# 실제 스테이지(BaseStage)에서만 뜨므로 _ready 등을 비운 가짜 스테이지를 current_scene으로 쓴다
func make_fake_stage() -> Node2D:
	var script := GDScript.new()
	script.source_code = "extends BaseStage
func _ready() -> void:
	pass
func _process(_d: float) -> void:
	pass
func _physics_process(_d: float) -> void:
	pass
"
	script.reload()
	var stage := Node2D.new()
	for pair in [["SpawnPoint", Marker2D.new()], ["Camera2D", Camera2D.new()]]:
		pair[1].name = pair[0]
		stage.add_child(pair[1])
	stage.set_script(script)
	return stage

func close_popup() -> void:
	var popup = root.get_node("TutorialPopup")
	popup.hide_popup()
	while popup.is_active:
		await process_frame
	paused = false

func check_first_time_tutorials() -> void:
	var popup = root.get_node("TutorialPopup")
	while popup.is_active:
		await close_popup()
	gm().seen_tutorials.clear()
	check(not popup.show_once(&"TUTORIAL_TORCH") and not gm().has_seen_tutorial("TUTORIAL_TORCH"), "Tutorials should not show outside a real stage")

	var stage := make_fake_stage()
	root.add_child(stage)
	current_scene = stage
	check(popup.show_once(&"TUTORIAL_TORCH", false) and gm().has_seen_tutorial("TUTORIAL_TORCH"), "A first-time tutorial should show in a stage and be recorded")
	await close_popup()
	check(not popup.show_once(&"TUTORIAL_TORCH", false), "The same tutorial should not show twice")

	# 상태이상에 처음 걸리면 (플레이어)
	var player = load("res://Scenes/Entitites/Player.tscn").instantiate()
	player.position = Vector2(20000, 0)
	stage.add_child(player)
	player.set_physics_process(false)
	await process_frame
	player.apply_status_effect(load("res://resources/status_effects/snake_poison.tres"))
	check(gm().has_seen_tutorial("TUTORIAL_STATUS_POISON") and popup.is_active, "First poison should show the poison tutorial")
	await close_popup()
	player.clear_status_effects()
	player.apply_status_effect(load("res://resources/status_effects/flask_poison.tres"))
	check(not popup.is_active, "Poison from another source should not repeat the tutorial")
	await close_popup()
	for path in ["res://resources/status_effects/breath.tres", "res://resources/status_effects/drowsy.tres", "res://resources/status_effects/bleed_basic.tres", "res://resources/status_effects/flask_acid.tres"]:
		var key: StringName = load(path).tutorial_key
		check(key != &"" and TranslationServer.translate(key) != String(key), "%s should have a translated tutorial (%s)" % [path, key])

	# 블록을 처음 부수거나 쓸 때
	var block: CrumblingBlock = load("res://Scenes/System/CrumblingBlock.tscn").instantiate()
	stage.add_child(block)
	var stub := CharacterBody2D.new()
	stub.add_to_group("player")
	stage.add_child(stub)
	block._try_step_on(stub)
	check(gm().has_seen_tutorial("TUTORIAL_CRUMBLING_BLOCK"), "Stepping on a crumbling block first should show its tutorial")
	await close_popup()
	var wall = load(WALL_SCENE).instantiate()
	wall.persist_id = "F-tuttest"
	stage.add_child(wall)
	wall.ignite()
	check(gm().has_seen_tutorial("TUTORIAL_WOOL_WALL"), "Burning wool first should show its tutorial")
	await close_popup()
	for key in ["TUTORIAL_CRUMBLING_BLOCK", "TUTORIAL_CRACKED_WALL", "TUTORIAL_WOOL_WALL", "TUTORIAL_WOOL_BOUNCE", "TUTORIAL_TORCH"]:
		check(TranslationServer.translate(key) != key, "%s should be translated" % key)

	# 장비를 처음 얻으면 (가방으로 가든 바로 장착되든). 일반 아이템은 안 뜬다
	inv().reset()
	inv().add_item(db().get_item_by_id("lost_lamb"))
	check(not popup.is_active and not gm().has_seen_tutorial("TUTORIAL_EQUIPMENT"), "A normal item should not show the equipment tutorial")
	inv().add_item(db().get_item_by_id("lantern"))
	check(gm().has_seen_tutorial("TUTORIAL_EQUIPMENT") and popup.is_active and TranslationServer.translate(&"TUTORIAL_EQUIPMENT") != "TUTORIAL_EQUIPMENT",
		"Getting equipment for the first time should show the equipment tutorial")
	await close_popup()
	inv().add_item(db().get_item_by_id("lantern"))
	check(not popup.is_active, "The equipment tutorial should show only once")
	inv().reset()

	# 아이템 종류마다 처음 얻을 때 한 번 (열쇠·회복 물약·스탯 물약·플라스크 강화). 퀘스트 물건 같은 일반 아이템은 없다
	var inv_script = load("res://Script/base/Inventory.gd")
	for pair in [["lantern", "TUTORIAL_EQUIPMENT"], ["red_lighted_silver_key", "TUTORIAL_KEY"], ["flask_shard", "TUTORIAL_FLASK_UPGRADE"],
			["health_flask_essence", "TUTORIAL_FLASK_UPGRADE"], ["Attack_increase_potion", "TUTORIAL_STAT_POTION"], ["health_potion", "TUTORIAL_HEALING_POTION"],
			["health_flask", ""], ["lost_lamb", ""]]:
		var item = db().get_item_by_id(pair[0])
		check(item != null and inv_script.item_tutorial_key(item) == StringName(pair[1]), "%s should show tutorial '%s'" % pair)
	gm().seen_tutorials.erase("TUTORIAL_HEALING_POTION")
	inv().add_item(db().get_item_by_id("health_potion"))
	check(gm().has_seen_tutorial("TUTORIAL_HEALING_POTION") and popup.is_active, "The first healing potion should show its tutorial")
	await close_popup()
	inv().reset()

	# 처음 겪는 일마다: 죽고 부활, 다른 방으로, 변이체, 빠른 낙하, 가시, 세이브 포인트, 지름길, 달의 문
	gm().respawned_from_death = true
	stage._show_entry_tutorials()
	check(gm().has_seen_tutorial("TUTORIAL_DEATH") and not gm().respawned_from_death, "Getting back up after death should explain death once")
	await close_popup()
	stage.snap_to_room(Vector2i(1, 0), true)
	check(not gm().has_seen_tutorial("TUTORIAL_MINIMAP"), "The first room of a stage should not show the minimap tutorial")
	stage.snap_to_room(Vector2i(0, 0), false)
	check(gm().has_seen_tutorial("TUTORIAL_MINIMAP"), "Moving to another room should explain the minimap")
	await close_popup()
	var mutant = load("res://Scenes/Entitites/slime_1.tscn").instantiate()
	stage.add_child(mutant)
	mutant.global_position = Vector2(100, 100)
	mutant.home_position = mutant.global_position
	await process_frame
	stage._cached_enemies = [mutant]
	mutant.mutation = MobMutation.Kind.NONE
	stage.apply_room_rules(Vector2i(0, 0))
	check(not gm().has_seen_tutorial("TUTORIAL_MUTATION"), "Normal enemies should not show the mutation tutorial")
	mutant.mutation = MobMutation.Kind.TOUGH
	stage.apply_room_rules(Vector2i(0, 0))
	check(gm().has_seen_tutorial("TUTORIAL_MUTATION"), "Entering a room with a mutant should explain mutants")
	await close_popup()
	mutant.queue_free()
	stage._cached_enemies = []
	player.velocity.y = player.max_fall_speed
	player._update_fast_fall_hint(0.3, true)
	check(not gm().has_seen_tutorial("TUTORIAL_FAST_FALL"), "A short fall should not show the fast fall tutorial")
	player._update_fast_fall_hint(0.4, true)
	check(gm().has_seen_tutorial("TUTORIAL_FAST_FALL"), "A long fall at top speed should suggest fast falling")
	await close_popup()
	player.has_safe_position = true
	player.last_safe_position = player.global_position
	await player.respawn_from_hazard()
	check(gm().has_seen_tutorial("TUTORIAL_SPIKES"), "Being sent back by spikes should explain spikes")
	await close_popup()
	var save_point = load("res://Scenes/System/SavePoint.tscn").instantiate()
	stage.add_child(save_point)
	save_point._on_player_entered(player)
	check(gm().has_seen_tutorial("TUTORIAL_SAVE_POINT"), "Walking up to a save point should explain save and rest")
	await close_popup()
	save_point.queue_free()
	var door = load("res://Scenes/System/ShortcutDoor.tscn").instantiate()
	door.side = 1 # B: 처음 쓰는 쪽은 아직 아무것도 안 뜬다
	stage.add_child(door)
	door.place_player(player)
	await process_frame
	check(not gm().has_seen_tutorial("TUTORIAL_SHORTCUT"), "Arriving at side B should not show the shortcut tutorial")
	door.side = 0
	door.place_player(player)
	await process_frame
	check(gm().has_seen_tutorial("TUTORIAL_SHORTCUT"), "Arriving at side A through a new shortcut should explain it")
	await close_popup()
	door.queue_free()
	var gate = load("res://Scenes/System/MoonGate.tscn").instantiate()
	stage.add_child(gate)
	gate.global_position = player.global_position + Vector2(400, 0)
	await physics_frame
	await physics_frame
	check(not gm().has_seen_tutorial("TUTORIAL_MOON_GATE"), "A far moon gate should not show its tutorial")
	gate.global_position = player.global_position + Vector2(40, 0)
	await physics_frame
	await physics_frame
	check(gm().has_seen_tutorial("TUTORIAL_MOON_GATE") and not gate.is_physics_processing(), "Walking up to a moon gate should explain it once")
	await close_popup()
	gate.queue_free()
	player.queue_free()
	var old_locale := TranslationServer.get_locale()
	for locale in ["en", "ko"]:
		TranslationServer.set_locale(locale)
		for key in ["TUTORIAL_DEATH", "TUTORIAL_SAVE_POINT", "TUTORIAL_MUTATION", "TUTORIAL_DARKNESS", "TUTORIAL_SPIKES", "TUTORIAL_MINIMAP",
				"TUTORIAL_FAST_FALL", "TUTORIAL_HEALING_POTION", "TUTORIAL_KEY", "TUTORIAL_STAT_POTION", "TUTORIAL_FLASK_UPGRADE", "TUTORIAL_SHORTCUT", "TUTORIAL_MOON_GATE"]:
			check(TranslationServer.translate(key) != key, "%s should be translated (%s)" % [key, locale])
	TranslationServer.set_locale(old_locale)

	# 저장: 본 도움말 목록
	var saver = root.get_node("SaveManager")
	var data: Dictionary = gm().get_data_for_save()
	check(data.get("seen_tutorials", []).has("TUTORIAL_WOOL_WALL") and saver._is_valid_game(data), "Seen tutorials should be saved")
	var bad := data.duplicate(true)
	bad["seen_tutorials"] = [3]
	check(not saver._is_valid_game(bad), "Non-text seen tutorials should be rejected")

	gm().collected_items.erase("wool:F-tuttest")
	gm().seen_tutorials.clear()
	current_scene = fixture
	stage.queue_free()
	await process_frame
	paused = false
	print("Tutorials: first-time only, real stages only, status effects / crumbling block / wool wall / first equipment hooks, saved")
