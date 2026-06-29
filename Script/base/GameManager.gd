# GameManager.gd
extends Node

# --- 1. 재화 및 스탯 관리 ---
var gold: int = 0
var player_max_hp: int = 100
var player_current_hp: int = 100
var player_damage: int = 10
var player_parry_damage_multifac: float = 1.5
var defeated_bosses: Dictionary = {} # 영구 사망 보스 목록
var talked_bosses: Dictionary = {}   # [추가] 보스 대화 완료 목록
var triggered_dialogues: Array = []  # [추가] 이미 실행된 대화 블록 ID 목록
var npc_talk_counts: Dictionary = {} # [추가] NPC별 대화 횟수 저장 (세이브용)
var defeated_mobs: Array = []
var pending_status: String = ""
var inventory: Array[ItemData] = [null, null, null, null, null, null, null, null, null, null, null, null, null, null, null]
var collected_items: Array = []
var visited_rooms: Array[Vector2i] = [] # [추가됨] 미니맵 방문 기록 저장용
var active_ui_count: int = 0
var flask_max_charges: int = 1
var flask_current_charges: int = 1
var flask_Hamount: int = 30
signal flask_changed 
signal stats_changed # [추가] 공격력/패링배율 등 스탯 변화 신호

var is_menu_open: bool = false
var mouse_sensitivity: float = 1.0
var screenshake_intensity: float = 0.5
signal gold_changed(amount: int)
signal hp_changed(current_hp, max_hp) # [추가] 체력 변화 신호
signal interact_msg_requested(msg)    # [추가] 상호작용 텍스트 띄우기 요청
signal interact_msg_hidden()          # [추가] 상호작용 텍스트 숨기기 요청

# 리스폰 중복 방지 플래그
var is_respawning: bool = false

# --- [추가] 전역 SFX 플레이어 (UI 전용) ---
var _ui_sfx_player: AudioStreamPlayer
const SND_UI_CLICK = preload("res://Assets/sounds/UIC.wav")

func _ready() -> void:
	load_settings()
	_setup_ui_sfx()

func _setup_ui_sfx() -> void:
	_ui_sfx_player = AudioStreamPlayer.new()
	add_child(_ui_sfx_player)
	_ui_sfx_player.bus = &"SFX"

func play_ui_click() -> void:
	if _ui_sfx_player and SND_UI_CLICK:
		_ui_sfx_player.stream = SND_UI_CLICK
		_ui_sfx_player.play()

# --- 설정(옵션) 관리 ---
func save_settings() -> void:
	var data = {
		"master_vol": db_to_linear(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Master"))),
		"bgm_vol": db_to_linear(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("BGM"))),
		"sfx_vol": db_to_linear(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX"))),
		"mouse_sens": mouse_sensitivity,
		"screen_shake": screenshake_intensity,
		"window_mode": DisplayServer.window_get_mode(),
		"borderless": DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_BORDERLESS),
		"resolution_x": DisplayServer.window_get_size().x,
		"resolution_y": DisplayServer.window_get_size().y,
		"fps_limit": Engine.max_fps
	}
	SaveManager.save_settings(data)

func load_settings() -> void:
	var data = SaveManager.load_settings()
	if data.is_empty(): return
	
	# 오디오 적용
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), linear_to_db(data.get("master_vol", 1.0)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("BGM"), linear_to_db(data.get("bgm_vol", 1.0)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), linear_to_db(data.get("sfx_vol", 1.0)))
	
	# 게임플레이 설정
	mouse_sensitivity = data.get("mouse_sens", 1.0)
	screenshake_intensity = data.get("screen_shake", 0.5)
	
	# 그래픽 설정 (지연 실행)
	call_deferred("_apply_graphics_settings", data)

