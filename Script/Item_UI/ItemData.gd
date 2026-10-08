extends Resource
class_name ItemData

# 1. 아이템 타입을 숫자로 정의 (이걸 'Enum'이라고 함)
enum ItemType { GENERIC, CONSUMABLE, EQUIPMENT }

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

@export_group("Passive Setting")
# 인벤토리에 갖고만 있어도 시야 제한(VisionLimit) 반지름이 이 타일 수만큼 넓어진다. 여러 개면 가장 큰 값만 적용.
@export var vision_bonus_tiles: float = 0.0

@export_group("Equipment Setting")
@export var attack_damage: int = 0 # 무기 아니면 0으로 두면 됨
@export var parrymul: float = 0.0

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

# 장비일 때 실행될 로직 (나중에 구현)
func _use_equipment(player) -> void:
	DebugLog.info("%s 장착함! 공격력 +%d" % [name, attack_damage])
	# 여기에 장착 로직 넣으면 됨 (GameManager.equip_item(self) 등)
