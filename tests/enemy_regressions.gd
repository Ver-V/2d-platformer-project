extends SceneTree
# Run with Godot --headless --path . --script res://tests/enemy_regressions.gd
# 잡몹(GroundEnemy) 설정·이동·공격·사망 검사. 저장 파일은 건드리지 않는다.

var failures: int = 0
var fixture: Node2D

const MOBS := {
	"slime": "res://Scenes/Entitites/slime_1.tscn",
	"mushroom": "res://Scenes/Entitites/Emushroom.tscn",
	"snake": "res://Scenes/Entitites/esnake.tscn",
}

func _initialize() -> void:
	call_deferred("run_checks")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func run_checks() -> void:
	fixture = Node2D.new()
	root.add_child(fixture)
	check_scene_config()
	check_stage_overrides()
	check_attack_hitbox()
	check_knockback_resist()
	await check_patrol_on_platform()
	await check_melee_attack()
	await check_death_animation()
	await check_boss_stage_unload()
	await check_boss1_phase2()
	await check_rats()
	# 피격 효과(번쩍임·스파크 타이머, 효과음)가 끝난 뒤 정리해야 이미 지운 노드를 참조하는 에러·누수가 남지 않는다
	await create_timer(1.0).timeout
	fixture.queue_free()
	await process_frame
	print("Enemy regression checks: ", "PASS" if failures == 0 else "FAIL", " (", failures, " failures)")
	quit(0 if failures == 0 else 1)

# 보스가 있는 스테이지를 닫을 때 보스 방 비활성화 → _stop_boss_music이 current_scene 없이 불려도 에러가 나지 않아야 한다
# (실패하면 SCRIPT ERROR로 run_tests.sh가 잡는다)
func check_boss_stage_unload() -> void:
	var manager = root.get_node("GameManager")
	manager.reset_data()
	var stage = load("res://Scenes/Stage/Stage_01.tscn").instantiate()
	root.add_child(stage)
	await process_frame
	var bosses: Array = stage.find_children("*", "", true, false).filter(func(n): return n.is_in_group("bosses"))
	check(not bosses.is_empty(), "Stage_01 should have a boss for the unload check")
	for boss in bosses:
		boss._stop_boss_music() # 씬이 살아 있을 때도 정상 동작
	stage.queue_free()
	await process_frame
	await process_frame
	manager.reset_data()
	print("Boss stage unload: boss music stop is safe while the scene closes")

# 1스테이지 보스: 체력 50% 미만이면 페이즈 2 (대사, 패턴 1.5배), 4번 패턴은 2갈래 → 3갈래
func check_boss1_phase2() -> void:
	var manager = root.get_node("GameManager")
	manager.reset_data()
	var boss = load("res://Scenes/Entitites/boss_stage_1.tscn").instantiate()
	fixture.add_child(boss)
	await process_frame
	check(boss.phase == 1 and boss._speed() == 1.0, "Boss 1 should start in phase 1 at normal speed")
	check(boss.phase2_speech_key != "", "Boss 1 should have a phase 2 speech key")
	boss.hp = boss.max_hp / 2
	boss._check_phase()
	check(boss.phase == 1, "Boss 1 should stay in phase 1 at exactly 50% HP")
	boss.hp = boss.max_hp / 2 - 1
	boss._check_phase()
	check(boss.phase == 2, "Boss 1 should enter phase 2 below 50% HP")
	check(is_equal_approx(boss._speed(), 1.5), "Boss 1 phase 2 patterns should run 1.5x faster")
	check(boss._speech_label != null and boss._speech_label.visible and boss._speech_label.text != "",
		"Boss 1 should show its phase 2 line above its head")
	boss.reset_to_home()
	check(boss.phase == 1 and not boss._speech_label.visible, "Resetting the boss should return it to phase 1")

	var dummy := Node2D.new()
	dummy.global_position = boss.global_position + Vector2(200, 0)
	fixture.add_child(dummy)
	boss.target = dummy
	boss.shooter.projectile_scene = boss.Fire_projectile
	var first = boss._split_toward_target([boss.shooter.shoot_dir(boss, Vector2.RIGHT, boss.global_position)], boss.SPLIT_FIRST_ANGLES)
	var second = boss._split_toward_target(first, boss.SPLIT_SECOND_ANGLES)
	check(first.size() == 2 and second.size() == 6, "Boss 1 pattern 4 should split into 2, then 3 each (got %d, %d)" % [first.size(), second.size()])
	boss.queue_free()
	dummy.queue_free()
	await process_frame
	manager.reset_data()

