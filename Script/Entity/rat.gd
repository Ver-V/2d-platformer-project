extends GroundEnemy
class_name Rat

# 쥐 (스테이지2): 공통 지상 이동 + 몸통 접촉 피해. 스프라이트는 걷기 4프레임뿐이라 공격 동작은 코드로 만든다:
# 달려들기 = 웅크림(lunge_windup, 눈이 깜빡임) → 앞으로 돌진(걷기 속도 × lunge_speed_mult) → 멈춤(lunge_recovery, 반격 틈).
# 변종은 rat.tscn을 상속한 씬에서 색(enemy_tint.gdshader)과 스탯만 바꾼다. 색 있는 변종은 변이체가 되지 않는다
# (mutation_enabled = false — 변이 테두리 셰이더가 몸 색 셰이더를 덮어쓰기 때문).
# 원거리 변종(파란 쥐)은 ShooterComponent 자식을 두고 shoot_range를 0보다 크게 준다:
# 타겟이 사거리 안에 있고 벽에 가리지 않으면 제자리에 서서 shoot_interval마다 쏜다. 가까이 오면 쏘지 않고 달려든다.

enum Lunge { NONE, WINDUP, DASH, RECOVER }

@export_group("Lunge")
@export var lunge_enabled: bool = true
@export var lunge_trigger_distance: float = 40.0 # 타겟이 가로로 이만큼 안에 오면 달려든다
@export var lunge_vertical_range: float = 20.0
@export var lunge_speed_mult: float = 2.0 # 걷기 속도 배율
@export var lunge_windup: float = 0.35
@export var lunge_dash_time: float = 0.35
@export var lunge_recovery: float = 0.5
@export var lunge_cooldown: float = 1.0 # 멈춤이 끝난 뒤 다음 달려들기까지
@export var lunge_windup_squash: Vector2 = Vector2(1.2, 0.75)
@export var lunge_dash_stretch: Vector2 = Vector2(1.25, 0.85)
@export var lunge_eye_flicker_hz: float = 14.0 # 웅크리는 동안 눈이 깜빡이는 빠르기 (어둠 속 예고). 0이면 안 깜빡임

@export_group("Ranged")
@export var shoot_range: float = 0.0 # 0이면 쏘지 않는다
@export var shoot_interval: float = 2.0
@export var shoot_windup: float = 0.8 # 사거리에 처음 들어온 뒤 첫 발까지 (갑자기 맞지 않게)
@export var shoot_offset: Vector2 = Vector2(8, -2) # 발사 위치 (오른쪽을 볼 때 기준, 왼쪽이면 x 반전)

const WORLD_MASK := 1

@onready var shooter: ShooterComponent = get_node_or_null("ShooterComponent")
@onready var glow_eyes: CanvasItem = get_node_or_null("GlowEyes")
var lunge_state: Lunge = Lunge.NONE
var _lunge_timer: float = 0.0
var _lunge_cooldown_left: float = 0.0
var _lunge_dir: int = 1
var _shoot_timer: float = 0.0

func _physics_process(delta: float) -> void:
	if _active and hp > 0:
		_update_lunge(delta)
	elif lunge_state != Lunge.NONE:
		_end_lunge()
	super._physics_process(delta)
	if not _active or hp <= 0:
		return
	if lunge_state == Lunge.NONE and _wants_shoot():
		_shoot_timer -= delta
		if _shoot_timer <= 0.0:
			shooter.shoot(self, target, muzzle_position())
			_shoot_timer = shoot_interval
	else:
		_shoot_timer = shoot_windup

func set_active(active: bool) -> void:
	super.set_active(active)
	if not active and lunge_state != Lunge.NONE:
		_end_lunge()

# --- 달려들기 ---

func wants_lunge() -> bool:
	if not lunge_enabled or lunge_state != Lunge.NONE or _lunge_cooldown_left > 0.0 or target == null or not is_on_floor():
		return false
	return absf(target.global_position.x - global_position.x) <= lunge_trigger_distance \
		and absf(target.global_position.y - global_position.y) <= lunge_vertical_range

