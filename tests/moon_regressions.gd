extends SceneTree
# Run with Godot --headless --path . --script res://tests/moon_regressions.gd
# 달의 위상(MoonPhase)과 지상 달빛 통로: 위상 순환, 통로 닫힘 = 효과 없음, 세이브, 적 체력·피해 배율,
# 양의 광기, 위상별 벽(MoonGate), 보름달에만 깨어나는 늑대, 지상 스테이지. 저장 파일은 건드리지 않는다.

var failures: int = 0

const SLIME := "res://Scenes/Entitites/slime_1.tscn"
const SHEEP := "res://Scenes/Entitites/sheep.tscn"
const WOLF := "res://Scenes/Entitites/boss_wolf.tscn"
const GATE := "res://Scenes/System/MoonGate.tscn"
const STAGE := "res://Scenes/Stage/Stage_03.tscn"
const SURFACE := "res://Scenes/Stage/Stage_Surface.tscn"

func gm() -> Node: return root.get_node("GameManager")

# 투사체처럼 shooter만 가진 노드
class FakeShot extends Node2D:
	var shooter: Node2D = null

func _initialize() -> void:
	call_deferred("run_checks")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func run_checks() -> void:
	gm().reset_data()
	check_phase_cycle()
	check_effects_need_passage()
	check_save_format()
	await check_enemy_stats_and_damage()
	await check_sheep_madness()
	await check_moon_gate()
	await check_wolf_waits_for_full_moon()
	await check_surface_stage()
	await check_moon_icon()
	gm().reset_data()
	print("Moon regression checks: ", "PASS" if failures == 0 else "FAIL", " (", failures, " failures)")
	quit(0 if failures == 0 else 1)

# 위상을 정한다: 회차를 그 위상이 나오는 값으로 맞춘다
func set_moon(phase: MoonPhase.Phase, open: bool) -> void:
	gm().mutation_epoch = MoonPhase.CYCLE.find(phase)
	gm().set_moon_passage(open)
	gm().moon_changed.emit()

func check_phase_cycle() -> void:
	gm().reset_data()
	check(gm().moon_phase() == MoonPhase.Phase.FULL, "New game should start on a full moon")
	var seen := []
	for i in 4:
		seen.append(gm().moon_phase())
		gm().reset_mobs()
	check(seen == [MoonPhase.Phase.FULL, MoonPhase.Phase.HALF, MoonPhase.Phase.NEW, MoonPhase.Phase.FULL],
		"Each rest should move full -> half -> new -> full, got %s" % str(seen))
	gm().reset_data()
	print("Cycle: full -> half -> new per rest")

func check_effects_need_passage() -> void:
	for phase in MoonPhase.CYCLE:
		for key in MoonPhase.DEFAULTS:
			check(MoonPhase.effect(phase, false, key) == MoonPhase.DEFAULTS[key], "Closed passage should give the default %s" % key)
			check(MoonPhase.effect(phase, true, key) == MoonPhase.EFFECTS[phase].get(key, MoonPhase.DEFAULTS[key]),
				"Open passage should give the table value of %s" % key)
	check(MoonPhase.DEFAULTS["mutation_chance"] == MobMutation.CHANCE, "Without moonlight the mutation chance is the old one")
	print("Effects: only with the passage open")

func check_save_format() -> void:
	var saver = root.get_node("SaveManager")
	gm().reset_data()
	gm().set_moon_passage(true)
	gm().mutation_epoch = 2
	var data: Dictionary = JSON.parse_string(JSON.stringify(gm().get_data_for_save()))
	check(saver._is_valid_game(data) and data.get("moon_passage") == true, "Save should keep the open passage")
	gm().reset_data()
	check(not gm().moon_passage_open, "New game should close the passage")
	gm().load_data_from_save(data)
	check(gm().moon_passage_open and gm().moon_phase() == MoonPhase.Phase.NEW, "Passage and phase should load back")
	var bad := data.duplicate(true)
	bad["moon_passage"] = "yes"
	check(not saver._is_valid_game(bad), "Non-bool moon_passage should be rejected")
	var old := data.duplicate(true)
	old.erase("moon_passage")
	check(saver._is_valid_game(old), "Old saves without moon_passage should load")
	gm().load_data_from_save(old)
	check(not gm().moon_passage_open, "Old saves start with the passage closed")
	gm().reset_data()
	print("Save: moon_passage saved, validated, old saves ok")

func open_stage():
	var stage = load(STAGE).instantiate()
	root.add_child(stage)
	current_scene = stage
	await process_frame
	return stage

func spawn(stage, path: String, offset := Vector2(80, -10)):
	var mob = load(path).instantiate()
	mob.mutation_enabled = false
	mob.coin_scene = null
	mob.position = stage.player.global_position + offset
	stage.get_node("Entities").add_child(mob)
	stage.register_spawned_enemy(mob)
	await process_frame
	return mob

