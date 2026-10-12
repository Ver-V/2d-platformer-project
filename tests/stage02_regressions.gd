extends SceneTree
# Run with Godot --headless --path . --script res://tests/stage02_regressions.gd
# 스테이지 기믹(시야 제한, 어둠 속 눈, 무너지는 블록)과 몹 동작(순찰 멈춤, 피격 스쿼시, 사망 뒤집기), 저장 ID 검사. 저장 파일은 건드리지 않는다.

var failures: int = 0
var fixture: Node2D

# 오토로드 (테스트 스크립트에선 오토로드 이름을 바로 못 쓴다)
func inv() -> Node: return root.get_node("Inventory")
func settings() -> Node: return root.get_node("SettingsManager")
func db() -> Node: return root.get_node("Database")

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
	check_torch()
	await check_crumbling_block()
	check_glow_eyes()
	check_patrol_idle()
	check_hit_squash_and_death_flip()
	check_persist_ids()
	check_elevator_floors()
	await check_elevator_transition()
	check_hazard_layers()
	await check_cave_ambience()
	await check_rat_room_sound()
	await check_world_ui_above_darkness()
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
	var lantern = db().get_item_by_id("lantern")
	check(lantern != null and lantern.vision_bonus_tiles > 0.0, "Lantern item missing or has no vision bonus")
	var stock2 = load("res://resources/shops/Stage2.tres")
	check(stock2.entries.any(func(e): return e.item != null and e.item.id == "lantern"), "Stage2 merchant should sell the lantern")
	fixture.add_child(vision)
	if lantern != null:
		inv().add_item(lantern)
		inv().add_item(lantern) # 여러 개 있어도 겹쳐서 더하지 않는다
		var goal: float = (4.0 + lantern.vision_bonus_tiles) * 16.0
		check(is_equal_approx(vision.get_radius(), goal), "Lantern should widen the vision radius (not stacking)")
		vision._process(0.1)
		check(vision._shown_radius > 64.0 and vision._shown_radius < goal, "Vision radius should grow gradually")
		vision._process(10.0)
		check(is_equal_approx(vision._shown_radius, goal), "Vision radius should reach the lantern radius")
	check(inv().accessories.count(lantern) == 2, "Lanterns should be equipped into accessory slots")
	inv().reset() # 테스트로 넣은 랜턴을 치운다 (신호로 시야도 갱신)
	check(is_equal_approx(vision.get_radius(), 64.0), "Vision radius should shrink back without the lantern")
	vision.free()

	var stage02 = load("res://Scenes/Stage/Stage_02.tscn").instantiate()
	check(is_equal_approx(stage02.vision_radius_tiles, 5.0), "Stage_02 should limit vision to 5 tiles")
	stage02.free()
	var stage01 = load("res://Scenes/Stage/Stage_01.tscn").instantiate()
	check(stage01.vision_radius_tiles <= 0.0, "Stage_01 should not limit vision")
	stage01.free()
	print("Vision: 5-tile radius on Stage_02 only, lantern widens it gradually")

const TORCH_SCENE := "res://Scenes/System/Torch.tscn"
func check_torch() -> void:
	var gm = root.get_node("GameManager")
	var lantern = db().get_item_by_id("lantern")
	var probe = load(TORCH_SCENE).instantiate()
	check(PersistIdAssigner.prefix_for(probe) == "T", "Torches should get T- persist ids")
	probe.free()

	var vision := VisionLimit.new()
	fixture.add_child(vision)
	var torch = load(TORCH_SCENE).instantiate()
	torch.persist_id = "T-torchtest"
	torch.position = Vector2(600, 0)
	fixture.add_child(torch)
	check(not torch.lit and torch.get_light_radius() == 0.0, "A new torch should start unlit with no light")

	# 랜턴 없이는 못 붙인다
	torch._on_interact()
	check(not torch.lit, "Torch should not light without the lantern equipped")

	inv().add_item(lantern) # 장착 칸으로 들어간다
	torch._on_interact()
	check(torch.lit and gm.collected_items.has("torch:T-torchtest"), "Torch should light with the lantern and record it for saving")
	check(not torch._can_interact(), "A lit torch should not be interactable again")
	torch._process(0.1)
	check(torch.get_light_radius() > 0.0 and torch.get_light_radius() < 150.0, "Torch light should spread gradually")
	torch._process(10.0)
	check(absf(torch.get_light_radius() - 160.0) <= torch.flicker_px + 0.01, "Torch should light a 10-tile radius")

	# 시야 제한: 플레이어 원 밖이어도 횃불 원 안은 밝다
	vision._process(0.0)
	var c: Vector2 = torch.get_light_center()
	check(vision.is_lit(c + Vector2(100, 0)), "Inside a lit torch's radius should count as lit")
	check(not vision.is_lit(c + Vector2(400, 0)), "Outside every light should stay dark")
	check(vision._light_centers.size() == 1, "Vision should pass the on-screen torch light to the shader")
	torch.position = Vector2(50000, 0) # 화면에서 먼 빛은 넘기지 않는다
	vision._process(0.0)
	check(vision._light_centers.is_empty(), "Far off-screen torches should be skipped")
	torch.free()

	# 저장된 기록이 있으면 다시 들어왔을 때 처음부터 다 밝혀져 있다
	var again = load(TORCH_SCENE).instantiate()
	again.persist_id = "T-torchtest"
	fixture.add_child(again)
	check(again.lit and absf(again.get_light_radius() - 160.0) <= again.flicker_px + 0.01, "A saved lit torch should be fully lit on load")
	again.free()

	gm.collected_items.erase("torch:T-torchtest")
	inv().reset()
	vision.free()
	print("Torch: needs the lantern, lights 10 tiles, saved via collected_items")

