extends SceneTree
# Run with Godot --headless --path . --script res://tests/tutorial_regressions.gd

class TrainingTarget extends CombatBody2D:
	var deaths: int = 0
	func _play_hit_effects() -> void:
		pass
	func _on_death() -> void:
		deaths += 1

var failures: int = 0
var fixture: Node2D

func _initialize() -> void:
	call_deferred("run_checks")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func make_target(health: int = 50) -> TrainingTarget:
	var target := TrainingTarget.new()
	target.hp = health
	target.max_hp = health
	fixture.add_child(target)
	target.add_to_group("enemies")
	return target

func make_projectile(target: Node2D, amount: int, practice: bool) -> Projectile:
	var projectile: Projectile = load("res://Scenes/Projectile/projectilefire.tscn").instantiate()
	projectile.shooter = target
	projectile.damage = amount
	projectile.practice_parry_defeats_shooter = practice
	projectile.is_parryable = true
	fixture.add_child(projectile)
	projectile.set_physics_process(false)
	return projectile

func run_checks() -> void:
	fixture = Node2D.new()
	root.add_child(fixture)
	current_scene = fixture
	check_practice_parry()
	check_parry_trajectory()
	await check_shooter_settings()
	await check_popup_queue()
	await check_player_guard()
	await check_corner_correction()
	await check_save_point_input()
	await check_hitstop_overlap()
	fixture.queue_free()
	await create_timer(0.5, true, false, true).timeout
	print("Tutorial regression checks: ", "PASS" if failures == 0 else "FAIL", " (", failures, " failures)")
	quit(0 if failures == 0 else 1)

func check_practice_parry() -> void:
	for extra in [0, 10]:
		var target := make_target()
		var projectile := make_projectile(target, 0, true)
		check(projectile.attempt_parry(Vector2.LEFT * 10, extra), "Practice parry rejected")
		check(target.hp == 50, "Parry should defeat target on impact, not immediately")
		projectile._on_body_entered(target)
		check(target.hp == 0 and target.deaths == 1, "Practice parry must use normal death handling, including counter bonus")
		check(projectile.is_queued_for_deletion(), "Lethal practice projectile was not consumed")
		target.queue_free()

	var offscreen_target := make_target()
	var offscreen_projectile := make_projectile(offscreen_target, 0, true)
	offscreen_projectile.attempt_parry(Vector2.LEFT * 10)
	offscreen_projectile._on_screen_exited()
	check(offscreen_target.hp == 0 and offscreen_target.deaths == 1, "Offscreen return should complete practice parry")
	offscreen_projectile._on_screen_exited()
	check(offscreen_target.deaths == 1, "Offscreen callback duplicated death")
	offscreen_target.queue_free()

	var target := make_target()
	var harmless := make_projectile(target, 0, true)
	harmless._on_body_entered(target)
	check(target.hp == 50, "Unparried training projectile damaged an enemy")
	check(not harmless.is_queued_for_deletion(), "Same-team projectile consumed")
	harmless.queue_free()
	var ordinary_zero := make_projectile(target, 0, false)
	ordinary_zero.attempt_parry(Vector2.LEFT * 10)
	ordinary_zero._on_body_entered(target)
	check(target.hp == 50, "Ordinary zero-damage parry should not gain a lethal effect")
	ordinary_zero.queue_free()
	var ordinary := make_projectile(target, 20, true)
	ordinary.attempt_parry(Vector2.LEFT * 10, 10, 1.5)
	ordinary._on_body_entered(target)
	check(target.hp == 10 and target.deaths == 0, "Positive damage should retain multiplier and counter bonus")
	var other := make_target()
	var practice := make_projectile(target, 0, true)
	practice.attempt_parry(Vector2.LEFT * 10)
	practice._on_body_entered(other)
	check(other.hp == 50, "Practice parry defeated an unrelated target")
	practice.queue_free()
	target.queue_free()
	other.queue_free()
	print("Practice parry: lethal impact, bonus, offscreen, normal damage and target isolation checked")

