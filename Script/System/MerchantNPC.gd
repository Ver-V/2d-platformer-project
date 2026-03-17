# MerchantNPC.gd
extends Area2D

# [1] 장소 구분용 변수
@export var location_name: String = "Stage1"
@onready var sprite = $AnimatedSprite2D
# [2] 말 건 횟수 기억하기
var talk_count: int = 0
var player_in_range = false

func _ready() -> void:
	add_to_group("npc")
	sprite.play("Idle")
	ShopUI.shop_closed.connect(_on_shop_closed)

func _on_shop_closed(bought: bool):
	if bought:
		# 물건을 샀다면, 상점 UI가 닫히자마자 즉시 감사 대사 출력!
		var bought_file = "res://resources/Dialogues/merchant_" + "thanks.json"
		
		if FileAccess.file_exists(bought_file):
			DialogueManager.start_dialogue(bought_file)
		else:
			print("구매 후 대사 파일이 없습니다: ", bought_file)
			
func _input(event):
	if player_in_range and event.is_action_pressed("interact"):
		
		# ⭐ [수정된 핵심 방어막] 대화 중이거나, 상점이 열려있다면 무조건 무시!
		if DialogueManager.is_dialogue_active or ShopUI.is_open:
			return
			
		# ⭐ [입력 삼키기] E키를 여기서 꿀꺽해서 다른 애들이 못 듣게 합니다.
		get_viewport().set_input_as_handled()
		var file_path = "res://resources/Dialogues/merchant_" + location_name + "_" + str(talk_count) + ".json"
		
		if FileAccess.file_exists(file_path):
			DialogueManager.start_dialogue(file_path)
			talk_count += 1
		
			await DialogueManager.dialogue_finished 
			ShopUI.open_shop(location_name)
			
		else:
			if talk_count > 0:
				talk_count -= 1 
				var last_file_path = "res://resources/Dialogues/merchant_" + location_name + "_" + str(talk_count) + ".json"
				
				if FileAccess.file_exists(last_file_path):
					DialogueManager.start_dialogue(last_file_path)
					
					# [수정] 대사가 끝날 때까지 코드 실행을 일시정지!
					await DialogueManager.dialogue_finished 
					
					# 대사가 완전히 화면에서 사라진 직후 상점 열기
					ShopUI.open_shop() 
				else:
					print("에러: 마지막 대사 파일조차 찾을 수 없습니다.")
			else:
				print("에러: 상인의 첫 번째 대사 파일이 없습니다.")

func _on_body_entered(body):
	if body.name == "Player":
		player_in_range = true
		GameManager.interact_msg_requested.emit("shop")

func _on_body_exited(body):
	if body.name == "Player":
		player_in_range = false
		GameManager.interact_msg_hidden.emit()
