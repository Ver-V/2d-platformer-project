# res://scripts/components/ShooterComponent.gd
extends Node2D
class_name ShooterComponent

# [설정] 발사체 및 패링 규칙
@export var projectile_scene: PackedScene
@export var projectile_damage: int = 10      # 투사체 기본 데미지 추가
@export var parry_interval: int = 3          # 몇 발마다 패링 가능한가?
@export var parry_cue_color: Color = Color(1, 0.6, 1)

# [추가] 자동 발사 설정
@export_group("Auto Shoot Settings")
@export var auto_shoot: bool = false      # 켜면 스스로 쏨
@export var fire_rate: float = 2.0        # 발사 간격 (초)
@export var attack_range: float = 250.0   # 사거리

# [내부 변수]
var _shot_count: int = 0
var _timer: float = 0.0

func _ready() -> void:
	# 시작할 때 약간의 랜덤 딜레이를 주어 여러 몹이 동시에 쏘는 것 방지
	_timer = randf_range(0.0, fire_rate)

func _physics_process(delta: float) -> void:
	if not auto_shoot: return
	
	var parent = get_parent()
	# 부모 노드가 타겟을 가지고 있는지 확인
	if not parent or not ("target" in parent) or parent.target == null:
		return
	
	# 부모가 활성화 상태(EnemyBase)이고 살아있는지 확인
	if "_active" in parent and not parent._active: return
	if "hp" in parent and parent.hp <= 0: return

	_timer -= delta
	if _timer <= 0.0:
		var dist = global_position.distance_to(parent.target.global_position)
		if dist <= attack_range:
			# 스스로 쏨 (부모, 타겟, 현재 내 위치)
			shoot(parent, parent.target, global_position)
			_timer = fire_rate

# 외부에서 수동으로 부를 수도 있는 함수들 (기본 기능 유지)
func shoot(shooter_mob: Node2D, target_node: Node2D, spawn_pos: Vector2) -> Node2D:
	if projectile_scene == null or target_node == null:
		return null
		
	_shot_count += 1
	
	var p = projectile_scene.instantiate()
	p.shooter = shooter_mob
	p.global_position = spawn_pos
	
	# 데미지 설정
	if "damage" in p:
		p.damage = projectile_damage
	
	# 타겟 중앙 조준
	var target_center = target_node.global_position + Vector2(0, -8)
	var dir = (target_center - spawn_pos).normalized()
	
	p.direction = dir
	p.rotation = dir.angle()
	p.team = "enemy"
	
	if "start_homing" in p and p.start_homing:
		p._homing_target = target_node
	
	var is_parry_shot = (_shot_count % parry_interval == 0)
	if p.has_method("set_parryable_mode"):
		if is_parry_shot:
			p.set_parryable_mode(true, parry_cue_color)
		else:
			p.set_parryable_mode(false)
			
	var current_scene = get_tree().current_scene
	if current_scene:
		current_scene.call_deferred("add_child", p)
	else:
		p.queue_free()
	
	return p
	
func reset_count() -> void:
	_shot_count = 0

func shoot_dir(shooter_mob: Node2D, dir: Vector2, spawn_pos: Vector2) -> Node2D:
	if projectile_scene == null:
		return null
		
	_shot_count += 1
	var p = projectile_scene.instantiate()
	p.shooter = shooter_mob
	p.global_position = spawn_pos
	
	# 데미지 설정
	if "damage" in p:
		p.damage = projectile_damage
		
	p.direction = dir.normalized()
	p.rotation = p.direction.angle()
	p.team = "enemy" 
	
	if "start_homing" in p:
		p.start_homing = false 
	
	var is_parry_shot = (_shot_count % parry_interval == 0)
	if p.has_method("set_parryable_mode"):
		if is_parry_shot:
			p.set_parryable_mode(true, parry_cue_color)
		else:
			p.set_parryable_mode(false)
			
	var current_scene = get_tree().current_scene
	if current_scene:
		current_scene.call_deferred("add_child", p)
	else:
		p.queue_free()
	
	return p
