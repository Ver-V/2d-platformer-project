# SaveManager.gd
extends Node

const SAVE_PATH = "user://save_game.json" # 슬롯 도입 전 단일 세이브 (첫 실행 때 1번 슬롯으로 옮긴다)
const SLOT_COUNT: int = 3
const SETTINGS_PATH = "user://settings.json"
const DEFAULT_LOCALE: String = "en"
const SAVE_VERSION: int = 3 # 3: 상점 재고를 판매 수량(shop_sold)으로 저장

func save_game(data: Dictionary, path: String = SAVE_PATH) -> bool:
	if not _is_valid_game(data):
		push_warning("SaveManager: 유효하지 않은 게임 데이터는 저장하지 않습니다.")
		return false
	var payload := data.duplicate(true)
	payload["save_version"] = SAVE_VERSION
	# 정상인 이전 저장만 백업한다. 손상 파일로 정상 백업을 덮어쓰지 않는다.
	if not _read_valid_game(path).is_empty():
		if DirAccess.copy_absolute(path, path + ".bak.tmp") != OK:
			return false
		if DirAccess.rename_absolute(path + ".bak.tmp", path + ".bak") != OK:
			return false
	return _write_json_atomic(path, payload)

func load_game(path: String = SAVE_PATH) -> Dictionary:
	var data := _read_valid_game(path)
	if not data.is_empty():
		return data
	data = _read_valid_game(path + ".bak")
	if not data.is_empty():
		push_warning("SaveManager: 이전 정상 저장으로 복구했습니다.")
	return data

func has_save(path: String = SAVE_PATH) -> bool:
	return not _read_valid_game(path).is_empty() or not _read_valid_game(path + ".bak").is_empty()

