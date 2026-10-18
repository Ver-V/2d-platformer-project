extends SceneTree
# Run with Godot --headless --path . --script res://tests/progression_regressions.gd
# 달 상자(MoonChest), 반사탄 처치 보너스 금화, 가시에 밀린 적 즉사, 양 울음으로 적도 잠듦, 보름달 보스 재도전,
# 보스 노히트, 몬스터 도감(처치 기록·씬에서 읽는 스탯), 사인 기록(해골)과 새 세이브 항목 검증. 저장 파일은 건드리지 않는다.

var failures: int = 0
var fixture: Node2D

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
	await check_moon_chest()
	await check_reflect_bonus()
	check_spike_kill_rule()
	await check_sheep_sleeps_enemies()
	await check_rematch_and_nohit()
	await check_bestiary()
	check_death_cause_and_save()
	await check_minimap_death_tooltip()
	current_scene = null
	fixture.queue_free()
	await process_frame
	gm().reset_data()
	print("Progression regression checks: ", "PASS" if failures == 0 else "FAIL", " (", failures, " failures)")
	quit(0 if failures == 0 else 1)

func frames(n: int) -> void:
	for i in n:
		await physics_frame

# 그믐달(기본) + 해치 열림일 때만 보이고 열 수 있다. 달이 바뀌면 사라진다
func check_moon_chest() -> void:
	gm().reset_data()
	gm().mutation_epoch = 2 # 그믐달
	gm().moon_passage_open = false
	var chest = load("res://Scenes/System/MoonChest.tscn").instantiate()
	chest.persist_id = "C-moontest"
	fixture.add_child(chest)
	await process_frame
	check("is_present" in chest and not chest.is_present and not chest.visible, "A moon chest should be hidden while the hatch is closed")
	gm().set_moon_passage(true)
	await process_frame
	check(chest.is_present and chest.is_in_group("minimap_chest"), "A new-moon chest should appear on a moonlit new moon")
	chest.current_player = null
	gm().mutation_epoch = 3 # 보름달
	gm().moon_changed.emit()
	await process_frame
	check(not chest.is_present and not chest._can_interact(), "Changing the moon should hide it again")
	chest.queue_free()
	gm().reset_data()

# 자기 탄이 반사돼 쓰러진 원거리 몹은 금화를 10 더 떨어뜨린다
func check_reflect_bonus() -> void:
	gm().reset_data()
	var rat = load("res://Scenes/Entitites/rat_blue.tscn").instantiate()
	fixture.add_child(rat)
	rat.set_active(true)
	await frames(2)
	var normal_gold: int = rat.reward_gold()
	var shot: Projectile = load("res://Scenes/Projectile/projectilefire.tscn").instantiate()
	shot.shooter = rat
	shot.is_parryable = true
	shot.damage = 999
	fixture.add_child(shot)
	shot.set_physics_process(false)
	shot.attempt_parry(rat.global_position + Vector2(-40, 0))
	var coins_before := _coin_total()
	shot.hit_target(rat)
	await process_frame
	await process_frame
	check(rat.hp <= 0, "Setup: the reflected shot should kill the blue rat")
	check(_coin_total() - coins_before == normal_gold + rat.reflect_kill_bonus_gold and rat.reflect_kill_bonus_gold == 10,
		"A ranged mob killed by its own shot should drop 10 more gold (dropped %d, normal %d)" % [_coin_total() - coins_before, normal_gold])
	for n in fixture.get_children():
		if "gold_amount" in n and "is_field_coin" in n:
			n.queue_free()
	gm().reset_data()

func _coin_total() -> int:
	var total := 0
	for n in fixture.get_children():
		if "gold_amount" in n and "is_field_coin" in n:
			total += int(n.gold_amount)
	return total

# 가시 끝 쪽 면에 부딪히면 즉사, 받침판 쪽이면 아니다
func check_spike_kill_rule() -> void:
	var layer: TileMapLayer = load("res://Scenes/Stage/HazardTileMap.tscn").instantiate()
	fixture.add_child(layer)
	layer.global_position = Vector2(-3000, 0)
	var V := TileSetAtlasSource.TRANSFORM_FLIP_V
	layer.set_cell(Vector2i(0, 0), 0, Vector2i(4, 0), V) # 바닥 가시 (위를 향함)
	var top := layer.to_global(layer.map_to_local(Vector2i(0, 0))) + Vector2(0, -8)
	check(EnemyBase.spike_kills(layer, top, Vector2.UP), "Landing on the points of floor spikes should kill a mob")
	var bottom := layer.to_global(layer.map_to_local(Vector2i(0, 0))) + Vector2(0, 8)
	check(not EnemyBase.spike_kills(layer, bottom, Vector2.DOWN), "Touching the base of the spikes should not kill")
	check(not EnemyBase.spike_kills(StaticBody2D.new(), top, Vector2.UP), "Normal ground should not kill")
	layer.queue_free()

