extends EnemyBase
class_name Slime

@export var gravity: float = 980.0
@export var max_fall_speed: float = 280.0

@export var slime_max_hp: int = 30
@export var slime_contact_damage: int = 10
@export var slime_move_speed: float = 60.0
@export var slime_knockback_res: float = 0.0

@export var turn_on_wall: bool = true
@export var turn_on_ledge: bool = true

@export var floor_ray_x: float = 14.0
@export var floor_ray_y: float = 24.0

@export var jump_impulse: float = -200.0
@export var jump_cooldown: float = 2.5
@export var jump_only_when_player_near: bool = true

@export var jump_chase_speed: float = 90.0
@export var jump_chase_time: float = 0.12

@export var attack_distance: float = 40.0

var dir: int = -1
var _jump_left: float = 0.0
var _air_chase_left: float = 0.0
var is_attacking: bool = false

@onready var hitbox_shape = get_node_or_null("Hitbox/CollisionShape2D")
var default_hitbox_extents: Vector2 = Vector2.ZERO
var default_hitbox_radius: float = 0.0
var default_hitbox_pos: Vector2 = Vector2.ZERO

func _ready() -> void:
	max_hp_base = slime_max_hp
	contact_damage_base = slime_contact_damage
	move_speed_base = slime_move_speed
	knockback_resist = slime_knockback_res
	super._ready()
	
	if sprite:
		sprite.animation_finished.connect(_on_animation_finished)
	
	if is_instance_valid(hitbox_shape):
		default_hitbox_pos = hitbox_shape.position
		if hitbox_shape.shape is RectangleShape2D:
			default_hitbox_extents = hitbox_shape.shape.extents
		elif hitbox_shape.shape is CircleShape2D:
			default_hitbox_radius = hitbox_shape.shape.radius

func _on_animation_finished() -> void:
	if sprite and sprite.animation.begins_with("attack"):
		is_attacking = false
		_set_attack_hitbox(false)
	
func _process(delta: float) -> void:
	super._process(delta)

	if hp <= 0:
		if sprite and sprite.animation != "died":
			sprite.play("died")
		_set_attack_hitbox(false)
		return

	if _jump_left > 0.0:
		_jump_left -= delta
		if _jump_left < 0.0:
			_jump_left = 0.0

	if _air_chase_left > 0.0:
		_air_chase_left -= delta
		if _air_chase_left < 0.0:
			_air_chase_left = 0.0

	if target != null and is_on_floor():
		var dist = global_position.distance_to(target.global_position)
		if dist <= attack_distance:
			if not is_attacking:
				is_attacking = true
				if sprite:
					if sprite.sprite_frames.has_animation("attack1"):
						sprite.play("attack1" if randf() > 0.5 else "attack2")
					elif sprite.sprite_frames.has_animation("attack"):
						sprite.play("attack")
			
			# esnake처럼 특정 프레임에서만 공격 판정 확장
			var is_active_frame = false
			if sprite and sprite.animation.begins_with("attack"):
				if sprite.sprite_frames.get_frame_count(sprite.animation) > 5:
					# 버섯처럼 프레임이 많은 경우 (3~6번 프레임)
					is_active_frame = sprite.frame >= 3 and sprite.frame <= 6
				else:
					# 슬라임처럼 프레임이 적은 경우 (2~3번 프레임)
					is_active_frame = sprite.frame >= 2
			
			_set_attack_hitbox(is_active_frame)
		else:
			if is_attacking:
				is_attacking = false
				if sprite:
					sprite.play("idle")
				_set_attack_hitbox(false)
	else:
		if is_attacking:
			is_attacking = false
			if sprite:
				sprite.play("idle")
			_set_attack_hitbox(false)

func _set_attack_hitbox(active: bool) -> void:
	if not is_instance_valid(hitbox_shape):
		return

	if hitbox_shape.shape is RectangleShape2D:
		var shape = hitbox_shape.shape as RectangleShape2D
		if active:
			# 4픽셀만 추가 (esnake 참고)
			shape.extents = Vector2(default_hitbox_extents.x + 4.0, default_hitbox_extents.y)
			hitbox_shape.position.x = default_hitbox_pos.x + (dir * 4.0)
		else:
			shape.extents = default_hitbox_extents
			hitbox_shape.position.x = default_hitbox_pos.x
	elif hitbox_shape.shape is CircleShape2D:
		var shape = hitbox_shape.shape as CircleShape2D
		if active:
			# 원형도 3.5픽셀 정도만 추가
			shape.radius = default_hitbox_radius + 3.5
			hitbox_shape.position.x = default_hitbox_pos.x + (dir * 3.5)
		else:
			shape.radius = default_hitbox_radius
			hitbox_shape.position.x = default_hitbox_pos.x

func _physics_process(delta: float) -> void:
	if not _active or hp <= 0:
		return

	if floor_ray != null:
		floor_ray.target_position = Vector2(floor_ray_x * float(dir), floor_ray_y)

	velocity.y += gravity * delta
	if velocity.y > max_fall_speed:
		velocity.y = max_fall_speed

	if is_on_floor():
		if is_attacking:
			velocity.x = 0
		else:
			velocity.x = float(dir) * move_speed
	else:
		if _air_chase_left > 0.0 and target != null:
			var dx: float = target.global_position.x - global_position.x
			var sgn: float = 1.0 if dx >= 0.0 else -1.0
			velocity.x = sgn * jump_chase_speed
		else:
			velocity.x = float(dir) * move_speed

	if not is_attacking:
		if turn_on_ledge and is_on_floor() and floor_ray != null:
			floor_ray.force_raycast_update()
			if not floor_ray.is_colliding():
				dir = -dir

		if is_on_floor() and _jump_left <= 0.0:
			var can_jump: bool = (not jump_only_when_player_near) or (target != null)
			if can_jump:
				if turn_on_ledge and floor_ray != null:
					floor_ray.target_position = Vector2(floor_ray_x * float(dir), floor_ray_y)
					floor_ray.force_raycast_update()
					if not floor_ray.is_colliding():
						return	
				if target != null:
					var dx2: float = target.global_position.x - global_position.x
					dir = 1 if dx2 >= 0.0 else -1

				velocity.y = jump_impulse
				_air_chase_left = jump_chase_time
				_jump_left = jump_cooldown

	super._physics_process(delta)
	
	if not is_attacking:
		if turn_on_wall and is_on_wall():
			dir = -dir
			velocity.x = 0.0
	
	if sprite:
		sprite.flip_h = dir > 0
