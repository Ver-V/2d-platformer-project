extends SceneTree
# Run with Godot --headless --path . --script res://tests/status_effect_regressions.gd
# 상태이상(StatusEffects 컴포넌트, 독, 출혈) 검사. 저장 파일은 건드리지 않는다.

var failures: int = 0
var fixture: Node2D

func _initialize() -> void:
	call_deferred("run_checks")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func run_checks() -> void:
	fixture = Node2D.new()
	root.add_child(fixture)
	check_snake_config()
	await check_poison_ticks_and_expires()
	await check_poison_reapply_refreshes()
	check_bleed_buildup_and_burst()
	await check_bleed_decays_away()
	check_status_damage_ignores_invuln_and_kills()
	check_clear_and_reset()
	await check_inactive_enemy_does_not_tick()
	check_hud_status_tint()
	await check_effects_carry_to_next_scene()
	await check_save_round_trip()
	check_player_status_bars()
	await create_timer(0.5).timeout
	fixture.queue_free()
	await process_frame
	print("Status effect regression checks: ", "PASS" if failures == 0 else "FAIL", " (", failures, " failures)")
	quit(0 if failures == 0 else 1)

func wait_seconds(t: float) -> void:
	await create_timer(t, true, true).timeout

func make_body(hp: int = 100) -> CombatBody2D:
	var b := CombatBody2D.new()
	b.max_hp = hp
	b.hp = hp
	fixture.add_child(b)
	return b

func fast_poison(dmg: int = 5) -> PoisonEffect:
	var p := PoisonEffect.new()
	p.tick_damage = dmg
	p.tick_interval = 0.1
	p.duration = 0.2
	return p

func check_snake_config() -> void:
	var snake = load("res://Scenes/Entitites/esnake.tscn").instantiate()
	check(snake.contact_status is PoisonEffect, "snake contact_status should be a PoisonEffect")
	check(is_equal_approx(snake.contact_status_chance, 0.2), "snake poison chance should be 0.2")
	if snake.contact_status is PoisonEffect:
		check(snake.contact_status.id == &"poison", "snake poison id should be poison")
		check(snake.contact_status.tick_damage == 1, "snake poison tick damage should be 1")
		check(is_equal_approx(snake.contact_status.duration, 20.0), "snake poison should last 20s")
		check(snake.contact_status.screen_tint.a > 0.0, "poison should have a screen tint")
	snake.free()

# 독: 틱마다 피해, 지속시간이 끝나면 해제. 원본(템플릿)은 건드리지 않는다.
func check_poison_ticks_and_expires() -> void:
	var b := make_body(100)
	var template := fast_poison(5)
	var applied := b.apply_status_effect(template)
	check(applied != null and applied != template, "apply should return a copy, not the template")
	check(b.has_status_effect(&"poison"), "poison should be active after apply")
	await wait_seconds(0.4)
	check(b.hp == 90, "poison should tick twice for 5 (hp=%d)" % b.hp)
	check(not b.has_status_effect(&"poison"), "poison should expire after its duration")
	check(template.host == null and template.elapsed == 0.0, "template should stay untouched")
	b.queue_free()

func check_poison_reapply_refreshes() -> void:
	var b := make_body(100)
	var template := fast_poison(1)
	template.duration = 0.3
	b.apply_status_effect(template)
	await wait_seconds(0.2)
	var again := b.apply_status_effect(template)
	check(again == b.get_status_effects().get_effect(&"poison"), "reapply should reuse the active effect")
	check(again.elapsed == 0.0, "reapply should restart the duration")
	check(b.get_status_effects().get_ids().size() == 1, "reapply should not stack another poison")
	b.queue_free()

