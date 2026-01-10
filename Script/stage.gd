extends Node2D

@export var player_scene: PackedScene
@export var room_size: Vector2 = Vector2(640.0, 360.0)
@export var grid_size: Vector2i = Vector2i(12, 3)
@export var grid_origin: Vector2 = Vector2(0.0, 0.0)

# 방 이동 관련 설정
@export var reset_enemies_on_room_enter: bool = true
@export var deactivate_enemies_outside_room: bool = true
@export var clear_projectiles_on_room_change: bool = true
@export var clear_projectiles_outside_current_room: bool = true

@onready var spawn_point: Marker2D = $SpawnPoint as Marker2D
@onready var entities: Node2D = $Entities as Node2D
@onready var cam: Camera2D = $Camera2D as Camera2D

var player: Player = null
var current_room: Vector2i = Vector2i(-1, -1)

# [로컬 장부] 현재 게임 플레이 중 죽은 적(잡몹)들을 기록
var killed_ids: Dictionary = {}

func _ready() -> void:
	cam.make_current()
	register_enemies()
	assign_persist_ids_by_formula()
	
	# [순서 중요] 적 등록 후 -> 이미 죽은 보스/잡몹 제거 -> 그 다음 플레이어 소환
	_cleanup_already_dead_enemies()
	
	spawn_player()

	if player != null:
		if not player.died.is_connected(_on_player_died):
			player.died.connect(_on_player_died)
		
		# 플레이어 위치에 맞춰 카메라 및 방 설정
		snap_to_room(room_from_pos(player.global_position), true)
	
	Engine.time_scale = 1.0
	HUD.visible = true

# --- 플레이어 관련 ---

func spawn_player() -> void:
	if player_scene == null:
		push_error("player_scene is not assigned.")
		return

	var inst: Node = player_scene.instantiate()
	var p: Player = inst as Player
	if p == null:
		push_error("Player scene root must be Player.")
		return

	entities.add_child(p)
	
	# [핵심] 1. 체크포인트가 있고 & 2. 그 체크포인트가 이 맵에서 찍힌 거라면?
	if GameManager.has_checkpoint and GameManager.last_scene_path == scene_file_path:
		p.global_position = GameManager.last_checkpoint_pos
		print("[Spawn] 세이브 포인트 위치에서 시작: ", p.global_position)
	else:
		# 아니면 맵에 배치된 SpawnPoint 마커 위치 사용
		if spawn_point:
			p.global_position = spawn_point.global_position
			print("[Spawn] 기본 SpawnPoint에서 시작: ", p.global_position)
		else:
			print("[Spawn] 경고: SpawnPoint가 없습니다! (0,0)에 배치됩니다.")
		
	player = p

func _on_player_died() -> void:
	restart_stage()

func restart_stage() -> void:
	GameManager.respawn_player()

# [수정] 이미 죽은 적들(보스 + 로컬 잡몹) 제거 함수
func _cleanup_already_dead_enemies() -> void:
	var nodes: Array = get_tree().get_nodes_in_group("enemies")
	for n in nodes:
		var e: EnemyBase = n as EnemyBase
		if e == null: continue
		
		var id: StringName = e.get_persist_id()
		
		# 1. 영구 사망한 보스인지 확인 (GameManager)
		if GameManager.defeated_bosses.has(id):
			e.queue_free()
			continue
			
		# 2. 이번 판에 잡은 잡몹인지 확인 (killed_ids)
		if killed_ids.has(id):
			e.queue_free()

func _on_enemy_died(e: EnemyBase) -> void:
	var id = e.get_persist_id()
	
	# 1. 로컬 장부 기록 (잡몹 리젠 방지용, 껏다 켜면 초기화됨)
	killed_ids[id] = true
	
	# 2. [추가] 만약 이 녀석이 '보스'라면 GameManager에 영구 저장!
	# (보스 씬 노드 옆 'Node' 탭 -> Groups에 "bosses"를 추가하세요)
	if e.is_in_group("bosses"):
		GameManager.defeated_bosses[id] = true
		GameManager.save_game()
		print("보스 처치됨 (영구 저장): ", id)
	
