extends SceneTree
# Run with Godot --headless --path . --script res://tests/stage02_regressions.gd
# 스테이지 기믹(시야 제한, 어둠 속 눈, 무너지는 블록)과 몹 동작(순찰 멈춤, 피격 스쿼시, 사망 뒤집기), 저장 ID 검사. 저장 파일은 건드리지 않는다.

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
	await check_vision_limit()
	await check_crumbling_block()
	check_glow_eyes()
	check_patrol_idle()
	check_hit_squash_and_death_flip()
	check_persist_ids()
	fixture.queue_free()
	await process_frame
	print("Stage02 regression checks: ", "PASS" if failures == 0 else "FAIL", " (", failures, " failures)")
	quit(0 if failures == 0 else 1)

func wait(seconds: float) -> void:
	await create_timer(seconds).timeout

func make_player_stub(pos: Vector2) -> CharacterBody2D:
	var body := CharacterBody2D.new()
	body.add_to_group("player")
	body.collision_layer = 2
	body.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(10, 14)
	shape.shape = rect
	body.add_child(shape)
	fixture.add_child(body)
	body.global_position = pos
	return body

func check_vision_limit() -> void:
	var vision := VisionLimit.new()
	vision.radius_tiles = 4.0
	check(is_equal_approx(vision.get_radius(), 64.0), "Vision radius should be 4 tiles = 64px")

	# 랜턴: 갖고 있으면 반지름이 넓어지고, 그리는 반지름은 서서히 따라간다. 잃으면 원래대로.
	var manager = root.get_node("GameManager")
	var lantern = manager.get_item_by_id("lantern")
	check(lantern != null and lantern.vision_bonus_tiles > 0.0, "Lantern item missing or has no vision bonus")
	var stock2 = load("res://resources/shops/Stage2.tres")
	check(stock2.entries.any(func(e): return e.item != null and e.item.id == "lantern"), "Stage2 merchant should sell the lantern")
	fixture.add_child(vision)
	if lantern != null:
		manager.add_item(lantern)
		manager.add_item(lantern) # 여러 개 있어도 겹쳐서 더하지 않는다
		var goal: float = (4.0 + lantern.vision_bonus_tiles) * 16.0
		check(is_equal_approx(vision.get_radius(), goal), "Lantern should widen the vision radius (not stacking)")
		vision._process(0.1)
		check(vision._shown_radius > 64.0 and vision._shown_radius < goal, "Vision radius should grow gradually")
		vision._process(10.0)
		check(is_equal_approx(vision._shown_radius, goal), "Vision radius should reach the lantern radius")
	for i in manager.inventory.size(): # 테스트로 넣은 랜턴만 치운다 (신호로 시야도 갱신)
		if manager.inventory[i] != null and manager.inventory[i] == lantern:
			manager.remove_item_at(i)
	check(is_equal_approx(vision.get_radius(), 64.0), "Vision radius should shrink back without the lantern")
	vision.free()

	var stage02 = load("res://Scenes/Stage/Stage_02.tscn").instantiate()
	check(is_equal_approx(stage02.vision_radius_tiles, 5.0), "Stage_02 should limit vision to 5 tiles")
	stage02.free()
	var stage01 = load("res://Scenes/Stage/Stage_01.tscn").instantiate()
	check(stage01.vision_radius_tiles <= 0.0, "Stage_01 should not limit vision")
	stage01.free()
	print("Vision: 5-tile radius on Stage_02 only, lantern widens it gradually")

const BLOCK_SCENE := preload("res://Scenes/System/CrumblingBlock.tscn")

func make_block(width: int, independent: bool) -> CrumblingBlock:
	var block: CrumblingBlock = BLOCK_SCENE.instantiate()
	block.width_tiles = width
	block.independent_tiles = independent
	block.crumble_delay = 0.05
	block.respawn_delay = 0.1
	fixture.add_child(block)
	block.global_position = Vector2(0, 200)
	return block

func states_of(block: CrumblingBlock) -> Array:
	return block.tile_states.map(func(s): return ["SOLID", "SHAKING", "BROKEN"][s])