func check_parry_trajectory() -> void:
	# Even a fast return must approach the target monotonically at different frame rates.
	for delta in [1.0 / 30.0, 1.0 / 60.0, 1.0 / 120.0, 0.25]:
		var target := make_target(100)
		target.position = Vector2(500, 100)
		var projectile := make_projectile(target, 20, false)
		projectile.position = Vector2(100, 80)
		projectile.velocity = Vector2.LEFT * 1500
		projectile.speed = 1500
		projectile.attempt_parry(Vector2(110, 80))
		var aim := target.global_position + Vector2(0, -10)
		check(projectile.direction.dot((aim - projectile.global_position).normalized()) > 0.999, "Return not immediately aimed at shooter")
		var previous_distance := projectile.global_position.distance_to(aim)
		for frame in range(120):
			projectile._physics_process(delta)
			var distance := projectile.global_position.distance_to(aim)
			check(distance <= previous_distance + 0.001, "Reflected projectile moved away or orbited")
			previous_distance = distance
			if projectile.is_queued_for_deletion():
				break
		check(projectile.is_queued_for_deletion() and target.hp == 70, "Fast return missed, overshot or dealt duplicate damage")
		projectile.queue_free()
		target.queue_free()

	var moving_target := make_target(100)
	moving_target.position = Vector2(300, 100)
	var tracking := make_projectile(moving_target, 20, false)
	tracking.position = Vector2(0, 90)
	tracking.attempt_parry(Vector2.LEFT * 10)
	for frame in range(240):
		moving_target.position.y += 0.5
		tracking._physics_process(1.0 / 60.0)
		if tracking.is_queued_for_deletion():
			break
	check(tracking.is_queued_for_deletion() and moving_target.hp == 70, "Return failed to track moving shooter")
	tracking.queue_free()
	moving_target.queue_free()

	var dead_target := make_target()
	var orphaned := make_projectile(dead_target, 20, false)
	orphaned.attempt_parry(Vector2.LEFT * 10)
	dead_target.hp = 0
	var last_velocity := orphaned.velocity
	orphaned._physics_process(1.0 / 60.0)
	check(not orphaned._is_homing and orphaned.velocity.is_equal_approx(last_velocity), "Return kept chasing dead shooter")
	orphaned.queue_free()
	dead_target.queue_free()

	var fallback := make_projectile(null, 20, false)
	fallback.start_homing = true
	fallback._is_homing = true
	fallback._homing_target = fixture
	fallback.velocity = Vector2.LEFT * 150
	fallback.attempt_parry(fallback.global_position)
	check(not fallback._is_homing and fallback.velocity.x > 0, "Missing shooter left stale homing or stationary return")
	fallback.queue_free()
	print("Parry trajectory: straight return, fast/low-FPS arrival, moving target and missing/dead shooter checked")

func check_shooter_settings() -> void:
	var tutorial = load("res://Scenes/Stage/Stage_tutorial.tscn").instantiate()
	var shooter: ShooterComponent = tutorial.get_node("Entities/Slime3/ShooterComponent")
	check(shooter.practice_parry_defeats_shooter and shooter.projectile_damage == 0, "Tutorial practice shooter is not configured")
	check(not tutorial.get_node("Entities/Slime2/ShooterComponent").practice_parry_defeats_shooter, "Guard shooter unexpectedly has practice parry kill")
	shooter.get_parent().remove_child(shooter)
	shooter.owner = null
	shooter.auto_shoot = false
	fixture.add_child(shooter)
	var target := make_target()
	for directed in [false, true]:
		var projectile = shooter.shoot_dir(target, Vector2.LEFT, Vector2.ZERO) if directed else shooter.shoot(target, target, Vector2.ZERO)
		check(projectile.practice_parry_defeats_shooter and projectile.damage == 0, "Shooter did not pass practice settings")
		await process_frame
		projectile.queue_free()
	target.queue_free()
	shooter.queue_free()
	tutorial.free()

func wait_for_hide(popup: Node) -> void:
	for frame in range(240):
		if not popup._is_closing:
			return
		await process_frame
	check(false, "Popup hide animation did not finish")