# GroundEnemy → EnemyBase → GameManager(autoload) 의존이라 클래스 이름 대신 스크립트 경로로 확인한다
func _extends(node: Object, script_path: String) -> bool:
	var sc: Script = node.get_script()
	while sc != null:
		if sc.resource_path == script_path:
			return true
		sc = sc.get_base_script()
	return false

func wait_physics(frames: int) -> void:
	for i in frames:
		await physics_frame

func make_floor(center: Vector2, width: float) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(width, 16)
	shape.shape = rect
	body.add_child(shape)
	fixture.add_child(body)
	body.global_position = center + Vector2(0, 8) # 윗면이 center.y
	return body

func spawn(kind: String, pos: Vector2):
	var mob = load(MOBS[kind]).instantiate()
	mob.patrol_idle_enabled = false
	fixture.add_child(mob)
	mob.global_position = pos
	mob.home_position = pos
	mob.set_active(true)
	return mob

# 몹 씬마다 스탯이 공통 필드로 설정돼 있고, 옛 몹별 변수가 남아 있지 않다
func check_scene_config() -> void:
	var expected := {
		"slime": {"hp": 30, "dmg": 10, "speed": 40.0, "flip_right": true, "death": &"dead", "attacks": false},
		"mushroom": {"hp": 50, "dmg": 15, "speed": 50.0, "flip_right": false, "death": &"dead", "attacks": true},
		"snake": {"hp": 45, "dmg": 15, "speed": 40.0, "flip_right": true, "death": &"died", "attacks": true},
	}
	var stale := RegEx.create_from_string("(slime|mushroom|snake)_(max_hp|contact_damage|move_speed|knockback_res)|floor_ray_[xy]")
	for kind in MOBS:
		var path: String = MOBS[kind]
		var e: Dictionary = expected[kind]
		var mob = load(path).instantiate()
		check(_extends(mob, "res://Script/base/ground_enemy.gd"), "%s should be a GroundEnemy" % kind)
		check(mob.max_hp_base == e.hp and mob.contact_damage_base == e.dmg and is_equal_approx(mob.move_speed_base, e.speed),
			"%s stats should come from its scene (hp %d, dmg %d, speed %.0f)" % [kind, mob.max_hp_base, mob.contact_damage_base, mob.move_speed_base])
		check(mob.facing_flip_h(1) == e.flip_right and mob.facing_flip_h(-1) != e.flip_right, "%s should face its walking direction" % kind)
		var spr: AnimatedSprite2D = mob.get_node("AnimatedSprite2D")
		check(mob.death_animation(spr) == e.death, "%s death animation should be %s" % [kind, e.death])
		check((mob.attack_distance > 0.0) == e.attacks, "%s attack setting mismatch" % kind)
		for anim_name in mob.attack_animations if e.attacks else []:
			check(spr.sprite_frames.has_animation(anim_name), "%s is missing attack animation %s" % [kind, anim_name])
		check(stale.search(FileAccess.get_file_as_string(path)) == null, "%s scene still has old per-mob stat properties" % kind)
		check(mob.get_node_or_null("InvulnTimer") == null and mob.get_node_or_null("Sprite2D") == null, "%s should not carry unused base nodes" % kind)
		mob.free()
	# 베이스 씬(EnemyBase.tscn)에서 안 쓰는 노드를 뺀 뒤에도 상속 씬들이 자기 노드를 그대로 가진다
	var inherited := {
		"res://Scenes/Entitites/boss_stage_1.tscn": ["DetectArea/CollisionShape2D", "BGMPlayer", "ActionSFX", "ShooterComponent", "HitSound"],
		"res://Scenes/Entitites/Boss.tscn": ["BGMPlayer", "HitSound"],
		"res://Scenes/Entitites/enemy_ranged.tscn": ["ShooterComponent", "LineOfSight", "Muzzle", "DetectArea", "HitSound"],
	}
	for path in inherited:
		var inst = load(path).instantiate()
		for node_path in inherited[path]:
			check(inst.get_node_or_null(node_path) != null, "%s lost node %s" % [path, node_path])
		inst.free()
	print("Scenes: stats on common fields, facing, death/attack animations, unused nodes removed")

