extends SceneTree
# Run with Godot --headless --path . --script res://tests/stage02_regressions.gd
# 스테이지 기믹(시야 제한, 무너지는 블록) 검사. 저장 파일은 건드리지 않는다.

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
	vision.free()

	var stage02 = load("res://Scenes/Stage/Stage_02.tscn").instantiate()
	check(is_equal_approx(stage02.vision_radius_tiles, 4.0), "Stage_02 should limit vision to 4 tiles")
	stage02.free()
	var stage01 = load("res://Scenes/Stage/Stage_01.tscn").instantiate()
	check(stage01.vision_radius_tiles <= 0.0, "Stage_01 should not limit vision")
	stage01.free()
	print("Vision: 4-tile radius on Stage_02 only")

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
