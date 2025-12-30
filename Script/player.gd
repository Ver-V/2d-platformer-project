extends CharacterBody2D
class_name Player

@onready var sprite: AnimatedSprite2D = $PlayerAni

@export var movespeed: float = 120.0
@export var jumpforce: float = -350.0
@export var invincible_time: float = 0.5
@export var blink_interval: float = 0.1

@export var jump_cut_factor: float = 0.4
@export var fall_gravity_mult: float = 1.2
@export var max_fall_speed: float = 280.0

signal died

var hp: int = 100
var _invincible_left: float = 0.0
var left_down: bool = false
var right_down: bool = false
var last_dir: int = 0
var _blink_accum: float = 0.0

func _process(delta: float) -> void:
	if _invincible_left > 0.0:
		_invincible_left -= delta

		_blink_accum += delta
		if _blink_accum >= blink_interval:
			_blink_accum = 0.0
			sprite.visible = not sprite.visible

		if _invincible_left <= 0.0:
			_invincible_left = 0.0
			sprite.visible = true
			_blink_accum = 0.0

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

func apply_damage(amount: int) -> void:
	print("apply_damage called:", amount, "inv_left=", _invincible_left, "hp=", hp)
	if _invincible_left > 0.0:
		return

	hp -= amount

	# ⭐ 먼저 무적 세팅
	_invincible_left = invincible_time

	if hp <= 0:
		hp = 0
		emit_signal("died")
		return

func _physics_process(delta: float) -> void:
	var g := get_gravity()

	var dir: int = 0
	if left_down and right_down:
		dir = last_dir
	elif left_down:
		dir = -1
	elif right_down:
		dir = 1

	velocity.x = float(dir) * movespeed

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

	move_and_slide()
