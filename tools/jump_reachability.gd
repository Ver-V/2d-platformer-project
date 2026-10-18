extends SceneTree
# 점프 도달 검사: 스테이지를 실제로 불러와 실제 충돌(타일·가시·무너지는 블록·벽)과 플레이어 이동 수식(가감속, 점프 컷,
# 정점 체공, 코요테, 점프 선입력, 모서리 보정, 턱 올려 주기, 더블 점프, 수영)으로 점프 경로를 시뮬레이션해서
# 스폰 지점에서 어디까지 갈 수 있는지 BFS로 찾는다. 세 번 돌린다: 더블 점프 없음 → 더블 점프 → 더블 점프 + 금 간 벽 부숨.
# 결과: 갈 수 없는 상자·박스·세이브·횃불·문 등과, 한 번도 밟지 못한 바닥 구간을 방 좌표와 함께 적는다.
#
# 사용: godot --headless --path . --script res://tools/jump_reachability.gd -- res://Scenes/Stage/Stage_02.tscn [결과 파일 경로]
# 근사치다: 입력 패턴을 몇 가지로 고정해 시도하므로 "갈 수 없음"은 아주 정밀한 조작이 필요한 곳일 수도 있다.
# 몹은 지우고 계산한다 (몹 밟기·넉백 이용은 치지 않는다). 지름길 문은 B를 쓰면 A로 간다 (그 뒤 A↔B).
# 클래스 이름 대신 스크립트 경로로 구별한다 (오토로드를 쓰는 스크립트를 이 스크립트가 먼저 컴파일하지 않게).

const DT := 1.0 / 60.0
const MAX_FRAMES := 420
const WATER_NODE_FRAMES := 30
const SENSE_OFFSET := Vector2(0, -10)

# Player.gd 기본값 (씬 값으로 덮어쓴다)
var movespeed := 120.0
var jumpforce := -350.0
var jump_cut := 0.45
var max_fall := 280.0
var apex_threshold := 40.0
var apex_mult := 0.5
var accel := 1200.0
var friction := 2500.0
var coyote_time := 0.2
var buffer_time := 0.15
var water_move := 0.5
var water_jump := 0.25
var water_grav := 0.25
var water_max_fall := 50.0
var water_rise_accel := 600.0
var water_exit_h := 24.0
const CORNER_PX := 4
const LEDGE_PX := 6
const LEDGE_MAX_RISE := 60.0

var stage: Node
var p: CharacterBody2D
var body_col: CollisionShape2D
var gravity := 980.0
var water_layers: Array = []
var hazard_layers: Array = []
var sensors: Array = [] # CollisionShape2D
var bottom_limit := 1e9

