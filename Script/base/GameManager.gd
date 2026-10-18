# GameManager.gd
extends Node

# --- 1. 재화 및 스탯 관리 ---
var gold: int = 0
var player_max_hp: int = 100
var player_current_hp: int = 100
var player_damage: int = 10
var heavy_attack_unlocked: bool = false # 강공격 (수상한 과학자의 약물을 마시면 해금)
var double_jump_unlocked: bool = false # 더블 점프 (해금 아이템을 쓰면 영구 해금)
var player_parry_damage_multifac: float = 1.5
var player_attack_speed_bonus: float = 0.0 # 영구 공격 속도 + (0.1 = 10% 빠르게). 장비 보너스와 더한다
var guard_reduction: int = 10 # 일반 가드로 막은 투사체 피해에서 빼는 양
var breath_bonus: float = 0.0 # 물속에서 버티는 시간(초) +
var defeated_bosses: Dictionary = {} # 영구 사망 보스 목록
var talked_bosses: Dictionary = {}   # [추가] 보스 대화 완료 목록
var triggered_dialogues: Array = []  # [추가] 이미 실행된 대화 블록 ID 목록
var npc_talk_counts: Dictionary = {} # [추가] NPC별 대화 횟수 저장 (세이브용)
var seen_tutorials: Array = [] # 한 번 본 도움말 키 (TutorialPopup.show_once). 세이브용
var quest_progress: Dictionary = {} # 퀘스트별 진행 수 (예: "lost_lambs" = 양치기에게 돌려준 새끼양 수). 세이브용
var rematch_epochs: Dictionary = {} # 보름달 재도전에서 이긴 보스 {persist_id: 그때의 mutation_epoch} — 같은 보름달엔 다시 안 나온다. 세이브용
var bestiary: Dictionary = {} # 몬스터 도감 {종류(씬 경로): 처치 수} — 한 번이라도 잡은 몹·보스. 세이브용
var nohit_bosses: Dictionary = {} # 맞지 않고 잡은 보스 {persist_id: true}. 세이브용
var defeated_mobs: Array = []
var pending_status: String = ""
# 씬 이동·불러오기 때 다음 플레이어에게 넘길 상태이상. 불러오면 세이브의 status_effects로 채워지고, 새 게임 때 비운다.
var carried_status_effects: Array[StatusEffect] = []
# 다른 씬의 지름길 문으로 이동 중일 때 도착할 문 {"link_id", "side"}. 다음 스테이지가 플레이어를 그 문 앞에 소환하고 비운다 (저장 안 함)
var pending_shortcut_arrival: Dictionary = {}
# 엘리베이터로 다른 층에 가는 중. 다음 스테이지가 플레이어를 그 층 엘리베이터 앞에 소환하고 끈다 (저장 안 함)
var pending_elevator_arrival: bool = false
# 이어 하기 위치: 게임을 나갈 때(메인 메뉴로·창 닫기) 저장된 그 자리. 한 번 불러와 시작하면 지운다 (죽으면 쓰지 않고 세이브 포인트로)
var resume_scene_path: String = ""
var resume_pos: Vector2 = Vector2.ZERO
var collected_items: Array = []
var loot_seed: int = 0 # 세이브마다 정해지는 랜덤 보상 시드 (새 게임 때 생성, 세이브에 저장)
# 상자 스탯 포션 불운 보정 상태 (LootTable.stat_pity): 연속 실패 수, 이번 세트에서 받은 종류, 지금까지 받은 수. 저장됨
var stat_loot: Dictionary = {"fails": 0, "taken": [], "drops": 0}
# 몹 변이 리롤 회차. 휴식할 때(reset_mobs)마다 1 오르고 (죽어서 몹만 되살아날 때는 그대로), 세이브에 저장된다 (MobMutation)
var mutation_epoch: int = 0
# 변이체가 떨군 보상 상자 {씬 경로: {상자 id: [x, y]}}. 다음 리롤까지 남는다
var mutant_chests: Dictionary = {}
# 지상층 달빛 통로가 열려 있는가. 열려 있으면 달의 위상(MoonPhase, mutation_epoch로 정해짐) 효과가 적용된다. 저장됨 ("moon_passage")
var moon_passage_open: bool = false
# 죽은 자리에 떨어뜨린 금화 {씬 경로: {더미 id: {"x", "y", "gold"}}}. 다 주울 때까지 남고, 여러 번 죽으면 더미도 여러 개. 저장됨 ("death_drops")
var death_drops: Dictionary = {}
const DEATH_DROP_RATIO := 0.5 # 죽을 때 떨어뜨리는 금화 비율 (동화 10 단위로 내림)
# 자동 저장 (죽을 때·스테이지에 들어올 때·인벤토리가 바뀔 때). 헤드리스(테스트)에서는 꺼져 있다 — 실제 세이브 파일을 건드리지 않도록
var autosave_enabled: bool = DisplayServer.get_name() != "headless"
var _autosave_queued: bool = false
var respawned_from_death: bool = false # 죽고 부활한 직후 다음 스테이지가 사망 도움말(TUTORIAL_DEATH)을 띄우고 끈다 (저장 안 함)
signal moon_changed # 위상이 바뀌거나(휴식·부활) 통로를 열고 닫을 때
var current_slot: int = 1 # 지금 플레이 중인 세이브 슬롯 (메인 메뉴에서 고름). 저장·불러오기는 이 슬롯 파일로
var visited_rooms_by_scene: Dictionary = {} # 씬 경로별 미니맵 방문 기록
var seen_map_objects: Dictionary = {} # 씬 경로별로 플레이어가 가까이 가 본 미니맵 오브젝트 키 (MinimapUI.map_object_key)
# 씬 경로별 미니맵 지형 기록: {"w", "h", "bits"} — 맵 타일 한 칸당 1비트 (플레이어 주변 몇 칸 안에 들어온 칸)
var seen_tiles: Dictionary = {}
var _fog_from_rooms: Array = [] # 지형 기록이 없던 옛 세이브: 처음 열 때 다녀간 방 전체를 본 걸로 채울 씬들
var active_ui_count: int = 0
var _ui_owners: Dictionary = {}
var flask_max_charges: int = 1
var flask_current_charges: int = 1
const FLASK_HEAL_BASE: int = 30
var flask_heal_amount: int = FLASK_HEAL_BASE # 플라스크 한 번에 회복하는 HP (소모품으로 증가, 저장됨)
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
const SND_UI_CLICK = preload("res://Assets/sounds/system/UIC.wav")

