extends Boss
class_name Boss_stage1

enum CombatState {TELEPORT, ATTACK}
var current_state1 = CombatState.TELEPORT

var teleport_markers: Array[Node] = []
var teleport_timer: float = 0.0
var is_attacking: bool = false
var rng = RandomNumberGenerator.new()

@onready var shooter: ShooterComponent = $ShooterComponent
@onready var action_sfx: AudioStreamPlayer2D = $ActionSFX

const SND_EXPLOSION = preload("res://Assets/sounds/explosion.wav")
const SND_POWER_UP = preload("res://Assets/sounds/power_up.wav")
const Fire_projectile = preload("res://Scenes/Projectile/projectilefire.tscn")

const TELEPORT_INTERVAL := 3.0
const PHASE2_SPEED := 1.5 # 페이즈 2에서 패턴(대기 시간)이 빨라지는 배율
const SPLIT_FIRST_ANGLES: Array[float] = [-15.0, 15.0] # 4번 패턴 첫 분열 (2갈래)
const SPLIT_SECOND_ANGLES: Array[float] = [-30.0, 0.0, 30.0] # 4번 패턴 두 번째 분열 (3갈래)

func _ready() -> void:
	super._ready()
	rng.randomize() # 보스 랜덤 시드 초기화
	call_deferred("_setup_teleports_points")

	if not shooter:
		shooter = get_node_or_null("ShooterComponent")
	if not shooter:
		shooter = find_child("ShooterComponent")

func _setup_teleports_points() -> void:
	var points_node = get_tree().get_first_node_in_group("teleport_points_stage1")
	if points_node:
		teleport_markers = points_node.get_children()
	else:
		pass

func _idle_state(_delta: float) -> void:
	# 타겟 재포착
	if target == null:
		var players = get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			target = players[0]
			
	current_state = State.COMBAT
	current_state1 = CombatState.TELEPORT

func _combat_state(delta:float) -> void:
	if target == null:
		var players = get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			target = players[0]

	match current_state1:
		CombatState.TELEPORT:
			_teleport_state(delta)
		CombatState.ATTACK:
			_attack_state(delta)

func _teleport_state(delta:float) -> void:
	if is_attacking: return # 텔레포트 연출 중 중복 실행 방지
	
	teleport_timer += delta
	if teleport_timer >= TELEPORT_INTERVAL / _speed():
		teleport_timer = 0.0
		_execute_teleport_sequence()

func _speed() -> float:
	return PHASE2_SPEED if phase >= 2 else 1.0

# 패턴 사이 대기 — 페이즈 2에서는 짧아진다
func _wait(t: float) -> void:
	await _wait(t / _speed())

# 대기 중에 보스가 쓰러지면(사망 연출 중) 남은 패턴을 이어가지 않는다
func _still_fighting() -> bool:
	return hp > 0 and current_state != State.DEAD

func _execute_teleport_sequence() -> void:
	is_attacking = true
	
	if action_sfx:
		action_sfx.stream = SND_POWER_UP
		action_sfx.play()

	if boss_sprite and boss_sprite.material:
		var tween = create_tween()
		tween.tween_property(boss_sprite.material, "shader_parameter/flash_modifier", 1.0, 0.15 / _speed())
		await _wait(0.2)
		if not _still_fighting(): return
		
	var candidate_markers: Array[Node] = []
	for marker in teleport_markers:
		if is_instance_valid(marker) and global_position.distance_to(marker.global_position) > 50.0 :
			candidate_markers.append(marker)
	
	if candidate_markers.size() > 0:
		var random_marker = candidate_markers.pick_random()
		global_position = random_marker.global_position
		velocity = Vector2.ZERO
	else:
		pass
	
	if boss_sprite and boss_sprite.material:
		var tween2 = create_tween()
		tween2.tween_property(boss_sprite.material, "shader_parameter/flash_modifier", 0.0, 0.15 / _speed())
		await _wait(0.2)
		if not _still_fighting(): return

	is_attacking = false
	current_state1 = CombatState.ATTACK
				
