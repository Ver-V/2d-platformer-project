extends CharacterBody2D
class_name EnemyBase

signal died(enemy: EnemyBase)

@export var persist_id: StringName = &""

@export var max_hp_base: int = 10
@export var contact_damage_base: int = 1
@export var move_speed_base: float = 80.0

@export var invuln_time: float = 0.08
@export var knockback_resist: float = 0.0
@export var disable_when_inactive: bool = true

@onready var body_shape: CollisionShape2D = $CollisionShape2D as CollisionShape2D
@onready var hurtbox: Area2D = $Hurtbox as Area2D
@onready var hitbox: Area2D = $Hitbox as Area2D
@onready var invuln_timer: Timer = $InvulnTimer as Timer

var max_hp: int = 10
var hp: int = 10
var contact_damage: int = 1
var move_speed: float = 150.0

var home_position: Vector2 = Vector2.ZERO

var _invuln: bool = false
var _active: bool = true

func _ready()->void:
	home_position = global_position
	max_hp = max_hp_base
	contact_damage = contact_damage_base
	move_speed = move_speed_base
	hurtbox.area_entered.connect(_on_hurtbox_area_entered)
	hitbox.body_entered.connect(_on_hitbox_body_entered)
	
	invuln_timer.one_shot = true
	invuln_timer.timeout.connect(_on_invuln_timeout)
	
func get_persist_id() -> StringName:
	if persist_id != &"":
		return persist_id
	return StringName(str(get_path()))
	
func set_active(active:bool)->void:
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
	hp = clampi(hp,0,max_hp)

func reset_to_home(reset_hp: bool = true) -> void:
	global_position = home_position
	velocity = Vector2.ZERO
	_invuln = false
	invuln_timer.stop()
	if reset_hp:
		hp = max_hp

func take_damage(amount: int, knockback: Vector2 = Vector2.ZERO) -> void:
	if not _active:
		return
	if _invuln:
		return
	if amount <= 0:
		return

	var resist: float = clamp(knockback_resist, 0.0, 1.0)
	velocity += knockback * (1.0 - resist)

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

	take_damage(dmg, kb)

func _on_hitbox_body_entered(b: Node) -> void:
	if not _active:
		return
	if contact_damage <= 0:
		return
	if b.has_method("take_damage"):
		b.call("take_damage", contact_damage)
		
	