# 스테이지에 배치된 몹의 개별 설정(옛 이름에서 옮긴 값)이 유지된다
func check_stage_overrides() -> void:
	var tutorial = load("res://Scenes/Stage/Stage_tutorial.tscn").instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	var dummies: Array = tutorial.find_children("*", "Slime", true, false)
	check(not dummies.is_empty(), "Tutorial should have slimes")
	var still := 0
	for s in dummies:
		if s.max_hp_base == 10 and s.contact_damage_base == 0 and is_equal_approx(s.move_speed_base, 0.0):
			still += 1
	check(still == dummies.size(), "Tutorial slimes should keep hp 10 / no damage / no movement (%d of %d)" % [still, dummies.size()])
	tutorial.free()
	var stage01 = load("res://Scenes/Stage/Stage_01.tscn").instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	var weak_snakes := 0
	for s in stage01.find_children("*", "Esnake", true, false):
		if s.max_hp_base == 20:
			weak_snakes += 1
	check(weak_snakes == 10, "Stage_01 snakes overridden to 20 hp should keep it (found %d)" % weak_snakes)
	stage01.free()
	print("Stage overrides: migrated per-instance stats kept")

func check_attack_hitbox() -> void:
	var snake = load(MOBS["snake"]).instantiate()
	fixture.add_child(snake)
	var shape: CollisionShape2D = snake.get_node("Hitbox/CollisionShape2D")
	var base_size: Vector2 = shape.shape.size
	var base_x: float = shape.position.x
	snake.dir = 1
	snake.set_attack_hitbox(true)
	check(is_equal_approx(shape.shape.size.x, base_size.x + 8.0) and is_equal_approx(shape.position.x, base_x + 4.0),
		"Attack hitbox should grow forward while active")
	snake.set_attack_hitbox(false)
	check(shape.shape.size == base_size and is_equal_approx(shape.position.x, base_x), "Attack hitbox should shrink back")
	var other = load(MOBS["snake"]).instantiate()
	fixture.add_child(other)
	check(other.get_node("Hitbox/CollisionShape2D").shape != shape.shape, "Each mob should own its hitbox shape")
	snake.free()
	other.free()
	print("Attack hitbox: grows forward, restores, not shared")

# 좁은 발판 위 순찰: 떨어지지 않고 끝에서 뒤돈다
func check_patrol_on_platform() -> void:
	for kind in MOBS:
		var floor_body := make_floor(Vector2(0, 0), 160)
		var mob = spawn(kind, Vector2(0, -20))
		mob.dir = 1
		var min_x := 1e9
		var max_x := -1e9
		var turned := false
		var last_dir: int = mob.dir
		for i in 360: # 6초
			await physics_frame
			min_x = minf(min_x, mob.global_position.x)
			max_x = maxf(max_x, mob.global_position.x)
			if mob.dir != last_dir:
				turned = true
				last_dir = mob.dir
		check(mob.is_on_floor() and mob.global_position.y < 10.0, "%s should stay on the platform (y %.1f)" % [kind, mob.global_position.y])
		check(turned and max_x - min_x > 30.0, "%s should patrol and turn at the ledge (range %.1f)" % [kind, max_x - min_x])
		check(min_x > -80.0 and max_x < 80.0, "%s should not walk off the platform" % kind)
		mob.queue_free()
		floor_body.queue_free()
		await physics_frame
	print("Patrol: stays on platform, turns at ledges")

