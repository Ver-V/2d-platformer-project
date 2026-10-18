extends SceneTree
# Run with Godot --headless --path . --script res://tests/boss2_regressions.gd
# 2탄 보스(웨어랫 + 과학자 쥐): 씬 구성, 플라스크(종류·직격·스플래시·3번째마다 패링·반사), 산성·독 규칙,
# 할퀴기 판정, 충격파, 페이즈 2 붉은 기, 실제 전투가 오류 없이 도는지. 저장 파일은 건드리지 않는다.

var failures: int = 0
var fixture: Node2D

const BOSS := "res://Scenes/Entitites/boss_stage_2.tscn"
const PLAYER := "res://Scenes/Entitites/Player.tscn"
const FLASK := "res://Scenes/Projectile/projectile_flask.tscn"
const FLOOR_Y := 0.0

func _initialize() -> void:
	call_deferred("run_checks")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func gm() -> Node: return root.get_node("GameManager")

func run_checks() -> void:
	gm().reset_data()
	fixture = Node2D.new()
	root.add_child(fixture)
	current_scene = fixture # 투사체·충격파는 current_scene에 붙는다
	make_arena()
	await check_scene_setup()
	await check_flask_rules()
	await check_flask_ready_sound()
	await check_status_rules()
	await check_strike_and_shockwave()
	await check_phase_2_tint()
	await check_fight_runs()
	await check_reward_not_regranted()
	current_scene = null
	fixture.queue_free()
	await process_frame
	gm().reset_data()
	print("Boss2 regression checks: ", "PASS" if failures == 0 else "FAIL", " (", failures, " failures)")
	quit(0 if failures == 0 else 1)

# 바닥(위끝 y=0, x -400~400)과 양쪽 벽
func make_arena() -> void:
	for r in [Rect2(-400, 0, 800, 32), Rect2(-432, -300, 32, 332), Rect2(400, -300, 32, 332)]:
		var body := StaticBody2D.new()
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = r.size
		shape.shape = rect
		body.add_child(shape)
		fixture.add_child(body)
		body.global_position = r.get_center()

func spawn_boss(x: float = 0.0) -> Node:
	var boss = load(BOSS).instantiate()
	fixture.add_child(boss)
	boss.global_position = Vector2(x, FLOOR_Y - boss._feet_offset() - 1.0)
	return boss

func spawn_player(pos: Vector2) -> Node:
	var p = load(PLAYER).instantiate()
	fixture.add_child(p)
	p.global_position = pos
	return p

func physics_frames(n: int) -> void:
	for i in n:
		await physics_frame

func fresh(p) -> void:
	p.reset_combat_state()
	p.clear_status_effects()
	p.hp = 100

# --- 씬 구성 ---
func check_scene_setup() -> void:
	var boss = spawn_boss()
	await process_frame
	check(boss.get_script().resource_path == "res://Script/Entity/boss2.gd", "Stage 2 boss should run boss2.gd")
	check(is_equal_approx(boss.phase2_hp_ratio, 0.4), "Phase 2 should start below 40% HP")
	check(boss.shooter != null and boss.shooter.projectile_scene != null and boss.shooter.projectile_scene.resource_path == FLASK
		and boss.shooter.parry_interval == 3, "The scientist should throw flasks, every third one parryable")
	for n in [boss.facing, boss.melee_range, boss.dash_range, boss.attack1_box, boss.attack2_box, boss.eye_glint, boss.throw_point]:
		check(n != null, "Boss scene is missing a range/hitbox/marker node")
	check(boss.sprite.material is ShaderMaterial and boss.sprite.material.shader.resource_path.ends_with("boss_rage.gdshader"),
		"Boss sprite should use the rage shader")
	check(not boss.mutation_enabled, "Boss should never mutate")
	boss.queue_free()
	await process_frame

# --- 플라스크 ---

