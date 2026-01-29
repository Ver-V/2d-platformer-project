extends EnemyBase
class_name Slime

@export var gravity: float = 980.0
@export var max_fall_speed: float = 200.0

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

var dir: int = -1
var _jump_left: float = 0.0
var _air_chase_left: float = 0.0

func _ready() -> void:
	max_hp_base = slime_max_hp
	contact_damage_base = slime_contact_damage
	move_speed_base = slime_move_speed
	knockback_resist = slime_knockback_res
	super._ready()
	
func _process(delta: float) -> void:
	super._process(delta)

	if _jump_left > 0.0:
		_jump_left -= delta
		if _jump_left < 0.0:
			_jump_left = 0.0

	if _air_chase_left > 0.0:
		_air_chase_left -= delta
		if _air_chase_left < 0.0:
			_air_chase_left = 0.0
			

func _physics_process(delta: float) -> void:
	if floor_ray != null:
		floor_ray.target_position = Vector2(floor_ray_x * float(dir), floor_ray_y)

	velocity.y += gravity * delta
	if velocity.y > max_fall_speed:
		velocity.y = max_fall_speed

	if is_on_floor():
		velocity.x = float(dir) * move_speed
	else:
		if _air_chase_left > 0.0 and target != null:
			var dx: float = target.global_position.x - global_position.x
			var sgn: float = 1.0 if dx >= 0.0 else -1.0
			velocity.x = sgn * jump_chase_speed
		else:
			velocity.x = float(dir) * move_speed

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
	
	if turn_on_wall and is_on_wall():
		dir = -dir
		velocity.x = 0.0