func check_melee_attack() -> void:
	for kind in ["mushroom", "snake"]:
		var floor_body := make_floor(Vector2(0, 0), 300)
		var mob = spawn(kind, Vector2(0, -20))
		await wait_physics(20)
		var dummy := Node2D.new()
		fixture.add_child(dummy)
		dummy.global_position = mob.global_position + Vector2(-10, 0)
		mob.target = dummy
		await wait_physics(5)
		check(mob.is_attacking and mob.attack_animations.has(mob.sprite.animation), "%s should attack a target in range" % kind)
		check(mob.dir == -1, "%s should face the target" % kind)
		await wait_physics(10)
		check(absf(mob.velocity.x) < 1.0, "%s should stand still while attacking" % kind)
		var finished := false
		for i in 180:
			await physics_frame
			if not mob.is_attacking:
				finished = true
				break
		check(finished, "%s attack should end when its animation finishes" % kind)
		dummy.global_position = mob.global_position + Vector2(-150, 0)
		mob.is_attacking = false
		await wait_physics(10)
		check(not mob.is_attacking and mob.velocity.x < -1.0, "%s should chase a target out of range" % kind)
		mob.queue_free()
		dummy.queue_free()
		floor_body.queue_free()
		await physics_frame
	print("Melee: attacks in range, faces target, stops, ends, chases out of range")

# 스테이지2 쥐: 기본 + 색 변종(보라 독, 빨강 출혈, 하양 거대). 색은 enemy_tint 셰이더, 색 있는 쥐는 변이체가 되지 않는다
func check_rats() -> void:
	var expected := {
		"rat": {"hp": 45, "dmg": 15, "speed": 45.0, "gold": 15, "tinted": false},
		"rat_purple": {"hp": 60, "dmg": 15, "speed": 45.0, "gold": 20, "tinted": true},
		"rat_red": {"hp": 60, "dmg": 15, "speed": 45.0, "gold": 20, "tinted": true},
		"rat_white": {"hp": 150, "dmg": 30, "speed": 35.0, "gold": 50, "tinted": true},
		"rat_blue": {"hp": 45, "dmg": 10, "speed": 40.0, "gold": 25, "tinted": true},
	}
	var base_size: Vector2
	for kind in expected:
		var e: Dictionary = expected[kind]
		var mob = load("res://Scenes/Entitites/%s.tscn" % kind).instantiate()
		check(_extends(mob, "res://Script/Entity/rat.gd"), "%s should use the rat script" % kind)
		check(mob.max_hp_base == e.hp and mob.contact_damage_base == e.dmg and is_equal_approx(mob.move_speed_base, e.speed) and mob.drop_gold_amount == e.gold,
			"%s stats mismatch (hp %d, dmg %d, speed %.0f, gold %d)" % [kind, mob.max_hp_base, mob.contact_damage_base, mob.move_speed_base, mob.drop_gold_amount])
		check(mob.facing_flip_h(1) == false and mob.facing_flip_h(-1) == true, "%s sprite faces right" % kind)
		var spr: AnimatedSprite2D = mob.get_node("AnimatedSprite2D")
		check(spr.sprite_frames.get_frame_count(&"walk") == 4 and spr.sprite_frames.has_animation(&"idle"), "%s should have walk/idle" % kind)
		var mat = spr.material
		var tinted: bool = mat is ShaderMaterial and mat.shader.resource_path == "res://resources/Shaders/enemy_tint.gdshader"
		check(tinted == e.tinted and mob.mutation_enabled != e.tinted, "%s: tinted rats use the tint shader and never mutate" % kind)
		# 어둠 속에서 종류를 알 수 있게 눈 색이 몸 색과 맞다 (기본 쥐는 노랑)
		var eyes = mob.get_node_or_null("GlowEyes")
		var eye_tex := {"rat": "yelloweye", "rat_purple": "purpleeye", "rat_red": "redeye", "rat_blue": "blueeye", "rat_white": "whiteeye"}[kind] as String
		check(eyes is GlowEyes and eyes.hframes == spr.sprite_frames.get_frame_count(&"walk") and eyes.texture.resource_path == "res://Assets/sprites/%s.png" % eye_tex,
			"%s should have %s glow eyes matching its walk frames" % [kind, eye_tex])
		var body_size: Vector2 = mob.get_node("CollisionShape2D").shape.size
		if kind == "rat":
			base_size = body_size
		elif kind == "rat_white":
			check(body_size == base_size * 2.0 and spr.scale == Vector2(2, 2) and mob.knockback_resist >= 0.5, "White rat should be twice as big and hard to push")
		mob.free()
	var purple = load("res://Scenes/Entitites/rat_purple.tscn").instantiate()
	check(purple.contact_status is PoisonEffect and is_equal_approx(purple.contact_status_chance, 0.35), "Purple rat should poison on contact (35%)")
	purple.free()
	var red = load("res://Scenes/Entitites/rat_red.tscn").instantiate()
	check(red.contact_status is BleedEffect and is_equal_approx(red.contact_status_chance, 1.0) and is_equal_approx(red.contact_status.buildup_per_hit, 25.0),
		"Red rat should always build bleed by 25 per hit")
	red.free()
	# 색 셰이더에서도 피격 번쩍임·사망이 에러 없이 돈다 (실패하면 SCRIPT ERROR로 run_tests.sh가 잡는다)
	var floor_body := make_floor(Vector2(0, 0), 200)
	var mob = load("res://Scenes/Entitites/rat_red.tscn").instantiate()
	mob.patrol_idle_enabled = false
	mob.coin_scene = null
	fixture.add_child(mob)
	mob.global_position = Vector2(0, -20)
	mob.set_active(true)
	await wait_physics(5)
	mob.receive_hit(HitData.new(5))
	check(is_equal_approx(mob.sprite.material.get_shader_parameter("flash_modifier"), 1.0), "Tinted rat should flash when hit")
	mob.receive_hit(HitData.new(9999))
	await create_timer(0.3).timeout
	mob.queue_free()
	floor_body.queue_free()
	await physics_frame
	print("Rats: base + purple/red/white variants configured; tint shader flashes and dies cleanly")
	await check_blue_rat()
	await check_rat_lunge()
	await check_mob_in_water()