func check_crumbling_block() -> void:
	# --- 한 덩어리 모드 (기본) ---
	var block := make_block(3, false)
	await physics_frame
	check(states_of(block) == ["SOLID", "SOLID", "SOLID"], "Block should start solid")

	# 아래에서 점프해 올라가며 스치는 경우는 무너지지 않는다
	var player := make_player_stub(Vector2(8, 180))
	player.velocity = Vector2(0, -200)
	block._try_step_on(player)
	check(states_of(block) == ["SOLID", "SOLID", "SOLID"], "Block crumbled from a rising jump")

	# 한 칸만 밟아도 전부 같이 흔들리고 무너진다
	player.velocity = Vector2.ZERO
	block._try_step_on(player)
	check(states_of(block) == ["SHAKING", "SHAKING", "SHAKING"], "Whole block did not shake together")
	await wait(0.1)
	await physics_frame
	check(states_of(block) == ["BROKEN", "BROKEN", "BROKEN"], "Whole block did not break after the delay")

	# 다시 생길 때 그 자리에 플레이어가 있으면 비켜날 때까지 기다린다
	player.global_position = Vector2(40, 208)
	await physics_frame
	await physics_frame
	await wait(0.2)
	check(states_of(block) == ["BROKEN", "BROKEN", "BROKEN"], "Block respawned inside the player")
	player.global_position = Vector2(40, 120)
	await physics_frame
	await physics_frame
	await wait(0.35)
	await physics_frame
	check(states_of(block) == ["SOLID", "SOLID", "SOLID"], "Block did not respawn after the player left")
	block.queue_free()

	# --- 칸마다 따로 모드 ---
	block = make_block(5, true)
	await physics_frame
	# 2번 칸 가운데에 선 플레이어 (폭 10px): 2번 칸만 무너진다
	player.global_position = Vector2(40, 192)
	block._try_step_on(player)
	check(states_of(block) == ["SOLID", "SOLID", "SHAKING", "SOLID", "SOLID"], "Independent mode should only shake the stepped tile")
	# 2·3번 칸 경계에 걸쳐 서면 둘 다 (이미 흔들리는 2번은 그대로, 3번이 새로 흔들린다)
	player.global_position = Vector2(48, 192)
	block._try_step_on(player)
	check(states_of(block) == ["SOLID", "SOLID", "SHAKING", "SHAKING", "SOLID"], "Standing across a tile border should shake both tiles")
	await wait(0.1)
	await physics_frame
	check(states_of(block) == ["SOLID", "SOLID", "BROKEN", "BROKEN", "SOLID"], "Independent tiles did not break")

	# 칸 수를 바꾸면 크기·충돌이 다시 만들어지고 모두 멀쩡해진다
	block.width_tiles = 2
	check(block.tile_states.size() == 2 and states_of(block) == ["SOLID", "SOLID"], "Changing width_tiles did not rebuild the tiles")
	check(is_equal_approx(block.detector_shape.shape.size.x, 30.0), "Detector did not resize with width_tiles")
	await wait(0.3)
	check(states_of(block) == ["SOLID", "SOLID"], "Old crumble timers touched the rebuilt block")

	block.queue_free()
	player.queue_free()
	await process_frame
	print("Crumbling block: whole/independent modes, rising jumps ignored, respawns only when clear, width rebuild")

# Slime은 GameManager autoload에 의존하므로 실행 중에 로드한다 (테스트 스크립트 컴파일 시점엔 autoload가 없음)
const SLIME_SCRIPT := "res://Script/Entity/slime.gd"

func check_glow_eyes() -> void:
	check(GlowEyes.Z_INDEX > VisionLimit.Z_INDEX, "Glow eyes should draw above the vision-limit darkness")

	var owner_body: CharacterBody2D = load(SLIME_SCRIPT).new()
	owner_body.hp = 10
	var body := AnimatedSprite2D.new()
	body.name = "AnimatedSprite2D"
	var frames := SpriteFrames.new()
	frames.add_animation(&"walk")
	for i in 4:
		frames.add_frame(&"walk", ImageTexture.create_from_image(Image.create(32, 32, false, Image.FORMAT_RGBA8)))
	frames.add_frame(&"default", ImageTexture.create_from_image(Image.create(32, 32, false, Image.FORMAT_RGBA8)))
	body.sprite_frames = frames
	body.animation = &"walk"
	owner_body.add_child(body)
	var eyes := GlowEyes.new()
	eyes.hframes = 4 # 128x32 눈 시트
	eyes.blink_interval = Vector2.ZERO # 무작위 깜빡임 제외
	owner_body.add_child(eyes)
	eyes._body = body
	eyes._owner_body = owner_body

	body.frame = 2
	body.position = Vector2(1, -1) # 걷기 중 위아래 흔들림 / 스쿼시 위치 보정
	body.scale = Vector2(1.2, 0.8)
	body.offset = Vector2(0, -16)
	body.flip_h = true
	eyes._process(0.016)
	check(eyes.visible, "Glow eyes should be visible on a living enemy")
	check(eyes.frame == 2, "Glow eyes should show the same sheet frame as the body")
	check(eyes.position == body.position and eyes.scale == body.scale and eyes.offset == body.offset and eyes.flip_h,
		"Glow eyes should copy the body's position, squash, offset and facing")

	eyes.synced_animations = [&"walk"]
	body.animation = &"default"
	body.frame = 0
	eyes.sync_fallback_frame = 3
	eyes._process(0.016)
	check(eyes.frame == 3, "Glow eyes should use the fallback frame on unsynced animations")

	body.visible = false
	eyes._process(0.016)
	check(not eyes.visible, "Glow eyes should follow the body's hit blink")
	body.visible = true
	owner_body.hp = 0
	eyes._process(0.016)
	check(not eyes.visible, "Glow eyes should turn off when the enemy dies")
	owner_body.free()
	print("Glow eyes: above darkness, frame/transform sync, blink, off on death")

