# SavePoint.gd
extends Area2D

@onready var sprite = $AnimatedSprite2D # 색깔 바꾸기용
var can_save: bool = true # 저장 가능 여부 (쿨타임용)

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	if sprite != null:
		sprite.play("default")
		
func _on_body_entered(body: Node) -> void:
	if not can_save: return # 쿨타임 중이면 무시
	
	if body.is_in_group("player"):
		activate_checkpoint()

func activate_checkpoint() -> void:
	# 1. 저장 실행 (메모리 + 파일)
	# 플레이어가 바닥에 끼지 않게 Y축을 살짝(-10) 올려서 저장
	GameManager.save_checkpoint(global_position + Vector2(0, -10))
	GameManager.save_game()
	
	print("체크포인트 저장 완료!")
	
	# 2. 비주얼/사운드 효과 (지나갈 때마다 반짝이게)
	# 여기에 효과음 재생 코드 넣으면 좋습니다 (예: $AudioStreamPlayer.play())
	
	# 3. 짧은 쿨타임 적용 (저장 도배 방지용 2~3초)
	can_save = false
	await get_tree().create_timer(3.0).timeout 
	
	# 3초 뒤에 색깔 원래대로 & 다시 저장 가능
	can_save = true