func _attack_state(_delta:float) -> void:
	if is_attacking:
		return
	
	is_attacking = true
	
	if action_sfx:
		action_sfx.stream = SND_EXPLOSION
		action_sfx.play()

	if boss_sprite:
		boss_sprite.play("attack")

	# 페이즈 1: 4개 중 하나. 페이즈 2: 1번 패턴 + (2·3·4번 중 하나)
	if phase >= 2:
		await _attack_pattern_1()
		if _still_fighting():
			await _run_pattern(rng.randi_range(1, 3))
	else:
		await _run_pattern(rng.randi_range(0, 3)) # 보스 전용 RNG 사용
	if not _still_fighting():
		return
	
	if boss_sprite and boss_sprite.animation == "attack":
		boss_sprite.play("idle")

	is_attacking = false
	current_state1 = CombatState.TELEPORT

func _run_pattern(index: int) -> void:
	match index:
		0:
			await _attack_pattern_1()
		1:
			await _attack_pattern_2()
		2:
			await _attack_pattern_3()
		3:
			await _attack_pattern_4()

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
					
		await _wait(0.5)
		if not _still_fighting(): return

func _attack_pattern_2() -> void:
	if not shooter: return
	shooter.projectile_scene = Fire_projectile
	if target != null:
		var p: Projectile = shooter.shoot(self, target, global_position) as Projectile
		if p != null:
			p.set_parryable_mode(false)
			p.scale = Vector2(2.0, 2.0)
			if "damage" in p:
				p.damage = 35
	await _wait(0.5)
	if not _still_fighting(): return
	
func _attack_pattern_3() -> void:
	if not shooter: return
	shooter.projectile_scene = Fire_projectile
	
	# 1. 기본 8방향으로 2번 발사 (간격 0.8초)
	for i in range(2):
		for angle_deg in range(0, 360, 45): # 0, 45, 90, 135, 180, 225, 270, 315도
			var dir = Vector2.RIGHT.rotated(deg_to_rad(angle_deg))
			shooter.shoot_dir(self, dir, global_position)
		
		await _wait(0.8)
		if not _still_fighting(): return

	# 2. 22.5도를 틀어서 8방향으로 2번 발사 (간격 0.8초)
	for i in range(2):
		for angle_deg in range(0, 360, 45):
			var dir = Vector2.RIGHT.rotated(deg_to_rad(angle_deg + 22.5))
			shooter.shoot_dir(self, dir, global_position)
		
		await _wait(0.8)
		if not _still_fighting(): return
	
# 조준탄 하나가 멈춘 자리에서 2갈래로, 다시 각각 3갈래로 갈라진다 (갈래마다 패링 탄 하나)
func _attack_pattern_4() -> void:
	if not shooter or target == null: return
	shooter.projectile_scene = Fire_projectile

	var p1 = shooter.shoot(self, target, global_position) as Projectile
	if p1:
		p1.set_parryable_mode(false)

	await _wait(0.5)
	if not _still_fighting(): return

	var first := _split_toward_target([p1], SPLIT_FIRST_ANGLES)

	await _wait(0.6)
	if not _still_fighting(): return

	_split_toward_target(first, SPLIT_SECOND_ANGLES)

# 살아 있는 탄마다 그 자리에서 사라지고, 플레이어를 향해 angles만큼 벌어진 탄들로 갈라진다.
# 갈라진 무리마다 하나는 패링 가능. 새로 만든 탄들을 돌려준다.
func _split_toward_target(sources: Array, angles: Array[float]) -> Array[Node]:
	var spawned: Array[Node] = []
	for src in sources:
		if not is_instance_valid(src):
			continue
		var pos: Vector2 = src.global_position
		src.queue_free()
		if not is_instance_valid(target):
			continue
		var aim := (target.global_position + Vector2(0, -10) - pos).normalized()
		var parry_idx := rng.randi_range(0, angles.size() - 1)
		for i in angles.size():
			var p = shooter.shoot_dir(self, aim.rotated(deg_to_rad(angles[i])), pos) as Projectile
			if p != null:
				p.set_parryable_mode(i == parry_idx, shooter.parry_cue_color)
				spawned.append(p)
	return spawned