func check_patrol_idle() -> void:
	var enemy = load(SLIME_SCRIPT).new()
	enemy.patrol_walk_time = Vector2(0.5, 0.5)
	enemy.patrol_idle_time = Vector2(0.3, 0.3)
	enemy.patrol_turn_chance = 1.0
	enemy.dir = -1
	enemy._reset_patrol_idle()

	check(not enemy.update_patrol_idle(0.4), "Patrol should keep walking during walk time")
	check(enemy.update_patrol_idle(0.2), "Patrol should stop to idle after walk time")
	check(enemy.update_patrol_idle(0.2), "Patrol should stay idle during idle time")
	check(not enemy.update_patrol_idle(0.2), "Patrol should resume walking after idle time")
	check(enemy.dir == 1, "Patrol should turn around after idle when turn chance hits")

	enemy.update_patrol_idle(0.6)
	check(enemy.is_patrol_idling(), "Patrol should be idling before a target appears")
	enemy.target = Node2D.new()
	check(not enemy.update_patrol_idle(0.016) and not enemy.is_patrol_idling(), "Spotting a target should cancel patrol idle")
	enemy.target.free()
	enemy.target = null

	enemy.patrol_idle_enabled = false
	check(not enemy.update_patrol_idle(10.0), "Disabled patrol idle should never stop")
	enemy.free()
	print("Patrol idle: walk -> idle -> walk, turn, cancel on target")

# 스프라이트 세로 범위(로컬)에 현재 scale/position을 적용했을 때 화면상 발끝 y
func _sprite_visual_bottom(spr: AnimatedSprite2D) -> float:
	var h := spr.sprite_frames.get_frame_texture(spr.animation, spr.frame).get_size().y
	var top := spr.offset.y - (h * 0.5 if spr.centered else 0.0)
	return spr.position.y + maxf(top * spr.scale.y, (top + h) * spr.scale.y)

func check_hit_squash_and_death_flip() -> void:
	var enemy = load(SLIME_SCRIPT).new()
	var spr := AnimatedSprite2D.new()
	var frames := SpriteFrames.new()
	frames.add_frame(&"default", ImageTexture.create_from_image(Image.create(16, 20, false, Image.FORMAT_RGBA8)))
	spr.sprite_frames = frames
	spr.offset = Vector2(0, -6) # 발끝이 원점에서 벗어난 경우도 검사
	spr.position = Vector2(2, 3)
	spr.scale = Vector2(2, 2)
	enemy.add_child(spr)
	enemy.sprite = spr
	enemy._sprite_base_scale = spr.scale
	enemy._sprite_base_pos = spr.position
	enemy.death_bounce_height = 14.0
	var ground := _sprite_visual_bottom(spr)

	enemy._apply_squash(Vector2(1.3, 0.7))
	check(spr.scale.is_equal_approx(Vector2(2.6, 1.4)), "Hit squash should flatten the sprite")
	check(is_equal_approx(_sprite_visual_bottom(spr), ground), "Hit squash should keep the feet on the ground")

	enemy._apply_death_flip(0.5)
	check(absf(_sprite_visual_bottom(spr) - (ground - 14.0)) < 0.01, "Death flip should bounce up mid-flip") # Godot은 scale 0을 0.00001로 보정한다
	enemy._apply_death_flip(1.0)
	check(is_equal_approx(spr.scale.y, -2.0) and is_equal_approx(spr.scale.x, 2.0), "Death flip should end upside down without mirroring")
	check(is_equal_approx(_sprite_visual_bottom(spr), ground), "Death flip should land back on the ground")

	enemy._reset_sprite_motion()
	check(spr.scale.is_equal_approx(Vector2(2, 2)) and spr.position.is_equal_approx(Vector2(2, 3)), "Reset should restore the sprite transform")
	check(enemy._can_play_sprite_motion(), "Normal mobs should play hit/death motion")
	enemy.add_to_group("bosses")
	check(not enemy._can_play_sprite_motion(), "Bosses should keep their own hit/death presentation")
	enemy.free()
	print("Hit squash / death flip: grounded squash, bounce, upside-down landing, bosses excluded")

