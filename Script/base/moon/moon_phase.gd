extends RefCounted
class_name MoonPhase

# 달의 위상과 달빛 효과 표. 위상은 몹 리롤 회차(GameManager.mutation_epoch: 휴식마다 +1)로 정해진다:
#   보름달 → 반달 → 그믐달 → 보름달 ...
# 효과는 지상층 통로가 열려 달빛이 들어올 때만 적용된다 (GameManager.moon_passage_open). 닫혀 있으면 전부 기본값.
# 수치는 아래 표만 고치면 된다. 테스트 스크립트가 먼저 컴파일하므로 여기서는 오토로드를 쓰지 않는다.

enum Phase { FULL, HALF, NEW }

const CYCLE: Array[Phase] = [Phase.FULL, Phase.HALF, Phase.NEW]

# 위상별 효과 (달빛이 들어올 때만)
# mob_hp / mob_damage: 적(보스 포함) 체력·주는 피해 배율
# mutation_chance: 변이체 확률 (기본 MobMutation.CHANCE)
# mutant_chest_chance: 변이체가 보상 상자를 떨굴 확률 (기본 MobMutation.CHEST_CHANCE)
# mutant_gold_mult: 변이체 골드 보상 배율 (기본 MobMutation.REWARD_MULT)
# madness: 0~1, 짐승이 사나워지는 정도 (양: 울지 않고 돌진할 확률이 1에 가까워진다)
# vision_mult: 시야 제한 스테이지의 시야 반지름 배율
const EFFECTS := {
	Phase.FULL: {
		"mob_hp": 1.4, "mob_damage": 1.4,
		"mutation_chance": 0.10, "mutant_chest_chance": 0.15, "mutant_gold_mult": 4,
		"madness": 1.0, "vision_mult": 1.0,
	},
	Phase.HALF: {
		"mob_hp": 1.25, "mob_damage": 1.25,
		"mutation_chance": 0.05, "mutant_chest_chance": 0.06, "mutant_gold_mult": 3,
		"madness": 0.5, "vision_mult": 1.0,
	},
	Phase.NEW: {
		"mob_hp": 1.1, "mob_damage": 1.1,
		"mutation_chance": 0.03, "mutant_chest_chance": 0.05, "mutant_gold_mult": 3,
		"madness": 0.0, "vision_mult": 0.7,
	},
}

# 달빛이 없을 때(통로 닫힘)의 값
const DEFAULTS := {
	"mob_hp": 1.0, "mob_damage": 1.0,
	"mutation_chance": MobMutation.CHANCE, "mutant_chest_chance": MobMutation.CHEST_CHANCE,
	"mutant_gold_mult": MobMutation.REWARD_MULT,
	"madness": 0.0, "vision_mult": 1.0,
}

const NAME_KEYS := {
	Phase.FULL: &"MOON_FULL",
	Phase.HALF: &"MOON_HALF",
	Phase.NEW: &"MOON_NEW",
}

static func phase_for_epoch(epoch: int) -> Phase:
	return CYCLE[posmod(epoch, CYCLE.size())]

# 위상의 효과 값. lit = 달빛이 들어오는가 (통로가 열려 있는가)
static func effect(phase: Phase, lit: bool, key: String) -> Variant:
	if lit and EFFECTS.has(phase) and EFFECTS[phase].has(key):
		return EFFECTS[phase][key]
	return DEFAULTS[key]

# --- 오토로드를 경로로 찾아 쓰는 도우미 (테스트가 class_name으로 참조하는 스크립트용) ---

static func _gm(node: Node) -> Node:
	if node == null or not node.is_inside_tree():
		return null
	return node.get_tree().root.get_node_or_null("GameManager")

# 지금 위상의 효과 값. GameManager가 없으면(트리 밖) 기본값
static func current(node: Node, key: String) -> Variant:
	var gm := _gm(node)
	if gm == null:
		return DEFAULTS[key]
	return effect(gm.moon_phase(), gm.moon_passage_open, key)

# 때린 쪽(몹·투사체·충격파 등)의 달빛 피해 배율. 투사체는 쏜 몹(shooter)을 따른다
static func damage_mult_from(source: Node) -> float:
	if source == null or not is_instance_valid(source):
		return 1.0
	# EnemyBase는 오토로드에 의존하므로 타입 대신 moon_damage_mult가 있는지로 본다
	var enemy: Object = source
	if not "moon_damage_mult" in enemy:
		var shooter = source.get("shooter")
		enemy = shooter if shooter is Node and is_instance_valid(shooter) else null
	if enemy != null and "moon_damage_mult" in enemy:
		return float(enemy.moon_damage_mult)
	return 1.0