# 우는 양의 범위 안 적(다른 양 포함, 자기 자신 제외)도 졸음이 차서 잠든다. 잠든 몹은 몸통 피해를 주지 않고, 맞으면 깬다
func check_sheep_sleeps_enemies() -> void:
	gm().reset_data()
	var sheep = load("res://Scenes/Entitites/sheep.tscn").instantiate()
	var other = load("res://Scenes/Entitites/sheep.tscn").instantiate()
	var rat = load("res://Scenes/Entitites/rat.tscn").instantiate()
	var far_rat = load("res://Scenes/Entitites/rat.tscn").instantiate()
	for n in [sheep, other, rat, far_rat]:
		fixture.add_child(n)
	sheep.global_position = Vector2(500, 0)
	other.global_position = Vector2(530, 0)
	rat.global_position = Vector2(470, 0)
	far_rat.global_position = Vector2(2000, 0)
	for n in [sheep, other, rat, far_rat]:
		n.set_active(true)
	await frames(2)
	check(sheep.in_bleat_range(rat.global_position) and not sheep.in_bleat_range(far_rat.global_position), "Bleat range should use the BleatArea shape")
	for i in 6:
		sheep._expose_players(1.0) # 초당 20 → 5초면 잠든다
	check(rat.is_asleep() and other.is_asleep(), "A bleating sheep should put nearby enemies and other sheep to sleep")
	check(not sheep.is_asleep() and not far_rat.is_asleep(), "The bleating sheep itself and enemies out of range should stay awake")
	HitData.deliver(rat, HitData.new(1, Vector2.ZERO, null))
	check(not rat.is_asleep(), "A sleeping mob should wake up when hit")
	for n in [sheep, other, rat, far_rat]:
		n.queue_free()
	await process_frame
	gm().reset_data()

# 잡은 보스는 해치 열린 보름달에 강해져서 다시 나온다 (이번 보름달에 이기면 끝). 노히트는 전투 중 체력이 안 줄면
func check_rematch_and_nohit() -> void:
	gm().reset_data()
	var scene: PackedScene = load("res://Scenes/Entitites/boss_stage_2.tscn")
	var probe = scene.instantiate()
	var id: String = str(probe.persist_id)
	var base_hp: int = probe.max_hp_base
	probe.free()
	gm().defeated_bosses[id] = true
	gm().mutation_epoch = 0 # 보름달
	gm().moon_passage_open = false
	check(not gm().can_rematch(id), "No rematch without moonlight")
	gm().moon_passage_open = true
	check(gm().can_rematch(id), "A defeated boss can be rematched on a moonlit full moon")
	var boss = scene.instantiate()
	fixture.add_child(boss)
	await process_frame
	check(is_instance_valid(boss) and not boss.is_queued_for_deletion() and boss.is_rematch, "The defeated boss should come back for the rematch")
	var want_hp := roundi(roundi(base_hp * 1.4) * boss.rematch_stat_mult)
	check(boss.max_hp == want_hp and is_equal_approx(boss.moon_damage_mult, 1.4 * boss.rematch_stat_mult),
		"Rematch should be stronger than the moonlit boss (hp %d, want %d, dmg x%.2f)" % [boss.max_hp, want_hp, boss.moon_damage_mult])
	check(is_equal_approx(boss.idle_cut(), 0.5), "Rematch should cut 0.5s of idle time")
	# 노히트
	boss.boss_started = true
	boss._player_hit = false
	boss._last_player_hp = 100
	gm().hp_changed.emit(100, 100)
	check(boss.is_nohit_so_far(), "No damage so far = still no-hit")
	gm().hp_changed.emit(80, 100)
	check(not boss.is_nohit_so_far(), "Taking damage should break the no-hit")
	gm().record_rematch_win(id)
	check(not gm().can_rematch(id), "After winning the rematch it should not return until the next full moon")
	gm().mutation_epoch = 3
	check(gm().can_rematch(id), "The next full moon brings the rematch back")
	boss.queue_free()
	await process_frame
	gm().reset_data()