# 대기 중 플라스크: 예고음(flask_ready.wav)이 나고 flask_ready_delay(0.5초) 뒤에 던진다
func _flask_count() -> int:
	var n := 0
	for node in root.find_children("*", "", true, false):
		var sc = node.get_script()
		if sc != null and sc.resource_path.ends_with("flask_projectile.gd"):
			n += 1
	return n

func check_flask_ready_sound() -> void:
	var boss = spawn_boss()
	var p = spawn_player(Vector2(150, FLOOR_Y - 20))
	p.set_physics_process(false)
	await process_frame
	check(boss.action_sfx != null and boss.flask_ready_sound != null and boss.flask_ready_sound.resource_path.ends_with("flask_ready.wav"),
		"Boss should have the flask-ready sound and a player for it")
	check(is_equal_approx(boss.flask_ready_delay, 0.5), "Flask should be thrown 0.5s after the ready sound")
	boss.target = p
	boss.idle_time = 1.0 # 한 개, step 0.5 → 바로 예고음
	var before := _flask_count()
	boss._idle_phase()
	await process_frame
	check(boss.action_sfx.playing and boss.action_sfx.stream == boss.flask_ready_sound and _flask_count() == before,
		"The ready sound should play first, before any flask is thrown")
	await create_timer(0.3).timeout
	check(_flask_count() == before, "No flask should be thrown before the 0.5s delay")
	await create_timer(0.35).timeout
	check(_flask_count() == before + 1, "The flask should be thrown 0.5s after the ready sound")
	for n in root.find_children("*", "", true, false):
		var sc = n.get_script()
		if sc != null and sc.resource_path.ends_with("flask_projectile.gd"):
			n.queue_free()
	boss.queue_free()
	p.queue_free()
	await process_frame

func make_flask(kind: int):
	var f = load(FLASK).instantiate()
	f.kind = kind
	fixture.add_child(f)
	f.global_position = Vector2(0, -300)
	return f

