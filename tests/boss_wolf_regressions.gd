extends SceneTree
# Run with Godot --headless --path . --script res://tests/boss_wolf_regressions.gd
# 숨겨진 늑대 보스: 씬 구성, 인트로(변장·돌아보기 순서·조작 잠금·변신·인트로 기록), 인트로를 본 세이브는 늑대 모습,
# 할퀴기 판정, 울음 졸음, 잠든 플레이어 물기, 페이즈 2 붉은 기, 실제 전투가 오류 없이 도는지. 저장 파일은 건드리지 않는다.

var failures: int = 0
var fixture: Node2D

const BOSS := "res://Scenes/Entitites/boss_wolf.tscn"
const PLAYER := "res://Scenes/Entitites/Player.tscn"
const FLOOR_Y := 0.0
const BOSS_ID := &"B-wolftest"

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
	current_scene = fixture
	make_arena()
	await check_scene_setup()
	await check_intro()
	await check_talked_skips_disguise()
	await check_attacks()
	await check_sleep_shot()
	await check_phase_2_tint()
	await check_fight_runs()
	current_scene = null
	fixture.queue_free()
	await process_frame
	gm().reset_data()
	print("Wolf boss regression checks: ", "PASS" if failures == 0 else "FAIL", " (", failures, " failures)")
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

func spawn_boss(x: float = 100.0) -> Node:
	var boss = load(BOSS).instantiate()
	boss.persist_id = BOSS_ID
	boss.save_after_intro = false
	boss.requires_full_moon = false
	fixture.add_child(boss)
	boss.global_position = Vector2(x, FLOOR_Y - (boss._feet_y() - boss.global_position.y) - 1.0)
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

func short_intro(boss) -> void:
	boss.dialogue_file = ""
	for prop in ["intro_look_away_time", "intro_turn_time", "intro_stare_time", "intro_bleat_time", "intro_howl_time"]:
		boss.set(prop, 0.15)

func check_scene_setup() -> void:
	var boss = spawn_boss()
	await process_frame
	check(boss.get_script().resource_path == "res://Script/Entity/boss_wolf.gd" and boss.is_in_group("bosses"), "Wolf boss should run boss_wolf.gd as a boss")
	check(boss.disguised and boss.disguise.visible and not boss.sprite.visible, "Before the intro the wolf should look like a sheep")
	for path in ["Facing/ClawHitbox", "Facing/BiteHitbox", "Facing/PounceHitbox"]:
		check(boss.get_node(path).collision_mask == 256, "%s should hit the player hurtbox" % path)
	check(boss.howl_area != null and boss.howl_area.collision_mask == 2, "HowlArea should sense the player body")
	for lang in ["en", "ko"]:
		var data = JSON.parse_string(FileAccess.get_file_as_string(boss.dialogue_file.replace("/en/", "/%s/" % lang)))
		check(data is Dictionary and data.has("start"), "wolf_boss.json (%s) should have a start block" % lang)
	boss.queue_free()
	await process_frame

# 인트로: 문 반대쪽 → 문 쪽 → 플레이어 → 양 울음 → 변신 → 전투. 그동안 조작이 막히고 맞지 않는다
func check_intro() -> void:
	gm().talked_bosses.erase(BOSS_ID)
	var player = spawn_player(Vector2(-150, -12))
	var boss = spawn_boss(100.0)
	short_intro(boss)
	var door := Marker2D.new()
	fixture.add_child(door)
	door.global_position = Vector2(300, -10) # 문은 플레이어 반대편 (돌아보는 순서를 구분하려고)
	boss.door_marker = door
	await physics_frames(3)
	boss.set_active(true)
	await process_frame
	check(boss.current_state == boss.State.INTRO and boss.disguised, "Entering should start the disguised intro")
	check(boss._face_dir == -1, "The sheep should first look away from the door")
	check(gm().is_menu_open, "Player control should be locked during the intro")
	var hit := HitData.new(30, Vector2.ZERO, player)
	check(HitData.deliver(boss, hit) == HitData.Result.IGNORED and boss.hp == boss.max_hp, "The boss should not take hits during the intro")
	await create_timer(0.2).timeout
	check(boss._face_dir == 1, "Then it should turn toward the door")
	await create_timer(0.15).timeout
	check(boss._face_dir == -1, "Then it should stare at the player")
	await create_timer(0.35).timeout
	check(not boss.disguised and boss.sprite.visible and not boss.disguise.visible, "It should turn into the wolf after bleating")
	await create_timer(0.3).timeout
	check(boss.current_state != boss.State.INTRO and not gm().is_menu_open, "The fight should start and unlock the player")
	check(gm().talked_bosses.get(BOSS_ID, false), "The intro should be recorded")
	boss.queue_free()
	player.queue_free()
	door.queue_free()
	await process_frame

