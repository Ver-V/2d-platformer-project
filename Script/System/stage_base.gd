extends Node2D
class_name BaseStage

var is_waiting_respawn: bool = false

@export var stage_title: String = "" # [추가] 스테이지 이름 (예: Bunny's Forest)
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
@onready var Entities: Node = $Entities as Node
@onready var cam: Camera2D = $Camera2D as Camera2D

var player: Player = null
var current_room: Vector2i = Vector2i(-1, -1)
var current_shake_strength: float = 0.0 # 현재 흔들림 강도
@export var shake_decay_rate: float = 5.0 # 흔들림이 멈추는 속도

# [로컬 장부] 현재 게임 플레이 중 죽은 적(잡몹)들을 기록
var killed_ids: Dictionary = {}
var _cached_enemies: Array = []

func _ready() -> void:
	GameManager.is_respawning = false
	CustomCursor.hide_cursor()
	cam.make_current()
	_cached_enemies = get_tree().get_nodes_in_group("enemies")
	register_enemies()
	assign_persist_ids_by_formula()
	
	# [순서 중요] 적 등록 후 -> 이미 죽은 보스/잡몹 제거 -> 그 다음 플레이어 소환
	_cleanup_already_dead_enemies()
	
	spawn_player()

	if stage_title != "":
		_show_stage_title()

	if player != null:
		if not player.death_started.is_connected(_on_player_died):
			player.death_started.connect(_on_player_died)
		
		# 플레이어 위치에 맞춰 카메라 및 방 설정
		snap_to_room(room_from_pos(player.global_position), true)
	
	Engine.time_scale = 1.0
	HUD.visible = true

func _process(delta: float) -> void:
	# 흔들림이 남아있을 때만 작동
	if current_shake_strength > 0:
		# 1. 강도를 서서히 0으로 줄임 (Lerp)
		current_shake_strength = move_toward(current_shake_strength, 0.0, shake_decay_rate * delta)
		
		# 2. 아주 작은 값이 되면 0으로 확정 (불필요한 연산 방지)
		if current_shake_strength < 0.1:
			current_shake_strength = 0.0

		# 3. 흔들림 오프셋 계산 (랜덤 위치)
		# GameManager의 설정값(screenshake_intensity)을 곱해서 옵션 적용!
		var shake_offset = Vector2(
			randf_range(-current_shake_strength, current_shake_strength),
			randf_range(-current_shake_strength, current_shake_strength)
		) * GameManager.screenshake_intensity
		
		# 4. 카메라 위치 갱신 = [방의 중앙] + [흔들림]
		# 주의: current_room이 유효한지(-1이 아닌지) 확인 필요
		if current_room != Vector2i(-1, -1):
			cam.global_position = room_center(current_room) + shake_offset

	else:
		# 흔들림이 없을 때는 방의 정중앙에 고정 (혹시 모를 오차 수정)
		if current_room != Vector2i(-1, -1):
			cam.global_position = room_center(current_room)
			
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

	Entities.add_child(p)
	
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

func _show_stage_title() -> void:
	# Autoload에 StageTitleUI가 등록되어 있다고 가정하거나 
	# 혹은 직접 찾아서 실행합니다.
	if has_node("/root/StageTitleUI"):
		get_node("/root/StageTitleUI").play_title(stage_title)
	else:
		# Autoload가 아니더라도 씬에 수동으로 올렸을 경우를 대비
		var title_node = get_tree().root.find_child("StageTitleUI", true, false)
		if title_node and title_node.has_method("play_title"):
			title_node.play_title(stage_title)

func _input(event:InputEvent) -> void:
	if is_waiting_respawn and event.is_action_pressed("rest") and not GameManager.is_menu_open:
		is_waiting_respawn = false
		HUD.hide_death_screen()
		restart_stage()
		
func _on_player_died() -> void:
	is_waiting_respawn = true

func restart_stage() -> void:
	GameManager.respawn_player()

# [수정] 이미 죽은 적들(보스 + 로컬 잡몹) 제거 함수
func _cleanup_already_dead_enemies() -> void:
	for n in _cached_enemies:
		if not is_instance_valid(n): continue
		var e: EnemyBase = n as EnemyBase
		if e == null: continue
		
		var id: StringName = e.get_persist_id()
		
		# 1. 영구 사망한 보스인지 확인 (GameManager)
		if GameManager.defeated_bosses.get(id, false):
			e.queue_free()
			continue
			
		# 2. 이번 판에 잡은 잡몹인지 확인 (killed_ids)
		if killed_ids.get(id, false) or GameManager.defeated_mobs.has(id):
			e.queue_free()

func _on_enemy_died(e: EnemyBase) -> void:
	var id = e.get_persist_id()

	# 1. 로컬 장부 기록 (잡몹 리젠 방지용, 껏다 켜면 초기화됨)
	killed_ids[id] = true
	
	# [중요] 보스 그룹이거나 Boss 클래스인 경우 잡몹 리스트에서 제외
	if not e.is_in_group("bosses") and not (e is Boss):
		GameManager.add_defeated_mob(id)
		print("잡몹 처치됨: ", id)
	else:
		# 2. [추가] 만약 이 녀석이 '보스'라면 GameManager에 영구 저장!
		GameManager.defeated_bosses[id] = true
		GameManager.save_game()
		print("보스 처치됨 (영구 저장): ", id)
	
func apply_room_rules(r: Vector2i) -> void:
	_cached_enemies = _cached_enemies.filter(func(n) : return is_instance_valid(n))
	
	for n in _cached_enemies:
		if not is_instance_valid(n): continue
		var e: EnemyBase = n as EnemyBase
		if e == null: continue

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
	if not is_instance_valid(player): return
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
		if not is_instance_valid(n): continue
		var p: Node2D = n as Node2D
		if p == null: continue
		if clear_all: p.queue_free()
		else:
			var pr: Vector2i = room_from_pos(p.global_position)
			if pr != current_room: p.queue_free()

func register_enemies() -> void:
	for n in _cached_enemies:
		var e: EnemyBase = n as EnemyBase
		if e == null: continue
		if not e.died.is_connected(_on_enemy_died):
			e.died.connect(_on_enemy_died)

func assign_persist_ids_by_formula() -> void:
	var per_room: Dictionary = {}
	for n in _cached_enemies:
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
	
func apply_camera_shake(amount: float) -> void:
	current_shake_strength = amount
