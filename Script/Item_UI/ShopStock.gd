extends Resource
class_name ShopStock

# resources/shops/ 폴더에 두면 GameManager가 자동으로 읽는다.
# shop_id는 MerchantNPC의 location_name과 같아야 한다.
@export var shop_id: String = ""
@export var entries: Array[ShopEntry] = []
