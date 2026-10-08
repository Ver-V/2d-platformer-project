extends SceneTree
# Run with Godot --headless --path . --script res://tests/mutation_regressions.gd
# 잡몹 변이(MobMutation): 시드 고정 굴림, 종류별 효과·윤곽선, 보상 3배, 보상 상자, 분열, 리롤, 세이브. 저장 파일은 건드리지 않는다.

var failures: int = 0

const SLIME := "res://Scenes/Entitites/slime_1.tscn"
const STAGE := "res://Scenes/Stage/Stage_03.tscn"

func gm() -> Node: return root.get_node("GameManager")

func _initialize() -> void:
	call_deferred("run_checks")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func run_checks() -> void:
	gm().reset_data()
	check_roll_rules()
	check_seeded_and_reroll()
	var stage = await open_stage()
	await check_kind_effects(stage)
	await check_bleed_and_poison_hits(stage)
	await check_split(stage)
	await check_reward_chest(stage)
	stage.queue_free()
	await process_frame
	await check_chest_restored_on_reload()
	check_save_format()
	gm().reset_data()
	print("Mutation regression checks: ", "PASS" if failures == 0 else "FAIL", " (", failures, " failures)")
	quit(0 if failures == 0 else 1)

# EnemyBase·Chest는 오토로드(GameManager)에 의존해서 테스트에선 클래스 이름 대신 이렇게 확인한다
func _is_mob(n: Node) -> bool:
	return "is_split_minion" in n

func _is_chest(n: Node) -> bool:
	return n.get_script() != null and n.get_script().resource_path == "res://Script/System/Chest.gd"

func open_stage():
	var stage = load(STAGE).instantiate()
	root.add_child(stage)
	current_scene = stage
	await process_frame
	return stage

# 스테이지 Entities에 플레이어 옆으로 슬라임을 놓는다. 자동 변이는 끄고 apply_mutation으로 정한다
func spawn_slime(stage, offset := Vector2(60, -10), auto_mutation := false):
	var mob = load(SLIME).instantiate()
	mob.mutation_enabled = auto_mutation
	mob.patrol_idle_enabled = false
	mob.coin_scene = null
	mob.position = stage.player.global_position + offset
	stage.get_node("Entities").add_child(mob)
	stage.register_spawned_enemy(mob)
	await process_frame
	return mob

func check_roll_rules() -> void:
	var counts := {}
	var mutated := 0
	var n := 20000
	for i in n:
		var rng := RandomNumberGenerator.new()
		rng.seed = i
		var kind := MobMutation.roll(rng, true)
		if kind != MobMutation.Kind.NONE:
			mutated += 1
			counts[kind] = counts.get(kind, 0) + 1
	var rate := float(mutated) / n
	check(rate > 0.025 and rate < 0.035, "Mutation rate should be about 3%%, got %.4f" % rate)
	check(counts.size() == 5, "All five kinds should appear for a mob that can split: %s" % str(counts))
	var split_without_flag := false
	for i in 2000:
		var rng := RandomNumberGenerator.new()
		rng.seed = i
		if MobMutation.roll(rng, false, 1.0) == MobMutation.Kind.SPLIT:
			split_without_flag = true
	check(not split_without_flag, "Only mobs with can_split should split")
	print("Roll: ~3% mutants, split only for can_split mobs")

# 같은 세이브 시드 + 같은 몹 + 같은 회차 = 같은 결과. reset_mobs(휴식·부활)로 회차가 오르고 상자 기록이 지워진다
func check_seeded_and_reroll() -> void:
	gm().reset_data()
	var a: RandomNumberGenerator = gm().make_loot_rng(MobMutation.seed_key("M-test", gm().mutation_epoch))
	var b: RandomNumberGenerator = gm().make_loot_rng(MobMutation.seed_key("M-test", gm().mutation_epoch))
	check(MobMutation.roll(a, true, 0.5) == MobMutation.roll(b, true, 0.5), "Same save, mob and epoch should roll the same mutation")
	gm().add_mutant_chest("res://x.tscn", "mutant:M-test:0", Vector2(1, 2))
	gm().add_collected_item("chest:mutant:M-test:0")
	gm().add_collected_item("chest:other")
	gm().reset_mobs()
	check(gm().mutation_epoch == 1, "Rest/respawn should move to the next mutation epoch")
	check(gm().mutant_chests.is_empty() and not gm().collected_items.has("chest:mutant:M-test:0") and gm().collected_items.has("chest:other"),
		"Reroll should clear mutant chests and only their opened records")
	gm().reset_data()
	check(gm().mutation_epoch == 0, "New game should start from epoch 0")
	print("Seeded: same epoch same result, reset_mobs rerolls")