func delete_save(path: String = SAVE_PATH) -> void:
	# 새 게임에서 백업이 이전 진행 상태를 되살리지 않도록 함께 제거한다.
	for suffix in ["", ".bak", ".tmp", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(path + suffix)

# --- 세이브 슬롯 (1 ~ SLOT_COUNT) ---
func slot_path(slot: int) -> String:
	return "user://save_slot_%d.json" % slot

func has_any_slot_save() -> bool:
	for slot in range(1, SLOT_COUNT + 1):
		if has_save(slot_path(slot)):
			return true
	return false

# 슬롯 선택 화면에 보여줄 요약. 빈 슬롯이면 {}.
# stage_title_key: 저장한 스테이지 제목 번역 키(옛 세이브는 없음), scene_path, gold, saved_unix: 파일 수정 시각
func slot_summary(path: String) -> Dictionary:
	var data := load_game(path)
	if data.is_empty():
		return {}
	var file_path := path if FileAccess.file_exists(path) else path + ".bak"
	return {
		"stage_title_key": str(data.get("stage_title_key", "")),
		"scene_path": str(data.get("scene_path", "")),
		"gold": int(data.get("gold", 0)),
		"saved_unix": FileAccess.get_modified_time(file_path),
	}

# 슬롯 도입 전 세이브(legacy_path)를 1번 슬롯으로 옮긴다. 1번 슬롯이 비어 있을 때만. 옮겼으면 true.
func migrate_legacy_save(legacy_path: String = SAVE_PATH, target_path: String = "") -> bool:
	if target_path.is_empty():
		target_path = slot_path(1)
	if not has_save(legacy_path) or has_save(target_path):
		return false
	var data := load_game(legacy_path)
	if not _write_json_atomic(target_path, data):
		return false
	delete_save(legacy_path)
	return true

func _read_valid_game(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		return {}
	var data: Variant = parser.data
	return data if _is_valid_game(data) else {}

func _write_json_atomic(path: String, data: Dictionary) -> bool:
	var temp_path := path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		push_error("SaveManager: 임시 저장 파일을 열지 못했습니다: " + temp_path)
		return false
	file.store_string(JSON.stringify(data))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		return false
	# 쓰인 내용까지 검증한 후 같은 디렉터리에서 본 파일을 교체한다.
	var check := FileAccess.open(temp_path, FileAccess.READ)
	if check == null:
		return false
	var parser := JSON.new()
	var parse_error := parser.parse(check.get_as_text())
	check.close()
	if parse_error != OK or not parser.data is Dictionary:
		return false
	var error := DirAccess.rename_absolute(temp_path, path)
	if error != OK:
		push_error("SaveManager: 저장 파일 교체 실패 (오류 %s)" % error)
		return false
	return true

func _is_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

func _is_integer(value: Variant) -> bool:
	return _is_number(value) and float(value) == floor(float(value))

func _is_text(value: Variant) -> bool:
	return value is String or value is StringName

# 변이체 보상 상자 {씬 경로: {상자 id: [x, y]}}
func _valid_mutant_chests(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	for scene_path in value:
		if not scene_path is String or not value[scene_path] is Dictionary:
			return false
		for chest_id in value[scene_path]:
			var pos: Variant = value[scene_path][chest_id]
			if not chest_id is String or not pos is Array or pos.size() != 2 or not _is_number(pos[0]) or not _is_number(pos[1]):
				return false
	return true

func _valid_resume(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	if value.is_empty():
		return true
	return value.get("scene") is String and _is_number(value.get("x")) and _is_number(value.get("y"))

func _valid_rooms(value: Variant) -> bool:
	if not value is Array:
		return false
	for room in value:
		if not room is Dictionary or not _is_integer(room.get("x")) or not _is_integer(room.get("y")):
			return false
	return true

# 상태이상 세이브 값: bool·숫자·문자열 또는 색상 [r, g, b, a]
func _valid_effect_value(value: Variant) -> bool:
	if value is bool or _is_number(value) or value is String:
		return true
	if value is Array and value.size() == 4:
		for c in value:
			if not _is_number(c):
				return false
		return true
	return false

func _valid_status_effects(value: Variant) -> bool:
	if not value is Array:
		return false
	for entry in value:
		if not entry is Dictionary or not entry.get("script") is String:
			return false
		if not entry.script.begins_with(StatusEffect.SAVE_SCRIPT_DIR):
			return false
		for key in ["props", "state"]:
			if not entry.get(key, {}) is Dictionary:
				return false
			for name in entry.get(key, {}):
				if not name is String or not _valid_effect_value(entry[key][name]):
					return false
	return true

func _is_valid_game(data: Variant) -> bool:
	if not data is Dictionary:
		return false
	var version: Variant = data.get("save_version", 1)
	if not _is_integer(version) or version < 1 or version > SAVE_VERSION:
		return false
	if not _is_integer(data.get("current_hp")) or not _is_integer(data.get("max_hp")):
		return false
	if data.current_hp <= 0 or data.max_hp < data.current_hp:
		return false
	for key in ["gold", "damage", "flask_max", "flask_current"]:
		if data.has(key) and (not _is_integer(data[key]) or data[key] < 0):
			return false
	if data.get("flask_current", 1) > data.get("flask_max", 1):
		return false
	if data.has("loot_seed") and (not _is_integer(data.loot_seed) or data.loot_seed < 0):
		return false
	if data.has("mutation_epoch") and (not _is_integer(data.mutation_epoch) or data.mutation_epoch < 0):
		return false
	if data.has("mutant_chests") and not _valid_mutant_chests(data.mutant_chests):
		return false
	for key in ["parrydamage", "pos_x", "pos_y"]:
		if data.has(key) and not _is_number(data[key]):
			return false
	if data.get("parrydamage", 1.5) < 0:
		return false
	if data.has("has_checkpoint") and not data.has_checkpoint is bool:
		return false
	if data.has("scene_path") and not data.scene_path is String:
		return false
	if data.has("stage_title_key") and not data.stage_title_key is String:
		return false
	for key in ["defeated_mobs", "triggered_dialogues", "collected_items"]:
		if not data.get(key, []) is Array:
			return false
		for entry in data.get(key, []):
			if not _is_text(entry):
				return false
	for key in ["defeated_bosses", "talked_bosses", "npc_talk_counts"]:
		if not data.get(key, {}) is Dictionary:
			return false
		for id in data.get(key, {}):
			var entry: Variant = data[key][id]
			if not _is_text(id):
				return false
			if key == "npc_talk_counts":
				if not _is_integer(entry) or entry < 0:
					return false
			elif not entry is bool:
				return false
	if not data.get("inventory", []) is Array:
		return false
	for slot in data.get("inventory", []):
		if slot == null:
			continue
		if not slot is Dictionary or not slot.get("id") is String:
			return false
		if slot.has("key_uses") and (not _is_integer(slot.key_uses) or slot.key_uses < 0):
			return false
	# 저장 당시 걸려 있던 상태이상 (없으면 옛 세이브)
	# 이어 하기 위치 {scene, x, y} (비어 있으면 없음)
	if data.has("resume") and not _valid_resume(data.resume):
		return false
	if data.has("status_effects") and not _valid_status_effects(data.status_effects):
		return false
	# 버전 2 이하: 상점별 남은 재고 (불러올 때 shop_sold로 변환)
	if not data.get("merchant_stocks", {}) is Dictionary:
		return false
	for shop in data.get("merchant_stocks", {}):
		if not shop is String or not data.merchant_stocks[shop] is Array:
			return false
		for item in data.merchant_stocks[shop]:
			if not item is Dictionary or not item.get("id") is String or not _is_integer(item.get("stock")):
				return false
			if item.stock < 0:
				return false
	# 버전 3: 상점별 아이템 판매 수량
	if not data.get("shop_sold", {}) is Dictionary:
		return false
	for shop in data.get("shop_sold", {}):
		if not shop is String or not data.shop_sold[shop] is Dictionary:
			return false
		for item_id in data.shop_sold[shop]:
			var sold: Variant = data.shop_sold[shop][item_id]
			if not item_id is String or not _is_integer(sold) or sold < 0:
				return false
	if data.has("visited_rooms") and not _valid_rooms(data.visited_rooms):
		return false
	if not data.get("visited_rooms_by_scene", {}) is Dictionary:
		return false
	for scene in data.get("visited_rooms_by_scene", {}):
		if not scene is String or not _valid_rooms(data.visited_rooms_by_scene[scene]):
			return false
	return true

# --- 설정(옵션) 저장 및 불러오기 ---
# path는 테스트용 (기본: 실제 설정 파일)
func save_settings(data: Dictionary, path: String = SETTINGS_PATH) -> bool:
	return _write_json_atomic(path, data)

func load_settings(path: String = SETTINGS_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"locale": DEFAULT_LOCALE}
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("SaveManager: 설정 파일을 읽지 못했습니다: %s (오류 %s)" % [path, FileAccess.get_open_error()])
		return {"locale": DEFAULT_LOCALE}
	var data = JSON.parse_string(file.get_as_text())
	if typeof(data) == TYPE_DICTIONARY:
		if not data.has("locale"):
			data["locale"] = DEFAULT_LOCALE
		DebugLog.info("SaveManager: 설정 로드 성공")
		return data
	push_warning("SaveManager: 설정 파일 형식이 잘못되어 기본값을 사용합니다: " + path)
	return {"locale": DEFAULT_LOCALE}
