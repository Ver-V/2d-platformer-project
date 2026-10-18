extends RefCounted
class_name DeathCause

# 사인 문자열: "enemy:<몹 씬 경로>" / "spikes" / "status:<상태이상 id>" / "unknown".
# Player.death_cause에 쌓이고, 죽을 때 해골 더미(GameManager.death_drops의 "cause")에 남는다. describe로 읽을 글이 된다.

# 피해를 준 것(HitData.source)으로 사인을 정한다. 투사체는 쏜 몹, 가시는 "spikes"
static func of_source(source: Object) -> String:
	if source == null or not is_instance_valid(source):
		return "unknown"
	if source is HazardSensor:
		return "spikes"
	# EnemyBase는 이름으로 쓰지 않는다 (테스트가 먼저 컴파일) — 몹은 max_hp_base가 있다
	var node: Object = source
	if not "max_hp_base" in node and "shooter" in node:
		var shooter = node.get("shooter")
		node = shooter if shooter is Object and is_instance_valid(shooter) else null
	if node is Node and "max_hp_base" in node and not (node as Node).scene_file_path.is_empty():
		return "enemy:" + (node as Node).scene_file_path
	return "unknown"

static func describe(cause: String) -> String:
	if cause.begins_with("enemy:"):
		return Bestiary.display_name(cause.trim_prefix("enemy:"))
	if cause == "spikes":
		return TranslationServer.translate(&"CAUSE_SPIKES")
	if cause.begins_with("status:"):
		var key := StringName("CAUSE_STATUS_" + cause.trim_prefix("status:").to_upper())
		var text := TranslationServer.translate(key)
		return text if text != String(key) else TranslationServer.translate(&"CAUSE_UNKNOWN")
	return TranslationServer.translate(&"CAUSE_UNKNOWN")