const BLOCK_SCENE := preload("res://Scenes/System/CrumblingBlock.tscn")

func make_block(x: float = 0.0) -> CrumblingBlock:
	var block: CrumblingBlock = BLOCK_SCENE.instantiate()
	block.crumble_delay = 0.05
	block.respawn_delay = 0.1
	fixture.add_child(block)
	block.global_position = Vector2(x, 200)
	return block

func check_crumbling_block() -> void:
	var block := make_block()
	await physics_frame
	check(block.state == CrumblingBlock.State.SOLID and not block.body_shape.disabled, "Block should start solid")
	check(block.body_shape.shape.get_rect().size == Vector2(16, 16) and block.body_shape.position == Vector2(8, 8),
		"Block collision should be a real one-tile shape in the scene")

	# 아래에서 점프해 올라가며 스치는 경우는 무너지지 않는다
	var player := make_player_stub(Vector2(8, 180))
	player.velocity = Vector2(0, -200)
	block._try_step_on(player)
	check(block.state == CrumblingBlock.State.SOLID, "Block crumbled from a rising jump")

	# 밟으면 흔들리다가 무너지고 충돌이 꺼진다
	player.velocity = Vector2.ZERO
	block._try_step_on(player)
	check(block.state == CrumblingBlock.State.SHAKING, "Block did not shake when stepped on")
	await wait(0.1)
	await physics_frame
	check(block.state == CrumblingBlock.State.BROKEN and block.body_shape.disabled and not block.sprite.visible, "Block did not break after the delay")

	# 다시 생길 때 그 자리에 플레이어가 있으면 비켜날 때까지 기다린다
	player.global_position = Vector2(8, 208)
	await physics_frame
	await physics_frame
	await wait(0.2)
	check(block.state == CrumblingBlock.State.BROKEN, "Block respawned inside the player")
	player.global_position = Vector2(8, 120)
	await physics_frame
	await physics_frame
	await wait(0.35)
	await physics_frame
	check(block.state == CrumblingBlock.State.SOLID and not block.body_shape.disabled and block.sprite.visible, "Block did not respawn after the player left")
	block.queue_free()

	# 한 칸씩 이어 붙인 블록: 실제 감지 영역으로 한 칸을 밟으면 맞붙은 블록이 전부 같이 무너진다.
	# 한 칸 떨어진 블록, crumble_alone 블록은 묶이지 않는다
	var a := make_block(0.0)
	var b := make_block(16.0)
	var c := make_block(32.0)
	var gap := make_block(64.0)
	var alone := make_block(48.0)
	alone.crumble_alone = true
	player.global_position = Vector2(6, 199)
	player.velocity = Vector2.ZERO
	for i in 3:
		await physics_frame
	check(a.state == CrumblingBlock.State.SHAKING and b.state == CrumblingBlock.State.SHAKING and c.state == CrumblingBlock.State.SHAKING,
		"Blocks placed side by side should crumble together")
	check(alone.state == CrumblingBlock.State.SOLID and gap.state == CrumblingBlock.State.SOLID,
		"A crumble_alone block and a block past it should not join the chain")
	await wait(0.1)
	await physics_frame
	check(a.state == CrumblingBlock.State.BROKEN and c.state == CrumblingBlock.State.BROKEN, "The linked blocks should break together")

	for n in [a, b, c, gap, alone]:
		n.queue_free()
	player.queue_free()
	await process_frame
	print("Crumbling block: one tile with real collision, side-by-side tiles crumble together, rising jumps ignored, respawns only when clear")

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

	# 몸 충돌체가 있으면 프레임 여백은 무시하고, 뒤집힌 뒤 실제 그려진 픽셀의 맨 아래를 충돌체 바닥(땅)에 맞춘다.
	# 프레임 아래쪽 8줄에만 그림이 있는 시체 = 사망 애니메이션처럼 위 여백이 큰 경우
	var img := Image.create(16, 20, false, Image.FORMAT_RGBA8)
	img.fill_rect(Rect2i(0, 12, 16, 8), Color.WHITE)
	frames.set_frame(&"default", 0, ImageTexture.create_from_image(img))
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(12, 10)
	shape.shape = rect
	shape.position = Vector2(0, -5) # 바닥 y = 0
	enemy.add_child(shape)
	enemy.body_shape = shape
	enemy._prepare_death_flip()
	check(is_equal_approx(enemy._death_flip_ground_y, 0.0), "Death flip ground should be the body shape's bottom")
	enemy._apply_death_flip(0.0)
	check(spr.position.is_equal_approx(Vector2(2, 3)), "Death flip should start from the normal pose")
	enemy._apply_death_flip(1.0)
	var opaque_top := spr.offset.y - 10.0 + 12.0 # 그림 맨 윗줄 (스프라이트 로컬) — 뒤집히면 맨 아래가 된다
	check(is_equal_approx(spr.position.y + spr.scale.y * opaque_top, 0.0) and is_equal_approx(spr.scale.y, -2.0),
		"Flipped corpse should rest its drawn pixels on the body shape's bottom, ignoring frame padding")
	enemy._death_flip_ground_y = NAN

	enemy._reset_sprite_motion()
	check(spr.scale.is_equal_approx(Vector2(2, 2)) and spr.position.is_equal_approx(Vector2(2, 3)), "Reset should restore the sprite transform")
	check(enemy._can_play_sprite_motion(), "Normal mobs should play hit/death motion")
	enemy.add_to_group("bosses")
	check(not enemy._can_play_sprite_motion(), "Bosses should keep their own hit/death presentation")
	enemy.free()
	print("Hit squash / death flip: grounded squash, bounce, upside-down landing, bosses excluded")

