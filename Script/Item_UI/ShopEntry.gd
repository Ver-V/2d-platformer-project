extends Resource
class_name ShopEntry

# 상점 한 줄: 파는 아이템과 처음 재고
@export var item: ItemData
@export_range(0, 99, 1) var stock: int = 1
