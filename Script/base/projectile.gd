extends Area2D
class_name Projectile

@export_group("Stats")
@export var speed: float = 300.0
@export var damage: int = 1
@export var life_time: float = 10.0
var shooter: Node2D = null # [추가] 나를 쏜 놈을 기억하는 변수
var _reflected: bool = false
@export_group("Parry")
@export var is_parryable: bool = false         # 이 옵션을 켜면 패링 가능
@export var practice_parry_defeats_shooter: bool = false
var _practice_parried: bool = false
@export var parried_color: Color = Color(0.464, 0.727, 0.67, 1.0) # 반사시 색상 변경

@onready var anim_sprite: AnimatedSprite2D = $AnimatedSprite2D

@export_group("Homing Settings")
@export var start_homing: bool = false     # 적이 쏠 때부터 유도탄인가?
@export var enemy_homing_speed: float = 2.0 # 적 유도탄의 회전 속도 (너무 빠르면 피하기 힘듦)
var _is_homing: bool = false   # 현재 유도 모드인가?
var _homing_target: Node2D = null # 누구를 쫓을 것인가?
@export var homing_turn_speed: float = 5.0 # 유도 회전 속도 (클수록 급커브 가능)

var direction: Vector2 = Vector2.RIGHT
var velocity: Vector2 = Vector2.ZERO
var _current_life: float = 0.0

# 투사체의 소유자 (초기엔 'enemy'라고 가정)
# "enemy"면 플레이어를 때리고, "player"면 적을 때림
var team: String = "enemy" 

func _ready() -> void:
	add_to_group("projectiles")
	# 수명이 다하면 사라지도록 타이머 연결 혹은 직접 계산
	_current_life = life_time
	
	# 초기 속도 설정
	velocity = direction.normalized() * speed
	
	if anim_sprite:
		anim_sprite.play("default")
	
	# 벽이나 바닥에 닿으면 사라짐 (Body Entered)
	body_entered.connect(_on_body_entered)
	
	var notifier = get_node_or_null("VisibleOnScreenNotifier2D")
	if notifier:
		notifier.screen_exited.connect(_on_screen_exited)
	
	if start_homing and team == "enemy":
		_is_homing = true
		homing_turn_speed = enemy_homing_speed # 적 전용 회전 속도 적용
		# 유도탄 타겟 할당은 ShooterComponent에서 직접 처리하도록 최적화됨
	
	# Area(플레이어 히트박스 등)와의 충돌은 Player나 Enemy쪽에서 처리하거나
	# 여기서 area_entered로 처리할 수도 있지만, 보통 투사체는 '몸'에 닿는 걸 체크함.

func _physics_process(delta: float) -> void:
	var movement := velocity * delta
	if _is_homing:
		if _has_live_homing_target():
			# 상대방의 가슴/명치를 조준한다.
			var target_pos = _homing_target.global_position + Vector2(0, -10)
			var to_target: Vector2 = target_pos - global_position
			var desired_dir := to_target.normalized()
			if _reflected:
				# 패링탄은 직접 추적한다. 느린 선회로 목표 주변을 도는 현상을 방지한다.
				if not to_target.is_zero_approx():
					direction = desired_dir
			else:
				direction = direction.slerp(desired_dir, clampf(homing_turn_speed * delta, 0.0, 1.0)).normalized()
			velocity = direction * speed
			movement = velocity * delta
			if _reflected:
				# 빠른 탄환도 목표를 지나치지 않고 도착 지점에서 명중 처리한다.
				movement = direction * minf(speed * delta, to_target.length())
		else:
			# 타겟이 죽거나 사라지면 유도를 중단하고 현재 방향으로 직진한다.
			_is_homing = false
	
	# 이동
	global_position += movement
	
	# 회전 (선택사항: 진행 방향을 바라보게)
	if velocity != Vector2.ZERO:
		rotation = velocity.angle()

	if _reflected and _is_homing and _has_live_homing_target():
		var target_pos := _homing_target.global_position + Vector2(0, -10)
		if global_position.distance_squared_to(target_pos) <= 0.0001:
			_on_body_entered(_homing_target)

	# 수명 체크
	_current_life -= delta
	if _current_life <= 0.0:
		queue_free()

