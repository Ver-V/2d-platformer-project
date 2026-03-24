extends Area2D

# [설정] 필드 코인 여부 및 ID
@export_group("Field Settings")
@export var is_field_coin: bool = false
@export var id: String = ""

# [설정] 둥둥 떠다니는 느낌 조절
@export_group("Float Settings")
var float_speed: float = 5.0  # 꿀렁이는 속도
var float_range: float = 5.0  # 위아래 움직임 폭 (픽셀)

# 내부 변수
@export var gold_amount: int = 10
var target_body = null 
var speed = 0.0 
var time_passed: float = 0.0  # 시간 누적용 (sin 그래프용)
var can_float: bool = false   # "지금 둥둥 떠도 되니?" 상태 확인

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision: CollisionShape2D = $CollisionShape2D

func _ready():
	time_passed = randf_range(0.0, 10.0)
	
	if is_field_coin:
		_handle_field_coin_init()
	else:
		collision.set_deferred("disabled", true)
		_update_color()
		
func _process(delta):
	# 1. 자석 기능 (플레이어에게 날아가기)
	if is_instance_valid(target_body):
		var direction = global_position.direction_to(target_body.global_position)
		speed += 800 * delta 
		global_position += direction * speed * delta
		
		# [디테일] 날아갈 때는 둥둥 효과를 서서히 없애고 0으로 복귀 (덜덜 떨림 방지)
		sprite.position.y = move_toward(sprite.position.y, 0, delta * 50)
		
	# 2. 둥둥 떠다니기 (자석 아님 + 둥둥 허용 상태)
	elif can_float:
		time_passed = wrapf(time_passed + delta, 0.0, PI * 2.0)
		# sin(시간)은 -1 ~ 1을 반복하므로, 거기에 범위를 곱하면 위아래로 움직임
		sprite.position.y = sin(time_passed * float_speed) * float_range

func _handle_field_coin_init():
	# ID 자동 생성 및 중복 확인
	if id == "":
		var current_scene = get_tree().current_scene
		if current_scene:
			id = current_scene.name + "/" + str(get_path())
		else:
			id = "unknown_scene/" + str(get_path())
	
	if GameManager.collected_items.has(id):
		queue_free()
		return
		
	collision.set_deferred("disabled", false)
	_update_color()
	
	# [핵심] 필드 코인은 태어나자마자 둥둥 뜸
	can_float = true
	
# 자석에 감지되었을 때 호출될 함수
func attract_to(player_node):
	target_body = player_node
	# Tween kill 불필요 (process 분기문으로 처리되므로 안전함)
	collision.set_deferred("disabled", false)

func setup(amount: int):
	gold_amount = amount
	_update_color()
	_animate_pop()

func _start_floating():
	var t = create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(sprite, "position:y", -5.0, 1.0).as_relative()
	t.tween_property(sprite, "position:y", 5.0, 1.0).as_relative()

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
	if body.is_in_group("player"):
		GameManager.update_gold(gold_amount)
		
		# [핵심 수정] 필드 코인이라면 장부에 기록!
		if is_field_coin and id != "":
			GameManager.add_collected_item(id)
			
		# 효과음 재생 (AudioManager 코드 주석 해제하시면 됨)
		# AudioManager.play_sfx("coin_pickup") 
		queue_free()