func _update_lunge(delta: float) -> void:
	_lunge_cooldown_left = maxf(0.0, _lunge_cooldown_left - delta)
	if lunge_state == Lunge.NONE:
		if wants_lunge():
			_start_windup()
		return
	_lunge_timer -= delta
	if lunge_state == Lunge.WINDUP:
		_flicker_eyes()
	if _lunge_timer > 0.0:
		return
	match lunge_state:
		Lunge.WINDUP:
			lunge_state = Lunge.DASH
			_lunge_timer = lunge_dash_time
			_reset_eyes()
			_squash_to(lunge_dash_stretch, 0.06)
			if sprite: sprite.speed_scale = lunge_speed_mult
		Lunge.DASH:
			_start_recover()
		Lunge.RECOVER:
			_end_lunge()

func _start_windup() -> void:
	lunge_state = Lunge.WINDUP
	_lunge_timer = lunge_windup
	_lunge_dir = 1 if target.global_position.x >= global_position.x else -1
	_squash_to(lunge_windup_squash, lunge_windup * 0.8)

func _start_recover() -> void:
	lunge_state = Lunge.RECOVER
	_lunge_timer = lunge_recovery
	if sprite: sprite.speed_scale = 1.0
	_squash_to(Vector2.ONE, 0.15)

func _end_lunge() -> void:
	lunge_state = Lunge.NONE
	_lunge_cooldown_left = lunge_cooldown
	_reset_eyes()
	if sprite: sprite.speed_scale = 1.0
	if hp > 0:
		_squash_to(Vector2.ONE, 0.1)

# 돌진 중에는 정한 방향으로만 달린다 (플레이어를 넘어가도 돌아서지 않음). 낭떠러지·벽·방 끝이면 바로 멈춘다
func forced_ground_speed() -> float:
	if lunge_state != Lunge.DASH:
		return NAN
	dir = _lunge_dir
	if _is_blocked_ahead():
		_start_recover()
		return 0.0
	return _lunge_dir * move_speed * lunge_speed_mult

# 웅크림·멈춤 동안 제자리에 서 있고, 원거리 쥐는 쏘는 동안 서 있다
func wants_hold_position() -> bool:
	if lunge_state == Lunge.WINDUP or lunge_state == Lunge.RECOVER:
		if lunge_state == Lunge.WINDUP:
			dir = _lunge_dir # 웅크리는 동안 방향 고정
		return true
	return _wants_shoot()

func _squash_to(factor: Vector2, time: float) -> void:
	if not _can_play_sprite_motion():
		return
	_kill_motion_tween()
	var from := sprite.scale / _sprite_base_scale
	_motion_tween = create_tween()
	_motion_tween.tween_method(_apply_squash, from, factor, time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

# 눈 색은 그대로 두고 밝기(알파)만 깜빡인다 — 빨간 눈처럼 이미 가장 밝은 색도 예고가 보이게
func _flicker_eyes() -> void:
	if glow_eyes == null or lunge_eye_flicker_hz <= 0.0:
		return
	var phase := fmod((lunge_windup - _lunge_timer) * lunge_eye_flicker_hz, 1.0)
	glow_eyes.self_modulate.a = 1.0 if phase < 0.5 else 0.2

func _reset_eyes() -> void:
	if glow_eyes:
		glow_eyes.self_modulate = Color.WHITE

# --- 원거리 ---

func _wants_shoot() -> bool:
	if shooter == null or shoot_range <= 0.0 or target == null or is_attacking:
		return false
	# 가까이 오면 쏘지 않고 달려든다
	if lunge_enabled and absf(target.global_position.x - global_position.x) <= lunge_trigger_distance \
			and absf(target.global_position.y - global_position.y) <= lunge_vertical_range:
		return false
	if global_position.distance_to(target.global_position) > shoot_range:
		return false
	return _has_line_of_sight()

func muzzle_position() -> Vector2:
	return global_position + Vector2(shoot_offset.x * dir, shoot_offset.y)

func _has_line_of_sight() -> bool:
	var query := PhysicsRayQueryParameters2D.create(muzzle_position(), target.global_position + Vector2(0, -8), WORLD_MASK)
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()