func check_enemy_stats_and_damage() -> void:
	set_moon(MoonPhase.Phase.FULL, false)
	var stage = await open_stage()
	var plain = await spawn(stage, SLIME)
	check(plain.max_hp == plain.max_hp_base and is_equal_approx(plain.moon_damage_mult, 1.0), "Closed passage: normal stats")

	for phase in MoonPhase.CYCLE:
		set_moon(phase, true)
		var mob = await spawn(stage, SLIME)
		var hp_mult: float = MoonPhase.EFFECTS[phase]["mob_hp"]
		var dmg_mult: float = MoonPhase.EFFECTS[phase]["mob_damage"]
		check(mob.max_hp == maxi(1, roundi(mob.max_hp_base * hp_mult)) and mob.hp == mob.max_hp,
			"Phase %d: enemy HP should be base x %.2f" % [phase, hp_mult])
		check(is_equal_approx(mob.moon_damage_mult, dmg_mult), "Phase %d: damage mult should be %.2f" % [phase, dmg_mult])

		var player = stage.player
		player.reset_combat_state()
		player.hp = player.max_hp
		var before: int = player.hp
		player.receive_hit(HitData.new(20, Vector2.ZERO, mob))
		check(before - player.hp == maxi(1, roundi(20 * dmg_mult)), "Phase %d: a 20 hit should deal %d" % [phase, roundi(20 * dmg_mult)])
		mob.queue_free()
		await process_frame

	# 투사체는 쏜 몹의 배율을 따른다
	set_moon(MoonPhase.Phase.FULL, true)
	var shooter = await spawn(stage, SLIME)
	var fake_projectile := FakeShot.new()
	fake_projectile.shooter = shooter
	check(is_equal_approx(MoonPhase.damage_mult_from(fake_projectile), shooter.moon_damage_mult), "Projectiles use the shooter's moon mult")
	fake_projectile.free()
	check(is_equal_approx(MoonPhase.damage_mult_from(null), 1.0), "No source: no moon mult")
	stage.queue_free()
	await process_frame
	gm().reset_data()
	print("Enemies: HP/damage follow the phase only with moonlight")

func check_sheep_madness() -> void:
	gm().reset_data()
	var stage = await open_stage()
	var sheep = await spawn(stage, SHEEP)
	set_moon(MoonPhase.Phase.FULL, false)
	check(is_equal_approx(sheep.effective_charge_chance(), sheep.charge_chance), "Without moonlight sheep keep their charge chance")
	set_moon(MoonPhase.Phase.FULL, true)
	check(is_equal_approx(sheep.effective_charge_chance(), 1.0), "Full moon: sheep always charge")
	set_moon(MoonPhase.Phase.NEW, true)
	check(is_equal_approx(sheep.effective_charge_chance(), sheep.charge_chance), "New moon: sheep calm")
	stage.queue_free()
	await process_frame
	gm().reset_data()
	print("Sheep: maddened by the full moon")

func check_moon_gate() -> void:
	gm().reset_data()
	var holder := Node2D.new()
	root.add_child(holder)
	var gate = load(GATE).instantiate()
	gate.open_on_full = false
	gate.open_on_new = true
	holder.add_child(gate)
	await physics_frame
	var shape: CollisionShape2D = gate.get_node("CollisionShape2D")
	check(not gate.is_open and not shape.disabled, "Gate starts closed (passage closed)")
	set_moon(MoonPhase.Phase.NEW, false)
	await physics_frame
	check(not gate.is_open, "requires_passage: a new moon without moonlight keeps it shut")
	set_moon(MoonPhase.Phase.NEW, true)
	await physics_frame
	check(gate.is_open and shape.disabled, "New moon + open passage should open a new-moon gate")
	set_moon(MoonPhase.Phase.FULL, true)
	await physics_frame
	check(not gate.is_open and not shape.disabled, "Full moon should close a new-moon-only gate again")
	gate.requires_passage = false
	set_moon(MoonPhase.Phase.NEW, false)
	await physics_frame
	check(gate.is_open, "Without requires_passage the phase alone opens it")
	holder.queue_free()
	await process_frame
	gm().reset_data()
	print("MoonGate: opens only on its phases")

func check_wolf_waits_for_full_moon() -> void:
	gm().reset_data()
	var holder := Node2D.new()
	root.add_child(holder)
	var wolf = load(WOLF).instantiate()
	wolf.persist_id = &"test_moon_wolf"
	wolf.save_after_intro = false
	holder.add_child(wolf)
	await process_frame
	check(wolf.dormant and wolf.disguised, "Closed passage: the wolf stays a sheep")
	wolf.set_active(true)
	check(not wolf._active and not wolf.boss_started, "A dormant wolf should not wake when the room activates")
	set_moon(MoonPhase.Phase.HALF, true)
	check(wolf.dormant, "Half moon: still dormant")
	set_moon(MoonPhase.Phase.FULL, true)
	check(not wolf.dormant and wolf.disguised, "Full moon + open passage: ready to reveal itself (intro not seen yet)")
	holder.queue_free()
	await process_frame
	gm().reset_data()
	print("Wolf: wakes only on a moonlit full moon")

func check_surface_stage() -> void:
	gm().reset_data()
	var stage = load(SURFACE).instantiate()
	root.add_child(stage)
	current_scene = stage
	await process_frame
	check(stage.player != null, "Surface stage should spawn the player")
	check(stage.get_node_or_null("Entities/ElevatorBlock") != null, "Surface stage should have the elevator")
	var passage = stage.get_node_or_null("Entities/MoonPassage")
	check(passage != null, "Surface stage should have the moon passage")
	if passage != null:
		passage.set_open(true)
		check(gm().moon_passage_open, "Opening the passage should set GameManager.moon_passage_open")
		passage.set_open(false)
		check(not gm().moon_passage_open, "Closing it should clear it")
	stage.queue_free()
	await process_frame
	gm().reset_data()
	print("Surface: stage loads, passage toggles")

# HUD 달 아이콘은 통로가 열려 있을 때만 보인다
func check_moon_icon() -> void:
	gm().reset_data()
	var icon := MoonIcon.new()
	root.add_child(icon)
	await process_frame
	check(not icon.visible, "Moon icon should be hidden while the passage is closed")
	gm().set_moon_passage(true)
	check(icon.visible, "Moon icon should show once the passage opens")
	gm().set_moon_passage(false)
	check(not icon.visible, "Moon icon should hide again when the passage closes")
	icon.queue_free()
	await process_frame
	gm().reset_data()
	print("Moon icon: only while the passage is open")