func _apply_graphics_settings(data: Dictionary) -> void:
	Engine.max_fps = data.get("fps_limit", 60)
	var mode = data.get("window_mode", DisplayServer.WINDOW_MODE_WINDOWED)
	var is_borderless = data.get("borderless", false)
	
	DisplayServer.window_set_mode(mode)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, is_borderless)
	
	if mode == DisplayServer.WINDOW_MODE_WINDOWED:
		if is_borderless:
			# 테두리 없는 창의 경우 현재 모니터 크기로 맞춤
			var screen_id = DisplayServer.window_get_current_screen()
			var screen_size = DisplayServer.screen_get_size(screen_id)
			DisplayServer.window_set_size(screen_size)
			DisplayServer.window_set_position(DisplayServer.screen_get_position(screen_id))
		else:
			var res_x = data.get("resolution_x", 1280)
			var res_y = data.get("resolution_y", 720)
			
			# 시작 해상도가 너무 작으면 (예: 이전 버그로 저장된 640x360 등) 1280x720으로 강제 고정
			if res_x < 1280 or res_y < 720:
				res_x = 1280
				res_y = 720
				
			DisplayServer.window_set_size(Vector2i(res_x, res_y))
			
			# 화면 중앙 정렬 (다중 모니터 대응)
			var screen_id = DisplayServer.window_get_current_screen()
			var screen_rect = DisplayServer.screen_get_usable_rect(screen_id)
			var window_size = DisplayServer.window_get_size()
			var center_pos = screen_rect.position + (screen_rect.size - window_size) / 2
			DisplayServer.window_set_position(center_pos)

# --- 2. 체크포인트(세이브) 데이터 ---
var has_checkpoint: bool = false
var last_checkpoint_pos: Vector2
var last_scene_path: String = ""

var merchant_stocks: Dictionary = {
	"Stage1": [
		{"id": "health_potion", "stock": 3},
		{"id": "Parry_increase_potion", "stock": 1}
	],
	"Stage2": [
		{"id": "health_potion", "stock": 5},
		# {"id": "bomb", "stock": 2}
	]
}

func use_flask() -> bool:
	# 1. 플라스크 확인
	var has_flask = false
	for item in inventory:
		if item != null and item.id == "health_flask":
			has_flask = true
			break
	
	# 2. 플라스크 충전량이 있고 체력이 부족하면 사용
	if has_flask and flask_current_charges > 0 and player_current_hp < player_max_hp:
		flask_current_charges -= 1
		var new_hp = min(player_current_hp + flask_Hamount, player_max_hp)
		update_hp(new_hp)
		flask_changed.emit()
		return true
	
	# 3. [추가] 플라스크가 없거나 다 썼다면 인벤토리의 다른 힐링포션 검색
	return try_use_healing_potion()

func try_use_healing_potion() -> bool:
	if player_current_hp >= player_max_hp: return false
	
	for i in range(inventory.size()):
		var item = inventory[i]
		if item != null and item.type == ItemData.ItemType.CONSUMABLE and item.heal_amount > 0:
			# 플라스크는 여기서 제외 (위에서 이미 체크함)
			if item.id == "health_flask": continue
			
			var player = get_tree().get_first_node_in_group("player")
			if player:
				inventory[i] = null # 사용 후 소모 처리를 먼저 해서 UI 갱신 시 빈칸이 되도록 함
				item.use(player)
				return true
	return false

func add_defeated_mob(id: String) -> void:
	if id != "" and not defeated_mobs.has(id):
		defeated_mobs.append(id)
		
func add_collected_item(id: String) -> void:
	if not collected_items.has(id):
		collected_items.append(id)
		
# [추가] 휴식 시 호출: 일반 몹 기록만 싹 지움! (이게 핵심!)
func reset_mobs() -> void:
	defeated_mobs.clear()
	
func add_defeated_boss(id: String) -> void:
	if not defeated_bosses.has(id):
		defeated_bosses[id] = true

func add_player_damage(amount: int) -> void:
	player_damage += amount
	stats_changed.emit()

func add_parry_ratio(amount: float) -> void:
	player_parry_damage_multifac += amount
	stats_changed.emit()

# --- [함수 3] 체크포인트 저장 ---
func save_checkpoint(pos: Vector2) -> void:
	has_checkpoint = true
	last_checkpoint_pos = pos
	var current_scene = get_tree().current_scene
	if current_scene:
		last_scene_path = current_scene.scene_file_path

func add_item(item: ItemData) -> bool:
	# 빈 칸 찾기
	for i in range(inventory.size()):
		if inventory[i] == null:
			inventory[i] = item # 리소스 파일 자체를 저장!
			return true 
			
	return false
	
