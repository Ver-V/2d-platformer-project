extends RefCounted
class_name MobMutation

# 잡몹 변이 규칙. 몹마다 (세이브 시드 + persist_id + 리롤 회차)로 정해져서 같은 세이브·같은 회차면 늘 같다.
# 리롤 회차(GameManager.mutation_epoch)는 몹이 되살아날 때(휴식, 사망 후 부활)마다 1씩 오른다.
# 테스트 스크립트가 먼저 컴파일하므로 여기서는 오토로드를 쓰지 않는다.

enum Kind { NONE, TOUGH, SWIFT, POISON, BLEED, SPLIT }

const CHANCE := 0.03 # 변이체가 될 확률
const CHEST_CHANCE := 0.05 # 변이체를 잡았을 때 보상 상자가 떨어질 확률
const REWARD_MULT := 3 # 변이체 골드 보상 배율
const TOUGH_HP_MULT := 3
const SWIFT_SPEED_MULT := 2.0 # 이동 속도와 애니메이션(공격 포함) 속도
const SPLIT_COUNT := 3
const SPLIT_SCALE := 0.6
const SPLIT_HP_DIV := 3

const SHADER := preload("res://resources/Shaders/mutation_outline.gdshader")
# 상태이상은 쓸 때 불러온다 (preload하면 테스트가 이 스크립트를 먼저 컴파일할 때 상태이상 스크립트 없이 읽혀 버린다)
const POISON_EFFECT_PATH := "res://resources/status_effects/mutant_poison.tres"
const BLEED_EFFECT_PATH := "res://resources/status_effects/mutant_bleed.tres"

enum OutlineMode { SOLID, RAINBOW, PULSE }

# 종류별 윤곽선: [색, 두께(px), 모드]
const OUTLINES := {
	Kind.TOUGH: [Color(1, 1, 1), 1.0, OutlineMode.SOLID],
	Kind.SWIFT: [Color(1, 1, 1), 1.0, OutlineMode.RAINBOW],
	Kind.POISON: [Color(0.7, 0.2, 1.0), 2.0, OutlineMode.SOLID],
	Kind.BLEED: [Color(1.0, 0.1, 0.1), 2.0, OutlineMode.SOLID],
	Kind.SPLIT: [Color(1, 1, 1), 1.0, OutlineMode.PULSE],
}

static func seed_key(mob_id: String, epoch: int) -> String:
	return "mutation:%s:%d" % [mob_id, epoch]

static func chest_key(mob_id: String, epoch: int) -> String:
	return "mutant_chest:%s:%d" % [mob_id, epoch]

# 분열은 can_split인 몹(슬라임)만. 나머지 종류는 같은 확률로 고른다
static func roll(rng: RandomNumberGenerator, can_split: bool, chance: float = CHANCE) -> Kind:
	if rng.randf() >= chance:
		return Kind.NONE
	var kinds: Array[Kind] = [Kind.TOUGH, Kind.SWIFT, Kind.POISON, Kind.BLEED]
	if can_split:
		kinds.append(Kind.SPLIT)
	return kinds[rng.randi_range(0, kinds.size() - 1)]

static func rolls_chest(rng: RandomNumberGenerator) -> bool:
	return rng.randf() < CHEST_CHANCE

static func make_material(kind: Kind) -> ShaderMaterial:
	if not OUTLINES.has(kind):
		return null
	var cfg: Array = OUTLINES[kind]
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("outline_color", cfg[0])
	mat.set_shader_parameter("outline_width", cfg[1])
	mat.set_shader_parameter("mode", cfg[2])
	return mat