# 몹·박스·상자·문 persist_id: 빈 칸 배정, 중복 시 뒤쪽 재발급, 기존 값 유지, 씬 루트 제외
func check_persist_ids() -> void:
	var root := Node2D.new()
	var box_scene = load("res://Scenes/System/BreakableBox.tscn")
	var a = box_scene.instantiate()
	var b = box_scene.instantiate()
	var c = load("res://Scenes/System/Chest.tscn").instantiate()
	var d = load("res://Scenes/System/KeyDoor.tscn").instantiate()
	var m = load("res://Scenes/Entitites/slime_1.tscn").instantiate()
	var plain := Node2D.new()
	for n in [a, b, c, d, m, plain]:
		root.add_child(n)
		n.owner = root
	a.persist_id = "B-keepme01"
	b.persist_id = "B-keepme01" # Ctrl+D 복제 상황
	var changed := PersistIdAssigner.assign(root)
	check(changed == 4, "Assigner should fill 3 empty IDs and fix 1 duplicate (changed %d)" % changed)
	check(a.persist_id == "B-keepme01", "Assigner should keep the first of duplicated IDs")
	check(b.persist_id != "B-keepme01" and b.persist_id.begins_with("B-"), "Assigner should re-issue the later duplicate")
	check(c.persist_id.begins_with("C-") and d.persist_id.begins_with("D-") and str(m.persist_id).begins_with("M-"),
		"Assigner should prefix chests C, doors D, mobs M")
	check(PersistIdAssigner.assign(root) == 0 and PersistIdAssigner.problems(root).is_empty(), "Assigned scene should be stable and clean")
	check(PersistIdAssigner.prefix_for(plain) == "", "Unrelated nodes should not get IDs")
	root.free()

	var lone_box = box_scene.instantiate()
	check(PersistIdAssigner.assign(lone_box) == 0 and lone_box.persist_id == "", "Editing the box scene itself should not bake an ID into every instance")
	lone_box.free()

	# 실제 스테이지 씬 전체: 빈 ID 없음, 그리고 모든 스테이지를 합쳐서 같은 ID가 두 번 나오면 안 된다.
	# 저장 기록은 게임 전체에서 ID 하나로 남으므로, 다른 스테이지로 복사·붙여넣기했거나
	# 박스가 든 씬을 여러 번 인스턴스한 경우(인스턴스 안쪽 노드까지 셈)도 여기서 걸린다.
	var seen := {}
	var stage_count := 0
	for f in ResourceLoader.list_directory("res://Scenes/Stage"):
		if not f.ends_with(".tscn"):
			continue
		var path := "res://Scenes/Stage/" + f
		var stage = load(path).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
		stage_count += 1
		var empty := []
		for node in _all_persist_targets(stage, stage):
			var id := str(node.get("persist_id"))
			var where := "%s:%s" % [f, stage.get_path_to(node)]
			if id.is_empty():
				empty.append(where)
			elif seen.has(id):
				check(false, "Duplicate persist_id %s: %s / %s (clear one of them in the inspector and save — the editor plugin re-issues it)" % [id, seen[id], where])
			else:
				seen[id] = where
		check(empty.is_empty(), "%s has objects without persist_id: %s" % [f, empty])
		stage.free()
	check(stage_count >= 3 and seen.size() > 0, "Persist ID check should scan the stage scenes")
	print("Persist IDs: auto-assign, duplicate fix, prefixes, stage scenes clean")

# 인스턴스 안쪽까지 포함한 모든 대상 노드 (씬 루트 제외)
func _all_persist_targets(node: Node, root: Node) -> Array:
	var out := []
	for child in node.get_children():
		if PersistIdAssigner.prefix_for(child) != "":
			out.append(child)
		out.append_array(_all_persist_targets(child, root))
	return out