func _ready() -> void:
	loot_seed = new_loot_seed() # 세이브 없이 바로 시작해도 시드가 있도록. 불러오면 세이브 값으로 덮어씀
	_setup_ui_sfx()
	Inventory.inventory_changed.connect(queue_autosave) # 아이템을 얻거나 쓰면 저장

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
	if player_current_hp <= 0: # 사망 화면에서 인벤토리로 마시는 것 막기
		return false
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
	if player_current_hp <= 0 or player_current_hp >= player_max_hp: return false
	
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
		
# 휴식(R) 시 호출: 몹을 되살리고, 변이·달의 위상도 다음 회차로 넘긴다
func reset_mobs() -> void:
	revive_mobs()
	# 변이 리롤: 다음 회차로 넘어가고, 지난 회차의 보상 상자(열었든 안 열었든)는 치운다
	mutation_epoch += 1
	mutant_chests.clear()
	collected_items = collected_items.filter(func(id): return not str(id).begins_with(MUTANT_CHEST_SAVE_PREFIX))
	moon_changed.emit()

# 쓰러뜨린 일반 몹을 모두 되살린다 (보스 제외). 죽고 부활할 때는 이것만 — 달·변이는 그대로라 같은 위상에서 바로 다시 도전할 수 있다
func revive_mobs() -> void:
	defeated_mobs.clear()

# 지금 달의 위상 (보름달 → 반달 → 그믐달, 리롤 회차마다 다음 위상)
func moon_phase() -> MoonPhase.Phase:
	return MoonPhase.phase_for_epoch(mutation_epoch)

