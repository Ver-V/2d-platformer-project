# MerchantNPC.gd
extends Area2D

# [1] 장소 구분용 변수
@export var location_name: String = "Stage1"
@onready var sprite = $AnimatedSprite2D
# [2] 말 건 횟수 기억하기
var talk_count: int = 0

var player_in_range = false

func _ready() -> void:
	sprite.play("Idle")
	
func _input(event):
	if player_in_range and event.is_action_pressed("interact"):
		# 만약 대화창이 이미 떠있다면 무시
		if DialogueManager.is_dialogue_active:
			return
			
		# [핵심 1] 장소와 횟수를 조합해서 파일 경로를 자동 완성!
		var file_path = "res://resources/Dialogues/merchant_" + location_name + "_" + str(talk_count) + ".json"
		
		# [핵심 2] 파일이 진짜 있는지 확인 (더 이상 할 말이 없을 때를 대비)
		if FileAccess.file_exists(file_path):
			DialogueManager.start_dialogue(file_path)
			
			# 말 걸었으니 횟수 1 증가
			talk_count += 1
			
		else:
			# [수정된 부분] 만약 준비된 대사를 다 봐서 더 이상 파일이 없다면?
			if talk_count > 0:
				# 횟수를 다시 1 깎아서 마지막 대사를 부르도록 함
				talk_count -= 1 
				
				# ⭐ [가장 중요] 여기 경로도 똑같이 res://resources/... 로 맞춰줍니다!
				var last_file_path = "res://resources/Dialogues/merchant_" + location_name + "_" + str(talk_count) + ".json"
				
				if FileAccess.file_exists(last_file_path):
					DialogueManager.start_dialogue(last_file_path)
				else:
					print("에러: 마지막 대사 파일조차 찾을 수 없습니다.")
			else:
				# 0번 파일(첫 대사)조차 아예 만들어두지 않았을 때 튕김 방지
				print("에러: 상인의 첫 번째 대사 파일이 없습니다.")

func _on_body_entered(body):
	if body.name == "Player":
		player_in_range = true
		HUD.interact_label.visible = true

func _on_body_exited(body):
	if body.name == "Player":
		player_in_range = false
		HUD.interact_label.visible = false