# 출혈: 게이지가 차기 전엔 피해 없음, 임계치에서 최대 HP 비례 피해 후 게이지 리셋
func check_bleed_buildup_and_burst() -> void:
	var b := make_body(100)
	var bleed := BleedEffect.new() # 35씩, 100에서 터짐, 20% (최소 10)
	bleed.decay_per_sec = 0.0
	b.apply_status_effect(bleed)
	b.apply_status_effect(bleed)
	check(b.hp == 100, "bleed should not damage before reaching the threshold")
	var active: BleedEffect = b.get_status_effects().get_effect(&"bleed")
	check(active != null and is_equal_approx(active.buildup, 70.0), "bleed buildup should stack per hit")
	b.apply_status_effect(bleed)
	check(b.hp == 80, "bleed burst should deal 20%% of max hp (hp=%d)" % b.hp)
	check(not b.has_status_effect(&"bleed"), "bleed should clear after bursting")

	var small := make_body(30)
	var big_hit := BleedEffect.new()
	big_hit.buildup_per_hit = 100.0
	small.apply_status_effect(big_hit)
	check(small.hp == 20, "bleed burst should deal at least burst_min_damage (hp=%d)" % small.hp)
	b.queue_free()
	small.queue_free()

func check_bleed_decays_away() -> void:
	var b := make_body(100)
	var bleed := BleedEffect.new()
	bleed.buildup_per_hit = 10.0
	bleed.decay_per_sec = 100.0
	b.apply_status_effect(bleed)
	check(b.has_status_effect(&"bleed"), "bleed should be active after a hit")
	await wait_seconds(0.3)
	check(not b.has_status_effect(&"bleed"), "bleed should end when its buildup decays to 0")
	check(b.hp == 100, "decayed bleed should not deal damage")
	b.queue_free()

func check_status_damage_ignores_invuln_and_kills() -> void:
	var b := make_body(10)
	b.start_invuln(5.0)
	check(b.apply_status_damage(4), "status damage should apply during invulnerability")
	check(b.hp == 6, "status damage should lower hp")
	b.apply_status_damage(100)
	check(b.hp == 0, "status damage should clamp hp at 0")
	check(not b.apply_status_damage(1), "status damage should not apply to a dead body")
	check(b.apply_status_effect(fast_poison()) == null, "dead bodies should not receive effects")
	b.queue_free()

# 세이브 포인트 휴식은 clear_status_effects(), 사망·적 리셋은 reset_combat_state()로 해제된다
func check_clear_and_reset() -> void:
	var b := make_body(100)
	b.apply_status_effect(fast_poison())
	b.apply_status_effect(BleedEffect.new())
	check(b.get_status_effects().get_ids().size() == 2, "poison and bleed should coexist")
	b.clear_status_effects()
	check(b.get_status_effects().get_ids().is_empty(), "clear_status_effects should remove all effects")
	b.apply_status_effect(fast_poison())
	b.reset_combat_state()
	check(not b.has_status_effect(&"poison"), "reset_combat_state should clear effects")
	check(b.hp == 100, "clearing should not deal damage")
	b.queue_free()

	var src := FileAccess.get_file_as_string("res://Script/System/SavePoint.gd")
	var rest_body := src.substr(src.find("func action_rest"))
	check(rest_body.find("clear_status_effects") != -1, "save point rest should clear status effects")

func check_inactive_enemy_does_not_tick() -> void:
	var snake = load("res://Scenes/Entitites/esnake.tscn").instantiate()
	fixture.add_child(snake)
	snake.set_active(false)
	var hp0: int = snake.hp
	snake.apply_status_effect(fast_poison(5))
	await wait_seconds(0.4)
	check(snake.hp == hp0, "inactive enemy should not take poison ticks")
	snake.set_active(true)
	await wait_seconds(0.4)
	check(snake.hp == hp0 - 10, "active enemy should take poison ticks (hp=%d)" % snake.hp)
	snake.queue_free()

# 독이 걸려 있는 동안 HUD 화면 점멸이 켜지고, 해제되면 꺼진다
func check_hud_status_tint() -> void:
	var hud = root.get_node("HUD")
	hud.clear_status_tints()
	check(not hud.status_tint_rect.visible, "status tint should start hidden")
	hud.add_status_tint(&"poison", Color(0.55, 0.1, 0.8))
	check(hud.status_tint_rect.visible, "status tint should show while poisoned")
	hud.add_status_tint(&"other", Color.GREEN)
	hud.remove_status_tint(&"other")
	check(hud.status_tint_rect.visible, "removing one tint should keep the remaining one")
	hud.remove_status_tint(&"poison")
	check(not hud.status_tint_rect.visible, "status tint should hide when no effect remains")