var double_jump := false
var nodes := {}        # key -> {pos, water, pass}
var queue: Array = []
var door_links: Array = [] # [{b_rect, a_pos, a_rect}]
var trajectories := 0

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	var scene_path := args[0] if args.size() > 0 else "res://Scenes/Stage/Stage_02.tscn"
	var out_path := args[1] if args.size() > 1 else ""
	var gm := root.get_node("GameManager")
	gm.reset_data()
	stage = load(scene_path).instantiate()
	root.add_child(stage)
	current_scene = stage
	for i in 3:
		await physics_frame
	_setup()
	for i in 2:
		await physics_frame

	var targets := _collect_targets()
	var report := PackedStringArray()
	report.append("Jump reachability: %s" % scene_path)
	report.append("start = %s, rooms %s x %s" % [str(p.global_position), str(stage.grid_size), str(stage.room_size)])

	# A: 더블 점프 없이 BFS. B: A에서 찾은 자리마다 더블 점프 패턴만 더 돌리고, 새로 닿은 자리는 모든 패턴으로 퍼진다
	var start_pos := p.global_position
	var results := []
	var t0 := Time.get_ticks_msec()
	double_jump = false
	_bfs(start_pos)
	results.append({"name": "A: no double jump", "nodes": nodes.duplicate(), "reached": _reached_targets(targets)})
	print("A: %d standing spots, %d trajectories, %.1fs" % [nodes.size(), trajectories, (Time.get_ticks_msec() - t0) / 1000.0])
	t0 = Time.get_ticks_msec()
	double_jump = true
	_continue_with_double_jump()
	results.append({"name": "B: double jump", "nodes": nodes.duplicate(), "reached": _reached_targets(targets)})
	print("B: %d standing spots, %d trajectories, %.1fs" % [nodes.size(), trajectories, (Time.get_ticks_msec() - t0) / 1000.0])

	# --- 보고 ---
	report.append("")
	for r in results:
		report.append("%s: %d standing spots, %d/%d targets reachable" % [r.name, r.nodes.size(), r.reached.size(), targets.size()])
	report.append("")
	report.append("== Targets (A = no double jump, B = needs double jump, X = unreachable; cracked walls stay intact) ==")
	var counts := {"A": 0, "B": 0, "X": 0}
	var lines := []
	for i in targets.size():
		var t: Dictionary = targets[i]
		var tier := "X"
		if results[0].reached.has(i): tier = "A"
		elif results[1].reached.has(i): tier = "B"
		counts[tier] += 1
		if tier != "A":
			lines.append("[%s] %-14s %-28s pos %s room %s" % [tier, t.kind, t.name, _fmt(t.pos), str(_room(t.pos))])
	report.append("A %d, B %d, X %d" % [counts.A, counts.B, counts.X])
	lines.sort()
	report.append_array(PackedStringArray(lines))
	report.append("")
	report.append("== Floor stretches never stood on (>= 2 tiles), even with double jump ==")
	report.append_array(_unreached_floors(results[1].nodes))
	report.append("")
	report.append("== Floor stretches reachable only with double jump (>= 2 tiles) ==")
	report.append_array(_floors_only_in(results[1].nodes, results[0].nodes))

	var text := "\n".join(report)
	print(text)
	if out_path != "":
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		if f:
			f.store_string(text)
	quit(0)

# -------------------------------------------------------------------------
# 준비
# -------------------------------------------------------------------------

func _setup() -> void:
	p = stage.player
	for prop in ["movespeed", "jumpforce", "max_fall_speed", "apex_threshold", "apex_gravity_mult", "acceleration", "friction",
			"coyote_time", "jump_buffer_time", "water_move_mult", "water_jump_mult", "water_gravity_mult", "water_max_fall_speed",
			"water_rise_accel", "water_exit_jump_height", "jump_cut_factor"]:
		if not prop in p:
			push_warning("player has no %s" % prop)
	movespeed = p.movespeed
	jumpforce = p.jumpforce
	jump_cut = p.jump_cut_factor
	max_fall = p.max_fall_speed
	apex_threshold = p.apex_threshold
	apex_mult = p.apex_gravity_mult
	accel = p.acceleration
	friction = p.friction
	coyote_time = p.coyote_time
	buffer_time = p.jump_buffer_time
	water_move = p.water_move_mult
	water_jump = p.water_jump_mult
	water_grav = p.water_gravity_mult
	water_max_fall = p.water_max_fall_speed
	water_rise_accel = p.water_rise_accel
	water_exit_h = p.water_exit_jump_height
	gravity = p.get_gravity().y

	p.set_physics_process(false)
	p.set_process(false)
	p.set_process_input(false)
	p.set_process_unhandled_input(false)
	for child in p.get_children():
		if child is CollisionShape2D and not child.disabled and body_col == null:
			body_col = child
		if _script_is(child, "hazard_sensor.gd"):
			child.set_physics_process(false)
			for c in child.get_children():
				if c is CollisionShape2D:
					sensors.append(c)
	stage.set_process(false)
	stage.set_physics_process(false)
	for n in _all_nodes(stage):
		if is_instance_valid(n) and (n.is_in_group("enemies") or n.is_in_group("bosses")):
			n.get_parent().remove_child(n)
			n.free()
	for n in _all_nodes(stage):
		if n is TileMapLayer:
			if n.has_method("has_water_at"):
				water_layers.append(n)
			elif n.tile_set != null and n.tile_set.get_custom_data_layer_by_name("damage") != -1:
				hazard_layers.append(n)
		if _script_is(n, "crumbling_block.gd"):
			n.set_physics_process(false)
			n.set_process(false)
	bottom_limit = stage.grid_origin.y + stage.grid_size.y * stage.room_size.y + 400.0
	# 지름길 문: B를 쓰면 A로
	var doors := {}
	for n in _all_nodes(stage):
		if _script_is(n, "shortcut_door.gd") and n.partner_scene == "":
			doors["%s:%d" % [n.link_id, n.side]] = n
	for key in doors:
		var d = doors[key]
		if d.side == 1 and doors.has("%s:0" % d.link_id):
			var a = doors["%s:0" % d.link_id]
			door_links.append({"b_rect": _node_rect(d), "a_pos": a.arrival_position(), "name": d.link_id})