# 파란 쥐: 사거리 안 + 벽에 안 가리면 제자리에서 물탄을 쏘고, 사거리 밖이면 쫓아간다. 물탄은 어둠(VisionLimit) 위에 그린다
func check_blue_rat() -> void:
	var water = load("res://Scenes/Projectile/projectile_water.tscn").instantiate()
	check(water is Projectile and water.z_index > VisionLimit.Z_INDEX and not water.z_as_relative and water.damage == 15,
		"Water projectile should be a Projectile drawn above the darkness")
	water.free()
	var floor_body := make_floor(Vector2(0, 0), 600)
	var mob = load("res://Scenes/Entitites/rat_blue.tscn").instantiate()
	mob.patrol_idle_enabled = false
	mob.coin_scene = null
	fixture.add_child(mob)
	mob.global_position = Vector2(0, -20)
	mob.home_position = mob.global_position
	mob.set_active(true)
	check(mob.shooter != null and mob.shooter.projectile_damage == 15 and mob.shoot_range > 0.0, "Blue rat should have a water shooter")
	var dummy := Node2D.new()
	fixture.add_child(dummy)
	dummy.global_position = Vector2(100, -10)
	mob.target = dummy
	await wait_physics(70) # 첫 발 준비(0.8초) 뒤 한 발
	check(mob.shooter._shot_count == 1 and absf(mob.velocity.x) < 1.0 and not mob.sprite.flip_h,
		"Blue rat should stand, face the target and shoot once after the windup (shots %d, vx %.1f)" % [mob.shooter._shot_count, mob.velocity.x])
	# 벽에 가리면 쏘지 않고 다가간다
	var wall := make_floor(Vector2(50, -60), 8)
	wall.get_child(0).shape.size = Vector2(8, 80)
	wall.global_position = Vector2(50, -40) # 바닥부터 80px 높이
	var shots: int = mob.shooter._shot_count
	var start_x: float = mob.global_position.x
	await wait_physics(150)
	check(mob.shooter._shot_count == shots and mob.global_position.x > start_x + 4.0, "Blue rat should walk toward a target behind a wall instead of shooting")
	wall.queue_free()
	# 사거리 밖이면 쫓아간다
	mob.global_position = Vector2(-200, -20)
	await wait_physics(30) # 떨어져 착지한 뒤
	check(absf(mob.velocity.x) > 1.0 and mob.velocity.x > 0.0, "Blue rat should chase a target out of range")
	mob.queue_free()
	dummy.queue_free()
	floor_body.queue_free()
	await physics_frame
	print("Blue rat: stands and shoots in range, not through walls, chases out of range; water drawn above darkness")

