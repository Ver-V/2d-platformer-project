# MerchantNPC.gd
extends Area2D

# [1] 장소 구분용 변수
@export var location_name: String = "Stage1"
@onready var sprite = $AnimatedSprite2D
# [2] 말 건 횟수 기억하기
var talk_count: int = 0
var player_in_range = false

var has_bought: bool = false

func _ready() -> void:
	sprite.play("Idle")
	ShopUI.shop_closed.connect(_on_shop_closed)

func _on_shop_closed(bought: bool):
	if bought:
		has_bought = true # 물건을 하나라도 샀다면 상태 변경!
		
func _input(event):
	if player_in_range and event.is_action_pressed("interact"):
		if DialogueManager.is_dialogue_active:
			return
			
		# ----------------------------------------------------
		# 1. 만약 물건을 이미 산 상태라면? -> 감사 대사 전용 파일 실행
		# ----------------------------------------------------
		if has_bought:
			var bought_file = "res://resources/Dialogues/merchant_" + "thanks.json"
			
			if FileAccess.file_exists(bought_file):
				DialogueManager.start_dialogue(bought_file)
				
				# 대사가 끝날 때까지 기다림 (핵심!)
				await DialogueManager.dialogue_finished 
				
				# 대화 끝나고 상점 다시 열어주기
				ShopUI.open_shop() 
			else:
				print("구매 후 대사 파일이 없습니다: ", bought_file)
			return # 아래 로직은 무시하고 여기서 끝냄
			
		# ----------------------------------------------------
		# 2. 아직 물건을 안 산 상태 (기존 로직 + await 추가)
		# ----------------------------------------------------
		var file_path = "res://resources/Dialogues/merchant_" + location_name + "_" + str(talk_count) + ".json"
		
		if FileAccess.file_exists(file_path):
			DialogueManager.start_dialogue(file_path)
			talk_count += 1
		
			await DialogueManager.dialogue_finished 
			ShopUI.open_shop()
			
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