func _all_nodes(n: Node) -> Array:
	var out := [n]
	for c in n.get_children():
		out.append_array(_all_nodes(c))
	return out

func _script_is(n: Node, file: String) -> bool:
	var s = n.get_script()
	return s != null and str(s.resource_path).ends_with("/" + file)

# 노드 아래 모든 CollisionShape2D를 합친 전역 사각형 (없으면 원점 둘레 16px)
func _node_rect(n: Node) -> Rect2:
	var r := Rect2()
	var has := false
	for c in _all_nodes(n):
		if c is CollisionShape2D and c.shape != null:
			var local: Rect2 = c.shape.get_rect()
			var g: Transform2D = c.global_transform
			var rr := Rect2(g * local.position, Vector2.ZERO).expand(g * local.end)
			r = rr if not has else r.merge(rr)
			has = true
	if not has and n is Node2D:
		r = Rect2(n.global_position - Vector2(8, 16), Vector2(16, 16))
	return r

func _collect_targets() -> Array:
	var kinds := {
		"Chest.gd": "chest", "BreakableBox.gd": "box", "SavePoint.gd": "save point", "torch.gd": "torch",
		"shortcut_door.gd": "shortcut door", "cracked_wall.gd": "cracked wall", "merchant_npc.gd": "merchant",
		"field_item.gd": "item", "elevator_block.gd": "elevator", "KeyDoor.gd": "key door", "Interactable.gd": "interactable",
	}
	var out := []
	for n in _all_nodes(stage):
		var s = n.get_script()
		if s == null:
			continue
		var file := str(s.resource_path).get_file()
		var kind := ""
		if kinds.has(file):
			kind = kinds[file]
		elif n.has_method("_on_interact") or file.to_lower().contains("npc"):
			kind = file.get_basename()
		if kind == "":
			continue
		if not n is Node2D:
			continue
		out.append({"kind": kind, "name": str(stage.get_path_to(n)), "pos": n.global_position, "rect": _node_rect(n)})
	return out

# -------------------------------------------------------------------------
# BFS
# -------------------------------------------------------------------------

func _key(pos: Vector2, water: bool) -> Vector3i:
	if water:
		return Vector3i(floori(pos.x / 32.0), floori(pos.y / 32.0), 1)
	return Vector3i(floori(pos.x / 16.0), floori(pos.y / 16.0), 0)

func _add_node(pos: Vector2, water: bool) -> void:
	var k := _key(pos, water)
	if nodes.has(k):
		return
	nodes[k] = {"pos": pos, "water": water}
	queue.append(k)
	if not water:
		var body := _body_rect(pos)
		for link in door_links:
			if body.intersects(link.b_rect):
				_add_node(link.a_pos, false)

func _bfs(start: Vector2) -> void:
	nodes.clear()
	queue.clear()
	trajectories = 0
	var settled = _settle(start)
	if settled == null:
		push_error("start position does not land")
		return
	_add_node(settled, false)
	_drain(0)

# 큐에 남은 자리를 모든 패턴으로 퍼뜨린다
func _drain(head: int) -> void:
	while head < queue.size():
		var k: Vector3i = queue[head]
		head += 1
		if head % 250 == 0:
			print("  ... %d/%d spots" % [head, queue.size()])
		var node: Dictionary = nodes[k]
		var pats := _water_patterns() if node.water else _ground_patterns()
		for pat in pats:
			_simulate(node.pos, node.water, pat)

# 이미 찾은 자리에서 더블 점프 패턴만 돌리고, 새 자리는 _drain으로 모든 패턴
func _continue_with_double_jump() -> void:
	trajectories = 0
	var old_keys := nodes.keys()
	var head := queue.size()
	for i in old_keys.size():
		if i % 500 == 0:
			print("  ... dj %d/%d old spots" % [i, old_keys.size()])
		var node: Dictionary = nodes[old_keys[i]]
		var pats := _water_patterns() if node.water else _ground_patterns()
		for pat in pats:
			if pat.get("dj", false):
				_simulate(node.pos, node.water, pat)
	_drain(head)