# 쥐 달려들기 (코드 연출): 가까이 오면 웅크림(눈 밝아짐·제자리) → 걷기 2배 속도로 돌진(방향 고정) → 멈춤 → 쿨다운.
# 하얀 쥐는 달려들지 않고, 파란 쥐는 가까이 오면 쏘지 않고 달려든다
func check_rat_lunge() -> void:
	var floor_body := make_floor(Vector2(0, 0), 600)
	var dummy := Node2D.new()
	fixture.add_child(dummy)
	var mob = load("res://Scenes/Entitites/rat.tscn").instantiate()
	mob.patrol_idle_enabled = false
	mob.coin_scene = null
	fixture.add_child(mob)
	mob.global_position = Vector2(0, -20)
	mob.home_position = mob.global_position
	mob.set_active(true)
	await wait_physics(30) # 떨어져 착지한 뒤
	dummy.global_position = Vector2(30, -6)
	mob.target = dummy
	var min_eye_alpha := 1.0
	for i in 8:
		await physics_frame
		min_eye_alpha = minf(min_eye_alpha, mob.glow_eyes.self_modulate.a)
	check(mob.lunge_state == mob.Lunge.WINDUP and min_eye_alpha < 1.0 and mob.sprite.scale.y < mob._sprite_base_scale.y,
		"Rat should crouch with flickering eyes when the target is close")
	await wait_physics(roundi(mob.lunge_windup * 60.0) - 3)
	check(mob.lunge_state == mob.Lunge.DASH and is_equal_approx(mob.velocity.x, mob.move_speed * mob.lunge_speed_mult),
		"Rat should dash at %.0fx walk speed (vx %.1f)" % [mob.lunge_speed_mult, mob.velocity.x])
	dummy.global_position = Vector2(-100, -6) # 돌진 중 타겟이 뒤로 가도 방향은 그대로
	await wait_physics(3)
	check(mob.lunge_state != mob.Lunge.DASH or mob.velocity.x > 0.0, "Dash direction should stay locked")
	await wait_physics(roundi((mob.lunge_dash_time + mob.lunge_recovery) * 60.0) + 5)
	check(mob.lunge_state == mob.Lunge.NONE and mob._lunge_cooldown_left > 0.0 and mob.glow_eyes.self_modulate == Color.WHITE,
		"Rat should recover, then wait for the lunge cooldown")
	mob.queue_free()
	await physics_frame

	var white = load("res://Scenes/Entitites/rat_white.tscn").instantiate()
	check(not white.lunge_enabled, "White rat should not lunge")
	white.free()

	var blue = load("res://Scenes/Entitites/rat_blue.tscn").instantiate()
	blue.patrol_idle_enabled = false
	blue.coin_scene = null
	fixture.add_child(blue)
	blue.global_position = Vector2(0, -20)
	blue.home_position = blue.global_position
	blue.set_active(true)
	await wait_physics(30) # 떨어져 착지한 뒤
	dummy.global_position = Vector2(30, -6)
	blue.target = dummy
	await wait_physics(roundi((blue.lunge_windup + blue.lunge_dash_time) * 60.0))
	check(blue.shooter._shot_count == 0 and blue.lunge_state != blue.Lunge.NONE, "Blue rat should lunge instead of shooting at close range")
	blue.queue_free()
	dummy.queue_free()
	floor_body.queue_free()
	await physics_frame
	print("Rat lunge: crouch + eye flicker, 2x dash with locked direction, recovery, cooldown; white never lunges, blue lunges up close")

