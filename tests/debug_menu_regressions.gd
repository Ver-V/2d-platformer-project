extends SceneTree
# Run with Godot --headless --path . --script res://tests/debug_menu_regressions.gd
# 개발용 바로 가기(DebugMenu): 스테이지마다 시작 지점·세이브 포인트·보스 위치를 읽고, 프리셋을 적용해 그 자리에서 시작한다.
# 저장은 디버그 파일로만 간다. 늑대 아레나에서 늑대가 실제로 싸운다.

var failures: int = 0

func _initialize() -> void:
	call_deferred("run_checks")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func gm() -> Node: return root.get_node("GameManager")

func run_checks() -> void:
	check_jump_points()
	check_preset()
	await check_wolf_arena()
	await check_menu_builds()
	gm().reset_data()
	gm().save_path_override = ""
	print("Debug menu regression checks: ", "PASS" if failures == 0 else "FAIL", " (", failures, " failures)")
	quit(0 if failures == 0 else 1)

func _labels(points: Array) -> Array:
	return points.map(func(p): return p.label)

func check_jump_points() -> void:
	for stage in DebugMenu.STAGES:
		var points := DebugMenu.jump_points(stage[1])
		check(not points.is_empty() and _labels(points).has("시작 지점"), "%s should list its start point" % stage[0])
	var st1 := _labels(DebugMenu.jump_points("res://Scenes/Stage/Stage_01.tscn"))
	var st2 := _labels(DebugMenu.jump_points("res://Scenes/Stage/Stage_02.tscn"))
	check(st1.any(func(l): return l.begins_with("보스:")), "Stage_01 should list its boss (got %s)" % [st1])
	check(st2.any(func(l): return l.begins_with("보스:")), "Stage_02 should list its boss (got %s)" % [st2])
	check(st2.filter(func(l): return l.begins_with("세이브:")).size() >= 2, "Stage_02 should list its save points")

func check_preset() -> void:
	DebugMenu.apply_preset("res://Scenes/Stage/Stage_02.tscn", Vector2(10, 20), {
		"heavy_attack": true, "double_jump": true, "full_moon": true, "damage": 25, "flasks": 3, "gold": 500,
		"items": ["lantern"], "skip_tutorials": ["TUTORIAL_DEATH"],
	})
	check(gm().current_save_path() == DebugMenu.DEBUG_SAVE_PATH, "Debug runs must save only to the debug file")
	check(gm().has_checkpoint and gm().last_scene_path == "res://Scenes/Stage/Stage_02.tscn" and gm().last_checkpoint_pos == Vector2(10, 20),
		"The jump point should become the checkpoint (respawn there)")
	check(gm().heavy_attack_unlocked and gm().double_jump_unlocked and gm().player_damage == 25 and gm().flask_max_charges == 3
		and gm().flask_current_charges == 3 and gm().gold == 500, "Preset stats should apply")
	check(gm().is_moonlit(MoonPhase.Phase.FULL), "Full moon preset should open the hatch on a full moon")
	check(root.get_node("Inventory").has_item("lantern") and gm().has_seen_tutorial("TUTORIAL_DEATH"), "Preset items and skipped tutorials should apply")
	check(DebugMenu._all_tutorial_keys().has("TUTORIAL_DEATH"), "All tutorial keys should be read from ui.csv")

func check_wolf_arena() -> void:
	const ARENA := "res://Scenes/Debug/WolfArena.tscn"
	DebugMenu.apply_preset(ARENA, DebugMenu.jump_points(ARENA)[0].pos, {"skip_tutorials": DebugMenu._all_tutorial_keys()})
	change_scene_to_file(ARENA)
	for i in 10:
		await physics_frame
	var stage = current_scene
	check(stage != null and stage.has_method("spawn_player") and is_instance_valid(stage.player), "The wolf arena should spawn the player")
	var wolf = stage.get_node_or_null("Entities/WolfBoss")
	check(wolf != null and not wolf.dormant and not wolf.disguised, "The arena wolf should be awake (no full moon needed) and skip the intro")
	for i in 6:
		await create_timer(0.5).timeout
		stage.player.hp = 100
		gm().player_current_hp = 100
	check(wolf.current_state == wolf.State.COMBAT and wolf._loop_running, "The arena wolf should fight")
	change_scene_to_file("res://Scenes/Debug/DebugMenu.tscn")
	await process_frame
	await process_frame

func check_menu_builds() -> void:
	var menu = current_scene
	check(menu is DebugMenu, "The debug menu scene should load")
	var buttons := menu.find_children("*", "Button", true, false).filter(func(b): return not b is CheckBox)
	check(buttons.size() >= 8, "The debug menu should show jump buttons (got %d)" % buttons.size())