# 시작 위치를 떨어뜨려 바닥에 세운다
func _settle(pos: Vector2):
	p.global_position = pos
	for i in 240:
		p.velocity = Vector2(0, minf(max_fall, 60.0 + i * 16.0))
		p.move_and_slide()
		if p.is_on_floor():
			return p.global_position
	return null

# --- 입력 패턴 ---
# walk: true면 d 방향으로 걸어서 발판을 벗어난 순간이 t0 (못 벗어나면 걷기 끝에 선 자리를 기록)
# dirs: [[t0 기준 프레임, 방향], ...], jumps: [[누름, 뗌], ...] (t0 기준), dj: 더블 점프가 필요한 패턴
func _ground_patterns() -> Array:
	var out := []
	out.append({"walk": false, "dirs": [[0, 0]], "jumps": [[0, 60]]})
	for d in [-1, 1]:
		# 걸음 (같은 바닥의 옆 칸들)
		out.append({"walk": false, "dirs": [[0, d], [8, 0]], "jumps": [], "steps": 30})
		# 제자리 점프
		out.append({"walk": false, "dirs": [[0, d]], "jumps": [[0, 60]]})
		out.append({"walk": false, "dirs": [[0, d]], "jumps": [[0, 5]]})
		out.append({"walk": false, "dirs": [[0, 0]], "jumps": [[0, 5]]})
		for k in [8, 16, 24, 36]:
			out.append({"walk": false, "dirs": [[0, d], [k, 0]], "jumps": [[0, 60]]})
			out.append({"walk": false, "dirs": [[0, 0], [k, d]], "jumps": [[0, 60]]})
		out.append({"walk": false, "dirs": [[0, d], [20, -d]], "jumps": [[0, 60]]})
		# 걸어서 떨어지기 (+코요테 점프)
		out.append({"walk": true, "d": d, "dirs": [[0, d]], "jumps": []})
		out.append({"walk": true, "d": d, "dirs": [[0, 0]], "jumps": []})
		out.append({"walk": true, "d": d, "dirs": [[0, -d]], "jumps": []})
		out.append({"walk": true, "d": d, "dirs": [[0, d], [8, 0]], "jumps": []})
		for c in [0, 10]:
			out.append({"walk": true, "d": d, "dirs": [[0, d]], "jumps": [[c, c + 60]]})
			out.append({"walk": true, "d": d, "dirs": [[0, d], [c + 16, 0]], "jumps": [[c, c + 60]]})
			out.append({"walk": true, "d": d, "dirs": [[0, d], [c + 20, -d]], "jumps": [[c, c + 60]]})
		if double_jump:
			for j in [14, 24, 34]:
				out.append({"walk": false, "dirs": [[0, d]], "jumps": [[0, j - 1], [j, j + 60]], "dj": true})
				out.append({"walk": false, "dirs": [[0, d], [j + 10, 0]], "jumps": [[0, j - 1], [j, j + 60]], "dj": true})
				out.append({"walk": false, "dirs": [[0, 0], [j, d]], "jumps": [[0, j - 1], [j, j + 60]], "dj": true})
				out.append({"walk": false, "dirs": [[0, d], [16, 0]], "jumps": [[0, j - 1], [j, j + 60]], "dj": true})
			for j in [6, 20]:
				out.append({"walk": true, "d": d, "dirs": [[0, d]], "jumps": [[j, j + 60]], "dj": true})
				out.append({"walk": true, "d": d, "dirs": [[0, d], [j + 12, 0]], "jumps": [[j, j + 60]], "dj": true})
			# 코요테 점프 + 더블 점프
			out.append({"walk": true, "d": d, "dirs": [[0, d]], "jumps": [[10, 33], [34, 94]], "dj": true})
	if double_jump:
		out.append({"walk": false, "dirs": [[0, 0]], "jumps": [[0, 23], [24, 84]], "dj": true})
	return out