# 달빛이 들어오는 밤인가 (통로가 열려 있을 때만 위상 효과가 있다)
func is_moonlit(phase: MoonPhase.Phase) -> bool:
	return moon_passage_open and moon_phase() == phase

func set_moon_passage(open: bool) -> void:
	if moon_passage_open == open:
		return
	moon_passage_open = open
	moon_changed.emit()

const MUTANT_CHEST_SAVE_PREFIX := "chest:mutant:"

func add_mutant_chest(scene_path: String, chest_id: String, pos: Vector2) -> void:
	if not mutant_chests.has(scene_path):
		mutant_chests[scene_path] = {}
	mutant_chests[scene_path][chest_id] = [pos.x, pos.y]
	
func add_defeated_boss(id: String) -> void:
	if not defeated_bosses.has(id):
		defeated_bosses[id] = true

# 강공격 해금: 한 번만 안내(튜토리얼 팝업)를 띄운다
func unlock_heavy_attack() -> void:
	if heavy_attack_unlocked:
		return
	heavy_attack_unlocked = true
	TutorialPopup.display(&"TUTORIAL_HEAVY_ATTACK")

# 더블 점프 해금: 한 번만 안내(튜토리얼 팝업)를 띄운다
func has_seen_tutorial(key: String) -> bool:
	return seen_tutorials.has(key)

func mark_tutorial_seen(key: String) -> void:
	if key != "" and not seen_tutorials.has(key):
		seen_tutorials.append(key)

# 퀘스트 진행 수 (없으면 0). JSON에서 읽은 숫자는 float이라 int로 바꿔 돌려준다
# --- 도감·노히트·재도전 ---
func record_kill(kind: String) -> void:
	if kind.is_empty():
		return
	bestiary[kind] = int(bestiary.get(kind, 0)) + 1
	TutorialPopup.show_once(&"TUTORIAL_BESTIARY") # 처음 잡았을 때: 도감 [B]

func kill_count(kind: String) -> int:
	return int(bestiary.get(kind, 0))

func record_nohit(boss_id: String) -> void:
	if not boss_id.is_empty():
		nohit_bosses[boss_id] = true

# 이 보스를 지금 보름달에 다시 불러낼 수 있는가 (해치 열림 + 보름달, 이번 보름달 회차에 아직 안 이겼다)
func can_rematch(boss_id: String) -> bool:
	return is_moonlit(MoonPhase.Phase.FULL) and int(rematch_epochs.get(boss_id, -1)) != mutation_epoch

func record_rematch_win(boss_id: String) -> void:
	rematch_epochs[boss_id] = mutation_epoch

func get_quest_progress(quest_id: String) -> int:
	return int(quest_progress.get(quest_id, 0))

func set_quest_progress(quest_id: String, value: int) -> void:
	quest_progress[quest_id] = maxi(0, value)

func unlock_double_jump() -> void:
	if double_jump_unlocked:
		return
	double_jump_unlocked = true
	TutorialPopup.display(&"TUTORIAL_DOUBLE_JUMP")

func add_player_damage(amount: int) -> void:
	player_damage += amount
	stats_changed.emit()

func add_parry_ratio(amount: float) -> void:
	player_parry_damage_multifac += amount
	stats_changed.emit()

func add_attack_speed(amount: float) -> void:
	player_attack_speed_bonus += amount
	stats_changed.emit()

func add_guard_reduction(amount: int) -> void:
	guard_reduction += amount
	stats_changed.emit()

func add_breath(seconds: float) -> void:
	breath_bonus += seconds
	stats_changed.emit()

# 플라스크 최대 사용 횟수 +. 늘어난 칸은 바로 채워 준다
func add_flask_charges(amount: int) -> void:
	flask_max_charges += amount
	flask_current_charges += amount
	flask_changed.emit()

# 플라스크 한 번 회복량 +
func add_flask_heal(amount: int) -> void:
	flask_heal_amount += amount
	flask_changed.emit()