# 월드에 그리는 HUD성 요소(플레이어 머리 위 팝업, 몸 옆 게이지, 몹 체력바)는 어둠(VisionLimit)보다 위에 그린다
func check_world_ui_above_darkness() -> void:
	var dark_z: int = load("res://Script/System/vision_limit.gd").Z_INDEX
	var player = load("res://Scenes/Entitites/Player.tscn").instantiate()
	fixture.add_child(player)
	player.set_physics_process(false)
	for item in [player.status_label, player.get_node("Visuals")]:
		check(not item.z_as_relative and item.z_index > dark_z, "%s should draw above the darkness" % item.name)
	var mob = load("res://Scenes/Entitites/slime_1.tscn").instantiate()
	fixture.add_child(mob)
	var bar: Node2D = mob.get_node_or_null("HealthBarLayer")
	check(bar != null and not bar.z_as_relative and bar.z_index > dark_z, "Mob health bar should draw above the darkness")

	# 체력바는 빛 안에서만 보인다 (어둠 속 몹은 눈만). 시야 제한이 없는 스테이지에선 항상 보인다
	mob.set_active(true)
	mob._update_health_bar_light()
	check(bar.visible, "Without darkness the health bar should always show")
	var vision = load("res://Script/System/vision_limit.gd").new()
	vision.radius_tiles = 5.0
	vision.target = player
	fixture.add_child(vision)
	player.global_position = Vector2.ZERO
	await process_frame
	mob.global_position = Vector2(30, 0)
	mob._update_health_bar_light()
	check(bar.visible, "A mob inside the light should show its health bar")
	mob.global_position = Vector2(400, 0)
	mob._update_health_bar_light()
	check(not bar.visible, "A mob in the dark should hide its health bar")
	vision.queue_free()
	player.queue_free()
	mob.queue_free()
	await process_frame
	print("World UI: popups, gauges and mob health bars above the darkness")