# --- [함수 4] 플레이어 사망 시 부활 처리 ---
func respawn_player() -> void:
	# 안전장치: 이미 리스폰 중이더라도 너무 오래 걸리면 강제 초기화 (혹은 무조건 실행)
	is_respawning = true
	
	# [1] 임시 부활 (사망 상태 해제)
	player_current_hp = player_max_hp
	
	# [2] 저장된 데이터 불러오기
	var load_result = load_game()
	
	# [3] 몹 사망 기록 초기화 (휴식 효과)
	reset_mobs()
	
	get_tree().paused = false 
	Engine.time_scale = 1.0
	
	# [4] 씬 전환 시도
	if load_result and has_checkpoint and last_scene_path != "" and ResourceLoader.exists(last_scene_path):
		print("[Respawn] 세이브 로드 성공. 체크포인트로 이동: ", last_scene_path)
		call_deferred("_change_scene_safe", last_scene_path)
	else:
		# 세이브가 없거나 경로가 잘못된 경우: 1스테이지 강제 이동
		player_current_hp = player_max_hp
		var stage1_path = get_stage_path(1)
		print("[Respawn] 세이브 없음/오류. 1스테이지로 시작: ", stage1_path)
		call_deferred("_change_scene_safe", stage1_path)
		

func ui_opened() -> void:
	active_ui_count += 1
	is_menu_open = true
	CustomCursor.show_cursor()

func ui_closed() -> void:
	active_ui_count -= 1
	if active_ui_count <= 0:
		active_ui_count = 0
		is_menu_open = false
		CustomCursor.hide_cursor()
	
func save_game() -> void:
	if player_current_hp <= 0: return
	var data = get_data_for_save()
	SaveManager.save_game(data)

func load_game() -> bool:
	var data = SaveManager.load_game()
	if data.is_empty(): return false
	
	load_data_from_save(data)
	return true

# --- [데이터 직렬화] 저장용 딕셔너리 생성 ---
func get_data_for_save() -> Dictionary:
	var inventory_save_data = []
	for item in inventory:
		if item == null:
			inventory_save_data.append(null)
		else:
			inventory_save_data.append({"id": item.id})
			
	return {
		"gold": gold,
		"current_hp": player_current_hp,
		"max_hp": player_max_hp,
		"damage": player_damage,
		"parrydamage": player_parry_damage_multifac,
		"defeated_bosses": defeated_bosses,
		"talked_bosses": talked_bosses,
		"triggered_dialogues": triggered_dialogues,
		"npc_talk_counts": npc_talk_counts,
		"defeated_mobs": defeated_mobs,
		"has_checkpoint": has_checkpoint,
		"scene_path": last_scene_path,
		"pos_x": last_checkpoint_pos.x,
		"pos_y": last_checkpoint_pos.y,
		"inventory": inventory_save_data,
		"collected_items": collected_items,
		"merchant_stocks": merchant_stocks,
		"visited_rooms": visited_rooms.map(func(r): return {"x": r.x, "y": r.y}),
		"flask_max": flask_max_charges,
		"flask_current": flask_current_charges
	}

# --- [데이터 역직렬화] 불러온 데이터 적용 ---
func load_data_from_save(data: Dictionary) -> void:
	gold = data.get("gold", 0)
	player_current_hp = data.get("current_hp", 100)
	player_max_hp = data.get("max_hp", 100)
	player_damage = data.get("damage", 10)
	player_parry_damage_multifac = data.get("parrydamage", 1.5)
	defeated_mobs = data.get("defeated_mobs", [])
	defeated_bosses = data.get("defeated_bosses", {})
	talked_bosses = data.get("talked_bosses", {})
	triggered_dialogues = data.get("triggered_dialogues", [])
	npc_talk_counts = data.get("npc_talk_counts", {})
	has_checkpoint = data.get("has_checkpoint", false)
	
	var loaded_path = data.get("scene_path", "")
	if loaded_path == "" or loaded_path.get_file() == "Stage.tscn":
		last_scene_path = get_stage_path(1)
	else:
		last_scene_path = loaded_path
	
	collected_items = data.get("collected_items", [])
	merchant_stocks = data.get("merchant_stocks", {})
	flask_max_charges = data.get("flask_max", 1)
	flask_current_charges = data.get("flask_current", 1)
	
	# 미니맵 방문 기록 복구
	visited_rooms.clear()
	for r in data.get("visited_rooms", []):
		visited_rooms.append(Vector2i(int(r.get("x", 0)), int(r.get("y", 0))))
	
	# 인벤토리 복구
	inventory.fill(null)
	var loaded_inv = data.get("inventory", [])
	for i in range(min(loaded_inv.size(), inventory.size())):
		var slot = loaded_inv[i]
		if typeof(slot) == TYPE_DICTIONARY and slot.has("id"):
			inventory[i] = get_item_by_id(slot["id"])
	
	last_checkpoint_pos = Vector2(data.get("pos_x", 0.0), data.get("pos_y", 0.0))
	is_respawning = false

	