# --- [함수 3] 체크포인트 저장 ---
func save_checkpoint(pos: Vector2) -> void:
	has_checkpoint = true
	last_checkpoint_pos = pos
	var current_scene = get_tree().current_scene
	if current_scene:
		last_scene_path = current_scene.scene_file_path

# --- [함수 4] 플레이어 사망 시 부활 처리 ---
# 세이브를 다시 불러오지 않는다: 아이템·상자·처치한 몹 등 진행은 그대로 두고, 마지막 세이브 포인트에서 체력·플라스크를 채워 다시 시작한다.
# 대가: 죽은 자리에 떨어뜨린 금화 (on_player_died), 그리고 쓰러뜨린 일반 몹이 모두 되살아난다 (들이박아 몹을 조금씩 지워 나가는 꼼수 방지).
# 달의 위상·변이는 휴식할 때만 바뀐다.
func respawn_player() -> void:
	is_respawning = true
	respawned_from_death = true
	_restore_after_death()
	revive_mobs()
	get_tree().paused = false
	Engine.time_scale = 1.0

	var path := last_scene_path
	if not has_checkpoint or path == "" or not ResourceLoader.exists(path):
		# 세이브 포인트를 아직 안 찍었으면 지금 스테이지를 처음부터
		var scene := get_tree().current_scene
		path = scene.scene_file_path if scene else get_stage_path(1)
	DebugLog.info(str("[Respawn] 진행 유지, 이동: ", path))
	call_deferred("_change_scene_safe", path)

# 부활 상태: 체력·플라스크를 채우고 상태이상을 푼다 (독에 걸린 채 낮은 HP로 부활해 바로 다시 죽는 일이 없도록)
func _restore_after_death() -> void:
	player_current_hp = player_max_hp
	flask_current_charges = flask_max_charges
	carried_status_effects.clear()
	pending_shortcut_arrival.clear()
	pending_elevator_arrival = false
	clear_resume_point() # 죽으면 이어 하기 위치가 아니라 세이브 포인트에서
	hp_changed.emit(player_current_hp, player_max_hp)
	flask_changed.emit()

# 플레이어가 쓰러진 순간 (BaseStage가 부른다): 금화 일부를 그 자리에 떨어뜨리고, 부활할 상태로 바로 저장한다.
# 부활 키를 누르기 전에 게임을 꺼도 잃은 금화가 되돌아오지 않는다. 떨어뜨린 금액을 돌려준다
func on_player_died(scene_path: String, drop_pos: Vector2, cause: String = "") -> int:
	var lost := drop_gold_on_death(scene_path, drop_pos, cause)
	if autosave_enabled and has_checkpoint:
		# 부활 화면 동안 게임 상태는 그대로 두고(실제 회복은 respawn_player), 저장 내용만 부활한 상태로
		var data := get_data_for_save()
		data["current_hp"] = player_max_hp
		data["flask_current"] = flask_max_charges
		data["status_effects"] = []
		data["resume"] = {}
		data["defeated_mobs"] = [] # 부활하면 몹은 되살아난다 (revive_mobs)
		SaveManager.save_game(data, current_save_path())
	return lost

# 가진 금화의 절반(동화 10 단위로 내림)을 drop_pos에 더미로 남긴다. 이미 있던 더미는 그대로 남는다
func drop_gold_on_death(scene_path: String, drop_pos: Vector2, cause: String = "") -> int:
	var lost := int(gold * DEATH_DROP_RATIO) / 10 * 10
	if lost <= 0 or scene_path.is_empty():
		return 0
	gold -= lost
	gold_changed.emit(gold)
	if not death_drops.has(scene_path):
		death_drops[scene_path] = {}
	var drops: Dictionary = death_drops[scene_path]
	var n := drops.size()
	while drops.has("drop_%d" % n):
		n += 1
	drops["drop_%d" % n] = {"x": drop_pos.x, "y": drop_pos.y, "gold": lost, "cause": cause} # cause: 사인 (DeathCause, 해골에 표시)
	PlayLog.event("gold_dropped", {"scene": scene_path, "gold": lost})
	return lost

