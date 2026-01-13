extends Area2D

# 이 동전이 얼마짜리인지 (생성될 때 적이 정해줄 예정)
var gold_amount: int = 10 
var target_body = null # 날아갈 목표(플레이어)
var speed = 0.0 # 날아가는 속도 (점점 빨라지게)
@onready var anim_player = $AnimationPlayer
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision: CollisionShape2D = $CollisionShape2D

func _ready():
	collision.set_deferred("disabled", true)
	_update_color()
		
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
	
	# 기존에 튀어오르던 트윈을 강제로 끄기 (Kill)
	# 그래야 공중에 있다가도 바로 플레이어한테 날아옴
	var tweens = get_tree().get_processed_tweens()
	for t in tweens:
		# 이 트윈이 '나(self)'를 움직이고 있다면 죽여라
		if t.is_valid(): 
			t.kill()
			
	# 즉시 충돌 켜기
	collision.set_deferred("disabled", false)

func setup(amount: int):
	gold_amount = amount
	_update_color()
	_animate_pop()
	

func _animate_pop():
	# 1. 랜덤한 방향으로 퍼질 거리 설정 (좌우 -40 ~ +40)
	var random_x = randf_range(-25, 25)
	
	# 2. 튀어오를 높이 (위로 50픽셀)
	var jump_height = -35.0 
	
	# 3. 원래 바닥 위치 (착지 지점)
	var start_y = position.y
	var land_y = position.y + 10.0
	
	_start_jump_sequence(start_y, land_y, jump_height, random_x)

func _start_jump_sequence(start_y, land_y, jump_height, target_x_offset):
	var t = create_tween()
	
	# 1) 위로 솟구치기 (시작점 -> 점프 높이)
	t.tween_property(self, "position:y", start_y + jump_height, 0.2).set_ease(Tween.EASE_OUT)
	
	# 2) 바닥으로 떨어지기 (점프 높이 -> 착지 위치 land_y)
	# start_y로 돌아오는 게 아니라, 더 아래인 land_y로 가야 합니다!
	t.tween_property(self, "position:y", land_y, 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BOUNCE)
	
	# 3) 동시에 옆으로 퍼지기 (X축)
	var t_x = create_tween()
	t_x.tween_property(self, "position:x", position.x + target_x_offset, 0.7)
	
	# 4) 다 끝나면 먹을 수 있게 켜기
	await t.finished
	collision.disabled = false
	
func _update_color():
	sprite.modulate = Color(1, 1, 1, 1)
	if gold_amount >= 1000:
		# 금화: "default" 애니메이션 재생 (이미지가 노란색이니 그대로 둠)
		sprite.play("default")
		
	elif gold_amount >= 100:
		# 은화: "silver" 애니메이션 재생 (이미지가 은색이니 그대로 둠)
		sprite.play("silver")
		
	else:
		# 동화: "default"(금화)를 틀어놓고 -> 구리색으로 칠하기!
		sprite.play("default")
		sprite.modulate = Color(0.8, 0.5, 0.2) # 구리색 덧칠
		
func _on_body_entered(body):
	# 플레이어가 닿으면
	if body.is_in_group("player"):
		GameManager.update_gold(gold_amount)

		# AudioManager.play_sfx("coin_pickup") 

		queue_free()