func check_popup_queue() -> void:
	var popup = root.get_node("TutorialPopup")
	var manager = root.get_node("GameManager")
	var initial_ui_count: int = manager.active_ui_count
	check(not popup.display(&""), "Empty popup key accepted")
	check(popup.display(&"TUTORIAL_JUMP"), "First popup rejected")
	check(paused and popup.is_active, "Tutorial did not pause")
	popup.display(&"TUTORIAL_ATTACK")
	popup.hide_popup()
	popup.hide_popup() # Repeated close must not consume the next queued entry.
	popup.display(&"TUTORIAL_GUARD", false) # An entry arriving during close must be retained.
	check(paused and popup.is_active and popup._is_closing, "Pause released before hide animation finished")
	await wait_for_hide(popup)
	check(popup._current_text_key == &"TUTORIAL_ATTACK" and paused, "Queued popups not shown in FIFO order")
	manager.set_locale("ko")
	check(popup.label.text == TranslationServer.translate(&"TUTORIAL_ATTACK"), "Active popup language did not refresh")
	popup.hide_popup()
	await wait_for_hide(popup)
	check(popup._current_text_key == &"TUTORIAL_GUARD" and not paused, "Non-pausing queued popup did not release its predecessor's pause")
	popup.hide_popup()
	await wait_for_hide(popup)
	check(not popup.is_active and not popup.visible and not paused, "Popup did not fully close")
	check(manager.active_ui_count == initial_ui_count, "Popup leaked UI ownership")

	paused = true # Simulate a pause owned by another system.
	popup.display(&"TUTORIAL_JUMP")
	popup.hide_popup()
	await wait_for_hide(popup)
	check(paused, "Popup released another system's pause")
	paused = false
	print("Popup lifecycle: FIFO, repeated close, close-time arrivals, mixed pause modes, locale and pause ownership checked")

func check_player_guard() -> void:
	var player = load("res://Scenes/Entitites/Player.tscn").instantiate()
	fixture.add_child(player)
	player.global_position = Vector2(500, 400)
	player.set_physics_process(false)
	player.anim_player.stop()
	player.hp = 100
	player.change_state(player.State.GUARD)
	check(is_zero_approx(player.get_guard_recharge_ratio()), "Guard-active bar should start empty")
	player.change_state(player.State.IDLE)
	check(is_equal_approx(player.guard_cooldown_timer, 1.5), "Guard cooldown not started")
	player.guard_cooldown_timer = 0.75
	check(is_equal_approx(player.get_guard_recharge_ratio(), 0.5), "Cooldown bar did not fill halfway")
	check(player._get_guard_bar_center().y > 0.0, "Guard bar is not below the player")
	player.guard_cooldown_timer = 0.0
	check(is_equal_approx(player.get_guard_recharge_ratio(), 1.0), "Ready guard bar not full")
	var manager = root.get_node("GameManager")
	for locale in ["en", "ko"]:
		manager.set_locale(locale)
		player.update_damage(1)
		check(player.status_label.text == TranslationServer.translate(&"COMBAT_DAMAGE_UP"), "Damage popup not translated")
		player.update_parry_ratio(0.1)
		check(player.status_label.text == TranslationServer.translate(&"COMBAT_PARRY_POWER_UP"), "Parry popup not translated")
		for status in ["save", "heal", "mana", "key", "rest", "full"]:
			player.show_status(status)
			check(not player.status_label.text.begins_with("STATUS_"), "Status translation key exposed")
		for perfect in [false, true]:
			player.reset_combat_state()
			player.is_guarding = true
			player.guard_timer = 0.1 if perfect else 0.3
			player.has_perfect_guard_bonus = false
			var projectile := make_projectile(null, 0, false)
			projectile.velocity = Vector2.LEFT * 150
			player._on_guard_area_entered(projectile)
			var key: StringName = &"COMBAT_PERFECT_GUARD" if perfect else &"COMBAT_GUARD"
			check(projectile.is_queued_for_deletion() and player.hp == 100, "Zero-damage guard regression")
			check(player.status_label.text == TranslationServer.translate(key), "Guard feedback not translated")
			check(player.has_perfect_guard_bonus == perfect, "Perfect guard bonus regression")
	player.queue_free()
	print("Guard: cooldown state, bar placement, zero-damage guard and English/Korean feedback checked")

