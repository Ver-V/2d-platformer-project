extends Resource
class_name ItemData

@export var id: String = ""           # [핵심] 저장할 때 쓸 주민등록번호 (예: "potion_red")
@export var name: String = "Item"
@export var icon: Texture2D = null
@export var description: String = ""
@export var max_stack: int = 99       # 한 칸에 몇 개까지 겹치나?

# 아이템 사용 시 효과 (나중에 상속받아서 구현)
func use(player) -> void:
	return
