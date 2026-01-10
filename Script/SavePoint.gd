# SavePoint.gd
extends Area2D

@onready var sprite = $AnimatedSprite2D # 색깔/애니메이션 바꾸기용

var can_save: bool = true   # 쿨타임 체크용
var player_in_range: bool = false # 플레이어가 범위 안에 있는지?

func _ready() -> void:
	# 시그널 연결
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	
	if sprite != null:
		sprite.play("default")

# 플레이어가 범위에 들어왔을 때 -> "저장하기" 안내 띄움
func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		player_in_range = true
		# 텍스트 내용은 필요 없으니 빈칸("")을 보냅니다. HUD가 알아서 무시하고 켜기만 할 겁니다.
		GameManager.interact_msg_requested.emit("Save")

# 플레이어가 나갔을 때 -> 안내 끄기
func _on_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		player_in_range = false
		GameManager.interact_msg_hidden.emit()

# 키 입력 감지 (process나 input 함수 사용)
func _input(event: InputEvent) -> void:
	# 1. 플레이어가 범위 안에 있고
	# 2. 저장 가능한 상태(쿨타임 아님)이고
	# 3. 방금 'interact'(E키)를 눌렀다면?
	if player_in_range and can_save and event.is_action_pressed("Interact"):
		activate_checkpoint()

func activate_checkpoint() -> void:
	# 중복 저장 방지 (쿨타임 시작)
	can_save = false
	
	# 1. 플레이어 체력 회복 (선택사항 - 할로우 나이트 스타일)
	# 범위 내의 플레이어를 찾아서 체력을 채워줍니다.
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		GameManager.player_current_hp = players[0].hp
	
	GameManager.save_checkpoint(global_position + Vector2(0, -10))
	GameManager.save_game()
	print("Saved Game")
	
	print("체크포인트 저장 완료!")
	
	# 3. 피드백 (텍스트 변경 & 깜빡임)
	GameManager.interact_msg_requested.emit("Saved!")
	
	if sprite:
		# 저장됐다는 느낌을 주기 위해 색을 잠시 바꿈 (예: 초록색)
		var original_modulate = sprite.modulate
		sprite.modulate = Color(0.5, 1.5, 0.5) # 밝은 초록빛
		await get_tree().create_timer(0.5).timeout
		sprite.modulate = original_modulate
	
	# 4. 쿨타임 해제 (다시 저장 가능)
	# 바로 저장이 가능하게 할지, 조금 기다리게 할지 결정 (여기선 1초 대기)
	await get_tree().create_timer(3.0).timeout
	can_save = true
	
	# 플레이어가 여전히 서 있다면 다시 안내 문구로 복귀
	if player_in_range:
		GameManager.interact_msg_requested.emit("Save")