func check_kind_effects(stage) -> void:
	var expected := {
		MobMutation.Kind.TOUGH: "tough", MobMutation.Kind.SWIFT: "swift", MobMutation.Kind.POISON: "poison",
		MobMutation.Kind.BLEED: "bleed", MobMutation.Kind.SPLIT: "split",
	}
	for kind in expected:
		var mob = await spawn_slime(stage)
		var base_gold: int = mob.drop_gold_amount
		mob.apply_mutation(kind)
		var mat: ShaderMaterial = mob.sprite.material
		check(mat != null and mat.shader == MobMutation.SHADER, "%s mutant should get the outline shader" % expected[kind])
		check(mob.reward_gold() == base_gold * 3, "%s mutant should give 3x gold" % expected[kind])
		match kind:
			MobMutation.Kind.TOUGH:
				check(mob.max_hp == mob.max_hp_base * 3 and mob.hp == mob.max_hp and is_equal_approx(mob.knockback_resist, 1.0),
					"Tough: 3x HP and no knockback")
				check(mat.get_shader_parameter("outline_color") == Color(1, 1, 1) and mat.get_shader_parameter("mode") == MobMutation.OutlineMode.SOLID,
					"Tough: white outline")
			MobMutation.Kind.SWIFT:
				check(is_equal_approx(mob.move_speed, mob.move_speed_base * 2.0) and is_equal_approx(mob.sprite.speed_scale, 2.0),
					"Swift: 2x move and animation (attack) speed")
				check(mat.get_shader_parameter("mode") == MobMutation.OutlineMode.RAINBOW, "Swift: rainbow outline")
			MobMutation.Kind.POISON:
				check(mob.contact_status is PoisonEffect and is_equal_approx(mob.contact_status_chance, 1.0), "Poison: always poisons on hit")
				check(is_equal_approx(mat.get_shader_parameter("outline_width"), 2.0), "Poison: thick outline")
			MobMutation.Kind.BLEED:
				check(mob.contact_status is BleedEffect and is_equal_approx(mob.contact_status_chance, 1.0), "Bleed: always bleeds on hit")
			MobMutation.Kind.SPLIT:
				check(mat.get_shader_parameter("mode") == MobMutation.OutlineMode.PULSE and mat.get_shader_parameter("outline_color") == Color(1, 1, 1),
					"Split: pulsing white outline")
		mob.queue_free()
		await process_frame
	var plain = await spawn_slime(stage)
	check(plain.mutation == MobMutation.Kind.NONE and plain.sprite.material == null and plain.reward_gold() == plain.drop_gold_amount,
		"Normal mobs keep their look and gold")
	plain.queue_free()
	print("Kinds: tough/swift/poison/bleed/split stats, outlines, 3x gold")

# 출혈 변이체는 한 대에 바로 터지고, 독 변이체는 반드시 독을 건다
func check_bleed_and_poison_hits(stage) -> void:
	var player = stage.player
	var hurtbox = player.get_node("Hurtbox")
	var mob = await spawn_slime(stage)
	mob.apply_mutation(MobMutation.Kind.BLEED)
	player.hp = 100
	player.reset_combat_state()
	mob._apply_contact_damage_once(hurtbox)
	var bleed_left = player.get_status_effects().get_effects().filter(func(e): return e is BleedEffect)
	check(player.hp < 100 - mob.contact_damage and bleed_left.is_empty(), "Bleed mutant: one hit should burst immediately (hp %d)" % player.hp)
	mob.queue_free()
	player.clear_status_effects()
	player.hp = 100
	player.reset_combat_state()
	var poisoner = await spawn_slime(stage)
	poisoner.apply_mutation(MobMutation.Kind.POISON)
	poisoner._apply_contact_damage_once(hurtbox)
	check(player.get_status_effects().get_effects().any(func(e): return e is PoisonEffect), "Poison mutant: a hit should always poison")
	player.clear_status_effects()
	player.hp = 100
	player.reset_combat_state()
	poisoner.queue_free()
	await process_frame
	print("Hits: bleed bursts at once, poison always applies")