func spawn_player():
	var player = load("res://Scenes/Entitites/Player.tscn").instantiate()
	fixture.add_child(player)
	player.global_position = Vector2(500, 400)
	player.set_physics_process(false)
	return player

# 씬 이동(플레이어 노드 교체) 때 상태이상이 남은 시간 그대로 넘어가고, 휴식·불러오기 땐 넘어가지 않는다
func check_effects_carry_to_next_scene() -> void:
	var hud = root.get_node("HUD")
	var gm = root.get_node("GameManager") # 테스트 스크립트에선 autoload 이름을 바로 쓸 수 없다
	gm.carried_status_effects.clear()
	var p1 = spawn_player()
	var poison := PoisonEffect.new() # 실제 값: 1 x 20초
	p1.apply_status_effect(poison)
	await wait_seconds(0.3)
	var elapsed_before: float = p1.get_status_effects().get_effect(&"poison").elapsed
	p1.queue_free()
	await process_frame
	check(gm.carried_status_effects.size() == 1, "leaving the scene should hand the poison to GameManager")

	var p2 = spawn_player()
	var carried: StatusEffect = p2.get_status_effects().get_effect(&"poison")
	check(carried != null, "next scene's player should inherit the poison")
	check(carried != null and carried.host == p2, "inherited poison should target the new player")
	check(carried != null and carried.elapsed >= elapsed_before, "inherited poison should keep its elapsed time")
	check(gm.carried_status_effects.is_empty(), "carry slot should be emptied after handing over")
	check(hud.status_tint_rect.visible, "inherited poison should turn the screen tint back on")

	# 휴식처럼 해제한 뒤 떠나면 넘어가지 않는다
	p2.clear_status_effects()
	p2.queue_free()
	await process_frame
	check(gm.carried_status_effects.is_empty(), "cleared effects should not carry over")
	check(not hud.status_tint_rect.visible, "screen tint should be off after leaving")

	# 메뉴로 나가 불러오기·새 게임을 하면 들고 있던 효과는 버린다
	gm.carried_status_effects.append(PoisonEffect.new())
	gm.load_data_from_save({})
	check(gm.carried_status_effects.is_empty(), "loading a save should drop carried effects")

