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
# 씬 이동·불러오기 때 다음 플레이어에게 넘길 상태이상. 불러오면 세이브의 status_effects로 채워지고, 새 게임 때 비운다.
var carried_status_effects: Array[StatusEffect] = []
var collected_items: Array = []
var loot_seed: int = 0 # 세이브마다 정해지는 랜덤 보상 시드 (새 게임 때 생성, 세이브에 저장)
var current_slot: int = 1 # 지금 플레이 중인 세이브 슬롯 (메인 메뉴에서 고름). 저장·불러오기는 이 슬롯 파일로
var visited_rooms_by_scene: Dictionary = {} # 씬 경로별 미니맵 방문 기록
var active_ui_count: int = 0
var _ui_owners: Dictionary = {}
var flask_max_charges: int = 1
var flask_current_charges: int = 1
var flask_heal_amount: int = 30 # 플라스크 한 번에 회복하는 HP
signal flask_changed 
signal stats_changed # [추가] 공격력/패링배율 등 스탯 변화 신호

var is_menu_open: bool = false
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
	loot_seed = new_loot_seed() # 세이브 없이 바로 시작해도 시드가 있도록. 불러오면 세이브 값으로 덮어씀
	_setup_ui_sfx()

func _setup_ui_sfx() -> void:
	_ui_sfx_player = AudioStreamPlayer.new()
	add_child(_ui_sfx_player)
	_ui_sfx_player.bus = &"SFX"

func play_ui_click() -> void:
	if _ui_sfx_player and SND_UI_CLICK:
		_ui_sfx_player.stream = SND_UI_CLICK
		_ui_sfx_player.play()

# --- 2. 체크포인트(세이브) 데이터 ---
var has_checkpoint: bool = false
var last_checkpoint_pos: Vector2
var last_scene_path: String = ""

# 상점별 판매 수량만 저장한다. 남은 재고 = ShopStock의 처음 재고 - 판매 수량
var shop_sold: Dictionary = {} # shop_id -> {item_id: 판매 수량}

# 상점 UI용 목록: [{"item": ItemData, "stock": 남은 수량}]
func get_shop_stock(shop_id: String) -> Array:
	var result: Array = []
	var shop := Database.get_shop(shop_id)
	if shop == null:
		return result
	var sold: Dictionary = shop_sold.get(shop_id, {})
	for entry in shop.entries:
		if entry == null or entry.item == null:
			continue
		var remaining := maxi(0, entry.stock - int(sold.get(entry.item.id, 0)))
		result.append({"item": entry.item, "stock": remaining})
	return result

func record_shop_purchase(shop_id: String, item_id: String) -> void:
	if not shop_sold.has(shop_id):
		shop_sold[shop_id] = {}
	shop_sold[shop_id][item_id] = int(shop_sold[shop_id].get(item_id, 0)) + 1

