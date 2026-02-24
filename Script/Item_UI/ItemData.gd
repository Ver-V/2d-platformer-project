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

@export_group("Consumable Setting")
@export var heal_amount: int = 0  # 포션 아니면 그냥 0으로 두면 됨
@export var damage_amount: int = 0

@export_group("Equipment Setting")
@export var attack_damage: int = 0 # 무기 아니면 0으로 두면 됨
@export var parrymul: float = 0.0

# 2. 통합된 use 함수
func use(player) -> void:
	# 타입에 따라 행동을 가름 (Switch 문법)
	match type:
		ItemType.CONSUMABLE:
			_use_consumable(player)
		ItemType.EQUIPMENT:
			_use_equipment(player)
		_:
			print("이 아이템은 사용할 수 없습니다. (재료/열쇠 등)")

# 소모품일 때 실행될 로직
func _use_consumable(player) -> void:
	if heal_amount > 0:
		player.hp += heal_amount
		if player.hp > player.max_hp: player.hp = player.max_hp
		GameManager.update_hp(player.hp)
		HUD.show_hud_temporarily()
	if damage_amount > 0:
		player.damage += attack_damage

# 장비일 때 실행될 로직 (나중에 구현)
func _use_equipment(player) -> void:
	print("%s 장착함! 공격력 +%d" % [name, attack_damage])
	# 여기에 장착 로직 넣으면 됨 (GameManager.equip_item(self) 등)
