extends CharacterBody2D
class_name EnemyBase

signal died(enemy: EnemyBase)

@export var persist_id: StringName = &""
@export var contact_tick: float = 0.75
@export var max_hp_base: int = 10
@export var contact_damage_base: int = 1
@export var move_speed_base: float = 80.0

@export var invuln_time: float = 0.08
@export var blink_interval: float = 0.05

@export var knockback_resist: float = 0.0
@export var knockback_cooldown: float = 0.12
@export var knockback_decay: float = 2200.0

@export var disable_when_inactive: bool = true

@onready var body_shape: CollisionShape2D = $CollisionShape2D as CollisionShape2D
@onready var hurtbox: Area2D = $Hurtbox as Area2D
@onready var hitbox: Area2D = $Hitbox as Area2D
@onready var invuln_timer: Timer = $InvulnTimer as Timer
@onready var floor_ray: RayCast2D = $FloorRay as RayCast2D
@onready var detect_area: Area2D = $DetectArea as Area2D
@onready var sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D

var max_hp: int = 10
var hp: int = 10
var contact_damage: int = 10
var move_speed: float = 150.0
var _touching: Dictionary = {}
var home_position: Vector2 = Vector2.ZERO

var _invuln: bool = false
var _active: bool = true
var target: Node2D = null
var knockback_vel: Vector2 = Vector2.ZERO
var _kb_left: float = 0.0
var _blink_accum: float = 0.0

func _ready() -> void:
	add_to_group("enemies")
	home_position = global_position
	max_hp = max_hp_base
	contact_damage = contact_damage_base
	move_speed = move_speed_base

	hurtbox.area_entered.connect(_on_hurtbox_area_entered)
	hitbox.body_entered.connect(_on_hitbox_body_entered)
	hitbox.body_exited.connect(_on_hitbox_body_exited)
	
	invuln_timer.one_shot = true
	invuln_timer.timeout.connect(_on_invuln_timeout)
	
	if detect_area != null:
		detect_area.body_entered.connect(_on_detect_entered)
		detect_area.body_exited.connect(_on_detect_exited)
		
	add_to_group("enemies")
	set_active(false)
	
	if sprite != null:
		sprite.play()

func _process(delta: float) -> void:
	if _kb_left > 0.0:
		_kb_left -= delta
		if _kb_left < 0.0:
			_kb_left = 0.0

	if _invuln and sprite != null:
		_blink_accum += delta
		if _blink_accum >= blink_interval:
			_blink_accum = 0.0
			sprite.visible = not sprite.visible
	

	if not _active:
		return
	if contact_damage <= 0:
		return
	if contact_tick <= 0.0:
		return

	for b in _touching.keys():
		if b == null:
			continue
		var t: float = float(_touching[b])
		t += delta
		if t >= contact_tick:
			t -= contact_tick
			_apply_contact_damage_once(b)
		_touching[b] = t
		
func _physics_process(delta: float) -> void:
	knockback_vel = knockback_vel.move_toward(Vector2.ZERO, knockback_decay * delta)

	var kb: Vector2 = knockback_vel
	velocity += kb
	move_and_slide()
	velocity -= kb
	
func _on_detect_entered(body: Node) -> void:
	if body != null and body.is_in_group("player") and body is Node2D:
		target = body as Node2D
	
func _on_detect_exited(body: Node) -> void:
	if body == target:
		target = null
		
func get_persist_id() -> StringName:
	if persist_id != &"":
		return persist_id
	return StringName(str(get_path()))

func set_active(active: bool) -> void:
	_active = active
	if disable_when_inactive:
		set_physics_process(active)
		set_process(active)
		hurtbox.monitoring = active
		hitbox.monitoring = active
		body_shape.disabled = not active

func apply_difficulty(hp_mult: float, dmg_mult: float, speed_mult: float) -> void:
	max_hp = max(1, int(round(float(max_hp_base) * hp_mult)))
	contact_damage = max(0, int(round(float(contact_damage_base) * dmg_mult)))
	move_speed = float(move_speed_base) * speed_mult
	hp = clampi(hp, 0, max_hp)

func reset_to_home(reset_hp: bool = true) -> void:
	global_position = home_position
	velocity = Vector2.ZERO
	knockback_vel = Vector2.ZERO
	_kb_left = 0.0

	_invuln = false
	invuln_timer.stop()

	_blink_accum = 0.0
	if sprite != null:
		sprite.visible = true

	if reset_hp:
		hp = max_hp

func apply_knockback(kb: Vector2, ignore_cooldown: bool = false) -> void:
	if not _active:
		return
	if not ignore_cooldown and _kb_left > 0.0:
		return
	if kb == Vector2.ZERO:
		return

	_kb_left = knockback_cooldown

	var resist: float = clamp(knockback_resist, 0.0, 1.0)
	knockback_vel += kb * (1.0 - resist)

func take_damage(amount: int, knockback: Vector2 = Vector2.ZERO, ignore_knockback_cooldown: bool = false) -> void:
	if not _active:
		return
	if _invuln:
		return
	if amount <= 0:
		return

	if knockback != Vector2.ZERO:
		apply_knockback(knockback, ignore_knockback_cooldown)

	hp -= amount
	if hp <= 0:
		die()
		return

	if invuln_time > 0.0:
		_invuln = true
		invuln_timer.start(invuln_time)

func die() -> void:
	died.emit(self)
	queue_free()

func _on_invuln_timeout() -> void:
	_invuln = false
	_blink_accum = 0.0
	if sprite != null:
		sprite.visible = true

func _on_hurtbox_area_entered(a: Area2D) -> void:
	if not _active:
		return
	if _invuln:
		return

	var dmg: int = 0
	if a.has_method("get_damage"):
		dmg = int(a.call("get_damage"))
	elif a.has_meta("damage"):
		dmg = int(a.get_meta("damage"))

	if dmg <= 0:
		return

	var kb: Vector2 = Vector2.ZERO
	if a.has_method("get_knockback"):
		var v: Variant = a.call("get_knockback")
		if v is Vector2:
			kb = v as Vector2
	elif a.has_meta("knockback"):
		var mv: Variant = a.get_meta("knockback")
		if mv is Vector2:
			kb = mv as Vector2

	take_damage(dmg, kb)

func _on_hitbox_body_entered(b: Node) -> void:
	if not _active:
		return
	if contact_damage <= 0:
		return
	if b == null:
		return

	_touching[b] = 0.0
	_apply_contact_damage_once(b)

func _on_hitbox_body_exited(b: Node) -> void:
	if b == null:
		return
	if _touching.has(b):
		_touching.erase(b)

func _apply_contact_damage_once(b: Node) -> void:
	if b.has_method("apply_damage"):
		b.call("apply_damage", contact_damage)
	elif b.has_method("take_damage"):
		b.call("take_damage", contact_damage)
