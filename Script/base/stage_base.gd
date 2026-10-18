extends Node2D
class_name BaseStage

var is_waiting_respawn: bool = false
@export var respawn_input_delay: float = 3.0 # 죽고 이만큼 지나야 [R] 안내가 뜨고 눌러서 바로 불러올 수 있다

@export var stage_title_key: StringName = &"" # 스테이지 제목 번역 키
@export var stage_prefix: String = "" # 몹 ID용 스테이지 접두사 
@export var player_scene: PackedScene
@export var room_size: Vector2 = Vector2(640.0, 360.0)
@export var grid_size: Vector2i = Vector2i(12, 3)
@export var grid_origin: Vector2 = Vector2(0.0, 0.0)
@export var vision_radius_tiles: float = 0.0 # 0보다 크면 플레이어 주변 이 반지름(타일 수)만 보인다

# 방 이동 관련 설정
@export var reset_enemies_on_room_enter: bool = true # 재진입 시 위치·전투 상태 초기화, HP 유지
@export var deactivate_enemies_outside_room: bool = true
@export var clear_projectiles_on_room_change: bool = true
@export var clear_projectiles_outside_current_room: bool = true

@onready var spawn_point: Marker2D = $SpawnPoint as Marker2D
@onready var Entities: Node = get_node_or_null("Entities")
@onready var cam: Camera2D = $Camera2D as Camera2D

var player: Player = null
var current_room: Vector2i = Vector2i(-1, -1)
# 카메라: 보통은 방 하나의 가운데(기본 확대). CameraZone 안에서는 구역 가운데·구역 확대. _cam_pos는 흔들림을 뺀 기준 위치
var _cam_pos: Vector2 = Vector2.ZERO
var _cam_target_zoom: Vector2 = Vector2.ONE
var _default_zoom: Vector2 = Vector2.ONE
var _current_zone: CameraZone = null
var _cam_tween: Tween
var current_shake_strength: float = 0.0 # 현재 흔들림 강도
@export var shake_decay_rate: float = 5.0 # 흔들림이 멈추는 속도

# 처음 한 번 띄우는 도움말 (TutorialPopup.show_once)
const TUTORIAL_DEATH := &"TUTORIAL_DEATH" # 죽고 처음 부활했을 때
const TUTORIAL_DARKNESS := &"TUTORIAL_DARKNESS" # 시야가 좁은 층에 처음 들어왔을 때
const TUTORIAL_MINIMAP := &"TUTORIAL_MINIMAP" # 처음 다른 방으로 넘어갔을 때
const TUTORIAL_MUTATION := &"TUTORIAL_MUTATION" # 변이체가 있는 방에 처음 들어갔을 때

# [로컬 장부] 현재 게임 플레이 중 죽은 적(잡몹)들을 기록
var killed_ids: Dictionary = {}
var _cached_enemies: Array = []

func _ready() -> void:
	GameManager.is_respawning = false
	GameManager.refresh_ui_owners() # 이전 씬에서 사라진 잠금 주인이 조작을 계속 막지 않게
	CustomCursor.hide_cursor()
	cam.make_current()
	_default_zoom = cam.zoom
	_cam_target_zoom = cam.zoom
	_cached_enemies = get_tree().get_nodes_in_group("enemies")
	register_enemies()
	assign_persist_ids_by_formula()
	
	# [순서 중요] 적 등록 후 -> 이미 죽은 보스/잡몹 제거 -> 그 다음 플레이어 소환
	_cleanup_already_dead_enemies()
	_cleanup_triggered_dialogues() # [추가] 이미 실행된 대화 블록 제거
	
	spawn_player()
	PlayLog.stage_entered(scene_file_path)
	_setup_vision_limit()
	_spawn_saved_mutant_chests()
	_spawn_death_drops()

	if stage_title_key != &"":
		_show_stage_title()

	if player != null:
		if not player.death_started.is_connected(_on_player_died):
			player.death_started.connect(_on_player_died)
		
		# 플레이어 위치에 맞춰 카메라 및 방 설정
		snap_to_room(room_from_pos(player.global_position), true)
	
	Engine.time_scale = 1.0
	HUD.visible = true
	GameManager.autosave.call_deferred() # 맵을 옮기면 저장 (부활 직후 포함)
	_show_entry_tutorials.call_deferred()

# 스테이지에 들어오자마자 처음 한 번 알려 줄 것: 죽고 부활했을 때, 어두운 층
func _show_entry_tutorials() -> void:
	if GameManager.respawned_from_death:
		GameManager.respawned_from_death = false
		Tutorials.show_once(self, TUTORIAL_DEATH)
	if vision_radius_tiles > 0.0:
		Tutorials.show_once(self, TUTORIAL_DARKNESS)