func _water_patterns() -> Array:
	var out := []
	for d in [-1, 0, 1]:
		out.append({"walk": false, "dirs": [[0, d]], "jumps": [], "water_steps": true})
		out.append({"walk": false, "dirs": [[0, d]], "jumps": [[0, 300]], "water_steps": true})
		out.append({"walk": false, "dirs": [[0, 0], [20, d]], "jumps": [[0, 300]], "water_steps": true})
		if double_jump and d != 0:
			# 수면 위로 솟은 뒤 더블 점프 (물을 벗어난 프레임 기준은 아니지만 길게 떠오른 뒤 여러 번 눌러 본다)
			for j in [40, 70, 100]:
				out.append({"walk": false, "dirs": [[0, d]], "jumps": [[0, j], [j + 1, j + 60]], "dj": true})
	return out

func _dir_at(pat: Dictionary, rel: int) -> int:
	var d := 0
	for e in pat.dirs:
		if rel >= e[0]:
			d = e[1]
	return d

# --- 한 경로 시뮬레이션 (Player._physics_process의 이동 부분을 그대로 따른다) ---
func _simulate(start: Vector2, start_water: bool, pat: Dictionary) -> void:
	trajectories += 1
	p.global_position = start
	p.velocity = Vector2(0, 5)
	if not start_water:
		p.move_and_slide()
	var vel := Vector2.ZERO
	var coyote := 0.0
	var buffer := 0.0
	var air_avail := true
	var in_water := start_water
	var walking: bool = pat.get("walk", false)
	var t0 := -1 if walking else 0
	var walk_dir: int = pat.get("d", 0)
	var steps: int = pat.get("steps", 0)
	var water_frames := 0
	var last_press := -1
	for e in pat.jumps:
		last_press = maxi(last_press, e[0])
	var left_start := false
	for f in MAX_FRAMES:
		var on_floor := p.is_on_floor()
		if walking and t0 < 0 and not on_floor and f > 0:
			t0 = f
		var rel := f - t0 if t0 >= 0 else -1
		var dir := walk_dir if rel < 0 else _dir_at(pat, rel)
		var held := false
		var pressed := false
		var released := false
		if rel >= 0:
			for e in pat.jumps:
				if rel >= e[0] and rel < e[1]:
					held = true
				if rel == e[0]:
					pressed = true
				if rel == e[1]:
					released = true

		# 물
		var now_water := _water_at(p.global_position + SENSE_OFFSET)
		if in_water and not now_water and vel.y < 0.0 and held:
			vel.y = minf(vel.y, -sqrt(2.0 * gravity * water_exit_h))
		in_water = now_water
		if in_water:
			water_frames += 1
		coyote -= DT
		buffer -= DT
		if on_floor or in_water:
			air_avail = true
		if on_floor:
			coyote = coyote_time

		# 모서리 보정 (오르는 중)
		if vel.y < 0.0:
			var motion := Vector2(0, vel.y * DT)
			if p.test_move(p.global_transform, motion):
				var done := false
				for i in range(1, CORNER_PX + 1):
					for sd in [-1, 1]:
						var off := Vector2(sd * i, 0)
						if p.test_move(p.global_transform, off):
							continue
						if not p.test_move(p.global_transform.translated(off), motion):
							p.global_position.x += off.x
							done = true
							break
					if done:
						break

		if pressed:
			buffer = buffer_time
			if double_jump and air_avail and not on_floor and coyote <= 0.0 and not in_water:
				air_avail = false
				buffer = 0.0
				vel.y = jumpforce
		if buffer > 0.0 and coyote > 0.0:
			vel.y = jumpforce * (water_jump if in_water else 1.0)
			buffer = 0.0
			coyote = 0.0

		# 달리기
		var target := dir * movespeed * (water_move if in_water else 1.0)
		if not on_floor:
			vel.x = target
		elif dir != 0:
			vel.x = move_toward(vel.x, target, accel * DT)
		else:
			vel.x = move_toward(vel.x, 0.0, friction * DT)

		# 중력
		if in_water:
			vel.y += gravity * water_grav * DT
			if held:
				vel.y = move_toward(vel.y, jumpforce * water_jump, water_rise_accel * DT)
			vel.y = minf(vel.y, water_max_fall)
		elif not on_floor:
			var mult := 1.0
			if absf(vel.y) < apex_threshold and held:
				mult *= apex_mult
			vel.y += gravity * mult * DT
			if released and vel.y < 0.0:
				vel.y *= jump_cut
			vel.y = minf(vel.y, max_fall)

		# 턱 올려 주기
		if not on_floor and not in_water and dir != 0 and vel.y >= -LEDGE_MAX_RISE:
			var side := Vector2(signf(dir), 0)
			if p.test_move(p.global_transform, side):
				for i in range(1, LEDGE_PX + 1):
					var up := Vector2(0, -i)
					if p.test_move(p.global_transform, up):
						break
					if not p.test_move(p.global_transform.translated(up), side):
						p.global_position.y -= i
						vel.y = minf(vel.y, 0.0)
						break

		p.velocity = vel
		p.move_and_slide()
		vel = p.velocity
		var pos := p.global_position

		if pos.y > bottom_limit:
			return
		if _hazard_hit(vel):
			return
		if not on_floor:
			left_start = true

		# 걷기 패턴: steps 프레임 뒤 선 자리
		if steps > 0 and f >= steps:
			if p.is_on_floor():
				_add_node(pos, false)
			elif in_water:
				_add_node(pos, true)
			return
		# 걸어서 떨어지려다 못 떨어짐 (벽): 선 자리 기록
		if walking and t0 < 0 and f > 200:
			if p.is_on_floor():
				_add_node(pos, false)
			return
		# 착지
		if (rel > last_press + 1 or (last_press < 0 and rel >= 1)) and p.is_on_floor() and vel.y >= 0.0 and left_start:
			_add_node(pos, in_water)
			return
		if p.is_on_floor() and steps == 0 and not walking and pat.jumps.is_empty() and f > 2:
			_add_node(pos, in_water)
			return
		# 물속: 일정 시간마다 물 노드로 기록하고 끝 (그 자리에서 다시 퍼진다)
		if in_water and water_frames >= WATER_NODE_FRAMES and rel > last_press + 1:
			_add_node(pos, true)
			return
		if in_water and pat.get("water_steps", false) and water_frames >= WATER_NODE_FRAMES:
			_add_node(pos, true)
			return
	if p.is_on_floor():
		_add_node(p.global_position, in_water)