func check_flask_rules() -> void:
	var player = spawn_player(Vector2(100, FLOOR_Y - 1))
	var boss = spawn_boss(-200)
	await physics_frames(3)
	boss.target = player
	boss.shooter.reset_count()
	var flasks: Array = []
	for i in 3:
		flasks.append(boss.shooter.shoot_dir(boss, Vector2.RIGHT, boss.throw_point.global_position))
	await process_frame
	check(flasks.all(func(f): return f != null and "throw_gravity" in f), "Shooter should spawn flasks")
	check(not flasks[0].is_parryable and not flasks[1].is_parryable and flasks[2].is_parryable, "Only every third flask should be parryable")
	for f in flasks:
		f.queue_free()

	# 종류별 직격·스플래시 수치
	var bleed = make_flask(0) # FlaskProjectile.Kind: BLEED, POISON, FIRE, ACID
	var poison = make_flask(1)
	var fire = make_flask(2)
	var acid = make_flask(3)
	await process_frame
	check(bleed._direct_damage() == 20 and bleed._splash_damage() == 10, "Flask direct 20 / splash 10")
	# 그림: 종류마다 자기 색 애니메이션 (빨강 출혈, 보라 독, 주황 화염, 청록 산성)
	for pair in [[bleed, &"bleed"], [poison, &"poison"], [fire, &"fire"], [acid, &"acid"]]:
		var spr: AnimatedSprite2D = pair[0].get_node("AnimatedSprite2D")
		check(pair[0]._has_art() and spr.visible and spr.animation == pair[1] and spr.is_playing()
			and spr.sprite_frames.get_frame_count(pair[1]) == 8, "Flask kind should play its own 8-frame animation (%s)" % pair[1])
	var thrown = make_flask(0)
	thrown.kind = 3 # 트리에 넣은 뒤에 종류를 바꿔도 그림이 따라간다 (보스가 던질 때 순서)
	check(thrown.get_node("AnimatedSprite2D").animation == &"acid", "Changing the kind after spawning should switch the animation")
	thrown.velocity = Vector2(100, 0)
	thrown._physics_process(0.1)
	check(not is_zero_approx(thrown.rotation), "A thrown flask should spin")
	thrown.queue_free()
	check(fire._direct_damage() == 30 and fire._splash_damage() == 15, "Fire flask direct 30 / splash 15")
	check(is_equal_approx(bleed._direct_status().buildup_per_hit, 80.0) and is_equal_approx(bleed._splash_status().buildup_per_hit, 50.0),
		"Bleed flask builds 80 on a direct hit, 50 on a splash")
	check(poison._direct_status().id == &"poison" and is_equal_approx(poison._splash_status().duration, 5.0), "Poison flask splash poisons for 5s")
	check(fire._direct_status() == null and fire._splash_status() == null, "Fire flask has no status effect")
	check(acid._direct_status().id == &"acid" and acid._splash_status().id == &"acid" and acid._direct_status().attack_modifier == -5
		and is_equal_approx(acid._direct_status().duration, 10.0), "Acid flask lowers attack by 5 for 10s (direct and splash)")

	# 직격: 피해 + 직격 상태이상
	fresh(player)
	poison.hit_target(player)
	check(player.hp == 80 and player.get_status_effects().has(&"poison"), "A direct poison flask should deal 20 and poison")
	check(_splash_effects() > 0, "A direct hit should still burst with the splash particles")
	# 직격은 앞쪽 가드로 막힌다: 깎인 피해만, 상태이상 없음, 깨지는 파티클은 나온다
	fresh(player)
	await physics_frames(2)
	for n in _splash_effect_nodes():
		n.free()
	var guarded = make_flask(1)
	guarded.velocity = Vector2(150, 60) # 왼쪽에서 날아온다
	player.attack_pivot.scale.x = -1 # 왼쪽을 본다
	player.guard.is_guarding = true
	player.guard.guard_timer = 0.3 # 퍼펙트 가드 시간 밖
	guarded.hit_target(player)
	check(player.hp == 100 - player.guard.chip_damage(20) and player.get_status_effects().has(&"poison"),
		"Guarding a direct flask from the front should take chip damage and still the status")
	check(guarded.is_queued_for_deletion() and _splash_effects() > 0, "A guarded flask should break with the splash particles")
	# 퍼펙트 가드: 피해 0, 상태이상 없음, 플라스크는 깨진다
	fresh(player)
	await physics_frames(2)
	var perfect = make_flask(0)
	perfect.velocity = Vector2(150, 60)
	player.guard.is_guarding = true
	player.guard.guard_timer = 0.0
	perfect.hit_target(player)
	var half_bleed = player.get_status_effects().get_effect(&"bleed")
	check(player.hp == 100 and half_bleed != null and is_equal_approx(half_bleed.buildup, 40.0) and perfect.is_queued_for_deletion(),
		"A perfect-guarded flask should deal no damage, half the bleed buildup (80 -> 40), and break")
	player.guard.is_guarding = false
	# 스플래시: 3타일 안이면 10 + 스플래시 상태이상, 밖이면 없음
	fresh(player)
	await physics_frames(2)
	bleed.apply_splash_at(player.global_position + Vector2(40, -10))
	var b = player.get_status_effects().get_effect(&"bleed")
	check(player.hp == 90 and b != null and is_equal_approx(b.buildup, 50.0), "A bleed splash within 3 tiles should deal 10 and build 50")
	fresh(player)
	await physics_frames(2)
	fire.apply_splash_at(player.global_position + Vector2(80, -10))
	check(player.hp == 100, "A splash farther than 3 tiles should not hit")
	fresh(player)
	await physics_frames(2)
	fire.apply_splash_at(player.global_position + Vector2(0, -10))
	check(player.hp == 85, "A fire splash should deal 15")

	# 패링해서 되돌리면 보스가 직격 피해 × 패링 배율(기본 1.5 → 30)과 상태이상을 받는다 (플라스크만의 추가 배율은 없다)
	boss._active = true
	var hp0: int = boss.hp
	acid.shooter = boss
	acid.is_parryable = true
	acid.attempt_parry(acid.global_position + Vector2(10, 0))
	acid.hit_target(boss)
	check(boss.hp == hp0 - 30 and boss.get_status_effects().has(&"acid"), "A reflected flask should deal 20 x 1.5 = 30 to the boss and apply its effect (dealt %d)" % (hp0 - boss.hp))
	# 보스의 출혈은 최대 HP의 10%로 터진다 (플레이어·잡몹은 20%)
	boss.apply_status_effect(load("res://resources/status_effects/flask_bleed.tres"))
	var boss_bleed = boss.get_status_effects().get_effect(&"bleed")
	check(boss_bleed != null and boss_bleed.get_burst_damage() == int(ceil(boss.max_hp * 0.1)), "Bleed should burst for 10% of a boss's max HP")
	player.apply_status_effect(load("res://resources/status_effects/flask_bleed.tres"))
	check(player.get_status_effects().get_effect(&"bleed").get_burst_damage() == int(ceil(player.max_hp * 0.2)), "Bleed should still burst for 20% on the player")
	for n in [bleed, poison, fire, player, boss]:
		if is_instance_valid(n):
			n.queue_free()
	await process_frame