# 세이브: 걸려 있던 상태이상이 진행 상태 그대로 저장·복원되고, 잘못된 데이터는 거른다 (파일은 쓰지 않음)
func check_save_round_trip() -> void:
	var gm = root.get_node("GameManager")
	var sm = root.get_node("SaveManager")
	gm.carried_status_effects.clear()
	var p = spawn_player()
	p.apply_status_effect(PoisonEffect.new())
	var bleed := BleedEffect.new()
	bleed.decay_per_sec = 0.0
	p.apply_status_effect(bleed)
	p.get_status_effects().get_effect(&"poison").elapsed = 7.5

	var data: Dictionary = gm.get_data_for_save()
	check(data.has("status_effects") and data.status_effects.size() == 2, "save should include the player's status effects")
	var json_data = JSON.parse_string(JSON.stringify(data)) # 실제 저장처럼 JSON을 거친다
	check(sm._is_valid_game(json_data), "save with status effects should pass validation")

	gm.load_data_from_save(json_data)
	var restored := {}
	for e in gm.carried_status_effects:
		restored[e.id] = e
	check(restored.has(&"poison") and restored.has(&"bleed"), "loading should restore poison and bleed")
	if restored.has(&"poison"):
		var poison: PoisonEffect = restored[&"poison"]
		check(is_equal_approx(poison.elapsed, 7.5), "poison elapsed time should survive the save")
		check(poison.tick_damage == 1 and is_equal_approx(poison.duration, 20.0), "poison settings should survive the save")
		check(poison.screen_tint.is_equal_approx(Color(0.55, 0.1, 0.8)), "poison screen tint should survive the save")
	if restored.has(&"bleed"):
		check(is_equal_approx(restored[&"bleed"].buildup, 35.0), "bleed buildup should survive the save")
	p.clear_status_effects()
	p.queue_free()
	await process_frame
	gm.carried_status_effects.clear()

	# 다음 플레이어가 불러온 효과를 이어받는다
	gm.load_data_from_save(json_data)
	var p2 = spawn_player()
	check(p2.has_status_effect(&"poison") and p2.has_status_effect(&"bleed"), "player should start with the loaded effects")
	p2.clear_status_effects()
	p2.queue_free()
	await process_frame

	# 상태이상 폴더 밖 스크립트, 이상한 값은 거부
	var bad: Dictionary = json_data.duplicate(true)
	bad.status_effects = [{"script": "res://Script/base/GameManager.gd", "props": {}, "state": {}}]
	check(not sm._is_valid_game(bad), "status effect scripts outside the status folder should be rejected")
	bad.status_effects = [{"script": "res://Script/base/status/poison_effect.gd", "props": {"tick_damage": {"x": 1}}, "state": {}}]
	check(not sm._is_valid_game(bad), "non-primitive status effect values should be rejected")
	check(StatusEffect.from_save({"script": "res://Script/base/status/status_effects.gd"}) == null, "non-StatusEffect scripts should not load")
	var old_save: Dictionary = json_data.duplicate(true)
	old_save.erase("status_effects")
	check(sm._is_valid_game(old_save), "saves without status_effects should stay valid")
	gm.load_data_from_save(old_save)
	check(gm.carried_status_effects.is_empty(), "old saves should load with no status effects")

	# 사망 후 부활은 세이브를 불러오지만 상태이상은 풀린다 (실제 호출은 세이브를 읽고 씬을 바꾸므로 소스로 확인)
	var gm_src := FileAccess.get_file_as_string("res://Script/base/GameManager.gd")
	var respawn_src := gm_src.substr(gm_src.find("func respawn_player"))
	respawn_src = respawn_src.substr(0, respawn_src.find("
func ", 1))
	var load_at := respawn_src.find("load_game()")
	var clear_at := respawn_src.find("carried_status_effects.clear()")
	check(load_at != -1 and clear_at > load_at, "respawn should clear status effects after loading the save")

# 상태이상마다 몸 왼쪽에 세로 게이지가 하나씩 생기고, 남은 양(get_progress)이 줄어든다
func check_player_status_bars() -> void:
	var gm = root.get_node("GameManager")
	gm.carried_status_effects.clear()
	var p = spawn_player()
	check(p.get_status_bar_rects().is_empty(), "no status bars without effects")
	var poison: StatusEffect = p.apply_status_effect(PoisonEffect.new())
	var rects: Array[Rect2] = p.get_status_bar_rects()
	check(rects.size() == 1, "one status bar per effect")
	var body_left: float = p.collision_stand.position.x + p.collision_stand.shape.get_rect().position.x
	check(rects.size() == 1 and rects[0].end.x <= body_left, "status bar should sit left of the body")
	check(rects.size() == 1 and rects[0].size.y > rects[0].size.x, "status bar should be vertical")
	check(is_equal_approx(poison.get_progress(), 1.0), "fresh poison bar should be full")
	poison.elapsed = 15.0
	check(is_equal_approx(poison.get_progress(), 0.25), "poison bar should show remaining time")
	check(poison.is_bar_warning() == false, "poison at 25%% left should not blink yet")
	poison.elapsed = 15.5
	check(poison.is_bar_warning(), "poison below 25%% left should blink")
	var bleed: BleedEffect = p.apply_status_effect(BleedEffect.new())
	bleed.buildup = 69.0
	check(not bleed.is_bar_warning(), "bleed below 70%% should not blink")
	bleed.buildup = 70.0
	check(bleed.is_bar_warning(), "bleed at 70%% or more should blink")
	rects = p.get_status_bar_rects()
	check(rects.size() == 2 and rects[1].end.x <= rects[0].position.x, "second bar should line up further left")
	p.clear_status_effects()
	check(p.get_status_bar_rects().is_empty(), "bars should disappear when effects clear")
	p.queue_free()