func get_stage_path(stage_num: int) -> String:
	return "res://Scenes/Stage/Stage_%02d.tscn" % stage_num

func apply_hitstop(time_scale: float, duration: float):
	Engine.time_scale = time_scale
	await get_tree().create_timer(duration, true, false, true).timeout
	Engine.time_scale = 1.0

var item_database: Dictionary = {
	"health_potion": "res://resources/items/health_potion.tres",
	"health_flask": "res://resources/items/health_flask.tres",
	"Parry_increase_potion": "res://resources/items/Parry_increase_potion.tres"
}

func get_item_by_id(item_id: String) -> ItemData:
	if item_database.has(item_id):
		var path = item_database[item_id]
		if ResourceLoader.exists(path):
			return load(path)
		else:
			print ("Not found Item")
	return null
	
func reset_data() -> void:
	print("[GameManager] Resetting all game data for New Game...")
	gold = 0
	player_current_hp = 100
	player_max_hp = 100
	player_damage = 10
	player_parry_damage_multifac = 1.5
	has_checkpoint = false
	last_checkpoint_pos = Vector2.ZERO
	last_scene_path = ""
	
	defeated_bosses.clear()
	talked_bosses.clear()
	triggered_dialogues.clear()
	npc_talk_counts.clear()
	defeated_mobs.clear()
	collected_items.clear()
	visited_rooms.clear()
	
	inventory.fill(null)
	
	flask_max_charges = 1
	flask_current_charges = 1
	
	# 상점 재고 초기화
	merchant_stocks = {
		"Stage1": [
			{"id": "health_potion", "stock": 3},
			{"id": "Parry_increase_potion", "stock": 1}
		],
		"Stage2": [
			{"id": "health_potion", "stock": 5},
		]
	}
	
	active_ui_count = 0
	is_menu_open = false
	is_respawning = false
	pending_status = ""
	
	# UI 업데이트 신호 발송
	gold_changed.emit(gold)
	hp_changed.emit(player_current_hp, player_max_hp)
	flask_changed.emit()

# --- [함수 수정] 플레이어 체력 갱신 ---
# Player 스크립트에서 직접 변수를 바꾸는 대신, 이 함수를 쓰도록 할 겁니다.
func update_hp(new_hp: int) -> void:
	player_current_hp = new_hp
	
	# [추가] 실제 씬에 있는 플레이어 노드의 HP도 같이 갱신해줘야 함 (동기화)
	var p = get_tree().get_first_node_in_group("player")
	if p:
		p.hp = new_hp
		
	# 체력이 변했음을 UI에게 알림
	hp_changed.emit(player_current_hp, player_max_hp)
	
func update_gold(amount: int) -> void:
	# 2. 값 변경
	gold += amount
	
	# 3. [핵심] "돈 바뀌었으니 UI 업데이트해!"라고 신호 발사
	gold_changed.emit(gold)
		
	
# --- [추가됨] 실제로 씬을 변경하는 함수들 ---
func _change_scene_safe(path: String) -> void:
	
	var error = get_tree().change_scene_to_file(path)
	if error != OK:
		print("Error Changing Scene: ", error)
	# 변경 완료 후 리스폰 플래그 해제
	is_respawning = false

func _reload_scene_safe() -> void:
	# 현재 씬 재시작
	get_tree().reload_current_scene()
	# 변경 완료 후 리스폰 플래그 해제
	is_respawning = false
