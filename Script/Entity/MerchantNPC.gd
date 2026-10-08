# MerchantNPC.gd
extends Interactable

# [1] 장소 구분용 변수
@export var location_name: String = "Stage1"
@onready var sprite = $AnimatedSprite2D
# [2] 말 건 횟수 기억하기 (GameManager와 연동)
var talk_count: int:
	get:
		return GameManager.npc_talk_counts.get(location_name, 0)
	set(value):
		GameManager.npc_talk_counts[location_name] = value

func _ready() -> void:
	interact_msg = "shop"
	super()
	add_to_group("npc")
	sprite.play("Idle")
	ShopUI.shop_closed.connect(_on_shop_closed)

func _on_shop_closed(bought: bool):
	# 같은 씬에 상인이 여럿이어도 방금 닫힌 상점의 상인만 대사를 한다
	if bought and ShopUI.current_shop_id == location_name:
		# 물건을 샀다면, 상점 UI가 닫히자마자 즉시 감사 대사 출력!
		var bought_file = "res://resources/Dialogues/en/merchant_" + "thanks.json"
		
		if DialogueManager.has_dialogue_file(bought_file):
			DialogueManager.start_dialogue(bought_file)
		else:
			push_warning("구매 후 대사 파일이 없습니다: " + str(bought_file))
			
# 메뉴 잠금은 Interactable이 확인한다. 대화·상점 상태도 한 번 더 확인.
func _can_interact() -> bool:
	return not DialogueManager.is_dialogue_active and not ShopUI.is_open

func _on_interact() -> void:
	var file_path = "res://resources/Dialogues/en/merchant_" + location_name + "_" + str(talk_count) + ".json"
	
	if DialogueManager.has_dialogue_file(file_path):
		DialogueManager.start_dialogue(file_path)
	
		await DialogueManager.dialogue_finished 
		
		# 대화가 끝났는데 플레이어가 범위 밖에 있다면
		if not player_in_range:
			return
			
		# 정상적으로 끝났을 때만 횟수 증가 및 상점 오픈
		talk_count += 1
		ShopUI.open_shop(location_name)
		
	else:
		var last_file_path = "res://resources/Dialogues/en/merchant_" + location_name + "_" + str(talk_count - 1) + ".json"
		if talk_count > 0 and DialogueManager.has_dialogue_file(last_file_path):
			DialogueManager.start_dialogue(last_file_path)
			await DialogueManager.dialogue_finished 
			
			if not player_in_range:
				return
			
			ShopUI.open_shop(location_name) 
		else:
			# 대사 파일이 하나도 없는 상인(merchant_<location_name>_0.json 없음)은 바로 상점을 연다
			ShopUI.open_shop(location_name)

# 플레이어가 멀어지면 대화창 강제 종료!
func _on_player_exited(_body: Node) -> void:
	if DialogueManager.is_dialogue_active:
		DialogueManager.force_close()