func check_talked_skips_disguise() -> void:
	gm().talked_bosses[BOSS_ID] = true
	var boss = spawn_boss()
	await process_frame
	check(not boss.disguised and boss.sprite.visible, "A boss whose intro was seen should start as the wolf")
	boss.queue_free()
	await process_frame

func check_attacks() -> void:
	gm().talked_bosses[BOSS_ID] = true
	var player = spawn_player(Vector2(-60, -12))
	var boss = spawn_boss(-30.0)
	await physics_frames(4)
	fresh(player)
	boss.target = player
	boss._face(-1)
	await physics_frames(2)
	check(boss.strike(boss.claw_box, boss.claw_damage) == 1 and player.hp == 100 - boss.claw_damage, "Claw should hit a player in front")

	# 울음: HowlArea 안에서 졸음 (울부짖기는 2.5배)
	fresh(player)
	boss._howl_mult = boss.howl_drowsy_mult
	for i in 30: # 보스의 물리 처리는 방이 꺼져 있어 멈춰 있으므로 울음 효과만 직접 돌린다
		await physics_frame
		boss._expose_howl(1.0 / 60.0)
	boss._howl_mult = 0.0
	var drowsy := player.get_status_effects().get_effect(&"drowsy") as DrowsyEffect
	check(drowsy != null and drowsy.buildup > 15.0, "Howling should make a nearby player drowsy fast (got %s)" % (drowsy.buildup if drowsy else -1.0))

	# 잠든 플레이어에겐 물기 (맞으면 깬다)
	fresh(player)
	player.apply_status_effect(boss.drowsy_effect).expose(10.0)
	check(player.is_asleep(), "Setup: the player should be asleep")
	boss.bite_windup = 0.05
	boss.melee_recover = 0.05
	await boss._do_pattern()
	check(player.hp == 100 - boss.bite_damage and not player.is_asleep(), "A sleeping player should get bitten hard and wake up (hp %d)" % player.hp)
	boss.queue_free()
	player.queue_free()
	await process_frame

