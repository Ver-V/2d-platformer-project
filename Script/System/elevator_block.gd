extends Area2D

@export_file("*.json") var dialogue_file: String = ""
@export var bounce_height: float = 10.0
@export var bounce_speed: float = 0.2

var is_active: bool = true
var original_pos: Vector2

func _ready() -> void:
	original_pos = position
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if not is_active or DialogueManager.is_dialogue_active: return
	
	if body.is_in_group("player"):
		var p = body as CharacterBody2D
		if p == null: return
		
		# [디버그] 어떤 상태로 부딪혔는지 확인
		print("ElevatorBlock 접촉! 플레이어 Y 속도: ", p.velocity.y)
		
		# 1. 플레이어가 위로 상승 중이거나, 거의 정지 상태(박은 직후)인 경우
		# 2. 플레이어의 위치가 블록의 중심보다 아래에 있는 경우 (아래에서 위로 박음)
		# velocity.y 체크를 -10.0 정도로 넉넉하게 잡거나, 
		# 이미 박아서 0이 된 경우를 대비해 위치 조건을 우선시합니다.
		if p.global_position.y > global_position.y:
			# 박치기 판정: 상승 중이거나, 점프 상태에서 머리가 닿았을 때
			if p.velocity.y < 50.0: # 떨어지는 중만 아니면 됨
				_hit_block()

func _hit_block() -> void:
	print("ElevatorBlock 작동!")
	# 블록 튕김 연출
	var tween = create_tween()
	# ... rest of the code
	tween.tween_property(self, "position:y", original_pos.y - bounce_height, bounce_speed / 2).set_trans(Tween.TRANS_SINE)
	tween.tween_property(self, "position:y", original_pos.y, bounce_speed / 2).set_trans(Tween.TRANS_SINE)
	
	if dialogue_file != "":
		DialogueManager.start_dialogue(dialogue_file)
	
	# 필요하다면 일정 시간 쿨다운
	is_active = false
	await get_tree().create_timer(1.0).timeout
	is_active = true
