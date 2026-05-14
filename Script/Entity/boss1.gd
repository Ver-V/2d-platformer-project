extends Boss
class_name Boss_stage1

enum CombatState {TELEPORT, ATTACK}
var current_state1 = CombatState.TELEPORT

var teleport_markers: Array[Node] = []
var teleport_timer: float = 0.0
var is_attacking: bool = false
var rng = RandomNumberGenerator.new()

@onready var shooter: ShooterComponent = $ShooterComponent

const Fire_projectile = preload("res://Scenes/Projectile/projectilefire.tscn")
func _ready() -> void:
	super._ready()
	rng.randomize() # 보스 전용 랜덤 시드 초기화
	call_deferred("_setup_teleports_points")
	
	# ShooterComponent를 직접 찾거나 자식에서 검색
	if not shooter:
		shooter = get_node_or_null("ShooterComponent")
	if not shooter:
		shooter = find_child("ShooterComponent")

func _setup_teleports_points() -> void:
	var points_node = get_tree().get_first_node_in_group("teleport_points_stage1")
	if points_node:
		teleport_markers = points_node.get_children()
		print("[Boss Debug] 텔레포트 마커 로드 완료: ", teleport_markers.size(), "개")
	else:
		print("[Boss Debug] 오류: 'teleport_points_stage1' 그룹 노드를 찾을 수 없습니다!")

func _idle_state(_delta: float) -> void:
	# 타겟 재포착
	if target == null:
		var players = get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			target = players[0]
			
	current_state = State.COMBAT
	current_state1 = CombatState.TELEPORT

func _combat_state(delta:float) -> void:
	# 타겟 재포착 (텔레포트 후 대비)
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
	if teleport_timer >= 3.0:
		print("[Boss Debug] 3초 대기 완료 -> 텔레포트 실행")
		teleport_timer = 0.0
		_execute_teleport_sequence()

func _execute_teleport_sequence() -> void:
	is_attacking = true
	print("[Boss Debug] 텔레포트 시퀀스 시작 (마커 개수: ", teleport_markers.size(), ")")
	
	if boss_sprite and boss_sprite.material:
		var tween = create_tween()
		tween.tween_property(boss_sprite.material, "shader_parameter/flash_modifier", 1.0, 0.15)
		# await 대신 타이머를 사용하여 혹시 모를 멈춤 방지
		await get_tree().create_timer(0.2).timeout
		
	var candidate_markers: Array[Node] = []
	for marker in teleport_markers:
		if is_instance_valid(marker) and global_position.distance_to(marker.global_position) > 50.0 :
			candidate_markers.append(marker)
	
	if candidate_markers.size() > 0:
		var random_marker = candidate_markers.pick_random()
		print("[Boss Debug] 텔레포트 이동 대상: ", random_marker.name, " 위치: ", random_marker.global_position)
		global_position = random_marker.global_position
		velocity = Vector2.ZERO
	else:
		print("[Boss Debug] 경고: 텔레포트할 유효한 마커를 찾지 못했습니다!")
	
	if boss_sprite and boss_sprite.material:
		var tween2 = create_tween()
		tween2.tween_property(boss_sprite.material, "shader_parameter/flash_modifier", 0.0, 0.15)
		await get_tree().create_timer(0.2).timeout
		
	print("[Boss Debug] 텔레포트 완료 -> 공격 상태로 전환")
	is_attacking = false
	current_state1 = CombatState.ATTACK
				
func _attack_state(_delta:float) -> void:
	if is_attacking:
		return
	
	is_attacking = true
	var pattern = rng.randi_range(0, 3) # 보스 전용 RNG 사용
	print("[Boss Debug] 공격 패턴 실행: ", pattern)
		
	if boss_sprite:
		boss_sprite.play("attack")
		
	match pattern:
		0:
			await _attack_pattern_1()
		1:
			await _attack_pattern_2()
		2:
			await _attack_pattern_3()
		3:
			await _attack_pattern_4()
	
	if boss_sprite and boss_sprite.animation == "attack":
		boss_sprite.play("idle")
		
	print("[Boss Debug] 공격 완료 -> 다시 텔레포트 대기")
	is_attacking = false
	current_state1 = CombatState.TELEPORT

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
	if not shooter: return
	shooter.projectile_scene = Fire_projectile
	
	# 1. 기본 8방향으로 2번 발사 (간격 0.8초)
	for i in range(2):
		for angle_deg in range(0, 360, 45): # 0, 45, 90, 135, 180, 225, 270, 315도
			var dir = Vector2.RIGHT.rotated(deg_to_rad(angle_deg))
			shooter.shoot_dir(self, dir, global_position)
		
		await get_tree().create_timer(0.8).timeout

	# 2. 22.5도를 틀어서 8방향으로 2번 발사 (간격 0.8초)
	for i in range(2):
		for angle_deg in range(0, 360, 45):
			var dir = Vector2.RIGHT.rotated(deg_to_rad(angle_deg + 22.5))
			shooter.shoot_dir(self, dir, global_position)
		
		await get_tree().create_timer(0.8).timeout
	
func _attack_pattern_4() -> void:
	if not shooter or target == null: return
	shooter.projectile_scene = Fire_projectile
	
	var p1 = shooter.shoot(self, target, global_position) as Projectile
	if p1:
		p1.set_parryable_mode(false)
	
	await get_tree().create_timer(0.5).timeout
	
	var p2_list: Array[Node] = []
	if is_instance_valid(p1) :
		var pos1 = p1.global_position
		p1.queue_free()
		
		if is_instance_valid(target):
			var target_pos1 = target.global_position + Vector2(0,-10)
			var dir1 = (target_pos1 - pos1).normalized()
			
			var parry_idx1 = rng.randi_range(0, 2)
			var idx1 = 0
			for angle_deg in [-30, 0, 30]:
				var dir = dir1.rotated(deg_to_rad(angle_deg))
				var p = shooter.shoot_dir(self, dir, pos1) as Projectile
				if p != null:
					p.set_parryable_mode(idx1 == parry_idx1, shooter.parry_cue_color)
					p2_list.append(p)
				idx1 += 1
	
	await get_tree().create_timer(0.6).timeout
	
	for p2 in p2_list:
		if is_instance_valid(p2):
			var pos2 = p2.global_position
			p2.queue_free()
			if is_instance_valid(target):
				var target_pos2 = target.global_position + Vector2(0,-10)
				var dir2 = (target_pos2 - pos2).normalized()
				
				var parry_idx2 = rng.randi_range(0, 2)
				var idx2 = 0
				for angle_deg in [-30, 0, 30]:
					var dir = dir2.rotated(deg_to_rad(angle_deg))
					var p = shooter.shoot_dir(self, dir, pos2) as Projectile
					if p != null:
						p.set_parryable_mode(idx2 == parry_idx2, shooter.parry_cue_color)
					idx2 += 1
					
			
	
	
	