# 잠 탄환: 작고 빠르고 매 발 패링 가능. 맞으면 개당 졸음 40 (세 발이면 잠들고, 그 타격으로 바로 깨지 않는다).
# 일반 가드는 그대로 40, 퍼펙트 가드는 20. 세 발을 반사해 맞히면 보스가 2.5초 잠들고 그동안 피해 2배, 공격하지 않는다
func check_sleep_shot() -> void:
	gm().talked_bosses[BOSS_ID] = true
	var player = spawn_player(Vector2(-150, -12))
	var boss = spawn_boss(100.0)
	await physics_frames(3)
	fresh(player)
	boss.target = player
	boss._face(-1)
	var shot: Projectile = boss.fire_sleep_shot()
	check(shot != null and shot.is_parryable and shot.speed > 300.0 and shot.get_node("AnimatedSprite2D").scale.x < 1.0,
		"Sleep shots should be small, fast and parryable")
	check(shot.status_effects.size() == 1 and shot.status_effects[0] is DrowsyEffect and is_equal_approx(shot.status_effects[0].buildup_per_hit, 40.0),
		"Each sleep shot should carry 40 drowsiness")
	shot.queue_free()
	# 맞으면 40씩: 두 발은 80, 세 발이면 잠든다
	for i in 3:
		var s: Projectile = boss.fire_sleep_shot()
		s.hit_target(player)
		s.queue_free()
		var d := player.get_status_effects().get_effect(&"drowsy") as DrowsyEffect
		if i == 1:
			check(d != null and is_equal_approx(d.buildup, 80.0) and not player.is_asleep(), "Two sleep shots should build 80 drowsiness")
	check(player.is_asleep(), "Three sleep shots should put the player to sleep (and the third hit must not wake them)")
	# 가드: 일반은 그대로, 퍼펙트는 절반
	for perfect in [false, true]:
		fresh(player)
		player.attack_pivot.scale.x = 1 # 오른쪽(보스 쪽)을 본다
		player.guard.is_guarding = true
		player.guard.guard_timer = 0.0 if perfect else 0.3
		var g: Projectile = boss.fire_sleep_shot()
		g.velocity = Vector2(-420, 0)
		g.hit_target(player)
		g.queue_free()
		var gd := player.get_status_effects().get_effect(&"drowsy") as DrowsyEffect
		var want := 20.0 if perfect else 40.0
		check(gd != null and is_equal_approx(gd.buildup, want), "%s guard should take %d drowsiness (got %s)" % ["Perfect" if perfect else "Normal", want, gd.buildup if gd else -1.0])
		player.guard.is_guarding = false
	# 세 발 모두 반사해 맞히면 보스가 잠든다
	fresh(player)
	boss.set_active(true)
	await physics_frames(2)
	for i in 3:
		var r: Projectile = boss.fire_sleep_shot()
		await process_frame
		check(r.attempt_parry(player.global_position), "Every sleep shot should be parryable")
		r.hit_target(boss)
	check(boss.is_asleep(), "Three reflected sleep shots should put the wolf to sleep")
	var bd := boss.get_status_effects().get_effect(&"drowsy") as DrowsyEffect
	check(bd != null and is_equal_approx(bd.sleep_left, 2.5), "The wolf should sleep for 2.5s (got %s)" % (bd.sleep_left if bd else -1.0))
	var hp_before: int = boss.hp # 잠 탄환은 무적시간을 주지 않으니 바로 때릴 수 있다 (reset_combat_state는 상태이상까지 지운다)
	HitData.deliver(boss, HitData.new(10, Vector2.ZERO, player))
	check(hp_before - boss.hp == 20, "A sleeping wolf should take double damage (took %d)" % (hp_before - boss.hp))
	check(boss.strike(boss.claw_box, boss.claw_damage) == 0, "A sleeping wolf should not attack")
	await create_timer(2.7).timeout
	check(not boss.is_asleep(), "The wolf should wake up after 2.5s")
	boss.queue_free()
	player.queue_free()
	await process_frame

func check_phase_2_tint() -> void:
	gm().talked_bosses[BOSS_ID] = true
	var boss = spawn_boss()
	await process_frame
	boss.set_active(true)
	boss.reset_combat_state()
	var hit := HitData.new(int(boss.max_hp * 0.6), Vector2.ZERO, null)
	HitData.deliver(boss, hit)
	check(boss.phase == 2, "Below half HP the wolf should enter phase 2")
	await create_timer(boss.rage_fade_time + 0.1).timeout
	var mat := boss.sprite.material as ShaderMaterial
	check(mat != null and float(mat.get_shader_parameter(&"rage_amount")) > 0.3, "Phase 2 should tint the wolf red")
	boss.queue_free()
	await process_frame

func check_fight_runs() -> void:
	gm().talked_bosses[BOSS_ID] = true
	var player = spawn_player(Vector2(-150, -12))
	var boss = spawn_boss(100.0)
	await physics_frames(3)
	boss.set_active(true)
	for i in 8:
		await create_timer(0.5).timeout
		player.hp = 100
		gm().player_current_hp = 100
	check(boss._loop_running and boss.current_state == boss.State.COMBAT, "The wolf should keep fighting")
	boss.queue_free()
	player.queue_free()
	await process_frame
	print("Wolf boss: intro order/lock/transform, claw, howl drowsy, bite on sleep, phase 2, live fight")
