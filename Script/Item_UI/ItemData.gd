extends Resource
class_name ItemData

# 1. 아이템 타입을 숫자로 정의 (이걸 'Enum'이라고 함)
enum ItemType { GENERIC, CONSUMABLE, EQUIPMENT }
# 장착하는 칸: 보조 장비(랜턴 등) 4칸, 보석(공격·스탯 추가 효과) 2칸. NONE이면 장착하지 않는 아이템
enum EquipSlot { NONE, ACCESSORY, GEM }

@export_group("Basic Info")
@export var id: String = ""
@export var name: String = "Item Name"
@export var icon: Texture2D
@export var price: int = 0
@export_multiline var description: String = ""
@export var type: ItemType = ItemType.GENERIC # 기본값은 잡동사니

@export_group("Animation")
# 있으면 필드(FieldItem)와 인벤토리 슬롯에서 icon 대신 이 애니메이션을 재생한다. 상점 등 나머지 UI는 icon 그대로.
@export var anim_frames: SpriteFrames
@export var anim_name: StringName = &"default"

@export_group("Key Setting")
@export_range(0, 99, 1) var key_uses: int = 0 # 0이면 열쇠가 아님; 문에서 요구하는 일반 아이템은 1회 사용
# 이 열쇠로 여는 문에 뜨는 자물쇠 그림. 같은 열쇠를 쓰는 문은 모두 같은 자물쇠가 뜬다.
# 애니메이션: "locked" = 열쇠 없이 열려고 할 때, "unlock" = 열쇠로 풀릴 때 (반복 끄기)
@export var lock_sprite_frames: SpriteFrames

@export_group("Consumable Setting")
@export var heal_amount: int = 0  # 포션 아니면 그냥 0으로 두면 됨
@export var damage_amount: int = 0
@export var parry_multifactor: float = 0.0
@export var unlocks_heavy_attack: bool = false # 마시면 강공격 해금 (수상한 과학자의 약물)

@export_group("Passive Setting")
# 장착(equip_slot)하면 시야 제한(VisionLimit) 반지름이 이 타일 수만큼 넓어진다. 여러 개면 가장 큰 값만 적용.
@export var vision_bonus_tiles: float = 0.0

@export_group("Equipment Setting")
# 장착해야 효과가 있다 (가방에 들고만 있으면 없음). 효과는 장착한 것끼리 더한다 (시야 보너스만 가장 큰 값)
@export var equip_slot: EquipSlot = EquipSlot.NONE
@export var attack_damage: int = 0 # 장착 중 공격력 +
@export var parrymul: float = 0.0 # 장착 중 패링 배율 +
@export var attack_speed_bonus: float = 0.0 # 장착 중 공격 속도 + (0.1 = 10% 빠르게: 공격 쿨다운·공격 애니메이션)
# 장착 중 검으로 때리면 hit_status_chance 확률로 거는 상태이상 (보석용, 비우면 없음)
@export var hit_status: StatusEffect
@export_range(0.0, 1.0) var hit_status_chance: float = 1.0

# 장착 효과를 한 줄씩 번역해서 돌려준다 (정보창의 이름 아래에 표시). 장착 아이템이 아니거나 효과가 없으면 빈 배열
# 각 줄은 {"text": 번역된 문구, "buff": 값이 오르면 true / 내리면 false}
func effect_lines() -> Array[Dictionary]:
	var lines: Array[Dictionary] = []
	if equip_slot == EquipSlot.NONE:
		return lines
	if attack_damage != 0:
		lines.append(_effect_line(&"ITEM_EFFECT_ATTACK", attack_damage))
	if not is_zero_approx(attack_speed_bonus):
		lines.append(_effect_line(&"ITEM_EFFECT_ATTACK_SPEED", roundi(attack_speed_bonus * 100.0)))
	if not is_zero_approx(parrymul):
		lines.append(_effect_line(&"ITEM_EFFECT_PARRY", parrymul))
	if not is_zero_approx(vision_bonus_tiles):
		lines.append(_effect_line(&"ITEM_EFFECT_VISION", vision_bonus_tiles))
	return lines

# "+ 5" / "- 5" 처럼 부호와 숫자 사이를 띄운다
func _effect_line(key: StringName, value: float) -> Dictionary:
	var v := absf(value)
	var number := str(roundi(v)) if is_equal_approx(v, roundf(v)) else String.num(v, 2) # 정수면 "5", 아니면 "0.25"
	var signed := ("+ " if value >= 0.0 else "- ") + number
	return {"text": TranslationServer.translate(key).format({"value": signed}), "buff": value >= 0.0}

func has_animation() -> bool:
	return anim_frames != null and anim_frames.has_animation(anim_name) and anim_frames.get_frame_count(anim_name) > 0

# 재생 시작 후 time초가 지났을 때 보여줄 프레임 (AnimatedSprite2D를 못 쓰는 TextureRect용). 애니메이션이 없으면 icon.
func get_frame_at(time: float) -> Texture2D:
	if not has_animation():
		return icon
	var count := anim_frames.get_frame_count(anim_name)
	var fps := anim_frames.get_animation_speed(anim_name)
	var total := 0.0
	for i in count:
		total += anim_frames.get_frame_duration(anim_name, i)
	if fps <= 0.0 or total <= 0.0:
		return anim_frames.get_frame_texture(anim_name, 0)
	var pos := time * fps
	pos = fmod(pos, total) if anim_frames.get_animation_loop(anim_name) else minf(pos, total)
	for i in count:
		pos -= anim_frames.get_frame_duration(anim_name, i)
		if pos < 0.0:
			return anim_frames.get_frame_texture(anim_name, i)
	return anim_frames.get_frame_texture(anim_name, count - 1)

# 2. 통합된 use 함수
func use(player) -> void:
	# 타입에 따라 행동을 가름 (Switch 문법)
	match type:
		ItemType.CONSUMABLE:
			_use_consumable(player)
		ItemType.EQUIPMENT:
			_use_equipment(player)
		_:
			DebugLog.info("이 아이템은 사용할 수 없습니다. (재료/열쇠 등)")

# 소모품일 때 실행될 로직
func _use_consumable(player) -> void:
	if heal_amount > 0:
		player.hp += heal_amount
		if player.hp > player.max_hp: player.hp = player.max_hp
		GameManager.update_hp(player.hp)
		HUD.show_hud_temporarily()
	if damage_amount > 0:
		player.update_damage(damage_amount)
	if parry_multifactor > 0:
		player.update_parry_ratio(parry_multifactor)
	if unlocks_heavy_attack:
		GameManager.unlock_heavy_attack()

# 장비일 때 실행될 로직 (나중에 구현)
func _use_equipment(player) -> void:
	DebugLog.info("%s 장착함! 공격력 +%d" % [name, attack_damage])
	# 여기에 장착 로직 넣으면 됨 (GameManager.equip_item(self) 등)