func _water_at(pos: Vector2) -> bool:
	for layer in water_layers:
		if layer.has_water_at(pos):
			return true
	return false

# HazardSensor와 같은 판정: 센서 영역의 다섯 점에서 damage 타일을 찾고, 방향 가시면 끝 쪽에서 다가갈 때만
func _hazard_hit(vel: Vector2) -> bool:
	if hazard_layers.is_empty():
		return false
	var center: Vector2 = body_col.global_position
	for s in sensors:
		var sr: Rect2 = s.shape.get_rect()
		var gr := Rect2(s.global_position + sr.position, sr.size)
		for pt in [gr.get_center(), gr.position, gr.position + Vector2(gr.size.x, 0), gr.position + Vector2(0, gr.size.y), gr.end]:
			for layer in hazard_layers:
				var cell: Vector2i = layer.local_to_map(layer.to_local(pt))
				var data: TileData = layer.get_cell_tile_data(cell)
				if data == null or int(data.get_custom_data("damage")) <= 0:
					continue
				var dir := _spike_dir(layer, cell, data)
				var cc: Vector2 = layer.to_global(layer.map_to_local(cell))
				if dir == Vector2.ZERO:
					return true
				if (center - cc).dot(dir) <= 0.0:
					continue
				if vel.dot(dir) <= 0.0:
					return true
	return false

func _spike_dir(layer: TileMapLayer, cell: Vector2i, data: TileData) -> Vector2:
	if layer.tile_set.get_custom_data_layer_by_name("spike_dir") == -1:
		return Vector2.ZERO
	var base: Vector2i = data.get_custom_data("spike_dir")
	if base == Vector2i.ZERO:
		return Vector2.ZERO
	var alt := layer.get_cell_alternative_tile(cell)
	var d := Vector2(base)
	if alt & TileSetAtlasSource.TRANSFORM_TRANSPOSE:
		d = Vector2(d.y, d.x)
	if alt & TileSetAtlasSource.TRANSFORM_FLIP_H:
		d.x = -d.x
	if alt & TileSetAtlasSource.TRANSFORM_FLIP_V:
		d.y = -d.y
	return d.normalized()

