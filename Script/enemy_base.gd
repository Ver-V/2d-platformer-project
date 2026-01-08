extends CombatBody2D
class_name EnemyBase

signal died(enemy: EnemyBase)

@export_group("Identity")
@export var persist_id: StringName = &""

@export_group("Stats")
@export var max_hp_base: int = 10
@export var contact_damage_base: int = 1
@export var move_speed_base: float = 80.0
@export var contact_knockback_x: float = 320.0
@export var contact_knockback_y: float = -240.0

@export_group("Combat")
@export var invuln_time: float = 0.7
@export var blink_interval: float = 0.05
@export var knockback_resist: float = 0.0
@export var knockback_cooldown: float = 0.7
@export var knockback_decay: float = 2600.0
@export var contact_tick: float = 1.0

@export_group("Behavior")
@export var disable_when_inactive: bool = true

@onready var hurtbox: Area2D = $Hurtbox
@onready var hitbox: Area2D = $Hitbox
@onready var body_shape: CollisionShape2D = $CollisionShape2D
@onready var detect_area: Area2D = $DetectArea
@onready var sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D")
@onready var floor_ray: RayCast2D = get_node_or_null("FloorRay")

var contact_damage: int = 0
var move_speed: float = 0.0
var _touching: Dictionary = {}
var home_position: Vector2 = Vector2.ZERO
var _active: bool = true
var target: Node2D = null

func _ready() -> void:
	add_to_group("enemies")
	home_position = global_position
	max_hp = max_hp_base
	hp = max_hp
	contact_damage = contact_damage_base
	move_speed = move_speed_base

	hurtbox.area_entered.connect(_on_hurtbox_area_entered)
	hitbox.body_entered.connect(_on_hitbox_body_entered)
	hitbox.body_exited.connect(_on_hitbox_body_exited)

	if detect_area:
		detect_area.body_entered.connect(_on_detect_entered)
		detect_area.body_exited.connect(_on_detect_exited)

	set_active(false)
	if sprite: sprite.play()

# --- Overrides ---
func get_invuln_time() -> float: return invuln_time
func get_blink_interval() -> float: return blink_interval
func get_knockback_decay() -> float: return knockback_decay
func get_knockback_resist() -> float: return knockback_resist
func get_knockback_cooldown() -> float: return knockback_cooldown
func get_blink_node() -> CanvasItem: return sprite

func _on_death() -> void:
	died.emit(self)
	queue_free()

func apply_damage(amount: int, knockback: Vector2 = Vector2.ZERO, ignore_cd: bool = false, or_invuln_time: float = -1.0) -> bool:
	if not _active: return false
	return super.apply_damage(amount, knockback, ignore_cd, or_invuln_time)

# --- Logic ---
func _process(delta: float) -> void:
	super._process(delta) # 깜빡임, 넉백 쿨타임 처리
	if not _active: return

	# 지속 접촉 데미지 처리
	if contact_damage > 0 and contact_tick > 0.0:
		var removed_keys := []
		for b in _touching.keys():
			# 객체가 유효한지 확인 (중요!)
			if not is_instance_valid(b):
				removed_keys.append(b)
				continue
			
			var t: float = float(_touching[b])
			t += delta
			if t >= contact_tick:
				t = 0.0 # 틱 리셋
				_apply_contact_damage_once(b)
			_touching[b] = t
		
		# 유효하지 않은 키 정리
		for k in removed_keys:
			_touching.erase(k)

func _physics_process(delta: float) -> void:
	if not _active: return
	
	# 넉백 적용
	var kb: Vector2 = update_knockback(delta)
	velocity += kb
	move_and_slide()
	velocity -= kb

# --- Collision Callbacks ---
func _on_hurtbox_area_entered(a: Area2D) -> void:
	if not _active or is_invulnerable(): return
	
	# 데미지/넉백 정보 추출 (메타데이터 or 메서드)
	var dmg: int = 0
	if a.has_method("get_damage"): dmg = int(a.call("get_damage"))
	elif a.has_meta("damage"): dmg = int(a.get_meta("damage"))
	
	if dmg <= 0: return

	var kb: Vector2 = Vector2.ZERO
	if a.has_method("get_knockback"): kb = a.call("get_knockback")
	elif a.has_meta("knockback"): kb = a.get_meta("knockback")

	apply_damage(dmg, kb)

func _on_hitbox_body_entered(b: Node) -> void:
	if not _active or contact_damage <= 0 or b == null: return
	_touching[b] = 0.0 # 닿자마자
	_apply_contact_damage_once(b)

func _on_hitbox_body_exited(b: Node) -> void:
	if _touching.has(b): _touching.erase(b)

func _apply_contact_damage_once(b: Node) -> void:
	if not is_instance_valid(b): return
	
	var did_dmg: bool = false
	
	# CombatBody2D 타입을 우선 체크 (가장 깔끔)
	if b is CombatBody2D:
		var dx: float = b.global_position.x - global_position.x
		var k_dir := Vector2(1.0 if dx >= 0.0 else -1.0, 0.0)
		var k_vec := Vector2(k_dir.x * contact_knockback_x, contact_knockback_y)
		did_dmg = b.apply_damage(contact_damage, k_vec)
	
	# 그 외 (has_method로 fallback)
	elif b.has_method("apply_damage"):
		b.call("apply_damage", contact_damage)
		did_dmg = true
	
	# 데미지를 입혔는데 넉백 메서드가 따로 있는 경우 (CombatBody2D가 아닌 경우)
	if did_dmg and not (b is CombatBody2D) and b.has_method("apply_knockback") and b is Node2D:
		var dx: float = b.global_position.x - global_position.x
		var k_dir := Vector2(1.0 if dx >= 0.0 else -1.0, 0.0)
		b.call("apply_knockback", k_dir, contact_knockback_x, contact_knockback_y)

func _on_detect_entered(body: Node) -> void:
	if body.is_in_group("player") and body is Node2D:
		target = body

func _on_detect_exited(body: Node) -> void:
	if body == target:
		target = null

# ... (나머지 active 설정, ID 로직 등은 기존 유지) ...
func get_persist_id() -> StringName:
	return persist_id if persist_id != &"" else StringName(str(get_path()))

func set_active(active: bool) -> void:
	_active = active
	if disable_when_inactive:
		set_physics_process(active)
		set_process(active)
		hurtbox.set_deferred("monitoring", active)
		hitbox.set_deferred("monitoring", active)
		body_shape.set_deferred("disabled", not active)

func reset_to_home(reset_hp: bool = true) -> void:
	global_position = home_position
	velocity = Vector2.ZERO
	reset_combat_state()
	if reset_hp: hp = max_hp