func _splash_effect_nodes() -> Array:
	return fixture.get_children().filter(func(n): return n is CPUParticles2D)

func _splash_effects() -> int:
	return _splash_effect_nodes().size()

# --- 산성·독 ---
func check_status_rules() -> void:
	var player = spawn_player(Vector2(100, FLOOR_Y - 1))
	await process_frame
	player.apply_status_effect(load("res://resources/status_effects/flask_acid.tres"))
	check(player.get_status_effects().get_attack_modifier() == -5, "Acid should lower the player's attack by 5")
	player.clear_status_effects()
	player.apply_status_effect(load("res://resources/status_effects/flask_poison.tres"))
	var poison = player.get_status_effects().get_effect(&"poison")
	poison.elapsed = 4.0
	player.apply_status_effect(load("res://resources/status_effects/flask_poison_splash.tres"))
	check(is_equal_approx(poison.duration - poison.elapsed, 16.0), "A short splash poison should not shorten a longer poison")
	player.clear_status_effects()
	player.apply_status_effect(load("res://resources/status_effects/flask_poison_splash.tres"))
	player.apply_status_effect(load("res://resources/status_effects/flask_poison.tres"))
	poison = player.get_status_effects().get_effect(&"poison")
	check(is_equal_approx(poison.duration - poison.elapsed, 20.0), "A direct poison should extend a short splash poison to 20s")
	player.clear_status_effects()
	player.queue_free()
	await process_frame

# --- 할퀴기·충격파 ---
func check_strike_and_shockwave() -> void:
	var boss = spawn_boss(0)
	var player = spawn_player(Vector2(40, FLOOR_Y - 1))
	await physics_frames(3)
	boss.target = player
	boss._face_dir = 1
	boss._update_facing()
	await physics_frames(2)
	fresh(player)
	check(boss.strike(boss.attack1_box, 20) == 1 and player.hp == 80, "Claw should hit a player in front for 20")
	boss._lock_face = true # 패턴 중처럼 방향 고정
	boss._face_dir = -1
	boss._update_facing()
	await physics_frames(2)
	fresh(player)
	check(boss.strike(boss.attack1_box, 20) == 0 and player.hp == 100, "Claw should not hit behind the boss (Facing flips)")
	check(boss.facing.scale.x == -1 and boss.sprite.flip_h, "Facing and sprite should flip together")
	# 충격파: 4타일 높이, 바닥을 따라 퍼져 맞힌다
	player.global_position = Vector2(boss.global_position.x + 90, FLOOR_Y - 1)
	fresh(player)
	var wave = boss.spawn_shockwave(1)
	check(is_equal_approx(wave.height, 64.0), "Shockwave should be 4 tiles tall")
	await physics_frames(30)
	check(player.hp == 80, "Shockwave should hit a grounded player for 20")
	for n in [boss, player]:
		n.queue_free()
	await process_frame