func check_split(stage) -> void:
	var mob = await spawn_slime(stage)
	mob.apply_mutation(MobMutation.Kind.SPLIT)
	var parent_hp: int = mob.max_hp_base
	mob.receive_hit(HitData.new(9999))
	await process_frame
	await process_frame
	var minions: Array = stage.get_node("Entities").get_children().filter(func(n): return _is_mob(n) and n.is_split_minion)
	check(minions.size() == 3, "Split mutant should split into 3 slimes, got %d" % minions.size())
	for m in minions:
		check(m.max_hp == maxi(1, parent_hp / 3) and m.scale.is_equal_approx(Vector2.ONE * 0.6) and m._active and m.mutation == MobMutation.Kind.NONE,
			"Split slimes should be small, weak, active and never mutate")
	if not minions.is_empty():
		var m = minions[0]
		m.receive_hit(HitData.new(9999))
		await process_frame
		check(not gm().defeated_mobs.has(m.get_persist_id()), "Split slimes should not be saved as defeated")
		var m2 = minions[1]
		m2.set_active(false)
		await process_frame
		check(not is_instance_valid(m2), "Split slimes should vanish when their room deactivates")
	for n in stage.get_node("Entities").get_children():
		if _is_mob(n):
			n.queue_free()
	await create_timer(0.3).timeout
	print("Split: 3 small slimes, not saved, gone when room deactivates")

# 보상 상자가 나오는 몹 id를 찾아 그 몹으로 잡는다 (5%)
func _chest_mob_id() -> String:
	for i in 1000:
		var id := "M-chest%d" % i
		if MobMutation.rolls_chest(gm().make_loot_rng(MobMutation.chest_key(id, gm().mutation_epoch))):
			return id
	return ""

func check_reward_chest(stage) -> void:
	var hits := 0
	for i in 4000:
		if MobMutation.rolls_chest(gm().make_loot_rng(MobMutation.chest_key("M-rate%d" % i, 0))):
			hits += 1
	check(hits > 4000 * 0.035 and hits < 4000 * 0.065, "Reward chest chance should be about 5%%, got %d/4000" % hits)
	var id := _chest_mob_id()
	var mob = await spawn_slime(stage)
	mob.persist_id = StringName(id)
	mob.apply_mutation(MobMutation.Kind.TOUGH)
	var ground: Vector2 = mob._ground_point()
	mob.receive_hit(HitData.new(9999))
	await process_frame
	await process_frame
	var chest_id := "mutant:%s:%d" % [id, gm().mutation_epoch]
	var chests: Array = stage.get_node("Entities").get_children().filter(func(n): return _is_chest(n) and n.persist_id == chest_id)
	check(chests.size() == 1, "A lucky mutant kill should drop a reward chest")
	if not chests.is_empty():
		check(chests[0].global_position.is_equal_approx(ground), "Reward chest should sit on the ground where the mutant died")
		check(chests[0].loot_table == load("res://resources/loot/mutant_chest.tres"), "Reward chest should use the mutant loot table")
	check(gm().mutant_chests.get(stage.scene_file_path, {}).has(chest_id), "Reward chest should be remembered until the next reroll")
	await create_timer(0.3).timeout
	print("Reward chest: ~5%, dropped on the ground, remembered")

func check_chest_restored_on_reload() -> void:
	var stage = await open_stage()
	var restored: Array = stage.get_node("Entities").get_children().filter(func(n): return _is_chest(n) and str(n.persist_id).begins_with("mutant:"))
	check(restored.size() == 1, "Reopening the scene should bring back the unopened reward chest")
	stage.queue_free()
	await process_frame
	gm().reset_mobs()
	stage = await open_stage()
	restored = stage.get_node("Entities").get_children().filter(func(n): return _is_chest(n) and str(n.persist_id).begins_with("mutant:"))
	check(restored.is_empty(), "After a reroll the reward chest should be gone")
	stage.queue_free()
	await process_frame
	print("Reload: chest kept until reroll")

func check_save_format() -> void:
	var saver = root.get_node("SaveManager")
	gm().reset_data()
	gm().mutation_epoch = 4
	gm().add_mutant_chest("res://Scenes/Stage/Stage_03.tscn", "mutant:M-a:4", Vector2(10, 20))
	var data: Dictionary = JSON.parse_string(JSON.stringify(gm().get_data_for_save()))
	check(saver._is_valid_game(data), "Save with mutation epoch and chests should be valid")
	gm().reset_data()
	gm().load_data_from_save(data)
	check(gm().mutation_epoch == 4 and gm().mutant_chests.get("res://Scenes/Stage/Stage_03.tscn", {}).has("mutant:M-a:4"),
		"Mutation epoch and chests should load back")
	var bad := data.duplicate(true)
	bad["mutant_chests"] = {"res://x.tscn": {"c": "oops"}}
	check(not saver._is_valid_game(bad), "Broken mutant chest data should be rejected")
	bad = data.duplicate(true)
	bad["mutation_epoch"] = -1
	check(not saver._is_valid_game(bad), "Negative mutation epoch should be rejected")
	var old := data.duplicate(true)
	old.erase("mutation_epoch")
	old.erase("mutant_chests")
	check(saver._is_valid_game(old), "Old saves without mutation fields should still load")
	print("Save: epoch and chests saved, validated, old saves ok")
