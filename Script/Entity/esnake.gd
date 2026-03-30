extends EnemyBase
class_name Esnake

@export var gravity: float = 980.0
@export var max_fall_speed: float = 280.0

@export var snake_max_hp: int = 45
@export var snake_contact_damage: int = 15
@export var snake_move_speed: float = 40.0
@export var snake_knockback_res: float = 0.0

@export var turn_on_wall: bool = true
@export var turn_on_ledge: bool = true
@export var floor_ray_x: float = 14.0
@export var floor_ray_y: float = 24.0

@export var attack_distance: float = 35.0

var dir: int = -1
var is_attacking: bool = false

@onready var hitbox_shape = get_node_or_null("Hitbox/CollisionShape2D")
var default_hitbox_extents: Vector2 = Vector2(4.5, 5.0)
var default_hitbox_pos: Vector2 = Vector2.ZERO

func _ready() -> void:
	max_hp_base = snake_max_hp
	contact_damage_base = snake_contact_damage
	move_speed_base = snake_move_speed
	knockback_resist = snake_knockback_res
	super._ready()
	
	if sprite:
		sprite.play("idle")
		# [추가] 애니메이션이 끝나면 공격 상태를 해제하는 시그널 연결
		if not sprite.animation_finished.is_connected(_on_animation_finished):
			sprite.animation_finished.connect(_on_animation_finished)
	
	if hitbox_shape:
		hitbox_shape.shape = hitbox_shape.shape.duplicate()
		default_hitbox_pos = hitbox_shape.position
		default_hitbox_extents = hitbox_shape.shape.extents

# [추가] 애니메이션 종료 시 상태 리셋
func _on_animation_finished() -> void:
	if sprite and sprite.animation == "attack":
		is_attacking = false
		_set_attack_hitbox(false)

func _process(delta: float) -> void:
	super._process(delta)

	if hp <= 0:
		if sprite and sprite.animation != "died":
			sprite.play("died")
		_set_attack_hitbox(false)
		return

	if target != null:
		# [수정] 이미 공격 중이라면 상태 유지 (판정 감시)
		if is_attacking:
			if sprite and sprite.animation == "attack":
				_set_attack_hitbox(sprite.frame == 3)
			return

		# 플레이어 방향 바라보기 (추격 준비)
		dir = 1 if target.global_position.x > global_position.x else -1
		var dx = abs(global_position.x - target.global_position.x)
		var dy = abs(global_position.y - target.global_position.y)

		# 사거리 안일 때만 멈춰서 공격!
		if dx <= attack_distance and dy <= 24.0:
			is_attacking = true
			if sprite:
				sprite.play("attack")
		else:
			# 사거리 밖: 추격 애니메이션 재생 (이때 velocity.x가 물리 프로세스에서 작동함)
			if sprite and sprite.animation != "idle" and sprite.animation != "died":
				if sprite.sprite_frames.has_animation("Run"): # 혹은 Walk
					sprite.play("Run")
				else:
					sprite.play("idle")
			_set_attack_hitbox(false)
	else:
		if not is_attacking:
			if sprite and sprite.animation != "idle" and sprite.animation != "died":
				sprite.play("idle")
			_set_attack_hitbox(false)

func _set_attack_hitbox(active: bool) -> void:
	if not hitbox_shape or not hitbox_shape.shape is RectangleShape2D:
		return

	var shape = hitbox_shape.shape as RectangleShape2D
	if active:
		# 공격 시 히트박스의 가로 길이를 늘림 (원하는 수치로 조정 가능)
		shape.extents = Vector2(default_hitbox_extents.x + 4.0, default_hitbox_extents.y)
		# 바라보는 방향(dir)으로 늘어난 만큼 중심점을 이동 (dir: 1 오른쪽, -1 왼쪽)
		hitbox_shape.position.x = default_hitbox_pos.x + (dir * 4.0) 
	else:
		shape.extents = default_hitbox_extents
		hitbox_shape.position.x = default_hitbox_pos.x

func _physics_process(delta: float) -> void:
	if not _active or hp <= 0:
		return
		
	velocity.y += gravity * delta
	if velocity.y > max_fall_speed:
		velocity.y = max_fall_speed
		
	if floor_ray != null:
		floor_ray.target_position = Vector2(floor_ray_x * float(dir), floor_ray_y)
		
	if is_on_floor() and not is_attacking:
		velocity.x = float(dir) * move_speed
	else:
		if is_on_floor():
			velocity.x = 0
			
	if turn_on_ledge and is_on_floor() and floor_ray != null:
		floor_ray.force_raycast_update()
		if not floor_ray.is_colliding():
			dir = -dir

	super._physics_process(delta)
	
	if turn_on_wall and is_on_wall():
		dir = -dir
		velocity.x = 0.0
		
	if sprite:
		sprite.flip_h = dir > 0

func _apply_contact_damage_once(b: Node) -> void:
	super._apply_contact_damage_once(b)
	
	if b.is_in_group("player") and b is CombatBody2D:
		if randf() <= 0.20:
			apply_poison(b)

func apply_poison(player_node: CombatBody2D) -> void:
	if player_node.has_method("show_popup"):
		player_node.show_popup("Poisoned!", Color.PURPLE)
	_poison_routine(player_node)

func _poison_routine(player_node: Node) -> void:
	for i in range(2):
		await get_tree().create_timer(1.0).timeout
		if not is_inside_tree():
			return
		if is_instance_valid(player_node) and player_node.hp > 0:
			if player_node.has_method("apply_damage"):
				player_node.apply_damage(5, Vector2.ZERO, true, 0.0)