# 점프 상승 중 머리가 천장 모서리에 살짝 걸리면 옆으로 비켜준다.
# 플레이어 몸 판정: x -6~4, 위끝 y -20.225 (원점 기준)
func check_corner_correction() -> void:
	var player = load("res://Scenes/Entitites/Player.tscn").instantiate()
	fixture.add_child(player)
	player.set_physics_process(false)
	player.anim_player.stop()
	var origin := Vector2(3000, 3000)
	var delta := 1.0 / 60.0
	var head_y := origin.y - 20.225
	# [천장 왼끝 x, 오른끝 x (원점 기준), 머리와의 간격, 상승 속도, 기대 x 이동 최소, 최대]
	var cases := [
		[1.0, 41.0, 4.0, -350.0, -4.0, -3.0, "right corner 3px overlap, 4px gap"],
		[-41.0, -3.0, 4.0, -350.0, 3.0, 4.0, "left corner 3px overlap, 4px gap"],
		[1.0, 41.0, 1.0, -60.0, -4.0, -3.0, "slow rise near apex"],
		[-4.0, 36.0, 4.0, -350.0, 0.0, 0.0, "8px overlap is a real ceiling"],
		[1.0, 41.0, 20.0, -350.0, 0.0, 0.0, "ceiling out of this frame's reach"],
		[1.0, 41.0, 4.0, 100.0, 0.0, 0.0, "falling never corrects"],
	]
	for c in cases:
		var ceiling := StaticBody2D.new()
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(c[1] - c[0], 16)
		shape.shape = rect
		ceiling.add_child(shape)
		fixture.add_child(ceiling)
		ceiling.global_position = Vector2(origin.x + (c[0] + c[1]) / 2.0, head_y - c[2] - 8.0)
		player.global_position = origin
		player.velocity = Vector2(0, c[3])
		await physics_frame
		player._handle_corner_correction(delta)
		var moved: float = player.global_position.x - origin.x
		check(moved >= c[4] - 0.01 and moved <= c[5] + 0.01, "Corner correction (%s): moved %.2fpx" % [c[6], moved])
		if c[5] != 0.0:
			check(not player.test_move(player.global_transform, Vector2(0, c[3] * delta)), "Corner correction (%s): head still blocked" % c[6])
		ceiling.free()
	player.queue_free()
	print("Corner correction: 1~4px overlaps cleared in one frame, real ceilings and falls untouched")

func press_action(node: Node, action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	node._input(event)

func check_save_point_input() -> void:
	await process_frame
	var manager = root.get_node("GameManager")
	var body := make_target(100)
	body.add_to_group("player")
	# SavePoint.gd는 오토로드를 참조하므로 실행 중에 컴파일한다. 실제 저장·씬 재시작 대신 호출 횟수만 센다.
	var probe := GDScript.new()
	probe.source_code = "\n".join([
		'extends "res://Script/System/SavePoint.gd"',
		"var saves: int = 0",
		"var rests: int = 0",
		"func action_save_only() -> void:",
		"\tsaves += 1",
		"func action_rest() -> void:",
		"\trests += 1",
	])
	probe.reload()
	var save_point: Area2D = probe.new()
	var sprite := AnimatedSprite2D.new()
	sprite.name = "AnimatedSprite2D"
	sprite.sprite_frames = SpriteFrames.new()
	save_point.add_child(sprite)
	var sound := AudioStreamPlayer2D.new()
	sound.name = "AudioStreamPlayer2D"
	save_point.add_child(sound)
	fixture.add_child(save_point)
	save_point.player_in_range = true

	press_action(save_point, &"interact")
	press_action(save_point, &"rest")
	check(save_point.saves == 1 and save_point.rests == 1, "Save point ignored input while alive and no menu open")

	var menu := Node.new()
	fixture.add_child(menu)
	manager.ui_opened(menu, false)
	press_action(save_point, &"interact")
	press_action(save_point, &"rest")
	manager.ui_closed(menu)
	menu.queue_free()
	check(save_point.saves == 1 and save_point.rests == 1, "Save point acted while a menu or dialogue was open")

	body.hp = 0
	press_action(save_point, &"interact")
	press_action(save_point, &"rest")
	check(save_point.saves == 1 and save_point.rests == 1, "Save point acted on the death-screen restart input")

	save_point.queue_free()
	body.queue_free()
	print("Save point: input blocked while a menu is open and after player death")

func check_hitstop_overlap() -> void:
	var manager = root.get_node("GameManager")
	# 앞선 검사에서 건 히트스탑이 끝난 뒤 시작한다.
	await create_timer(0.3, true, false, true).timeout
	manager.apply_hitstop(0.25, 0.2)
	await create_timer(0.1, true, false, true).timeout
	manager.apply_hitstop(0.5, 0.2)
	check(is_equal_approx(Engine.time_scale, 0.25), "Weaker overlapping hitstop replaced the stronger time scale")
	await create_timer(0.15, true, false, true).timeout
	check(Engine.time_scale < 1.0, "First hitstop ended the overlapping one early")
	await create_timer(0.2, true, false, true).timeout
	check(is_equal_approx(Engine.time_scale, 1.0), "Time scale not restored after overlapping hitstops")
	Engine.time_scale = 1.0
	print("Hitstop: overlapping calls keep the stronger scale and only the last one restores time")