# 가시는 HazardTileMap(씬 루트가 바로 TileMapLayer)에 칠한다. 그 타일셋의 "damage" 데이터로 피해가 들어간다.
# 스테이지마다 HazardTileMap과 그 아래 칠해진 레이어는 전부 damage 데이터가 있는 타일셋이어야 한다 (복사한 타일셋 금지)
func check_hazard_layers() -> void:
	for path in ["res://Scenes/Stage/Stage_01.tscn", "res://Scenes/Stage/Stage_02.tscn", "res://Scenes/Stage/Stage_03.tscn"]:
		var stage: Node = load(path).instantiate()
		var hazard := stage.get_node_or_null("HazardTileMap")
		check(hazard != null, "%s should have a HazardTileMap" % path)
		if hazard != null:
			check(hazard is TileMapLayer, "%s: HazardTileMap should itself be the paintable TileMapLayer" % path)
			var layers: Array = hazard.find_children("*", "TileMapLayer", true, false)
			if hazard is TileMapLayer:
				layers.push_front(hazard)
			for layer in layers:
				if layer.get_used_cells().is_empty():
					continue
				var has_damage_layer: bool = layer.tile_set != null and layer.tile_set.get_custom_data_layer_by_name("damage") != -1
				check(has_damage_layer, "%s: %s paints spikes with a tileset that has no 'damage' data (spikes won't hurt)" % [path, layer.name])
				if has_damage_layer:
					var hurts: bool = layer.get_used_cells().any(func(c): return int(layer.get_cell_tile_data(c).get_custom_data("damage")) > 0)
					check(hurts, "%s: %s has spike cells but none deal damage" % [path, layer.name])
		stage.free()
	var spikes_s1: TileMapLayer = load("res://Scenes/Stage/Stage_01.tscn").instantiate().get_node("HazardTileMap")
	check(spikes_s1.get_used_cells().size() > 0 and spikes_s1.position == Vector2(1, -10), "Stage_01 spikes should keep their cells and offset after the HazardTileMap change")
	spikes_s1.get_parent().free()
	print("Hazards: HazardTileMap is a TileMapLayer and every spike layer uses the damage tileset")

# 엘리베이터 석판: 지하 1층 = Stage_02, 지하 4층 = Stage_01, 지하 8층 = Stage_03 (en·ko 같게). 지금 있는 층을 고르면 이동하지 않고 "이미 그 층" 블록
func check_elevator_floors() -> void:
	var floors := {"B1": "res://Scenes/Stage/Stage_02.tscn", "B4": "res://Scenes/Stage/Stage_01.tscn", "B8": "res://Scenes/Stage/Stage_03.tscn"}
	for lang in ["en", "ko"]:
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://resources/Dialogues/%s/elevator_block.json" % lang))
		var choices: Array = data["start"][0]["choices"]
		for block in floors:
			var picked = choices.filter(func(c): return c.get("next") == block)
			check(picked.size() == 1 and picked[0].get("scene_path") == floors[block] and not picked[0].has("condition"),
				"%s elevator: %s should go to %s" % [lang, block, floors[block]])
			check(data.has(block), "%s elevator: '%s' (already on this floor) block should exist" % [lang, block])
	var dm = root.get_node("DialogueManager")
	var stage := Node.new()
	stage.scene_file_path = floors["B1"]
	root.add_child(stage)
	current_scene = stage
	check(dm._is_current_scene(floors["B1"]) and not dm._is_current_scene(floors["B4"]), "Elevator should know which floor it is on")
	current_scene = null
	stage.free()
	print("Elevator: B1 -> Stage_02, B4 -> Stage_01, B8 -> Stage_03, current floor stays")

class ShakeRecorder extends Node:
	var shakes: Array[float] = []
	func apply_camera_shake(amount: float) -> void:
		shakes.append(amount)

# 엘리베이터 전환: 출발 층이 흔들리며 어두워지고, 도착 층도 흔들리며 다시 밝아진다 (Fade In)
func check_elevator_transition() -> void:
	var transition = root.get_node("SceneTransition")
	var from := ShakeRecorder.new()
	var to := ShakeRecorder.new()
	root.add_child(from)
	root.add_child(to)
	current_scene = from
	transition.start_elevator_transition(func(): current_scene = to)
	check(from.shakes.size() == 1 and from.shakes[0] > 0.0, "Elevator should shake the floor you leave")
	await wait(0.9)
	check(transition.color_rect.modulate.a > 0.99 and current_scene == to, "Screen should be black when the floor changes")
	await wait(0.5)
	check(to.shakes.size() == 1 and to.shakes[0] > 0.0, "Elevator should shake the floor you arrive at")
	await wait(1.0)
	check(transition.color_rect.modulate.a < 0.01, "Screen should fade back in on the new floor")
	current_scene = null
	from.free()
	to.free()
	print("Elevator transition: shake + fade out, arrival shake + fade in")

