extends Area2D

# 이 동전이 얼마짜리인지 (생성될 때 적이 정해줄 예정)
var gold_amount: int = 10 

func _ready():
	# (선택) 바닥에 떨어지는 느낌을 위해 튀어오르는 애니메이션 등을 넣을 수 있음
	pass

func _on_body_entered(body):
	# 플레이어가 닿으면
	if body.is_in_group("player"): # 플레이어 노드를 그룹에 추가해두세요!
		# 1. 골드 획득
		GameManager.update_gold(gold_amount)
		
		if body.has_method("show_status"):
			# show_status 함수에 "gold" 타입을 보내면 노란색으로 뜸
			# (Player.gd의 show_status를 조금 수정해서 amount를 받게 하거나, 
			#  show_popup을 직접 부를 수도 있습니다. 일단은 간단하게 "gold" 타입만 호출)
			body.show_status("gold")
		
		# 2. (선택) 획득 효과음 재생
		# AudioManager.play_sfx("coin_pickup") 
		
		# 3. 사라짐
		queue_free()