func apply_room_rules(r: Vector2i) -> void:
	var nodes: Array = get_tree().get_nodes_in_group("enemies")
	for n in nodes:
		var e: EnemyBase = n as EnemyBase
		if e == null: continue

		var id: StringName = e.get_persist_id()
		
		# [수정] 로컬(잡몹) 또는 글로벌(보스) 장부에 있으면 방에 들어와도 삭제
		if killed_ids.has(id) or GameManager.defeated_bosses.has(id):
			if is_instance_valid(e): e.queue_free()
			continue

		var eroom: Vector2i = room_from_pos(e.home_position)

		if eroom == r:
			if reset_enemies_on_room_enter:
				e.reset_to_home(true)
			e.set_active(true)
		else:
			if deactivate_enemies_outside_room:
				e.reset_to_home(false)
				e.set_active(false)

# --- 유틸리티 및 기타 로직 (기존 그대로) ---
# ... (assign_persist_ids_by_formula 등 아래 부분은 원래 코드 그대로 두시면 됩니다) ...
# ...
# ...
# --- 아래는 생략된 부분입니다. 작성하신 코드 그대로 유지하세요 ---
func _physics_process(_delta: float) -> void:
	if player == null: return
	var r: Vector2i = room_from_pos(player.global_position)
	if r != current_room: snap_to_room(r, false)

func snap_to_room(r: Vector2i, is_initial: bool) -> void:
	current_room = r
	cam.global_position = room_center(r)
	if not is_initial:
		if clear_projectiles_on_room_change: clear_projectiles(true)
		elif clear_projectiles_outside_current_room: clear_projectiles(false)
	else:
		if clear_projectiles_outside_current_room: clear_projectiles(false)
	apply_room_rules(r)

func clear_projectiles(clear_all: bool) -> void:
	var nodes: Array = get_tree().get_nodes_in_group("projectiles")
	for n in nodes:
		var p: Node2D = n as Node2D
		if p == null: continue
		if clear_all: p.queue_free()
		else:
			var pr: Vector2i = room_from_pos(p.global_position)
			if pr != current_room: p.queue_free()

func register_enemies() -> void:
	var nodes: Array = get_tree().get_nodes_in_group("enemies")
	for n in nodes:
		var e: EnemyBase = n as EnemyBase
		if e == null: continue
		if not e.died.is_connected(_on_enemy_died):
			e.died.connect(_on_enemy_died)

func assign_persist_ids_by_formula() -> void:
	var nodes: Array = get_tree().get_nodes_in_group("enemies")
	var per_room: Dictionary = {}
	for n in nodes:
		var e: EnemyBase = n as EnemyBase
		if e == null: continue
		var rid: int = room_id_from_pos(e.home_position)
		if not per_room.has(rid): per_room[rid] = []
		var arr: Array = per_room[rid] as Array
		arr.append(e)
		per_room[rid] = arr

	var total_rooms: int = grid_size.x * grid_size.y
	var rid2: int = 1
	while rid2 <= total_rooms:
		if per_room.has(rid2):
			var arr2: Array = per_room[rid2] as Array
			arr2.sort_custom(Callable(self, "_sort_enemy_home"))
			var i: int = 0
			while i < arr2.size():
				var e2: EnemyBase = arr2[i] as EnemyBase
				if e2 != null and e2.persist_id == &"":
					var idx: int = i + 1
					var s: String = "R%02d_E%02d" % [rid2, idx]
					e2.persist_id = StringName(s)
				i += 1
		rid2 += 1

func _sort_enemy_home(a: Variant, b: Variant) -> bool:
	var ea: EnemyBase = a as EnemyBase
	var eb: EnemyBase = b as EnemyBase
	if ea == null: return true
	if eb == null: return false
	var ay: float = ea.home_position.y
	var by: float = eb.home_position.y
	if ay == by: return ea.home_position.x < eb.home_position.x
	return ay < by

func room_from_pos(p: Vector2) -> Vector2i:
	var local: Vector2 = p - grid_origin
	var rx: int = clampi(int(floor(local.x / room_size.x)), 0, grid_size.x - 1)
	var ry: int = clampi(int(floor(local.y / room_size.y)), 0, grid_size.y - 1)
	return Vector2i(rx, ry)

func room_center(r: Vector2i) -> Vector2:
	return grid_origin + Vector2((float(r.x) + 0.5) * room_size.x, (float(r.y) + 0.5) * room_size.y)

func room_id_from_xy(x: int, y: int) -> int:
	return y * grid_size.x + x + 1

func room_id_from_pos(p: Vector2) -> int:
	var r: Vector2i = room_from_pos(p)
	return room_id_from_xy(r.x, r.y)