# 더미에서 금화를 주웠다 (DeathDrop). 다 주우면 더미 기록을 지운다
func take_death_drop_gold(scene_path: String, drop_id: String, amount: int) -> void:
	var drops: Dictionary = death_drops.get(scene_path, {})
	if not drops.has(drop_id):
		return
	drops[drop_id]["gold"] = int(drops[drop_id]["gold"]) - amount
	if int(drops[drop_id]["gold"]) <= 0:
		drops.erase(drop_id)
		if drops.is_empty():
			death_drops.erase(scene_path)

# 자동 저장: 스테이지 안에서 플레이어가 살아 있을 때만. 세이브 포인트를 한 번도 안 찍었으면 저장하지 않는다
func autosave() -> bool:
	if not autosave_enabled or not has_checkpoint or is_respawning or not is_inside_tree():
		return false
	var stage := get_tree().current_scene
	if stage == null or not stage.has_method("get_resume_position"):
		return false
	var p = stage.get("player")
	if not is_instance_valid(p) or p.hp <= 0:
		return false
	return save_game()

# 한 프레임에 여러 번 바뀌어도 (아이템 여러 개를 한꺼번에 얻는 등) 한 번만 저장한다
func queue_autosave() -> void:
	if _autosave_queued or not autosave_enabled:
		return
	_autosave_queued = true
	_run_queued_autosave.call_deferred()

func _run_queued_autosave() -> void:
	_autosave_queued = false
	autosave()

func ui_opened(owner: Node, needs_cursor: bool = true) -> void:
	_ui_owners[owner.get_instance_id()] = {"owner": weakref(owner), "cursor": needs_cursor}
	_refresh_ui_state()

func ui_closed(owner: Node) -> void:
	_ui_owners.erase(owner.get_instance_id())
	_refresh_ui_state()

# 조작은 막지 않고 마우스 커서만 보이게 (미니맵을 연 동안 등). on = false면 거둔다
var _cursor_requests: Dictionary = {}
func request_cursor(owner: Node, on: bool) -> void:
	if on:
		_cursor_requests[owner.get_instance_id()] = weakref(owner)
	else:
		_cursor_requests.erase(owner.get_instance_id())
	_refresh_ui_state()

# 씬이 바뀌어 사라진 잠금 주인(시체가 된 보스, 사라진 상자 등)을 지우고 잠금을 다시 계산한다. 스테이지가 시작할 때 부른다
func refresh_ui_owners() -> void:
	_refresh_ui_state()

# 층·씬 이동은 살아 있을 때만 (죽은 채로 넘어가면 HP 0인 플레이어가 새 씬에 생기고 부활 키도 안 먹는다)
func can_travel() -> bool:
	return player_current_hp > 0 and not is_respawning

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
	for id in _cursor_requests.keys():
		if _cursor_requests[id].get_ref() == null:
			_cursor_requests.erase(id)
		else:
			needs_cursor = true
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

func has_seen_map_object(scene_path: String, key: String) -> bool:
	return seen_map_objects.has(scene_path) and seen_map_objects[scene_path].has(key)

func see_map_object(scene_path: String, key: String) -> void:
	if not seen_map_objects.has(scene_path):
		seen_map_objects[scene_path] = []
	if not seen_map_objects[scene_path].has(key):
		seen_map_objects[scene_path].append(key)

# 씬의 지형 기록 (크기가 바뀐 맵이면 새로 만든다)
func map_fog(scene_path: String, w: int, h: int) -> Dictionary:
	var fog: Dictionary = seen_tiles.get(scene_path, {})
	if fog.get("w", 0) != w or fog.get("h", 0) != h:
		var bits := PackedByteArray()
		bits.resize((w * h + 7) / 8)
		fog = {"w": w, "h": h, "bits": bits}
		seen_tiles[scene_path] = fog
	return fog

# 옛 세이브에서 넘어온 씬이면 true를 한 번만 돌려준다 (그때 다녀간 방을 채운다)
func take_fog_from_rooms(scene_path: String) -> bool:
	if not _fog_from_rooms.has(scene_path):
		return false
	_fog_from_rooms.erase(scene_path)
	return true