# 버전 2 저장의 남은 재고(merchant_stocks)를 현재 상점 기준 판매 수량으로 바꾼다.
func _shop_sold_from_legacy(merchant_stocks: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for shop_id in merchant_stocks:
		var shop := Database.get_shop(shop_id)
		if shop == null:
			continue
		for saved in merchant_stocks[shop_id]:
			for entry in shop.entries:
				if entry != null and entry.item != null and entry.item.id == saved["id"]:
					var sold := entry.stock - int(saved["stock"])
					if sold > 0:
						if not result.has(shop_id):
							result[shop_id] = {}
						result[shop_id][entry.item.id] = sold
	return result

func use_flask() -> bool:
	# 1. 플라스크 확인
	var has_flask := Inventory.has_item("health_flask")
	
	# 2. 플라스크 충전량이 있고 체력이 부족하면 사용
	if has_flask and flask_current_charges > 0 and player_current_hp < player_max_hp:
		flask_current_charges -= 1
		var new_hp = min(player_current_hp + flask_heal_amount, player_max_hp)
		update_hp(new_hp)
		flask_changed.emit()
		return true
	
	# 3. [추가] 플라스크가 없거나 다 썼다면 인벤토리의 다른 힐링포션 검색
	return try_use_healing_potion()

func try_use_healing_potion() -> bool:
	if player_current_hp >= player_max_hp: return false
	
	for i in range(Inventory.inventory.size()):
		var item = Inventory.inventory[i]
		if item != null and item.type == ItemData.ItemType.CONSUMABLE and item.heal_amount > 0:
			# 플라스크는 여기서 제외 (위에서 이미 체크함)
			if item.id == "health_flask": continue
			
			var player = get_tree().get_first_node_in_group("player")
			if player:
				Inventory.remove_item_at(i) # 사용 후 소모 처리를 먼저 해서 UI 갱신 시 빈칸이 되도록 함
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

# --- [함수 4] 플레이어 사망 시 부활 처리 ---
func respawn_player() -> void:
	# 안전장치: 이미 리스폰 중이더라도 너무 오래 걸리면 강제 초기화 (혹은 무조건 실행)
	is_respawning = true
	
	# [1] 임시 부활 (사망 상태 해제)
	player_current_hp = player_max_hp
	
	# [2] 저장된 데이터 불러오기
	var load_result = load_game()
	# 죽으면 상태이상은 풀린다: 독에 걸린 채 낮은 HP로 저장해도 부활 직후 다시 죽는 무한 반복이 없도록
	carried_status_effects.clear()

	# [3] 몹 사망 기록 초기화 (휴식 효과)
	reset_mobs()
	
	get_tree().paused = false 
	Engine.time_scale = 1.0
	
	# [4] 씬 전환 시도
	if load_result and has_checkpoint and last_scene_path != "" and ResourceLoader.exists(last_scene_path):
		DebugLog.info(str("[Respawn] 세이브 로드 성공. 체크포인트로 이동: ", last_scene_path))
		call_deferred("_change_scene_safe", last_scene_path)
	else:
		# 세이브가 없거나 경로가 잘못된 경우: 1스테이지 강제 이동
		player_current_hp = player_max_hp
		var stage1_path = get_stage_path(1)
		DebugLog.info(str("[Respawn] 세이브 없음/오류. 1스테이지로 시작: ", stage1_path))
		call_deferred("_change_scene_safe", stage1_path)
		

func ui_opened(owner: Node, needs_cursor: bool = true) -> void:
	_ui_owners[owner.get_instance_id()] = {"owner": weakref(owner), "cursor": needs_cursor}
	_refresh_ui_state()

func ui_closed(owner: Node) -> void:
	_ui_owners.erase(owner.get_instance_id())
	_refresh_ui_state()

func _refresh_ui_state() -> void:
	var needs_cursor := false
	for id in _ui_owners.keys():
		var entry: Dictionary = _ui_owners[id]
		if entry["owner"].get_ref() == null:
			_ui_owners.erase(id)
		else:
			needs_cursor = needs_cursor or entry["cursor"]
	active_ui_count = _ui_owners.size()
	is_menu_open = active_ui_count > 0
	if needs_cursor:
		CustomCursor.show_cursor()
	else:
		CustomCursor.hide_cursor()

func get_visited_rooms(scene_path: String) -> Array:
	if not visited_rooms_by_scene.has(scene_path):
		visited_rooms_by_scene[scene_path] = []
	return visited_rooms_by_scene[scene_path]

func visit_room(scene_path: String, room: Vector2i) -> void:
	var rooms := get_visited_rooms(scene_path)
	if not rooms.has(room):
		rooms.append(room)

func _visited_rooms_for_save() -> Dictionary:
	var result: Dictionary = {}
	for path in visited_rooms_by_scene:
		var rooms: Array = visited_rooms_by_scene[path]
		result[path] = rooms.map(func(r): return {"x": r.x, "y": r.y})
	return result

func save_game() -> bool:
	if player_current_hp <= 0: return false
	var data = get_data_for_save()
	return SaveManager.save_game(data, current_save_path())

func load_game() -> bool:
	var data = SaveManager.load_game(current_save_path())
	if data.is_empty(): return false
	
	load_data_from_save(data)
	return true

# --- [데이터 직렬화] 저장용 딕셔너리 생성 ---
func get_data_for_save() -> Dictionary:
			
	return {
		"save_version": SaveManager.SAVE_VERSION,
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
		"stage_title_key": _current_stage_title_key(), # 슬롯 선택 화면 표시용
		"pos_x": last_checkpoint_pos.x,
		"pos_y": last_checkpoint_pos.y,
		"inventory": Inventory.to_save(),
		"collected_items": collected_items,
		"loot_seed": loot_seed,
		"shop_sold": shop_sold,
		"visited_rooms_by_scene": _visited_rooms_for_save(),
		"flask_max": flask_max_charges,
		"flask_current": flask_current_charges,
		"status_effects": _status_effects_for_save()
	}

# 저장 순간 플레이어에게 걸려 있는 상태이상 (씬 전환 중이라 플레이어가 없으면 들고 가던 것)
func _status_effects_for_save() -> Array:
	var effects: Array = carried_status_effects
	var player := get_tree().get_first_node_in_group("player") as CombatBody2D
	if player != null and player.hp > 0:
		effects = player.get_status_effects().get_effects()
	var out: Array = []
	for effect: StatusEffect in effects:
		out.append(effect.to_save())
	return out

# --- [데이터 역직렬화] 불러온 데이터 적용 ---
func load_data_from_save(data: Dictionary) -> void:
	# 저장 당시 걸려 있던 상태이상은 다음에 생기는 플레이어가 이어받는다
	carried_status_effects.clear()
	for entry in data.get("status_effects", []):
		var effect: StatusEffect = StatusEffect.from_save(entry) if entry is Dictionary else null
		if effect != null:
			carried_status_effects.append(effect)
		else:
			push_warning("Skipped invalid status effect in save: %s" % str(entry))
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
	# 시드가 없는 옛 세이브는 새로 만든다 (다음 저장부터 고정)
	loot_seed = int(data["loot_seed"]) if data.has("loot_seed") else new_loot_seed()
	if data.has("shop_sold"):
		shop_sold = data["shop_sold"].duplicate(true)
	else:
		shop_sold = _shop_sold_from_legacy(data.get("merchant_stocks", {}))
	flask_max_charges = data.get("flask_max", 1)
	flask_current_charges = data.get("flask_current", 1)
	
	# 미니맵 방문 기록 복구
	visited_rooms_by_scene.clear()
	var saved_rooms: Dictionary = data.get("visited_rooms_by_scene", {})
	# 이전 세이브는 씬 구분이 없으므로 체크포인트 씬에만 이전한다.
	if saved_rooms.is_empty() and data.has("visited_rooms"):
		saved_rooms = {last_scene_path: data["visited_rooms"]}
	for path in saved_rooms:
		for r in saved_rooms[path]:
			visit_room(str(path), Vector2i(int(r["x"]), int(r["y"])))
	
	Inventory.load_from_save(data.get("inventory", []))
	
	last_checkpoint_pos = Vector2(data.get("pos_x", 0.0), data.get("pos_y", 0.0))
	is_respawning = false

	
func get_stage_path(stage_num: int) -> String:
	return "res://Scenes/Stage/Stage_%02d.tscn" % stage_num

var _hitstop_token: int = 0
var _hitstop_end_ms: int = 0

# 겹친 히트스탑은 더 느린 배율과 더 늦은 종료 시각을 유지하고, 마지막 호출만 시간을 복구한다.
func apply_hitstop(time_scale: float, duration: float):
	var now := Time.get_ticks_msec()
	var end_ms := now + int(duration * 1000.0)
	if _hitstop_end_ms > now:
		time_scale = minf(time_scale, Engine.time_scale)
		end_ms = maxi(end_ms, _hitstop_end_ms)
	_hitstop_token += 1
	var token := _hitstop_token
	_hitstop_end_ms = end_ms
	Engine.time_scale = time_scale
	await get_tree().create_timer((end_ms - now) / 1000.0, true, false, true).timeout
	if token == _hitstop_token:
		_hitstop_end_ms = 0
		Engine.time_scale = 1.0

func current_save_path() -> String:
	return SaveManager.slot_path(current_slot)

func _current_stage_title_key() -> String:
	var scene := get_tree().current_scene if is_inside_tree() else null
	if scene != null and "stage_title_key" in scene:
		return str(scene.stage_title_key)
	return ""

# --- 랜덤 보상 시드 ---
# 상자·박스 보상은 (세이브 시드 + 보상 출처 id)로 굴린다.
# 같은 세이브에서는 다시 불러와도 같은 상자에서 같은 결과가 나오고(리셋 노가다 방지), 새 게임마다 바뀐다.
func new_loot_seed() -> int:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return rng.randi() # 0 ~ 2^32-1: JSON 숫자(double)로 정확히 저장된다

func make_loot_rng(source_id: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = ("%d:%s" % [loot_seed, source_id]).hash()
	return rng
	
func reset_data() -> void:
	DebugLog.info("[GameManager] Resetting all game data for New Game...")
	carried_status_effects.clear()
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
	visited_rooms_by_scene.clear()
	loot_seed = new_loot_seed()

	Inventory.reset()

	flask_max_charges = 1
	flask_current_charges = 1
	
	shop_sold.clear()
	
	_ui_owners.clear()
	_refresh_ui_state()
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
	
# 골드를 얻거나 쓰면 HUD를 잠깐 띄워 바뀐 금액을 보여준다
# (불러오기·새 게임 때의 표시 갱신은 gold_changed만 보내고 HUD를 띄우지 않는다)
func update_gold(amount: int) -> void:
	gold += amount
	gold_changed.emit(gold)
	if amount != 0:
		HUD.show_hud_temporarily()
		
	
# --- [추가됨] 실제로 씬을 변경하는 함수들 ---
func _change_scene_safe(path: String) -> void:
	
	var error = get_tree().change_scene_to_file(path)
	if error != OK:
		push_error("Error changing scene: " + str(error))
	# 변경 완료 후 리스폰 플래그 해제
	is_respawning = false
