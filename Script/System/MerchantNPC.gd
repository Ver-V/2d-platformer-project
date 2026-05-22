# MerchantNPC.gd
extends Area2D

# [1] 장소 구분용 변수
@export var location_name: String = "Stage1"
@onready var sprite = $AnimatedSprite2D
# [2] 말 건 횟수 기억하기 (GameManager와 연동)
var talk_count: int:
	get:
		return GameManager.npc_talk_counts.get(location_name, 0)
	set(value):
		GameManager.npc_talk_counts[location_name] = value

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
		
		# 대화 중이거나, 상점이 열려있다면 무조건 무시!
		if DialogueManager.is_dialogue_active or ShopUI.is_open:
			return
			
		get_viewport().set_input_as_handled()
		var file_path = "res://resources/Dialogues/merchant_" + location_name + "_" + str(talk_count) + ".json"
		
		if FileAccess.file_exists(file_path):
			DialogueManager.start_dialogue(file_path)
		
			await DialogueManager.dialogue_finished 
			
			# 대화가 끝났는데 플레이어가 범위 밖에 있다면
			if not player_in_range:
				return
				
			# 정상적으로 끝났을 때만 횟수 증가 및 상점 오픈
			talk_count += 1
			ShopUI.open_shop(location_name)
			
		else:
			if talk_count > 0:
				var last_file_path = "res://resources/Dialogues/merchant_" + location_name + "_" + str(talk_count - 1) + ".json"
				
				if FileAccess.file_exists(last_file_path):
					DialogueManager.start_dialogue(last_file_path)
					await DialogueManager.dialogue_finished 
					
					if not player_in_range:
						return
					
					ShopUI.open_shop(location_name) 

func _on_body_entered(body):
	if body.is_in_group("player"):
		player_in_range = true
		GameManager.interact_msg_requested.emit("shop")

func _on_body_exited(body):
	if body.is_in_group("player"):
		player_in_range = false
		GameManager.interact_msg_hidden.emit()
		
		# 플레이어가 멀어지면 대화창 강제 종료!
		if DialogueManager.is_dialogue_active:
			DialogueManager.force_close()
