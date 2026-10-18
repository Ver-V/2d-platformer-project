extends RefCounted
class_name Bestiary

# 몬스터 도감 데이터. 종류 = 몹 씬 경로 (EnemyBase.bestiary_kind). 처치 수는 GameManager.bestiary에 저장된다.
# 이름은 ui.csv의 ENEMY_<씬 파일 이름 대문자> 키 (예: rat_red.tscn → ENEMY_RAT_RED). 새 몹을 만들면 KINDS와 ui.csv에 한 줄씩.
# 스탯은 씬을 인스턴스만 해서(트리에 넣지 않아 _ready가 돌지 않음) 읽는다 — 씬의 값을 바꾸면 도감도 따라 바뀐다.
# 테스트가 먼저 컴파일하므로 오토로드도, 오토로드를 쓰는 클래스(Boss 등)도 이름으로 쓰지 않는다 (속성으로 구분).

const DIR := "res://Scenes/Entitites/"
# 도감 순서 (잡몹 → 보스)
const KINDS := [
	"slime_1", "Emushroom", "esnake", "enemy_ranged",
	"rat", "rat_blue", "rat_purple", "rat_red", "rat_white",
	"sheep",
	"boss_stage_1", "boss_stage_2", "boss_stage_3", "boss_wolf",
]

static func kind_path(kind: String) -> String:
	return DIR + kind + ".tscn"

static func name_key(scene_path: String) -> StringName:
	return StringName("ENEMY_" + scene_path.get_file().get_basename().to_upper())

# 읽을 수 있는 이름 (번역이 없으면 파일 이름)
static func display_name(scene_path: String) -> String:
	var key := name_key(scene_path)
	var text := TranslationServer.translate(key)
	return scene_path.get_file().get_basename() if text == String(key) else text

# 씬에서 읽은 정보: {name, hp, damage, speed, gold, status, status_chance, reward, is_boss}
static func info(scene_path: String) -> Dictionary:
	var result := {"name": display_name(scene_path)}
	if not ResourceLoader.exists(scene_path):
		return result
	var node := (load(scene_path) as PackedScene).instantiate()
	if "max_hp_base" in node: # EnemyBase
		var e = node
		result["hp"] = e.max_hp_base
		result["damage"] = e.contact_damage_base
		result["speed"] = e.move_speed_base
		result["gold"] = e.drop_gold_amount
		result["status"] = e.contact_status.id if e.contact_status != null else &""
		result["status_chance"] = e.contact_status_chance
		result["is_boss"] = "boss_started" in e # Boss
		result["persist_id"] = str(e.persist_id)
		var reward = e.get("reward_item") # ItemData (이름으로 쓰면 오토로드 의존이 딸려 온다)
		result["reward"] = TranslationServer.translate(reward.name) if reward != null else "" # ItemData.name = 번역 키
	node.free()
	return result
