# res://scripts/components/ShooterComponent.gd
extends Node2D
class_name ShooterComponent

# [설정] 발사체 및 패링 규칙
@export var projectile_scene: PackedScene
@export var parry_interval: int = 3          # 몇 발마다 패링 가능한가?
@export var parry_cue_color: Color = Color(1, 0.6, 1)

# [내부 변수]
var _shot_count: int = 0

# 외부(보스나 몹)에서 이 함수를 부르면 총알이 나갑니다.
# target_node: 누구를 향해 쏠 건지
# spawn_pos: 어디서 쏠 건지 (보스 손, 입 등)
func shoot(shooter_mob: Node2D, target_node: Node2D, spawn_pos: Vector2) -> void:
	if projectile_scene == null or target_node == null:
		return
		
	_shot_count += 1
	
	# 1. 총알 생성
	var p = projectile_scene.instantiate()
	p.shooter = shooter_mob # 쏜 사람 등록
	p.global_position = spawn_pos
	
	# 2. 방향 계산 (타겟의 가슴/중앙 조준)
	var target_center = target_node.global_position + Vector2(0, -10)
	var dir = (target_center - spawn_pos).normalized()
	
	p.direction = dir
	p.rotation = dir.angle()
	p.team = "enemy" # 보스도 적 팀
	
	# 3. [핵심] N번째 탄환 패링 설정 로직 (여기서 통합 관리!)
	var is_parry_shot = (_shot_count % parry_interval == 0)
	
	if p.has_method("set_parryable_mode"):
		if is_parry_shot:
			p.set_parryable_mode(true, parry_cue_color)
		else:
			p.set_parryable_mode(false)
			
	# 4. 씬에 추가
	get_tree().current_scene.add_child(p)
	
func reset_count() -> void:
	_shot_count = 0
