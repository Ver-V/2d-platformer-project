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

@export var jump_impulse: float = -320.0     # 점프 힘 (조금 더 강화)
@export var jump_cooldown: float = 2.0      # 점프 주기
@export var jump_horizontal_force: float = 120.0 # 점프 시 앞으로 나가는 힘

var dir: int = -1
var _jump_timer: float = 0.0
var _is_jumping: bool = false
var _squash_tween: Tween

func _ready() -> void:
	max_hp_base = slime_max_hp
	contact_damage_base = slime_contact_damage
	move_speed_base = slime_move_speed
	knockback_resist = slime_knockback_res
	super._ready()
	
	if sprite:
		sprite.play("idle")

func apply_squash(x: float, y: float) -> void:
	if _squash_tween:
		_squash_tween.kill()
	_squash_tween = create_tween()
	sprite.scale = Vector2(x, y)
	_squash_tween.tween_property(sprite, "scale", Vector2(1, 1), 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _process(delta: float) -> void:
	super._process(delta)

	if hp <= 0:
		if sprite and sprite.animation != "died" and sprite.animation != "dead":
			if sprite.sprite_frames.has_animation("dead"):
				sprite.play("dead")
			elif sprite.sprite_frames.has_animation("died"):
				sprite.play("died")
		return

	if _jump_timer > 0.0:
		_jump_timer -= delta

func _physics_process(delta: float) -> void:
	if not _active or hp <= 0:
		return

	# 중력 적용
	velocity.y += gravity * delta
	if velocity.y > max_fall_speed:
		velocity.y = max_fall_speed

	if is_on_floor():
		# 바닥에선 천천히 이동하거나 대기
		velocity.x = move_toward(velocity.x, 0, 500 * delta)
		
		if _is_jumping:
			_is_jumping = false
			apply_squash(1.3, 0.7) # 착지 효과
			if sprite: sprite.play("idle")
		
		# 점프 로직
		if _jump_timer <= 0.0:
			_perform_jump()
	else:
		# 공중에선 점프 방향 유지 (이미 velocity.x에 설정됨)
		pass

	super._physics_process(delta)
	
	# 벽에 부딪히면 방향 전환
	if is_on_wall():
		dir = -dir
		velocity.x = -velocity.x * 0.5 # 튕겨나가는 느낌

	if sprite:
		sprite.flip_h = dir > 0

func _perform_jump() -> void:
	_jump_timer = jump_cooldown
	_is_jumping = true
	
	# 타겟(플레이어)이 있으면 그 방향으로 점프
	if target != null:
		var dx = target.global_position.x - global_position.x
		dir = 1 if dx >= 0 else -1
	
	# 점프 예비 동작 및 점프
	apply_squash(0.7, 1.3) # 점프 준비 효과
	velocity.y = jump_impulse
	velocity.x = dir * jump_horizontal_force
	
	if sprite:
		if sprite.sprite_frames.has_animation("jump"):
			sprite.play("jump")
		else:
			sprite.play("idle")
