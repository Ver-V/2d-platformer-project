extends EnemyBase
class_name GroundEnemy

# 땅 위를 걷는 잡몹 공통 동작: 중력, 순찰(가끔 멈춤), 추격, 낭떠러지·벽·방 경계에서 멈춤/뒤돌기,
# 좌우 반전, 근접 공격(사거리·판정 프레임·히트박스 확장).
# 체력·공격력·이동속도 등 스탯은 EnemyBase의 *_base 필드를 각 몹 씬(.tscn)에서 설정한다.
# 몹별 고유 동작만 하위 스크립트에서 덮어쓴다 (예: 뱀의 독).

@export_group("Ground Movement")
@export var gravity: float = 980.0
@export var max_fall_speed: float = 280.0
@export var acceleration: float = 800.0 # 땅에서 목표 속도까지 붙는 가속
@export var air_drag: float = 300.0 # 공중에서 수평 속도가 줄어드는 정도
@export var chase_speed_multiplier: float = 1.0 # 플레이어를 쫓을 때 이동속도 배율
@export var turn_on_wall: bool = true
@export var turn_on_ledge: bool = true
@export var ledge_check_offset: float = 14.0 # 몸 앞쪽 몇 px 아래에 바닥이 없으면 낭떠러지로 본다 (가시 타일도 낭떠러지)
@export var room_edge_margin: float = 12.0
@export var sprite_faces_left: bool = true # 스프라이트 원본이 왼쪽을 보고 있으면 켠다 (오른쪽으로 갈 때 flip_h)
@export var detect_radius: float = 0.0 # 0보다 크면 DetectArea 원 반지름을 이 값으로 바꾼다

@export_group("Melee Attack")
@export var attack_distance: float = 0.0 # 0이면 공격하지 않음 (몸통 접촉 데미지만)
@export var attack_vertical_range: float = 24.0
@export var attack_animations: Array[StringName] = [&"attack"] # 여러 개면 무작위
@export var attack_active_frames: Vector2i = Vector2i(2, 99) # 이 프레임 구간에서만 히트박스가 늘어난다
@export var attack_hitbox_grow: float = 4.0 # 공격 판정 중 히트박스가 앞쪽으로 늘어나는 px

var dir: int = -1
var is_attacking: bool = false

@onready var _hitbox_shape: CollisionShape2D = get_node_or_null("Hitbox/CollisionShape2D")
var _hitbox_default_pos: Vector2 = Vector2.ZERO
var _hitbox_default_size: Vector2 = Vector2.ZERO
var _hitbox_default_radius: float = 0.0

func _ready() -> void:
	super._ready()
	if is_queued_for_deletion():
		return
	if detect_radius > 0.0 and detect_area:
		var shape := detect_area.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if shape and shape.shape is CircleShape2D:
			shape.shape = shape.shape.duplicate()
			shape.shape.radius = detect_radius
	if _hitbox_shape and _hitbox_shape.shape:
		_hitbox_shape.shape = _hitbox_shape.shape.duplicate() # 같은 몹끼리 히트박스 공유 방지
		_hitbox_default_pos = _hitbox_shape.position
		if _hitbox_shape.shape is RectangleShape2D:
			_hitbox_default_size = _hitbox_shape.shape.size
		elif _hitbox_shape.shape is CircleShape2D:
			_hitbox_default_radius = _hitbox_shape.shape.radius
	if sprite:
		sprite.animation_finished.connect(_on_sprite_animation_finished)
		play_move_animation(false)
	if turn_on_ledge and is_ledge_ahead(dir, ledge_check_offset):
		dir = -dir
	_update_facing()

func _physics_process(delta: float) -> void:
	if not _active or hp <= 0:
		return

	velocity.y = minf(velocity.y + gravity * delta, max_fall_speed)

	var idling := false
	var blocked := false
	if is_on_floor():
		idling = update_patrol_idle(delta)
		if target != null and not is_attacking:
			dir = 1 if target.global_position.x >= global_position.x else -1
			if wants_attack():
				_start_attack()
		blocked = _is_blocked_ahead()
		if is_attacking or idling:
			velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
		elif blocked:
			velocity.x = 0.0
			if target == null:
				dir = -dir # 순찰 중이면 방향 전환
		else:
			var speed := move_speed * (chase_speed_multiplier if target != null else 1.0)
			velocity.x = move_toward(velocity.x, dir * speed, acceleration * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, air_drag * delta)

	move_in_room(delta)

	# 순찰 중 벽에 막히면 뒤돌기 (추격 중엔 플레이어 쪽을 계속 본다)
	if turn_on_wall and is_on_floor() and is_on_wall() and target == null and not idling and not is_attacking:
		dir = -dir
		velocity.x = 0.0

	_update_facing()
	if is_attacking:
		_update_attack_hitbox()
	else:
		play_move_animation(absf(velocity.x) > 1.0)

func _is_blocked_ahead() -> bool:
	if room_rect.size != Vector2.ZERO:
		if (global_position.x < room_rect.position.x + room_edge_margin and dir < 0) or \
		   (global_position.x > room_rect.end.x - room_edge_margin and dir > 0):
			return true
	return turn_on_ledge and is_ledge_ahead(dir, ledge_check_offset)

func facing_flip_h(move_dir: int) -> bool:
	return move_dir > 0 if sprite_faces_left else move_dir < 0

func _update_facing() -> void:
	if sprite:
		sprite.flip_h = facing_flip_h(dir)

# --- 근접 공격 ---

func wants_attack() -> bool:
	if attack_distance <= 0.0 or target == null or is_attacking:
		return false
	return absf(target.global_position.x - global_position.x) <= attack_distance \
		and absf(target.global_position.y - global_position.y) <= attack_vertical_range

func _start_attack() -> void:
	var available: Array[StringName] = []
	if sprite and sprite.sprite_frames:
		for anim_name in attack_animations:
			if sprite.sprite_frames.has_animation(anim_name):
				available.append(anim_name)
	if available.is_empty():
		return
	is_attacking = true
	sprite.play(available.pick_random())

func _on_sprite_animation_finished() -> void:
	if is_attacking and attack_animations.has(sprite.animation):
		is_attacking = false
		set_attack_hitbox(false)

func _update_attack_hitbox() -> void:
	var active := sprite != null and attack_animations.has(sprite.animation) \
		and sprite.frame >= attack_active_frames.x and sprite.frame <= attack_active_frames.y
	set_attack_hitbox(active)

# 공격 판정 중에는 히트박스를 바라보는 쪽으로 attack_hitbox_grow 만큼 늘린다
func set_attack_hitbox(active: bool) -> void:
	if _hitbox_shape == null or _hitbox_shape.shape == null:
		return
	var grow := attack_hitbox_grow if active else 0.0
	_hitbox_shape.position.x = _hitbox_default_pos.x + dir * grow
	if _hitbox_shape.shape is RectangleShape2D:
		_hitbox_shape.shape.size = Vector2(_hitbox_default_size.x + grow * 2.0, _hitbox_default_size.y)
	elif _hitbox_shape.shape is CircleShape2D:
		_hitbox_shape.shape.radius = _hitbox_default_radius + grow

func _on_death() -> void:
	is_attacking = false
	set_attack_hitbox(false)
	super._on_death()

func reset_to_home(reset_hp: bool = true) -> void:
	super.reset_to_home(reset_hp)
	is_attacking = false
	set_attack_hitbox(false)
	play_move_animation(false)
