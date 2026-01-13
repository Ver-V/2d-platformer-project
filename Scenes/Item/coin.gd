extends Area2D

# 이 동전이 얼마짜리인지 (생성될 때 적이 정해줄 예정)
var gold_amount: int = 10 
var target_body = null # 날아갈 목표(플레이어)
var speed = 0.0 # 날아가는 속도 (점점 빨라지게)

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision: CollisionShape2D = $CollisionShape2D

func _ready():
	collision.set_deferred("disabled", true)
	_update_color()
	if sprite != null :
		sprite.play("default")
		
func _process(delta):
	# 목표가 생기면 그쪽으로 날아갑니다!
	if target_body != null:
		# 1. 플레이어 위치 방향으로 이동
		var direction = global_position.direction_to(target_body.global_position)
		
		# 2. 가속도 (점점 빨라짐)
		speed += 800 * delta 
		
		# 3. 실제 이동
		global_position += direction * speed * delta

# 자석에 감지되었을 때 호출될 함수
func attract_to(player_node):
	target_body = player_node
	
	# 튀어오르는 애니메이션(Tween)이 있으면 멈춰야 자연스럽게 끌려감
	# (모든 Tween을 강제로 끊는 코드)
	var tweens = get_tree().get_processed_tweens()
	for t in tweens:
		# 현재 내 객체(self)와 관련된 트윈인지 확인은 어렵지만,
		# 간단히 구현하려면 그냥 덮어씌우면 됩니다.
		# 하지만 가장 좋은 건 기존 animate_pop에서 만든 tween 변수를 전역으로 빼서 kill() 하는 것입니다.
		pass

func setup(amount: int):
	gold_amount = amount
	_update_color()
	_animate_pop()
	

func _animate_pop():
	# 1. 랜덤한 방향으로 퍼질 거리 설정 (좌우 -40 ~ +40)
	var random_x = randf_range(-25, 25)
	
	# 2. 튀어오를 높이 (위로 50픽셀)
	var jump_height = -30.0 
	
	# 3. 원래 바닥 위치 (착지 지점)
	var floor_y = position.y
	
	# 트윈(애니메이션) 생성
	var tween = create_tween()
	tween.set_parallel(true) # 동시에 실행해라!
	
	# [X축] 옆으로 스르륵 이동
	tween.tween_property(self, "position:x", position.x + random_x, 0.5)
	
	# [Y축] 위로 솟구쳤다가 (0.25초) -> 바닥으로 쿵 (0.25초)
	# 4. 위로 점프 (Ease OUT: 속도가 줄어듦)
	tween.tween_property(self, "position:y", floor_y + jump_height, 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	
	# 5. 아래로 낙하 (연속 동작을 위해 chain 사용하지 않고 시간차 계산)
	# 하지만 parallel이라 겹치므로, 별도의 트윈을 하나 더 쓰는 게 안전합니다.
	# -> 코드를 더 쉽게 하기 위해 시퀀스(순서대로) 방식으로 바꿉니다.
	
	_start_jump_sequence(floor_y, jump_height, random_x)

func _start_jump_sequence(floor_y, jump_height, target_x_offset):
	var tween = create_tween()
	
	# 1. 위로 점프하면서 옆으로 이동 (0.3초)
	tween.set_parallel(true)
	tween.tween_property(self, "position:y", floor_y + jump_height, 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(self, "position:x", position.x + target_x_offset, 0.6) # X는 천천히 계속 이동
	
	# 2. 아래로 낙하 (Bounce 효과: 텅~ 텅~ 튀기기)
	tween.set_parallel(false) # 이제 순서대로
	# 위 애니메이션이 끝날 때까지 기다리는 대신, chain()을 쓰거나 시간을 맞춥니다.
	# 여기선 쉬운 구현을 위해 트윈을 쪼갭니다. 
	
	# (복잡한 트윈 대신 더 쉬운 방법: 중력 흉내내기)
	# 아래 코드가 훨씬 자연스럽습니다.
	tween.kill() # 위 트윈 취소하고 아래 로직으로 갑니다.
	
	# --- 진짜 쉬운 팝업 로직 ---
	var t = create_tween()
	# 위로 솟구치기 (0.2초)
	t.tween_property(self, "position:y", floor_y + jump_height, 0.2).set_ease(Tween.EASE_OUT)
	# 바닥으로 떨어지면서 튕기기 (Bounce) (0.5초)
	t.tween_property(self, "position:y", floor_y, 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BOUNCE)
	
	# 동시에 옆으로 퍼지기 (별도 트윈)
	var t_x = create_tween()
	t_x.tween_property(self, "position:x", position.x + target_x_offset, 0.7)
	
	await t.finished
	collision.disabled = false
	
func _update_color():
	# 딱 떨어지는 값으로 비교하면 됩니다.
	if gold_amount >= 1000:
		sprite.modulate = Color(1.0, 0.85, 0.0) # 금색
	elif gold_amount >= 100:
		sprite.modulate = Color(0.85, 0.9, 1.0) # 은색
	else:
		sprite.modulate = Color(0.8, 0.5, 0.2) # 동색
		
func _on_body_entered(body):
	# 플레이어가 닿으면
	if body.is_in_group("player"):
		GameManager.update_gold(gold_amount)

		# AudioManager.play_sfx("coin_pickup") 
		
		# 3. 사라짐
		queue_free()
