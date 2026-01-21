# FieldItem.gd
extends Area2D

# [핵심] 여기에 아까 만든 potion_hp.tres를 드래그해서 넣으면 끝!
@export var item_resource: ItemData

func _ready():
	if item_resource != null:
		# 스프라이트도 리소스에 있는 그림으로 자동 설정
		$Sprite2D.texture = item_resource.icon
	
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node):
	if body.is_in_group("player"):
		if item_resource != null:
			# 리소스 파일을 통째로 인벤토리에 넘김
			if GameManager.add_item(item_resource):
				print("획득: ", item_resource.name)
				queue_free()
