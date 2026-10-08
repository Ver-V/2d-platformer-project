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
	# 피격 효과(번쩍임·스파크 타이머, 효과음)가 끝난 뒤 정리해야 이미 지운 노드를 참조하는 에러·누수가 남지 않는다
	await create_timer(1.0).timeout
	fixture.queue_free()
	await process_frame
	print("Enemy regression checks: ", "PASS" if failures == 0 else "FAIL", " (", failures, " failures)")
	quit(0 if failures == 0 else 1)

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