func _setup_vision_limit() -> void:
	if vision_radius_tiles <= 0.0:
		return
	var vision := VisionLimit.new()
	vision.name = "VisionLimit"
	vision.radius_tiles = vision_radius_tiles * float(MoonPhase.current(self, "vision_mult")) # 그믐달 밤엔 더 어둡다
	vision.target = player
	add_child(vision)

func _process(delta: float) -> void:
	# 흔들림이 남아있을 때만 작동
	if current_shake_strength > 0:
		# 1. 강도를 서서히 0으로 줄임 (Lerp)
		current_shake_strength = move_toward(current_shake_strength, 0.0, shake_decay_rate * delta)
		
		# 2. 아주 작은 값이 되면 0으로 확정 (불필요한 연산 방지)
		if current_shake_strength < 0.1:
			current_shake_strength = 0.0

		# 3. 흔들림 오프셋 계산 (랜덤 위치)
		var shake_offset = Vector2(
			randf_range(-current_shake_strength, current_shake_strength),
			randf_range(-current_shake_strength, current_shake_strength)
		) * SettingsManager.screenshake_intensity
		
		# 4. 카메라 위치 갱신 = [방의 중앙] + [흔들림]
		# 주의: current_room이 유효한지(-1이 아닌지) 확인 필요
		if current_room != Vector2i(-1, -1):
			cam.global_position = _cam_pos + shake_offset

	else:
		# 흔들림이 없을 때는 방의 정중앙에 고정 (혹시 모를 오차 수정)
		if current_room != Vector2i(-1, -1):
			cam.global_position = _cam_pos
			
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

	if Entities:
		Entities.add_child(p)
	else:
		add_child(p)
	
	# 다른 씬의 지름길 문을 타고 왔으면 짝 문 앞에서 시작
	if _place_at_shortcut_arrival(p):
		player = p
		return

	# 엘리베이터를 타고 왔으면 이 층 엘리베이터 앞에서 시작 (마지막 세이브 포인트가 이 층이어도)
	if _place_at_elevator_arrival(p):
		player = p
		return

	# 나갈 때 저장한 이어 하기 위치 (한 번 쓰면 지운다)
	if GameManager.resume_scene_path == scene_file_path:
		p.global_position = GameManager.resume_pos
		GameManager.clear_resume_point()
		player = p
		DebugLog.info(str("[Spawn] 이어 하기 위치에서 시작: ", p.global_position))
		return

	# [핵심] 1. 체크포인트가 있고 & 2. 그 체크포인트가 이 맵에서 찍힌 거라면?
	if GameManager.has_checkpoint and GameManager.last_scene_path == scene_file_path:
		p.global_position = GameManager.last_checkpoint_pos
		DebugLog.info(str("[Spawn] 세이브 포인트 위치에서 시작: ", p.global_position))
	else:
		# 아니면 맵에 배치된 SpawnPoint 마커 위치 사용
		if spawn_point:
			p.global_position = spawn_point.global_position
			DebugLog.info(str("[Spawn] 기본 SpawnPoint에서 시작: ", p.global_position))
		else:
			push_warning("[Spawn] SpawnPoint가 없습니다! (0,0)에 배치됩니다.")
		
	player = p

# 나갈 때 저장할 위치. 전투 중이거나 아직 안전한 땅을 밟지 않았으면 null (세이브 포인트에서 시작)
func get_resume_position() -> Variant:
	if not is_instance_valid(player) or player.hp <= 0 or not player.has_safe_position or is_player_in_combat():
		return null
	return player.last_safe_position

# 보스전이 시작된 보스가 살아 있거나, 활성화된 몹이 플레이어를 쫓고 있으면 전투 중
func is_player_in_combat() -> bool:
	for n in get_tree().get_nodes_in_group("enemies"):
		var e := n as EnemyBase
		if e == null or e.hp <= 0 or not e._active:
			continue
		if e.is_in_group("bosses"):
			if e.get("boss_started"):
				return true
		elif e.target == player:
			return true
	return false

func _place_at_shortcut_arrival(p: Player) -> bool:
	var arrival: Dictionary = GameManager.pending_shortcut_arrival
	if arrival.is_empty():
		return false
	GameManager.pending_shortcut_arrival = {}
	var door := ShortcutDoor.find_door(get_tree(), str(arrival.get("link_id", "")), int(arrival.get("side", -1)))
	if door == null:
		push_warning("[Spawn] 도착할 지름길 문이 이 씬에 없습니다: %s" % str(arrival))
		return false
	door.place_player(p)
	DebugLog.info(str("[Spawn] 지름길 문 앞에서 시작: ", p.global_position))
	return true

