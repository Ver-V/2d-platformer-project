extends CharacterBody2D
class_name Player

@onready var sprite: AnimatedSprite2D = $PlayerAni

@export var movespeed: float = 120.0
@export var jumpforce: float = -350.0
@export var invuln_time: float = 0.7
@export var blink_interval: float = 0.05
@export var knockback_decay: float = 1800.0
@export var default_knockback: float = 200.0
@export var jump_cut_factor: float = 0.4
@export var fall_gravity_mult: float = 1.2
@export var max_fall_speed: float = 280.0

signal died

var hp: int = 100
var _invuln_left: float = 0.0
var left_down: bool = false
var right_down: bool = false
var last_dir: int = 0
var _blink_accum: float = 0.0

var knockback_vel: Vector2 = Vector2.ZERO
var _knockback_left: float = 0.0

func _ready() -> void:
	add_to_group("player")
	if sprite != null:
		sprite.play()
	
func _process(delta: float) -> void:
	if _invuln_left > 0.0:
		_invuln_left -= delta
	
		_blink_accum += delta
		if _blink_accum >= blink_interval:
			_blink_accum = 0.0
			sprite.visible = not sprite.visible

		if _invuln_left <= 0.0:
			_invuln_left	 = 0.0
			sprite.visible = true
			_blink_accum = 0.0
			
	if _knockback_left > 0.0:
		_knockback_left -= delta
		if _knockback_left < 0.0:
			_knockback_left = 0.0
			
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("left"):
		left_down = true
		last_dir = -1
	elif event.is_action_released("left"):
		left_down = false
		if last_dir == -1:
			last_dir = 1 if right_down else 0

	if event.is_action_pressed("right"):
		right_down = true
		last_dir = 1
	elif event.is_action_released("right"):
		right_down = false
		if last_dir == 1:
			last_dir = -1 if left_down else 0

func reset_motion() -> void:
	velocity = Vector2.ZERO
	knockback_vel = Vector2.ZERO
	_invuln_left = 0.0
	_knockback_left = 0.0
	_blink_accum = 0.0
	sprite.visible = true
	
func apply_knockback(knock_dir: Vector2, kb_x: float, kb_y: float = 0.0, ignore_cooldown: bool = false, cooldown: float = -1.0, reset_y: bool = true) -> void:
	if not ignore_cooldown and _knockback_left > 0.0:
		return
	if knock_dir == Vector2.ZERO:
		return

	if cooldown < 0.0:
		_knockback_left = invuln_time
	else:
		_knockback_left = cooldown
		
	if reset_y:
		velocity.y = 0.0
		
	var d: Vector2 = knock_dir.normalized()
	knockback_vel.x = d.x * kb_x
	knockback_vel.y = kb_y


func apply_damage(amount: int) -> void:
	if _invuln_left > 0.0:
		return

	hp -= amount

	# ⭐ 먼저 무적 세팅
	_invuln_left = invuln_time
	
	if hp <= 0:
		hp = 0
		reset_motion()
		emit_signal("died")
		return

func _physics_process(delta: float) -> void:
	var g := get_gravity()
	
	knockback_vel = knockback_vel.move_toward(Vector2.ZERO, knockback_decay * delta)
	
	var dir: int = 0
	if left_down and right_down:
		dir = last_dir
	elif left_down:
		dir = -1
	elif right_down:
		dir = 1

	knockback_vel = knockback_vel.move_toward(Vector2.ZERO, knockback_decay * delta)
	velocity.x = float(dir) * movespeed + knockback_vel.x

	
	if is_on_floor() and Input.is_action_just_pressed("jump"):
		velocity.y = jumpforce

	if not is_on_floor():
		var mult := 1.0
		if velocity.y > 0.0:
			mult = fall_gravity_mult
		velocity += g * mult * delta

		if Input.is_action_just_released("jump") and velocity.y < 0.0:
			velocity.y *= jump_cut_factor

		if velocity.y > max_fall_speed:
			velocity.y = max_fall_speed
	
	velocity.y += knockback_vel.y
	move_and_slide()