# 물속 몹: 이동 0.5배, 중력 0.25배·낙하 50 상한, 멈춰 있어도 걷기 동작 (허우적거림)
func check_mob_in_water() -> void:
	var floor_body := make_floor(Vector2(0, 0), 600)
	var water = load("res://Scenes/Stage/WaterTileMap.tscn").instantiate()
	fixture.add_child(water)
	for x in range(-20, 20):
		for y in range(-12, 0):
			water.set_cell(Vector2i(x, y), 0, Vector2i(1, 0))
	var mob = load("res://Scenes/Entitites/rat.tscn").instantiate()
	mob.patrol_idle_enabled = false
	mob.coin_scene = null
	mob.lunge_enabled = false
	fixture.add_child(mob)
	mob.global_position = Vector2(0, -150)
	mob.home_position = mob.global_position
	mob.set_active(true)
	await wait_physics(30)
	check(mob.in_water and not mob.is_on_floor() and mob.velocity.y <= mob.water_max_fall_speed + 0.01,
		"A mob sinking in water should fall slowly (vy %.1f)" % mob.velocity.y)
	await wait_physics(240)
	check(mob.is_on_floor() and absf(absf(mob.velocity.x) - mob.move_speed * mob.water_move_mult) < 0.5,
		"A mob walking in water should move at half speed (vx %.1f)" % mob.velocity.x)
	mob.velocity.x = 0.0
	mob.set_physics_process(false)
	mob.play_move_animation(mob.in_water or absf(mob.velocity.x) > 1.0)
	check(mob.sprite.animation == mob.walk_animation, "A mob in water should keep its walk animation even when stopped")
	mob.queue_free()
	water.queue_free()
	floor_body.queue_free()
	await physics_frame
	print("Mob in water: slow sink, half speed, walk animation kept")

func check_death_animation() -> void:
	for kind in MOBS:
		var floor_body := make_floor(Vector2(0, 0), 200)
		var mob = spawn(kind, Vector2(0, -20))
		mob.coin_scene = null
		await wait_physics(5)
		mob.receive_hit(HitData.new(9999))
		await wait_physics(2)
		check(mob.sprite.animation == mob.death_animation(), "%s should play its death animation (%s)" % [kind, mob.sprite.animation])
		await create_timer(0.3).timeout # 피격 번쩍임 타이머(0.1초)가 끝난 뒤 지운다
		mob.queue_free()
		floor_body.queue_free()
		await physics_frame
	print("Death: each mob plays its own death animation")

# 넉백 저항: 1 = 안 밀림, 0.5 = 절반, 0 = 그대로, 음수 = 더 멀리 (-1이면 2배)
func check_knockback_resist() -> void:
	var mob = load(MOBS["slime"]).instantiate()
	fixture.add_child(mob)
	var kb := Vector2(100, -50)
	var expected := {1.0: 0.0, 0.5: 0.5, 0.0: 1.0, -1.0: 2.0, 2.0: 0.0}
	for resist in expected:
		mob.knockback_resist = resist
		mob.reset_combat_state()
		mob.apply_knockback_vec(kb, true)
		check(mob.knockback_vel.is_equal_approx(kb * expected[resist]), "Knockback resist %.1f should scale knockback by %.1f" % [resist, expected[resist]])
	mob.free()
	print("Knockback resist: 1 none, 0.5 half, 0 full, negative stronger")