# -------------------------------------------------------------------------
# 결과
# -------------------------------------------------------------------------

func _body_rect(feet: Vector2) -> Rect2:
	var off: Vector2 = body_col.position
	var size: Vector2 = body_col.shape.get_rect().size
	return Rect2(feet + off - size * 0.5, size)

# 선 자리에서 상호작용·칼이 닿는 거리 (가로 18px, 세로 8px 여유)
func _reached_targets(targets: Array) -> Dictionary:
	var out := {}
	for k in nodes:
		var reach := _body_rect(nodes[k].pos).grow_individual(18, 8, 18, 8)
		for i in targets.size():
			if not out.has(i) and reach.intersects(targets[i].rect):
				out[i] = true
	return out

func _room(pos: Vector2) -> Vector2i:
	return Vector2i(((pos - stage.grid_origin) / stage.room_size).floor())

func _fmt(v: Vector2) -> String:
	return "(%d, %d)" % [roundi(v.x), roundi(v.y)]

# 올라설 수 있는 바닥 칸: 충돌 있는 World 칸이고 위 두 칸이 비어 있다
func _standable_cells() -> Array:
	var world := stage.get_node_or_null("World") as TileMapLayer
	if world == null:
		return []
	var out := []
	for cell in world.get_used_cells():
		var data := world.get_cell_tile_data(cell)
		if data == null or data.get_collision_polygons_count(0) == 0:
			continue
		var free := true
		for up in [1, 2]:
			var above := world.get_cell_tile_data(cell - Vector2i(0, up))
			if above != null and above.get_collision_polygons_count(0) > 0:
				free = false
		if free:
			out.append(cell)
	return out

func _stretches(cells: Array) -> PackedStringArray:
	var world := stage.get_node("World") as TileMapLayer
	cells.sort_custom(func(a, b): return a.y < b.y or (a.y == b.y and a.x < b.x))
	var out := PackedStringArray()
	var i := 0
	while i < cells.size():
		var j := i
		while j + 1 < cells.size() and cells[j + 1].y == cells[i].y and cells[j + 1].x == cells[j].x + 1:
			j += 1
		var n := j - i + 1
		if n >= 2:
			var a: Vector2 = world.to_global(world.map_to_local(cells[i]))
			var b: Vector2 = world.to_global(world.map_to_local(cells[j]))
			out.append("%2d tiles  x %d..%d  y %d  room %s" % [n, roundi(a.x - 8), roundi(b.x + 8), roundi(a.y - 8), str(_room(a))])
		i = j + 1
	return out

# 선 자리를 칸 단위로 묶어 둔다 (바닥 칸마다 전부 훑지 않게)
func _index(node_set: Dictionary) -> Dictionary:
	var idx := {}
	for k in node_set:
		var pos: Vector2 = node_set[k].pos
		var key := Vector2i(floori(pos.x / 16.0), roundi(pos.y))
		if not idx.has(key):
			idx[key] = []
		idx[key].append(pos)
	return idx

# 그 바닥 칸 위에 선 적이 있는가 (발이 칸 윗면 ±4px, 몸이 칸에 걸침)
func _hit(cell: Vector2i, idx: Dictionary) -> bool:
	var world := stage.get_node("World") as TileMapLayer
	var center: Vector2 = world.to_global(world.map_to_local(cell))
	var top := roundi(center.y - 8.0)
	var col := floori(center.x / 16.0)
	for dx in [-1, 0, 1]:
		for dy in range(-4, 5):
			for pos in idx.get(Vector2i(col + dx, top + dy), []):
				if absf(pos.x - center.x) <= 13.0:
					return true
	return false

func _unreached_floors(node_set: Dictionary) -> PackedStringArray:
	var idx := _index(node_set)
	var cells := []
	for cell in _standable_cells():
		if not _hit(cell, idx):
			cells.append(cell)
	return _stretches(cells)

func _floors_only_in(with_set: Dictionary, without_set: Dictionary) -> PackedStringArray:
	var a := _index(with_set)
	var b := _index(without_set)
	var cells := []
	for cell in _standable_cells():
		if _hit(cell, a) and not _hit(cell, b):
			cells.append(cell)
	return _stretches(cells)