func _place_at_elevator_arrival(p: Player) -> bool:
	if not GameManager.pending_elevator_arrival:
		return false
	GameManager.pending_elevator_arrival = false
	for e in get_tree().get_nodes_in_group(&"minimap_elevator"):
		if e.has_method("arrival_position") and is_ancestor_of(e):
			p.global_position = e.arrival_position()
			DebugLog.info(str("[Spawn] 엘리베이터 앞에서 시작: ", p.global_position))
			return true
	push_warning("[Spawn] 엘리베이터로 왔는데 이 씬에 엘리베이터가 없습니다: %s" % scene_file_path)
	return false

func _show_stage_title() -> void:
	# Autoload에 StageTitleUI가 등록되어 있다고 가정하거나 
	# 혹은 직접 찾아서 실행합니다.
	if has_node("/root/StageTitleUI"):
		get_node("/root/StageTitleUI").play_title(stage_title_key)
	else:
		# Autoload가 아니더라도 씬에 수동으로 올렸을 경우를 대비
		var title_node = get_tree().root.find_child("StageTitleUI", true, false)
		if title_node and title_node.has_method("play_title"):
			title_node.play_title(stage_title_key)

func _input(event:InputEvent) -> void:
	if is_waiting_respawn and event.is_action_pressed("rest") and not GameManager.is_menu_open:
		is_waiting_respawn = false
		HUD.hide_death_screen()
		restart_stage()
		
func _on_player_died() -> void:
	if is_instance_valid(player):
		GameManager.on_player_died(scene_file_path, death_drop_position(player), player.death_cause)
	await Wait.seconds(self, respawn_input_delay)
	is_waiting_respawn = true
	HUD.show_restart_prompt()

# 금화를 떨어뜨릴 자리: 마지막으로 밟은 안전한 땅 (가시·구덩이·물속처럼 줍기 힘든 곳에서 죽어도 닿을 수 있게)
static func death_drop_position(p: Player) -> Vector2:
	return p.last_safe_position if p.has_safe_position else p.global_position

func restart_stage() -> void:
	GameManager.respawn_player()

# [추가] 이미 실행된 대화 블록 제거 함수
func _cleanup_triggered_dialogues() -> void:
	var blocks = get_tree().get_nodes_in_group("dialogue_blocks")
	# 만약 그룹이 안 잡혀있을 걸 대비해 수동으로도 찾음
	if blocks.is_empty():
		blocks = find_children("*", "DialogueBlock", true, false)
		
	for b in blocks:
		var db = b as DialogueBlock
		if db == null: continue
		
		# 대화 블록은 씬 경로 기반으로 ID를 생성하거나 
		# 에디터에서 수동으로 넣은 ID를 씁니다.
		if GameManager.triggered_dialogues.has(db.get_persist_id()):
			db.queue_free()

# [수정] 이미 죽은 적들(보스 + 로컬 잡몹) 제거 함수
func _cleanup_already_dead_enemies() -> void:
	for n in _cached_enemies:
		if not is_instance_valid(n): continue
		var e: EnemyBase = n as EnemyBase
		if e == null: continue
		
		var id: StringName = e.get_persist_id()
		
		# 1. 영구 사망한 보스인지 확인 (GameManager)
		if GameManager.defeated_bosses.get(id, false) and not e.get("is_rematch"):
			e.queue_free()
			continue
			
		# 2. 이번 판에 잡은 잡몹인지 확인 (killed_ids)
		if killed_ids.get(id, false) or GameManager.defeated_mobs.has(id):
			e.queue_free()

func _on_enemy_died(e: EnemyBase) -> void:
	if e.is_split_minion: # 분열로 생긴 작은 몹은 기록하지 않는다
		return
	var id = e.get_persist_id()

	# 1. 로컬 장부 기록 (잡몹 리젠 방지용, 껏다 켜면 초기화됨)
	killed_ids[id] = true
	
	# [중요] 보스 그룹이거나 Boss 클래스인 경우 잡몹 리스트에서 제외
	if not e.is_in_group("bosses") and not (e is Boss):
		GameManager.add_defeated_mob(id)
		DebugLog.info(str("잡몹 처치됨: ", id))
	else:
		# 2. [추가] 만약 이 녀석이 '보스'라면 GameManager에 영구 저장!
		GameManager.defeated_bosses[id] = true
		GameManager.save_game()
		DebugLog.info(str("보스 처치됨 (영구 저장): ", id))
	