# --- 페이즈 2 ---
func check_phase_2_tint() -> void:
	var boss = spawn_boss(0)
	await process_frame
	boss._active = true
	boss.hp = int(boss.max_hp * 0.39)
	boss._check_phase()
	check(boss.phase == 2, "Boss should enter phase 2 below 40% HP")
	await create_timer(0.8).timeout
	check(boss.sprite.material.get_shader_parameter(&"rage_amount") > 0.3, "Phase 2 should tint the boss red")
	check(is_equal_approx(boss._rush_speed(), boss.rush_speed * 1.25), "Phase 2 rush should be 25% faster")
	boss.queue_free()
	await process_frame

# --- 실제 전투가 돈다 ---
func check_fight_runs() -> void:
	var boss = spawn_boss(-150)
	var player = spawn_player(Vector2(200, FLOOR_Y - 1))
	await physics_frames(3)
	player.start_invuln(60.0)
	boss.target = player
	boss.set_active(true) # 대사 없음 → 바로 전투
	var start_y: float = boss.global_position.y
	var flask_seen := false
	var moved := false
	var start_x: float = boss.global_position.x
	for i in 50:
		await create_timer(0.1).timeout
		if fixture.get_children().any(func(n): return "throw_gravity" in n):
			flask_seen = true
		if absf(boss.global_position.x - start_x) > 8.0:
			moved = true
	check(boss._loop_running, "Boss pattern loop should be running")
	check(flask_seen, "The scientist should throw flasks while idle")
	check(moved, "Boss should move (walk, dash, jump or rush) within 5 seconds")
	check(boss.global_position.y < FLOOR_Y + 1.0 and boss.global_position.y > start_y - 200.0, "Boss should stay on the arena floor")
	boss.hp = 0
	boss.current_state = boss.State.DEAD
	for n in [boss, player]:
		n.queue_free()
	for n in fixture.get_children():
		if "throw_gravity" in n or "max_distance" in n:
			n.queue_free()
	await process_frame

# 처치한 보스의 보상은 한 번만: 마시거나 판 뒤 씬을 다시 열어도 되살아나지 않는다 (예전엔 스테이지를 열 때마다 약을 또 줬다).
# 보상 기록이 없는 옛 세이브는 한 번 채워 주고 기록을 남긴다. 죽은 채로는 플라스크·포션을 마실 수 없다
func check_reward_not_regranted() -> void:
	var inv = root.get_node("Inventory")
	var scene: PackedScene = load("res://Scenes/Entitites/boss_stage_2.tscn")
	var probe = scene.instantiate()
	var boss_id: String = str(probe.get_persist_id())
	var key: String = "boss_reward:" + boss_id
	var drug_id: String = probe.reward_item.id
	probe.free()
	gm().reset_data()
	gm().defeated_bosses[boss_id] = true
	gm().add_collected_item(key) # 받아서 이미 마셨다
	var boss = scene.instantiate()
	fixture.add_child(boss)
	await process_frame
	check(not inv.has_item(drug_id), "A reward already received should not come back when the stage loads again")
	gm().collected_items.erase(key) # 옛 세이브: 받은 기록이 없다
	boss = scene.instantiate()
	fixture.add_child(boss)
	await process_frame
	check(inv.has_item(drug_id) and gm().collected_items.has(key), "Old saves get the missing reward once and record it")
	inv.reset()
	boss = scene.instantiate()
	fixture.add_child(boss)
	await process_frame
	check(not inv.has_item(drug_id), "The backfilled reward should not be given a second time")
	# 죽은 상태에서는 회복하지 않는다
	gm().reset_data()
	gm().player_current_hp = 0
	check(not gm().use_flask() and gm().player_current_hp == 0, "Drinking while dead should do nothing")
	gm().reset_data()
