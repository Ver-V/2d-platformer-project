# Database.gd (autoload: Database)
extends Node

# 게임에 존재하는 아이템(ItemData)·상점(ShopStock) 정의. 플레이 중에 바뀌지 않는 읽기 전용 데이터.
# 폴더의 .tres를 자동으로 읽으므로 코드에 목록을 적지 않는다.
# "이번 판에 몇 개 팔렸나" 같은 진행 상태는 GameManager(shop_sold)가 들고 있다.

const ITEM_DIR: String = "res://resources/items/"
const SHOP_DIR: String = "res://resources/shops/"

var item_database: Dictionary = {} # id -> ItemData
var shop_database: Dictionary = {} # shop_id -> ShopStock

func _ready() -> void:
	reload()

func reload() -> void:
	item_database.clear()
	for res in _load_resources_in(ITEM_DIR):
		var item := res as ItemData
		if item == null:
			continue
		if item.id.is_empty() or item_database.has(item.id):
			push_warning("Database: 아이템 id가 비었거나 중복됩니다: %s (%s)" % [item.id, item.resource_path])
			continue
		item_database[item.id] = item
	shop_database.clear()
	for res in _load_resources_in(SHOP_DIR):
		var shop := res as ShopStock
		if shop == null:
			continue
		if shop.shop_id.is_empty() or shop_database.has(shop.shop_id):
			push_warning("Database: 상점 id가 비었거나 중복됩니다: %s (%s)" % [shop.shop_id, shop.resource_path])
			continue
		shop_database[shop.shop_id] = shop

func get_item_by_id(item_id: String) -> ItemData:
	return item_database.get(item_id)

func get_shop(shop_id: String) -> ShopStock:
	return shop_database.get(shop_id)

# 익스포트 빌드에서는 .tres가 변환되므로 DirAccess 대신 ResourceLoader.list_directory를 쓴다.
func _load_resources_in(dir: String) -> Array[Resource]:
	var result: Array[Resource] = []
	for file in ResourceLoader.list_directory(dir):
		if file.ends_with(".tres") or file.ends_with(".res"):
			var res := load(dir + file)
			if res != null:
				result.append(res)
	return result