static func fog_index(fog: Dictionary, cell: Vector2i) -> int:
	if cell.x < 0 or cell.y < 0 or cell.x >= fog.w or cell.y >= fog.h:
		return -1
	return cell.y * fog.w + cell.x

static func is_tile_seen(fog: Dictionary, cell: Vector2i) -> bool:
	var i := fog_index(fog, cell)
	return i >= 0 and (fog.bits[i >> 3] & (1 << (i & 7))) != 0

static func reveal_tile(fog: Dictionary, cell: Vector2i) -> void:
	var i := fog_index(fog, cell)
	if i >= 0:
		fog.bits[i >> 3] |= 1 << (i & 7)

func _seen_tiles_for_save() -> Dictionary:
	var result: Dictionary = {}
	for path in seen_tiles:
		var fog: Dictionary = seen_tiles[path]
		result[path] = {"w": fog.w, "h": fog.h, "bits": Marshalls.raw_to_base64(fog.bits)}
	return result

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
		"heavy_attack": heavy_attack_unlocked,
		"double_jump": double_jump_unlocked,
		"parrydamage": player_parry_damage_multifac,
		"attack_speed": player_attack_speed_bonus,
		"guard_reduction": guard_reduction,
		"breath_bonus": breath_bonus,
		"defeated_bosses": defeated_bosses,
		"talked_bosses": talked_bosses,
		"triggered_dialogues": triggered_dialogues,
		"npc_talk_counts": npc_talk_counts,
		"quest_progress": quest_progress,
		"rematch_epochs": rematch_epochs,
		"bestiary": bestiary,
		"nohit_bosses": nohit_bosses,
		"seen_tutorials": seen_tutorials,
		"defeated_mobs": defeated_mobs,
		"has_checkpoint": has_checkpoint,
		"scene_path": last_scene_path,
		"stage_title_key": _current_stage_title_key(), # 슬롯 선택 화면 표시용
		"pos_x": last_checkpoint_pos.x,
		"pos_y": last_checkpoint_pos.y,
		"inventory": Inventory.to_save(),
		"equipment": Inventory.equipment_to_save(),
		"collected_items": collected_items,
		"loot_seed": loot_seed,
		"stat_loot": stat_loot.duplicate(true),
		"mutation_epoch": mutation_epoch,
		"mutant_chests": mutant_chests,
		"moon_passage": moon_passage_open,
		"death_drops": death_drops.duplicate(true),
		"shop_sold": shop_sold,
		"visited_rooms_by_scene": _visited_rooms_for_save(),
		"seen_map_objects": seen_map_objects.duplicate(true),
		"seen_tiles": _seen_tiles_for_save(),
		"flask_max": flask_max_charges,
		"flask_current": flask_current_charges,
		"flask_heal": flask_heal_amount,
		"status_effects": _status_effects_for_save(),
		"resume": _resume_for_save(),
	}

