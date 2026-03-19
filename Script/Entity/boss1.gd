extends Boss
class_name Boss_stage1

const STATE_TELEPORT = 4
const STATE_ATTACK = 5

var teleport_markers: Array[Node] = []
var teleport_timer: float = 0.0
var is_attacking: bool = false

@onready var shooter: ShooterComponent = $ShooterComponent

const Fire_projectile = preload("res://Scenes/Projectile/projectilefire.tscn")

func _ready() -> void:
	super._ready()
	call_deferred("_setup_teleports_points")
	current_state = STATE_TELEPORT
	
func _setup_teleports_points() -> void:
	var points_node = get_tree().get_first_node_in_group("teleport_points_stage1")
	if points_node:
		teleport_markers = points_node.get_children()
	
func _physics_process(delta:float) -> void:
	match current_state:
		STATE_TELEPORT:
			_teleport_state(delta)
		STATE_ATTACK:
			_attack_state(delta)
		_:
			super._physics_process(delta)
			
func _teleport_state(delta:float) -> void:
	teleport_timer += delta
	if teleport_timer >= 3.0:
		teleport_timer = 0.0
		var candidate_markers: Array[Node] = []
		for marker in teleport_markers:
			if global_position.distance_to(marker.global_position) > 10.0 :
				candidate_markers.append(marker)
		
		if candidate_markers.size() > 0:
			var random_marker = candidate_markers.pick_random()
			global_position = random_marker.global_position
		
		is_attacking = false
		current_state = STATE_ATTACK
				
	
func _attack_state(delta:float) -> void:
	if is_attacking:
		return
	
	is_attacking = true
	var pattern = randi() % 4
		
	match pattern:
		0:
			await _attack_pattern_1()
		1:
			await _attack_pattern_2()
		2:
			await _attack_pattern_3()
		3:
			await _attack_pattern_4()
	
	current_state = STATE_TELEPORT

func _attack_pattern_1() -> void:
	if not shooter: return
	shooter.projectile_scene = Fire_projectile
	var random_parry_index = randi() % 4
	for i in range(4):
		if target != null:
			var p: Projectile = shooter.shoot(self, target, global_position) as Projectile
			if p != null and p.has_method("set_parryable_mode"):
				if i == random_parry_index:
					p.set_parryable_mode(true, shooter.parry_cue_color)
				else:
					p.set_parryable_mode(false)
					
		await get_tree().create_timer(0.5).timeout

func _attack_pattern_2() -> void:
	if not shooter: return
	shooter.projectile_scene = Fire_projectile
	if target != null:
		var p: Projectile = shooter.shoot(self, target, global_position) as Projectile
		if p != null:
			p.set_parryable_mode(false)
			p.scale = Vector2(2.5, 2.5)
			if "damage" in p:
				p.damage = 35
	await get_tree().create_timer(0.5).timeout
	
func _attack_pattern_3() -> void:
	pass
	
func _attack_pattern_4() -> void:
	pass
	
	