func _has_live_homing_target() -> bool:
	if not is_instance_valid(_homing_target) or _homing_target.is_queued_for_deletion():
		return false
	return not (_homing_target is CombatBody2D and _homing_target.hp <= 0)

func _on_screen_exited() -> void:
	if is_queued_for_deletion():
		return
	if _reflected and is_instance_valid(shooter):
		# 패링된 투사체가 화면 밖으로 나갈 때, 쏜 적이 살아있다면 즉시 데미지 적용
		if shooter is CombatBody2D:
			shooter.apply_damage(_get_impact_damage(shooter), Vector2.ZERO, false, -1.0, true)
		elif shooter.has_method("apply_damage"):
			shooter.call("apply_damage", damage, Vector2.ZERO)
		elif shooter.has_method("take_damage"):
			shooter.call("take_damage", damage, global_position)
	queue_free()

func _on_body_entered(body: Node) -> void:
	if is_queued_for_deletion():
		return
	if body is CombatBody2D:
		# 같은 팀이면 통과 (예: 적이 쏜 게 적을 맞추지 않음)
		if _is_same_team(body):
			return
			
		# 데미지 적용
		var knock_dir = velocity.normalized()
		# 넉백값은 투사체 설정에 따라 조절 가능. 일단 하드코딩 혹은 export 변수 사용
		var applied = body.apply_damage(_get_impact_damage(body), knock_dir * 150.0, false, -1.0, true)
		
		if applied:
			_destroy_projectile()
	

func _get_impact_damage(body: CombatBody2D) -> int:
	# 연습용 무해 탄환만, 반사 후 발사자에게 명중했을 때 처치한다.
	# apply_damage를 통해 기존 사망 연출·드롭·기록 처리를 유지한다.
	if _practice_parried and is_instance_valid(shooter) and body == shooter:
		return maxi(body.hp, 0)
	return damage

func _is_same_team(body: Node) -> bool:
	if team == "enemy" and body.is_in_group("enemies"):
		return true
	if team == "player" and body.is_in_group("player"):
		return true
	return false

func _destroy_projectile() -> void:
	# 여기서 폭발 이펙트 등을 인스턴스화 할 수 있음
	queue_free()

func set_parryable_mode(active: bool, cue_color: Color = Color.YELLOW) -> void:
	is_parryable = active
	
	if active:
		modulate = cue_color
		# scale = Vector2(1.2, 1.2) # 필요하면 크기 키우기
	else:
		modulate = Color.WHITE

func attempt_parry(source_pos: Vector2, extra_damage: int = 0, damage_multiplier: float = 1.5) -> bool:
	if not is_parryable or team != "enemy" or is_queued_for_deletion():
		return false
	
	_reflected = true
	_practice_parried = practice_parry_defeats_shooter and damage == 0
	
	team = "player"
	
	# 발사자가 없을 때는 플레이어 앞쪽으로 반사하고, 있으면 즉시 발사자를 조준한다.
	_is_homing = false
	_homing_target = shooter
	direction = (global_position - source_pos).normalized()
	if direction.is_zero_approx():
		direction = -velocity.normalized() if not velocity.is_zero_approx() else Vector2.RIGHT
	if _has_live_homing_target():
		_is_homing = true
		var to_shooter := shooter.global_position + Vector2(0, -10) - global_position
		if not to_shooter.is_zero_approx():
			direction = to_shooter.normalized()
	damage = ceili(damage * damage_multiplier) + extra_damage
	speed *= 2.0
	velocity = direction * speed
	rotation = velocity.angle()
	
	# [추가] 패링된 탄환은 5초 내로 못 맞추면 소멸
	_current_life = 5.0

	modulate = Color.CYAN

	# [핵심] 신분 세탁 (Layer & Mask 실시간 변경)
	call_deferred("set_collision_layer_value", 7, false) 
	call_deferred("set_collision_layer_value", 6, true) 
	call_deferred("set_collision_mask_value", 2, false)
	call_deferred("set_collision_mask_value", 1, false)
	call_deferred("set_collision_mask_value", 3, true)
	call_deferred("set_collision_mask_value", 4, true)
	
	return true