func _resume_for_save() -> Dictionary:
	if resume_scene_path.is_empty():
		return {}
	return {"scene": resume_scene_path, "x": resume_pos.x, "y": resume_pos.y}

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
	heavy_attack_unlocked = data.get("heavy_attack", false) == true
	double_jump_unlocked = data.get("double_jump", false) == true
	player_parry_damage_multifac = data.get("parrydamage", 1.5)
	player_attack_speed_bonus = float(data.get("attack_speed", 0.0))
	guard_reduction = int(data.get("guard_reduction", 10))
	breath_bonus = float(data.get("breath_bonus", 0.0))
	defeated_mobs = data.get("defeated_mobs", [])
	defeated_bosses = data.get("defeated_bosses", {})
	talked_bosses = data.get("talked_bosses", {})
	triggered_dialogues = data.get("triggered_dialogues", [])
	npc_talk_counts = data.get("npc_talk_counts", {})
	quest_progress = data.get("quest_progress", {})
	rematch_epochs = data.get("rematch_epochs", {})
	bestiary = data.get("bestiary", {})
	nohit_bosses = data.get("nohit_bosses", {})
	seen_tutorials = data.get("seen_tutorials", []).filter(func(k): return k is String)
	has_checkpoint = data.get("has_checkpoint", false)
	
	var loaded_path = data.get("scene_path", "")
	if loaded_path == "" or loaded_path.get_file() == "Stage.tscn":
		last_scene_path = get_stage_path(1)
	else:
		last_scene_path = loaded_path
	
	collected_items = data.get("collected_items", [])
	# 시드가 없는 옛 세이브는 새로 만든다 (다음 저장부터 고정)
	loot_seed = int(data["loot_seed"]) if data.has("loot_seed") else new_loot_seed()
	stat_loot = _new_stat_loot()
	var saved_stat_loot = data.get("stat_loot", {})
	if saved_stat_loot is Dictionary:
		stat_loot.fails = int(saved_stat_loot.get("fails", 0))
		stat_loot.drops = int(saved_stat_loot.get("drops", 0))
		for id in saved_stat_loot.get("taken", []):
			stat_loot.taken.append(str(id))
	mutation_epoch = int(data.get("mutation_epoch", 0))
	var resume: Dictionary = data.get("resume", {})
	resume_scene_path = str(resume.get("scene", ""))
	resume_pos = Vector2(float(resume.get("x", 0.0)), float(resume.get("y", 0.0)))
	mutant_chests = data.get("mutant_chests", {}).duplicate(true)
	moon_passage_open = bool(data.get("moon_passage", false))
	moon_changed.emit()
	death_drops = data.get("death_drops", {}).duplicate(true)
	if data.has("shop_sold"):
		shop_sold = data["shop_sold"].duplicate(true)
	else:
		shop_sold = _shop_sold_from_legacy(data.get("merchant_stocks", {}))
	flask_max_charges = data.get("flask_max", 1)
	flask_current_charges = data.get("flask_current", 1)
	flask_heal_amount = int(data.get("flask_heal", FLASK_HEAL_BASE))
	
	# 미니맵 방문 기록 복구
	visited_rooms_by_scene.clear()
	var saved_rooms: Dictionary = data.get("visited_rooms_by_scene", {})
	# 이전 세이브는 씬 구분이 없으므로 체크포인트 씬에만 이전한다.
	if saved_rooms.is_empty() and data.has("visited_rooms"):
		saved_rooms = {last_scene_path: data["visited_rooms"]}
	for path in saved_rooms:
		for r in saved_rooms[path]:
			visit_room(str(path), Vector2i(int(r["x"]), int(r["y"])))
	seen_map_objects.clear()
	var saved_seen: Dictionary = data.get("seen_map_objects", {}) # 없던 옛 세이브는 빈 기록 (다가가면 다시 기록된다)
	for path in saved_seen:
		for key in saved_seen[path]:
			see_map_object(str(path), str(key))
	seen_tiles.clear()
	_fog_from_rooms.clear()
	if data.has("seen_tiles"):
		var saved_tiles: Dictionary = data["seen_tiles"]
		for path in saved_tiles:
			var t: Dictionary = saved_tiles[path]
			var w := int(t["w"])
			var h := int(t["h"])
			var bits: PackedByteArray = Marshalls.base64_to_raw(str(t["bits"]))
			if bits.size() == (w * h + 7) / 8:
				seen_tiles[str(path)] = {"w": w, "h": h, "bits": bits}
	else:
		_fog_from_rooms = visited_rooms_by_scene.keys() # 지형 기록 전 세이브: 다녀간 방은 다 본 걸로
	
	Inventory.load_from_save(data.get("inventory", []), data.get("equipment")) # 장비 칸이 없던 옛 세이브는 랜턴 등을 자동 장착
	
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

# 테스트가 실제 슬롯 파일을 건드리지 않도록 다른 경로를 쓸 때만 채운다
var save_path_override: String = ""

func current_save_path() -> String:
	if not save_path_override.is_empty():
		return save_path_override
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

