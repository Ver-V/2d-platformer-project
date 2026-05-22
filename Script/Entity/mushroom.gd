extends EnemyBase
class_name Mushroom

@export var gravity: float = 980.0
@export var max_fall_speed: float = 280.0

@export var mushroom_max_hp: int = 50
@export var mushroom_contact_damage: int = 15
@export var mushroom_move_speed: float = 50.0
@export var mushroom_knockback_res: float = 0.0

@export var turn_on_wall: bool = true
@export var turn_on_ledge: bool = true

@export var floor_ray_x: float = 14.0
@export var floor_ray_y: float = 24.0

@export var attack_distance: float = 20.0

var dir: int = -1
var is_attacking: bool = false

@onready var hitbox_shape = get_node_or_null("Hitbox/CollisionShape2D")
var default_hitbox_extents: Vector2 = Vector2.ZERO
var default_hitbox_radius: float = 0.0
var default_hitbox_pos: Vector2 = Vector2.ZERO

func _ready() -> void:
	max_hp_base = mushroom_max_hp
	contact_damage_base = mushroom_contact_damage
	move_speed_base = mushroom_move_speed
	knockback_resist = mushroom_knockback_res
	super._ready()
	
	if sprite:
		sprite.animation_finished.connect(_on_animation_finished)
	
	if is_instance_valid(hitbox_shape):
		hitbox_shape.shape = hitbox_shape.shape.duplicate()
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

	if target != null and is_on_floor():
		if is_attacking:
			var is_active_frame = false
			if sprite and sprite.animation.begins_with("attack"):
				if sprite.sprite_frames.get_frame_count(sprite.animation) > 5:
					is_active_frame = sprite.frame >= 3 and sprite.frame <= 6
				else:
					is_active_frame = sprite.frame >= 2
			_set_attack_hitbox(is_active_frame)
			return

		dir = 1 if target.global_position.x > global_position.x else -1
		var dx = abs(global_position.x - target.global_position.x)
		var dy = abs(global_position.y - target.global_position.y)
		
		if dx <= attack_distance and dy <= 32.0:
			is_attacking = true
			if sprite:
				if sprite.sprite_frames.has_animation("attack1"):
					sprite.play("attack1" if randf() > 0.5 else "attack2")
				elif sprite.sprite_frames.has_animation("attack"):
					sprite.play("attack")
		else:
			if sprite and sprite.animation != "died":
				if sprite.sprite_frames.has_animation("Run"):
					sprite.play("Run")
				else:
					sprite.play("idle")
			_set_attack_hitbox(false)
	else:
		if not is_attacking:
			_set_attack_hitbox(false)

func _set_attack_hitbox(active: bool) -> void:
	if not is_instance_valid(hitbox_shape):
		return

	if hitbox_shape.shape is RectangleShape2D:
		var shape = hitbox_shape.shape as RectangleShape2D
		if active:
			shape.extents = Vector2(default_hitbox_extents.x + 5.0, default_hitbox_extents.y)
			hitbox_shape.position.x = default_hitbox_pos.x + (dir * 5.0)
		else:
			shape.extents = default_hitbox_extents
			hitbox_shape.position.x = default_hitbox_pos.x
	elif hitbox_shape.shape is CircleShape2D:
		var shape = hitbox_shape.shape as CircleShape2D
		if active:
			shape.radius = default_hitbox_radius + 3.5
			hitbox_shape.position.x = default_hitbox_pos.x + (dir * 3.5)
		else:
			shape.radius = default_hitbox_radius
			hitbox_shape.position.x = default_hitbox_pos.x

func _physics_process(delta: float) -> void:
	if not _active or hp <= 0:
		return

	velocity.y += gravity * delta
	if velocity.y > max_fall_speed:
		velocity.y = max_fall_speed

	if is_on_floor():
		if is_attacking:
			velocity.x = 0
		else:
			velocity.x = float(dir) * move_speed
	else:
		velocity.x = float(dir) * move_speed

	if not is_attacking:
		if turn_on_ledge and is_on_floor() and floor_ray != null:
			floor_ray.target_position = Vector2(floor_ray_x * float(dir), floor_ray_y)
			floor_ray.force_raycast_update()
			if not floor_ray.is_colliding():
				dir = -dir

	super._physics_process(delta)
	
	if not is_attacking:
		if turn_on_wall and is_on_wall():
			dir = -dir
			velocity.x = 0.0
	
	if sprite:
		sprite.flip_h = dir < 0