func apply_room_rules(current_player_room: Vector2i) -> void:
	_cached_enemies = _cached_enemies.filter(func(n) : return is_instance_valid(n))
	
	# [개선] 카메라가 보고 있는 영역(화면)에 들어오는 모든 방의 적을 활성화합니다.
	# 1280x720 해상도에서는 640x360 방이 여러 개 보일 수 있기 때문입니다.
	
	var view_rect = Rect2()
	if cam:
		# [수정] 1280x720 하드코딩 대신, 현재 실제 뷰포트 크기를 가져와 줌 배율을 적용합니다.
		# 카메라가 옮겨 가는 중이어도 도착할 자리(구역이면 구역 전체) 기준으로 정한다
		var viewport_size = get_viewport_rect().size
		var half_size = (viewport_size / _cam_target_zoom) / 2.0
		view_rect = Rect2(_cam_pos_target() - half_size, half_size * 2.0)
	
	for n in _cached_enemies:
		if not is_instance_valid(n): continue
		var e: EnemyBase = n as EnemyBase
		if e == null: continue

		var eroom: Vector2i = room_from_pos(e.home_position)
		
		# 적의 집 위치가 현재 화면(view_rect) 안에 있거나, 
		# 플레이어와 같은 방에 있다면 활성화
		var is_visible_in_cam = view_rect.has_point(e.global_position) if cam else false
		
		if eroom == current_player_room or is_visible_in_cam:
			if reset_enemies_on_room_enter and not e._active and e.hp > 0:
				e.reset_to_home(false)
			e.set_active(true)
			if eroom == current_player_room and e.mutation != MobMutation.Kind.NONE and e.hp > 0:
				Tutorials.show_once(self, TUTORIAL_MUTATION)
		else:
			if deactivate_enemies_outside_room:
				# 화면 밖으로 나가면 리셋 및 비활성화
				if reset_enemies_on_room_enter and e._active and e.hp > 0:
					e.reset_to_home(false)
				e.set_active(false)

# --- 방 이동·적 ID·좌표 유틸리티 ---
func _physics_process(_delta: float) -> void:
	if not is_instance_valid(player): return
	var r: Vector2i = room_from_pos(player.global_position)
	if r != current_room: snap_to_room(r, false)

func snap_to_room(r: Vector2i, is_initial: bool) -> void:
	current_room = r
	if not is_initial:
		Tutorials.show_once(self, TUTORIAL_MINIMAP)
	var target := camera_target_for_room(r, _viewport_size())
	var zone: CameraZone = target.zone
	var same_zone := zone != null and zone == _current_zone
	var leaving: CameraZone = _current_zone
	_current_zone = zone
	_cam_target_zoom = target.zoom
	if _cam_tween:
		_cam_tween.kill()
		_cam_tween = null
	if is_initial or zone == leaving:
		# 보통 방 → 방 (또는 같은 구역 안): 바로 붙는다
		_cam_pos = target.pos
		cam.zoom = target.zoom
	else:
		# 구역에 들어가거나 나올 때: 위치·확대를 서서히
		var time: float = (zone if zone != null else leaving).transition_time
		_cam_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_cam_tween.tween_property(self, "_cam_pos", target.pos, time)
		_cam_tween.tween_property(cam, "zoom", target.zoom, time)
	cam.global_position = _cam_pos
	if not is_initial:
		if same_zone:
			pass # 같은 구역(보스방) 안에서 방을 옮겨도 투사체는 지우지 않는다
		elif clear_projectiles_on_room_change: clear_projectiles(true)
		elif clear_projectiles_outside_current_room: clear_projectiles(false)
	else:
		if clear_projectiles_outside_current_room: clear_projectiles(false)
	apply_room_rules(r)

# --- 카메라 구역 (CameraZone) ---
func camera_zone_for_room(r: Vector2i) -> CameraZone:
	for zone in _camera_zones(self):
		if zone.contains_room(r):
			return zone
	return null

func _camera_zones(node: Node) -> Array[CameraZone]:
	var out: Array[CameraZone] = []
	for child in node.get_children():
		if child is CameraZone:
			out.append(child)
		out.append_array(_camera_zones(child))
	return out