# Stage_02 환경음: incave1·2를 번갈아 끝없이, 매번 피치 ±10%, 에코(리버브·딜레이)가 걸린 Ambient 버스 → SFX
func check_cave_ambience() -> void:
	var bus := AudioServer.get_bus_index(&"Ambient")
	check(bus >= 0 and AudioServer.get_bus_send(bus) == &"SFX", "Ambient bus should exist and send to SFX")
	var kinds := []
	for i in AudioServer.get_bus_effect_count(bus):
		kinds.append(AudioServer.get_bus_effect(bus, i).get_class())
	check(kinds.has("AudioEffectReverb") and kinds.has("AudioEffectDelay"), "Ambient bus should add echo (reverb + delay)")
	var stage = load("res://Scenes/Stage/Stage_02.tscn").instantiate()
	var amb = stage.get_node("CaveAmbience")
	check(amb is AmbientLoop and amb.effective_bus() == &"Ambient" and amb.streams.size() == 2, "Stage_02 should have the cave ambience on the Ambient bus")
	var names: Array = amb.streams.map(func(s): return s.resource_path.get_file())
	check(names == ["incave1.wav", "incave2.wav"], "Cave ambience should use incave1 and incave2")
	stage.free()
	var stage01 = load("res://Scenes/Stage/Stage_01.tscn").instantiate()
	var forest = stage01.get_node("ForestAmbience")
	check(forest is AmbientLoop and forest.effective_bus() == &"SFX" and forest.streams.size() == 1 and forest.streams[0].resource_path.ends_with("inforest1.wav"),
		"Stage_01 should loop inforest1 on the SFX bus (no echo)")
	stage01.free()
	var loop := AmbientLoop.new()
	loop.streams = [AudioStreamWAV.new(), AudioStreamWAV.new()]
	fixture.add_child(loop)
	var order := [loop.stream]
	var pitches := [loop.pitch_scale]
	for i in 3:
		loop.play_next()
		order.append(loop.stream)
		pitches.append(loop.pitch_scale)
	check(order[0] == loop.streams[0] and order[1] == loop.streams[1] and order[2] == loop.streams[0] and order[3] == loop.streams[1],
		"Ambience should alternate the two sounds")
	check(pitches.all(func(p): return p >= 0.9 - 0.0001 and p <= 1.1 + 0.0001), "Ambience pitch should vary within 10%")
	loop.queue_free()
	await process_frame
	print("Ambience: Stage_02 incave1/2 alternate on the Ambient bus (reverb + delay -> SFX), Stage_01 inforest1 on SFX, pitch +-10% each time")

# 쥐 소리: 플레이어 방(활성)에 쥐가 있으면 15초마다 ratsound1/2 중 하나, 여러 마리여도 한 번
func rat_sound_count() -> int:
	return root.get_children().filter(func(n): return n is AudioStreamPlayer and n.stream != null 		and n.stream.resource_path.get_file().begins_with("ratsound")).size()

func check_rat_room_sound() -> void:
	var rat_script = load("res://Script/Entity/rat.gd")
	var rat_scene = load("res://Scenes/Entitites/rat.tscn")
	var a = rat_scene.instantiate()
	var b = rat_scene.instantiate()
	fixture.add_child(a)
	fixture.add_child(b)
	check(rat_script.ROOM_SOUNDS.size() == 2 and is_equal_approx(rat_script.ROOM_SOUND_INTERVAL, 15.0), "Rats should share two room sounds every 15 seconds")
	await physics_frame
	var before := rat_sound_count()
	rat_script._room_sound_timer = 15.0
	rat_script._room_sound_frame = -1
	a._tick_room_sound(14.0)
	check(rat_sound_count() == before, "No rat sound before 15 seconds")
	await physics_frame
	a._tick_room_sound(1.0)
	b._tick_room_sound(1.0) # 같은 프레임의 다른 쥐는 세지 않는다
	check(rat_sound_count() == before + 1 and is_equal_approx(rat_script._room_sound_timer, 15.0), "One rat sound after 15 seconds, even with several rats")
	a.queue_free()
	b.queue_free()
	await process_frame
	print("Rat room sound: one of ratsound1/2 every 15s while rats are in the player's room")

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
