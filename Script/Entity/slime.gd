extends EnemyBase
class_name Slime

@export var gravity: float = 980.0
@export var max_fall_speed: float = 280.0

@export var slime_max_hp: int = 30
@export var slime_contact_damage: int = 10
@export var slime_move_speed: float = 40.0
@export var slime_knockback_res: float = 0.0

@export var turn_on_wall: bool = true
@export var turn_on_ledge: bool = true
@export var detect_radius: float = 50.0      # 인식 범위 반지름

var dir: int = -1
var _base_scale: Vector2 = Vector2.ONE

func _ready() -> void:
	max_hp_base = slime_max_hp
	contact_damage_base = slime_contact_damage
	move_speed_base = slime_move_speed
	knockback_resist = slime_knockback_res
	super._ready()
	
	# 인식 범위 설정
	if detect_area:
		var shape = detect_area.get_node("CollisionShape2D")
		if shape and shape.shape is CircleShape2D:
			shape.shape = shape.shape.duplicate()
			shape.shape.radius = detect_radius
	
	if sprite:
		_base_scale = sprite.scale
		sprite.play("idle")
		
	if turn_on_ledge and is_ledge_ahead(dir):
		dir = -dir
		if sprite: sprite.flip_h = dir > 0

func _process(delta: float) -> void:
	super._process(delta)

	if hp <= 0:
		if sprite and sprite.animation != "died" and sprite.animation != "dead":
			if sprite.sprite_frames.has_animation("dead"):
				sprite.play("dead")
			elif sprite.sprite_frames.has_animation("died"):
				sprite.play("died")
		return

func _physics_process(delta: float) -> void:
	if not _active or hp <= 0:
		return

	# 중력 적용
	velocity.y += gravity * delta
	if velocity.y > max_fall_speed:
		velocity.y = max_fall_speed

	if is_on_floor():
		# 1. 방향 결정 (추격 또는 순찰)
		if target != null:
			var dx = target.global_position.x - global_position.x
			dir = 1 if dx >= 0 else -1
		
		# 2. 이동 방해 요소 체크 (방 경계 및 낭떠러지) - 공통 적용
		var is_blocked = false
		if room_rect.size != Vector2.ZERO:
			# 방 경계 도달 여부
			if (global_position.x < room_rect.position.x + 12 and dir < 0) or \
			   (global_position.x > room_rect.end.x - 12 and dir > 0):
				is_blocked = true
		
		# 낭떠러지 감지
		if turn_on_ledge and is_ledge_ahead(dir):
			is_blocked = true

		# 3. 실제 속도 계산
		if is_blocked:
			velocity.x = 0 # 즉시 정지
			if target == null: 
				dir = -dir # 순찰 중이면 방향 전환
		else:
			# 추격 중엔 조금 더 빠르게, 정찰 중엔 원래 속도로
			var speed_mult = 1.3 if target != null else 1.0
			velocity.x = move_toward(velocity.x, dir * (slime_move_speed * speed_mult), 800 * delta)
			
		if sprite: sprite.play("idle")
	else:
		# 공중 상태: 수평 속도 감쇄 (관성 방지)
		velocity.x = move_toward(velocity.x, 0, 300 * delta)

	super._physics_process(delta)
	
	# 이동 후 벽 충돌 감지
	if is_on_floor() and is_on_wall():
		dir = -dir
	
	if sprite:
		sprite.flip_h = dir > 0