# 상자가 실제로 열린 뒤 부른다 (잠겨 있거나 가방이 가득 차 안 열리면 기록하지 않는다)
func record_chest_loot(table: LootTable, item: ItemData) -> void:
	if table == null or not table.stat_pity:
		return
	var ids := table.stat_ids()
	if ids.is_empty() or int(stat_loot.drops) >= LootTable.STAT_MAX_SETS * ids.size():
		return
	if item != null and ids.has(item.id):
		stat_loot.fails = 0
		stat_loot.drops = int(stat_loot.drops) + 1
		stat_loot.taken.append(item.id)
		if ids.all(func(id): return stat_loot.taken.has(id)):
			stat_loot.taken = [] # 한 세트를 다 받으면 다음 세트
	else:
		stat_loot.fails = int(stat_loot.fails) + 1

func _new_stat_loot() -> Dictionary:
	return {"fails": 0, "taken": [], "drops": 0}

func make_loot_rng(source_id: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = ("%d:%s" % [loot_seed, source_id]).hash()
	return rng
	
func reset_data() -> void:
	DebugLog.info("[GameManager] Resetting all game data for New Game...")
	carried_status_effects.clear()
	pending_shortcut_arrival.clear()
	pending_elevator_arrival = false
	clear_resume_point()
	gold = 0
	player_current_hp = 100
	player_max_hp = 100
	player_damage = 10
	heavy_attack_unlocked = false
	double_jump_unlocked = false
	player_parry_damage_multifac = 1.5
	player_attack_speed_bonus = 0.0
	guard_reduction = 10
	breath_bonus = 0.0
	has_checkpoint = false
	last_checkpoint_pos = Vector2.ZERO
	last_scene_path = ""
	
	defeated_bosses.clear()
	talked_bosses.clear()
	triggered_dialogues.clear()
	npc_talk_counts.clear()
	quest_progress.clear()
	rematch_epochs.clear()
	bestiary.clear()
	nohit_bosses.clear()
	seen_tutorials.clear()
	defeated_mobs.clear()
	collected_items.clear()
	visited_rooms_by_scene.clear()
	seen_map_objects.clear()
	seen_tiles.clear()
	_fog_from_rooms.clear()
	loot_seed = new_loot_seed()
	stat_loot = _new_stat_loot()
	mutation_epoch = 0
	mutant_chests.clear()
	death_drops.clear()
	moon_passage_open = false
	moon_changed.emit()

	Inventory.reset()

	flask_max_charges = 1
	flask_current_charges = 1
	flask_heal_amount = FLASK_HEAL_BASE
	
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
# --- 이어 하기 저장 (나갈 때 자동) ---
# 지금 상태 그대로 저장한다 (HP·플라스크·상태이상·처치 기록). 휴식이 아니므로 회복·몹 부활·변이 리롤 없음.
# 위치는 마지막으로 밟은 안전한 땅. 전투 중(보스전, 몹이 쫓는 중)이면 위치는 저장하지 않아 세이브 포인트에서 시작한다.
# 죽었거나 죽는 중, 스테이지 밖(메인 메뉴 등)에서는 저장하지 않는다.
func save_on_quit() -> bool:
	var stage := get_tree().current_scene if is_inside_tree() else null
	if stage == null or not stage.has_method("get_resume_position") or is_respawning:
		return false
	var p = stage.get("player")
	if not is_instance_valid(p) or p.hp <= 0 or player_current_hp <= 0:
		return false
	clear_resume_point()
	var pos: Variant = stage.get_resume_position()
	if pos is Vector2:
		resume_scene_path = stage.scene_file_path
		resume_pos = pos
	return save_game()

func clear_resume_point() -> void:
	resume_scene_path = ""
	resume_pos = Vector2.ZERO

# 불러오기 후 들어갈 씬: 이어 하기 위치가 있으면 그 씬, 없으면 세이브 포인트 씬
func get_continue_scene_path() -> String:
	if not resume_scene_path.is_empty() and ResourceLoader.exists(resume_scene_path):
		return resume_scene_path
	return last_scene_path

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_on_quit() # 창 닫기(X, Alt+F4)

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