# 처치가 도감에 쌓이고, 도감은 씬에서 스탯을 읽는다
func check_bestiary() -> void:
	gm().reset_data()
	for kind in Bestiary.KINDS:
		check(ResourceLoader.exists(Bestiary.kind_path(kind)), "Bestiary kind %s should exist" % kind)
		check(TranslationServer.translate(Bestiary.name_key(Bestiary.kind_path(kind))) != String(Bestiary.name_key(Bestiary.kind_path(kind))),
			"Bestiary kind %s should have a name in ui.csv" % kind)
	var info := Bestiary.info(Bestiary.kind_path("rat_red"))
	check(info.hp == 60 and info.damage == 15 and info.status == &"bleed" and is_equal_approx(info.status_chance, 1.0), "Bestiary should read red rat stats from its scene (%s)" % [info])
	var boss_info := Bestiary.info(Bestiary.kind_path("boss_stage_2"))
	check(boss_info.is_boss and String(boss_info.reward) != "", "Boss entries should show their reward item")
	var rat = load("res://Scenes/Entitites/rat.tscn").instantiate()
	fixture.add_child(rat)
	rat.set_active(true)
	await frames(1)
	HitData.deliver(rat, HitData.new(999, Vector2.ZERO, null))
	check(gm().kill_count("res://Scenes/Entitites/rat.tscn") == 1, "Killing a mob should record it in the bestiary")
	gm().reset_data()

func check_death_cause_and_save() -> void:
	gm().reset_data()
	var rat = load("res://Scenes/Entitites/rat_red.tscn").instantiate()
	fixture.add_child(rat)
	check(DeathCause.of_source(rat) == "enemy:res://Scenes/Entitites/rat_red.tscn", "An enemy hit should record the enemy kind")
	var shot := Projectile.new()
	shot.shooter = rat
	check(DeathCause.of_source(shot) == "enemy:res://Scenes/Entitites/rat_red.tscn", "A projectile should record its shooter")
	check(DeathCause.describe("status:poison") == TranslationServer.translate(&"CAUSE_STATUS_POISON"), "Status causes should read as the status name")
	check(DeathCause.describe("enemy:res://Scenes/Entitites/rat_red.tscn") == Bestiary.display_name("res://Scenes/Entitites/rat_red.tscn"), "Enemy causes should read as the enemy name")
	shot.free()
	rat.queue_free()
	gm().gold = 100
	gm().on_player_died("res://x.tscn", Vector2(1, 2), "spikes")
	var drop: Dictionary = gm().death_drops["res://x.tscn"].values()[0]
	check(drop.get("cause") == "spikes", "A death drop should remember the cause")
	gm().bestiary["res://Scenes/Entitites/rat.tscn"] = 3
	gm().nohit_bosses["bosss2"] = true
	gm().rematch_epochs["bosss2"] = 3
	var data: Dictionary = JSON.parse_string(JSON.stringify(gm().get_data_for_save()))
	var saver = root.get_node("SaveManager")
	check(saver._is_valid_game(data), "Saves with bestiary / no-hit / rematch / death cause should be valid")
	data["bestiary"] = {"res://x.tscn": "many"}
	check(not saver._is_valid_game(data), "A broken bestiary entry should be rejected")
	gm().reset_data()

# 미니맵을 열면 조작은 그대로 두고 커서만 보인다. 해골 표시에 마우스를 올리면 사인과 금화가 뜬다
func check_minimap_death_tooltip() -> void:
	gm().reset_data()
	var holder := Node.new()
	fixture.add_child(holder)
	gm().request_cursor(holder, true)
	check(not gm().is_menu_open, "Showing the cursor for the minimap must not lock player control")
	gm().request_cursor(holder, false)
	holder.queue_free()
	var drop = load("res://Script/System/death_drop.gd").new()
	drop.setup("res://x.tscn", "drop_0", 120, "enemy:res://Scenes/Entitites/rat_red.tscn")
	fixture.add_child(drop)
	drop.global_position = Vector2(100, 50)
	var minimap = load("res://Script/Item_UI/minimap_ui.gd").new()
	minimap.current_scene_path = "res://x.tscn"
	gm().visit_room("res://x.tscn", minimap._room_from_world(drop.global_position))
	fixture.add_child(minimap)
	var center := Vector2(100, 60)
	var origin := Vector2.ZERO
	var marker: Vector2 = center + (drop.global_position - origin) * minimap.MAP_SCALE
	check(minimap.hovered_death_drop(marker + Vector2(2, 2), center, origin) == drop, "Hovering a skull marker should find its death drop")
	check(minimap.hovered_death_drop(marker + Vector2(40, 0), center, origin) == null, "Hovering away from it should not")
	var text: String = minimap.death_tooltip_text(drop)
	check(text.contains(Bestiary.display_name("res://Scenes/Entitites/rat_red.tscn")) and text.contains("120"), "The tooltip should show the cause and the gold (%s)" % text)
	minimap.queue_free()
	drop.queue_free()
	await process_frame
