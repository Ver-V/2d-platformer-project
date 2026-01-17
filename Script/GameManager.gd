# GameManager.gd
extends Node

# --- 1. 재화 및 스탯 관리 ---
var gold: int = 0
var player_max_hp: int = 100
var player_current_hp: int = 100
var player_damage: int = 10
var player_parry_damage_multifac: float = 1.5
var defeated_bosses: Dictionary = {} # 영구 사망 보스 목록
var defeated_mobs: Array = []
var pending_status: String = ""

signal gold_changed(amount: int)
signal hp_changed(current_hp, max_hp) # [추가] 체력 변화 신호
signal interact_msg_requested(msg)    # [추가] 상호작용 텍스트 띄우기 요청
signal interact_msg_hidden()          # [추가] 상호작용 텍스트 숨기기 요청

const SAVE_PATH = "user://save_game.json"

# 리스폰 중복 방지 플래그
var is_respawning: bool = false

# --- 2. 체크포인트(세이브) 데이터 ---
var has_checkpoint: bool = false
var last_checkpoint_pos: Vector2
var last_scene_path: String = ""

func add_defeated_mob(id: String) -> void:
	if not defeated_mobs.has(id):
		defeated_mobs.append(id)
		
# [추가] 휴식 시 호출: 일반 몹 기록만 싹 지움! (이게 핵심!)
func reset_mobs() -> void:
	defeated_mobs.clear()
	
func add_defeated_boss(id: String) -> void:
	if not defeated_bosses.has(id):
		defeated_bosses[id] = true

# --- [함수 1] 돈 추가 ---
func add_gold(amount: int) -> void:
	gold += amount
	emit_signal("gold_changed", gold)
	print("현재 골드: ", gold)

# --- [함수 2] 체크포인트 저장 ---
func save_checkpoint(pos: Vector2) -> void:
	has_checkpoint = true
	last_checkpoint_pos = pos
	last_scene_path = get_tree().current_scene.scene_file_path
	print("저장 완료! 위치:", pos, " / 씬:", last_scene_path)

# --- [함수 3] 플레이어 사망 시 부활 처리 ---
func respawn_player() -> void:
	if is_respawning:
		return
	
	is_respawning = true
	
	# 로드 시도
	var load_result = load_game()
	
	get_tree().paused = false 
	Engine.time_scale = 1.0
	
	if load_result and has_checkpoint and last_scene_path != "":
		print("✅ 체크포인트 씬으로 이동: ", last_scene_path)
		# [수정] 함수 이름과 인자가 정확한지 확인하며 호출
		call_deferred("_change_scene_safe", last_scene_path)
	else:
		print("⚠️ 저장 데이터 없음/실패 -> 현재 씬 재시작")
		call_deferred("_reload_scene_safe")

func save_game() -> void:
	var save_data = {
		"gold": gold,
		"current_hp": player_current_hp,
		"max_hp": player_max_hp,
		"damage": player_damage,
		"parrydamage": player_parry_damage_multifac,
		"defeated_bosses": defeated_bosses,
		"defeated_mobs": defeated_mobs,
		"has_checkpoint": has_checkpoint,
		"scene_path": last_scene_path,
		"pos_x": last_checkpoint_pos.x,
		"pos_y": last_checkpoint_pos.y
	}
	
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		var json_string = JSON.stringify(save_data)
		file.store_string(json_string)
		print("게임 저장 완료!")
	else:
		print("게임 저장 실패! 경로 오류: ", FileAccess.get_open_error())

# --- [기능 2] 게임 불러오기 (Load) ---
func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		print("📂 저장된 파일이 없습니다. (New Game)")
		return false
	
	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		print("❌ 파일 열기 실패! (에러 코드: ", FileAccess.get_open_error(), ")")
		return false

	var json_string = file.get_as_text()
	var data = JSON.parse_string(json_string)
	
	if data:
		gold = data.get("gold", 0)
		player_current_hp = data.get("current_hp", 100)
		player_max_hp = data.get("max_hp", 100)
		player_damage = data.get("damage", 10)
		player_parry_damage_multifac = data.get("parrydamage", 1.5)
		defeated_mobs = data.get("defeated_mobs", [])
		defeated_bosses = data.get("defeated_bosses", {})
		has_checkpoint = data.get("has_checkpoint", false)
		last_scene_path = data.get("scene_path", "")
		
		var px = data.get("pos_x", 0.0)
		var py = data.get("pos_y", 0.0)
		last_checkpoint_pos = Vector2(px, py)

		return true
		
	return false
	
func apply_hitstop(time_scale: float, duration: float):
	Engine.time_scale = time_scale
	await get_tree().create_timer(duration, true, false, true).timeout
	Engine.time_scale = 1.0

	
func reset_data() -> void:
	gold = 0
	player_current_hp = 100
	player_max_hp = 100
	player_damage = 10
	player_parry_damage_multifac = 1.5
	has_checkpoint = false
	defeated_bosses = {}
	defeated_mobs = []

# --- [함수 수정] 플레이어 체력 갱신 ---
# Player 스크립트에서 직접 변수를 바꾸는 대신, 이 함수를 쓰도록 할 겁니다.
func update_hp(new_hp: int) -> void:
	player_current_hp = new_hp
	# 체력이 변했음을 UI에게 알림
	hp_changed.emit(player_current_hp, player_max_hp)
	
func update_gold(amount: int) -> void:
	# 2. 값 변경
	gold += amount
	
	# 3. [핵심] "돈 바뀌었으니 UI 업데이트해!"라고 신호 발사
	gold_changed.emit(gold)
		
	
# --- [추가됨] 실제로 씬을 변경하는 함수들 ---
# 이 함수들이 없어서 그동안 씬이 바뀌지 않고 멈춰있었던 것입니다.

func _change_scene_safe(path: String) -> void:
	# 씬 변경 시도
	get_tree().change_scene_to_file(path)
	# 변경 완료 후 리스폰 플래그 해제
	is_respawning = false

func _reload_scene_safe() -> void:
	# 현재 씬 재시작
	get_tree().reload_current_scene()
	# 변경 완료 후 리스폰 플래그 해제
	is_respawning = false