# 이 방에 있을 때 카메라가 설 자리와 확대: {"pos", "zoom", "zone"(없으면 null)}
func camera_target_for_room(r: Vector2i, viewport_size: Vector2) -> Dictionary:
	var zone := camera_zone_for_room(r)
	if zone != null:
		return {"pos": zone.world_rect(room_size, grid_origin).get_center(), "zoom": zone.zoom_for(room_size, viewport_size), "zone": zone}
	return {"pos": room_center(r), "zoom": _default_zoom, "zone": null}

func _cam_pos_target() -> Vector2:
	return camera_target_for_room(current_room, _viewport_size()).pos

func _viewport_size() -> Vector2:
	if is_inside_tree():
		return get_viewport_rect().size
	return Vector2(ProjectSettings.get_setting("display/window/size/viewport_width", 1280), ProjectSettings.get_setting("display/window/size/viewport_height", 720))

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

# 스테이지가 시작된 뒤에 생긴 몹 (분열 변이의 작은 몹). 방 규칙(활성화·리셋)을 같이 받는다
func register_spawned_enemy(e: EnemyBase) -> void:
	if not _cached_enemies.has(e):
		_cached_enemies.append(e)
	if not e.died.is_connected(_on_enemy_died):
		e.died.connect(_on_enemy_died)
	if is_instance_valid(player):
		apply_room_rules(room_from_pos(player.global_position))

const MUTANT_CHEST_SCENE_PATH := "res://Scenes/System/MutantRewardChest.tscn"

# 변이체 보상 상자. 상자 원점(바닥 중앙)이 pos에 온다
func spawn_mutant_chest(chest_id: String, pos: Vector2) -> Node:
	var chest_scene := load(MUTANT_CHEST_SCENE_PATH) as PackedScene
	if chest_scene == null:
		return null
	var chest := chest_scene.instantiate()
	chest.persist_id = chest_id
	(Entities if Entities else self).add_child(chest)
	chest.global_position = pos
	return chest

# 죽은 자리 금화 더미 (해골 표시). 줍기 전까지 계속 남는다
func _spawn_death_drops() -> void:
	var drops: Dictionary = GameManager.death_drops.get(scene_file_path, {})
	for drop_id in drops:
		var d: Dictionary = drops[drop_id]
		var drop := DeathDrop.new()
		drop.name = "DeathDrop_" + str(drop_id)
		drop.setup(scene_file_path, str(drop_id), int(d["gold"]), str(d.get("cause", "")))
		(Entities if Entities else self).add_child(drop)
		drop.global_position = Vector2(float(d["x"]), float(d["y"]))

# 리롤 전에 떨어진 상자는 씬을 다시 열어도 그 자리에 있다
func _spawn_saved_mutant_chests() -> void:
	var chests: Dictionary = GameManager.mutant_chests.get(scene_file_path, {})
	for chest_id in chests:
		var p: Array = chests[chest_id]
		spawn_mutant_chest(chest_id, Vector2(p[0], p[1]))

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
					var prefix: String = stage_prefix
					if prefix == "":
						# 접두사가 없으면 씬 이름에서 추출 (예: Stage_01 -> S01, Stage_tutorial -> S00)
						if name.to_lower().contains("tutorial"):
							prefix = "S00"
						else:
							var regex := RegEx.new()
							regex.compile("\\d+")
							var result := regex.search(name)
							if result:
								prefix = "S%02d" % int(result.get_string())
							else:
								prefix = "SXX"
					var s: String = "%s_R%02d_E%02d" % [prefix, rid2, idx]
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
	
# 연출용 카메라: world_pos 쪽으로 옮기며 확대(현재 확대 × zoom_mult). 시간 멈춤 중에도 실제 시간으로 움직인다.
# 끝나면 release_camera_focus로 방 카메라로 돌려놓는다
func focus_camera(world_pos: Vector2, zoom_mult: float, time: float) -> void:
	_tween_camera(world_pos, _cam_target_zoom * zoom_mult, time, Tween.EASE_OUT)

func release_camera_focus(time: float) -> void:
	var target := camera_target_for_room(current_room, _viewport_size())
	_tween_camera(target.pos, target.zoom, time, Tween.EASE_IN_OUT)

func _tween_camera(pos: Vector2, zoom: Vector2, time: float, ease_type: Tween.EaseType) -> void:
	if _cam_tween:
		_cam_tween.kill()
	_cam_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(ease_type).set_ignore_time_scale(true)
	_cam_tween.tween_property(self, "_cam_pos", pos, time)
	_cam_tween.tween_property(cam, "zoom", zoom, time)

func apply_camera_shake(amount: float) -> void:
	current_shake_strength = amount
