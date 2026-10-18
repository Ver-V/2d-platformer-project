extends Boss
class_name Boss_stage2

# 2탄 보스: 약물로 거대해진 웨어랫(본체) + 그 위에 탄 과학자 쥐(플라스크 투척).
# - 패턴이 하나 끝나면 항상 idle_time초 대기. 대기 중엔 과학자가 위에서 플라스크를 던진다
#   (ShooterComponent.parry_interval = 3 → 세 번째마다 패링 가능. 종류 4개는 FlaskProjectile).
# - 페이즈 1: [1] 초근접 할퀴기  [2] 앞으로 3타일 돌진 올려치기  [3] 반대쪽 벽으로 점프 → 플레이어 쪽으로 돌진
#   (빗나가면 반대편 벽에 박혀 크게 흔들리고 gethit 상태로 crash_stun_time초 멈춤)
#   [1]·[2]가 골라졌는데 범위 밖이면 걸어서 다가간 뒤 쓴다.
# - 페이즈 2 (체력 phase2_hp_ratio 아래, 몸이 붉어짐): [1] 올려치기 → 할퀴기 연계  [2] attack 3번째 프레임에서 멈춰
#   기를 모은 뒤 제자리 점프 → 착지하며 양쪽으로 4타일 높이 충격파  [3] 돌진 phase2_rush_mult배 빨라짐
# - 플레이어가 발판 위에 platform_chase_time초 이상 있고, 다가가도 칠 수 없으면 발판 위로 뛰어오른다 (발판 위에선 돌진 안 함)
# 범위·판정은 씬의 Facing 아래 Area2D(MeleeRange, DashRange, Attack1Hitbox, Attack2Hitbox)로 조정한다.
# Facing은 바라보는 쪽으로 좌우 반전된다 (오른쪽을 볼 때 기준으로 놓으면 된다).

signal move_finished

enum Move { NONE, WALK, DASH, RUSH, JUMP }

@export_group("Timing")
@export var idle_time: float = 2.0
@export var melee_windup: float = 0.5
@export var dash_windup: float = 0.75
@export var rush_windup: float = 0.3
@export var crash_stun_time: float = 2.0
@export var approach_timeout: float = 5.0
@export var charge_time: float = 1.0 # 페이즈 2 충격파 기 모으기

@export_group("Movement")
@export var walk_speed: float = 40.0
@export var dash_distance: float = 48.0 # 3타일
@export var dash_speed: float = 260.0
@export var rush_speed: float = 420.0
@export var phase2_rush_mult: float = 1.25
@export var jump_clearance: float = 24.0 # 점프할 때 목표보다 이만큼 더 높이 올라간다
@export var shockwave_jump_height: float = 40.0

@export_group("Damage")
@export var melee_damage: int = 20
@export var dash_damage: int = 20
@export var rush_damage_mult: float = 2.0 # 돌진 중 접촉 피해 = 접촉 피해 × 이 값
@export var hit_frame: int = 3 # attack·attack2의 4번째 프레임에서 판정
@export var attack_knockback: Vector2 = Vector2(300, -220)
@export var crash_shake: float = 10.0

@export_group("Shockwave")
@export var shockwave_damage: int = 20
@export var shockwave_height: float = 64.0 # 4타일
@export var shockwave_speed: float = 260.0
@export var shockwave_shake: float = 6.0

@export_group("Flask")
@export var flasks_per_idle: int = 1
@export var flask_flight_time: float = 0.9
@export var flask_ready_sound: AudioStream = preload("res://Assets/sounds/boss/boss02/flask_ready.wav") # 던지기 전 예고음
@export var flask_ready_delay: float = 0.5 # 예고음이 나고 이만큼 뒤에 던진다

@export_group("Platform")
@export var platform_chase_time: float = 3.0
@export var platform_min_height: float = 24.0 # 플레이어 발이 보스 발보다 이만큼 높으면 발판 위로 본다
@export var platform_jump_reach: float = 80.0 # 가로로 이만큼 가까워졌는데 못 치면 뛰어오른다

@export_group("Rage")
@export var rage_amount: float = 0.6
@export var rage_fade_time: float = 0.6

const RAGE_SHADER: Shader = preload("res://resources/Shaders/boss_rage.gdshader")
const MOVE_EPSILON := 2.0

@onready var shooter: ShooterComponent = get_node_or_null("ShooterComponent")
@onready var action_sfx: AudioStreamPlayer2D = get_node_or_null("ActionSFX")
@onready var facing: Node2D = get_node_or_null("Facing")
@onready var melee_range: Area2D = get_node_or_null("Facing/MeleeRange")
@onready var dash_range: Area2D = get_node_or_null("Facing/DashRange")
@onready var attack1_box: Area2D = get_node_or_null("Facing/Attack1Hitbox")
@onready var attack2_box: Area2D = get_node_or_null("Facing/Attack2Hitbox")
@onready var eye_glint: Node2D = get_node_or_null("Facing/EyeGlint")
@onready var throw_point: Node2D = get_node_or_null("Facing/Scientist/ThrowPoint")

var _move: Move = Move.NONE
var _move_dir: int = 1
var _move_left: float = 0.0
var _jump_airborne: bool = false
var _face_dir: int = 1
var _lock_face: bool = false
var _loop_running: bool = false
var _rush_hit_player: bool = false
var _on_platform_time: float = 0.0
var _hold_frame: bool = false # 충격파 기 모으기: 공격 3번째 프레임에 멈춰 있다
var _glint: float = 0.0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	super._ready()
	_rng.randomize()
	if sprite != null and sprite.material == null:
		var mat := ShaderMaterial.new()
		mat.shader = RAGE_SHADER
		sprite.material = mat
	if eye_glint != null:
		eye_glint.z_index = 60
		eye_glint.draw.connect(_draw_eye_glint)

# --- 상태 ---
func _idle_state(_delta: float) -> void:
	_acquire_target()
	current_state = State.COMBAT
	if not _loop_running:
		_run_loop()

func _still_fighting() -> bool:
	return hp > 0 and current_state != State.DEAD and is_inside_tree()

func _acquire_target() -> void:
	if is_instance_valid(target):
		return
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		target = players[0]

# --- 물리: 걷기·돌진·점프는 여기서 움직이고, 패턴(코루틴)은 move_finished를 기다린다 ---
func _physics_process(delta: float) -> void:
	if current_state != State.COMBAT:
		super._physics_process(delta)
		return
	if not _active:
		return
	_acquire_target()
	if not is_on_floor():
		velocity += get_gravity() * delta
	_tick_platform_watch(delta)
	match _move:
		Move.NONE:
			velocity.x = move_toward(velocity.x, 0.0, 2000.0 * delta)
		Move.WALK:
			velocity.x = _dir_to_target() * walk_speed
		Move.DASH:
			velocity.x = _move_dir * dash_speed
			_move_left -= dash_speed * delta
		Move.RUSH:
			velocity.x = _move_dir * _rush_speed()
	if _move == Move.JUMP and not is_on_floor():
		_jump_airborne = true
	move_in_room(delta)
	match _move:
		Move.DASH:
			if _move_left <= 0.0 or _at_wall(_move_dir):
				_end_move()
		Move.RUSH:
			if _rush_hit_player or _at_wall(_move_dir):
				_end_move()
		Move.JUMP:
			if _jump_airborne and is_on_floor():
				_end_move()
	_update_facing()

func _end_move() -> void:
	_move = Move.NONE
	velocity.x = 0.0
	move_finished.emit()

func _rush_speed() -> float:
	return rush_speed * (phase2_rush_mult if phase >= 2 else 1.0)

func _dir_to_target() -> int:
	if not is_instance_valid(target):
		return _face_dir
	return 1 if target.global_position.x >= global_position.x else -1

func _update_facing() -> void:
	if not _lock_face and (_move == Move.NONE or _move == Move.WALK):
		_face_dir = _dir_to_target()
	if _move == Move.DASH or _move == Move.RUSH:
		_face_dir = _move_dir
	if sprite != null:
		sprite.flip_h = _face_dir < 0
	if facing != null:
		facing.scale.x = _face_dir

# 진행 방향 쪽이 지형(벽)이거나 방 경계에 닿았는가
func _at_wall(dir: int) -> bool:
	if is_on_wall() and signf(get_wall_normal().x) == -dir:
		return true
	if room_rect.size != Vector2.ZERO:
		var margin := 9.0
		if dir > 0 and global_position.x >= room_rect.end.x - margin:
			return true
		if dir < 0 and global_position.x <= room_rect.position.x + margin:
			return true
	return false

# --- 패턴 루프: 대기(플라스크) → 패턴 → 대기 → ... ---
func _run_loop() -> void:
	_loop_running = true
	while _still_fighting():
		if not _active:
			await Wait.seconds(self, 0.2)
			continue
		await _idle_phase()
		if not _still_fighting():
			break
		if not _active:
			continue
		await _do_pattern()
		_lock_face = false
		_hold_frame = false
		if _move != Move.NONE:
			_move = Move.NONE
	_loop_running = false

func _idle_phase() -> void:
	_move = Move.NONE
	_lock_face = false
	_play(&"idle")
	var count := maxi(flasks_per_idle, 0)
	var step := maxf(idle_time - idle_cut(), 0.3) / float(count + 1)
	for i in count:
		# 예고음을 내고 flask_ready_delay 뒤에 던진다 (던지는 시점은 그대로 step 간격)
		await Wait.seconds(self, maxf(step - flask_ready_delay, 0.0))
		if not _still_fighting():
			return
		_play_flask_ready()
		await Wait.seconds(self, flask_ready_delay)
		if not _still_fighting():
			return
		throw_flask()
	await Wait.seconds(self, step)

func _play_flask_ready() -> void:
	if action_sfx != null and flask_ready_sound != null:
		action_sfx.stream = flask_ready_sound
		action_sfx.play()

func _do_pattern() -> void:
	var choices := [1, 2] if _on_platform() else [1, 2, 3] # 발판 위에선 돌진 안 함
	var pick: int = choices[_rng.randi_range(0, choices.size() - 1)]
	if phase >= 2:
		match pick:
			1:
				await _dash_pattern()
				if _still_fighting():
					await _melee_pattern()
			2: await _shockwave_pattern()
			3: await _rush_pattern()
	else:
		match pick:
			1: await _melee_pattern()
			2: await _dash_pattern()
			3: await _rush_pattern()

# --- 과학자: 플라스크 ---
func throw_flask() -> void:
	if shooter == null or not is_instance_valid(target):
		return
	var from := throw_point.global_position if throw_point != null else global_position + Vector2(0, -60)
	var to := target.global_position + Vector2(0, -8)
	var p = shooter.shoot_dir(self, Vector2.RIGHT, from)
	if p is FlaskProjectile:
		p.kind = _rng.randi_range(0, FlaskProjectile.Kind.size() - 1)
		p.launch_toward(from, to, flask_flight_time)

# --- 1페이즈 1: 할퀴기 ---
func _melee_pattern() -> void:
	if not await _approach(melee_range):
		return
	_lock_face = true
	_flash_eyes()
	await Wait.seconds(self, melee_windup)
	if not _still_fighting():
		return
	await _swing(&"attack", attack1_box, melee_damage)
	_lock_face = false

# --- 1페이즈 2: 돌진 올려치기 ---
func _dash_pattern() -> void:
	if not await _approach(dash_range):
		return
	_lock_face = true
	_flash_eyes()
	await Wait.seconds(self, dash_windup)
	if not _still_fighting():
		return
	_move_dir = _face_dir
	_move_left = dash_distance
	_move = Move.DASH
	await _swing(&"attack2", attack2_box, dash_damage)
	if _move == Move.DASH:
		_end_move()
	_lock_face = false

# --- 1페이즈 3: 반대쪽 벽으로 점프 → 돌진 ---
func _rush_pattern() -> void:
	var away := -_dir_to_target()
	var wall_x := _find_wall_x(away)
	var land_x := wall_x - away * (_half_width() + 4.0)
	await _jump_to(Vector2(land_x, _feet_y()))
	if not _still_fighting():
		return
	_face_dir = _dir_to_target()
	_lock_face = true
	_update_facing()
	_play(&"rush")
	await Wait.seconds(self, rush_windup)
	if not _still_fighting():
		return
	_rush_hit_player = false
	contact_damage = int(round(contact_damage_base * rush_damage_mult))
	_move_dir = _face_dir
	_move = Move.RUSH
	await move_finished
	contact_damage = contact_damage_base
	if not _still_fighting():
		return
	if not _rush_hit_player: # 피했다: 벽에 박혀 멈춘다
		_shake(crash_shake)
		_play(&"gethit", true)
		await Wait.seconds(self, crash_stun_time)
	_lock_face = false

# --- 2페이즈 2: 기 모아 점프 → 착지 충격파 ---
func _shockwave_pattern() -> void:
	_lock_face = true
	_play(&"attack", true)
	await _wait_frame(2) # 3번째 프레임에서 멈춘다
	if not _still_fighting():
		return
	_hold_frame = true
	if sprite != null:
		sprite.pause()
	await _charge_flash(charge_time)
	_hold_frame = false
	if not _still_fighting():
		return
	_play(&"jump", true)
	velocity.y = -sqrt(2.0 * get_gravity().y * shockwave_jump_height)
	_jump_airborne = false
	_move = Move.JUMP
	await move_finished
	if not _still_fighting():
		return
	_shake(shockwave_shake)
	for d in [-1, 1]:
		spawn_shockwave(d)
	_play(&"idle")
	_lock_face = false

func spawn_shockwave(dir: int) -> Shockwave:
	var wave := Shockwave.new()
	wave.dir = dir
	wave.speed = shockwave_speed
	wave.height = shockwave_height
	wave.damage = shockwave_damage
	wave.source = self
	var scene := get_tree().current_scene
	(scene if scene != null else get_parent()).add_child(wave)
	wave.global_position = Vector2(global_position.x + dir * _half_width(), _feet_y())
	return wave

# --- 다가가기 (발판 위 플레이어면 뛰어오른다) ---
func _approach(range_area: Area2D) -> bool:
	var waited := 0.0
	while _still_fighting():
		if _in_range(range_area):
			break
		if _should_jump_to_platform():
			_move = Move.NONE
			await _jump_to(Vector2(target.global_position.x, target.global_position.y))
			continue
		_move = Move.WALK
		_play(&"walk")
		await Wait.seconds(self, 0.05)
		waited += 0.05
		if waited >= approach_timeout:
			break
	if _move == Move.WALK:
		_move = Move.NONE
	return _still_fighting() and _in_range(range_area)

func _in_range(area: Area2D) -> bool:
	if area == null or not is_instance_valid(target):
		return false
	return area.overlaps_body(target)

# --- 발판 감시 ---
func _tick_platform_watch(delta: float) -> void:
	if _player_on_platform():
		_on_platform_time += delta
	else:
		_on_platform_time = 0.0

func _player_on_platform() -> bool:
	if not is_instance_valid(target) or not target is CharacterBody2D:
		return false
	return target.is_on_floor() and target.global_position.y < _feet_y() - platform_min_height

func _should_jump_to_platform() -> bool:
	return _on_platform_time >= platform_chase_time and is_on_floor() \
		and absf(target.global_position.x - global_position.x) <= platform_jump_reach

# 보스가 발판 위에 있는가 (집(처음 선 바닥)보다 높은 곳)
func _on_platform() -> bool:
	return _feet_y() < home_position.y + _feet_offset() - platform_min_height

# --- 점프 (포물선으로 목표 발 위치까지) ---
func _jump_to(feet_target: Vector2) -> void:
	var g := get_gravity().y
	var from_feet := _feet_y()
	var rise := maxf(0.0, from_feet - feet_target.y) + jump_clearance
	var vy := -sqrt(2.0 * g * rise)
	var t_up := -vy / g
	var fall := rise - (from_feet - feet_target.y)
	var t_down := sqrt(2.0 * maxf(fall, 0.0) / g)
	var total := maxf(t_up + t_down, 0.1)
	velocity = Vector2((feet_target.x - global_position.x) / total, vy)
	_move_dir = 1 if velocity.x >= 0.0 else -1
	_face_dir = _move_dir if absf(velocity.x) > MOVE_EPSILON else _face_dir
	_jump_airborne = false
	_move = Move.JUMP
	_play(&"jump", true)
	await move_finished

func _find_wall_x(dir: int) -> float:
	var y := global_position.y
	var query := PhysicsRayQueryParameters2D.create(Vector2(global_position.x, y), Vector2(global_position.x + dir * 1000.0, y), 1)
	query.exclude = [get_rid()]
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		return hit.position.x
	if room_rect.size != Vector2.ZERO:
		return room_rect.end.x if dir > 0 else room_rect.position.x
	return global_position.x + dir * 200.0

# --- 몸 크기 ---
func _half_width() -> float:
	var rect := _body_rect()
	return rect.size.x * 0.5 if rect.size != Vector2.ZERO else 12.0

func _feet_offset() -> float:
	var rect := _body_rect()
	return rect.end.y if rect.size != Vector2.ZERO else 0.0

func _feet_y() -> float:
	return global_position.y + _feet_offset()

func _body_rect() -> Rect2:
	if body_shape == null or body_shape.shape == null:
		return Rect2()
	var r := body_shape.shape.get_rect()
	r.position += body_shape.position
	return r

# --- 공격 판정 ---
# anim을 처음부터 재생하고 hit_frame에서 box 안의 플레이어 Hurtbox를 한 번 때린 뒤 애니메이션 끝까지 기다린다
func _swing(anim: StringName, box: Area2D, damage: int) -> void:
	_play(anim, true)
	await _wait_frame(hit_frame)
	if not _still_fighting():
		return
	strike(box, damage)
	await _wait_anim_end(anim)

func strike(box: Area2D, damage: int) -> int:
	if box == null:
		return 0
	var count := 0
	for area in box.get_overlapping_areas():
		if area is Hurtbox and area.receiver != self:
			var kb := Vector2(attack_knockback.x * _face_dir, attack_knockback.y)
			HitData.deliver(area, HitData.new(damage, kb, self))
			count += 1
	return count

# 돌진 중 플레이어에 닿으면 표시해 두고 멈춘다 (빗나가야만 벽에 박힌다)
func _apply_contact_damage_once(b: Node) -> void:
	if _move != Move.RUSH:
		super._apply_contact_damage_once(b)
		return
	if not is_instance_valid(b):
		return
	var hit := HitData.new(contact_damage, Vector2(_move_dir * contact_knockback_x, contact_knockback_y), self)
	if HitData.landed(HitData.deliver(b, hit)):
		_rush_hit_player = true

# 맞아도 공격·돌진 동작을 끊지 않는다 (BossBase는 HIT 때 gethit을 튼다)
func receive_hit(hit: HitData) -> HitData.Result:
	var anim := sprite.animation if sprite != null else &""
	var frame := sprite.frame if sprite != null else 0
	var progress := sprite.frame_progress if sprite != null else 0.0
	var result := super.receive_hit(hit)
	if result == HitData.Result.HIT and sprite != null and anim != &"idle" and anim != &"walk" and anim != &"":
		sprite.play(anim)
		sprite.set_frame_and_progress(frame, progress)
		if _hold_frame:
			sprite.pause()
	return result

# --- 페이즈 2: 붉은 기 ---
func _on_phase_2() -> void:
	if sprite != null and sprite.material is ShaderMaterial:
		create_tween().tween_method(_set_rage, 0.0, rage_amount, rage_fade_time)

func _set_rage(value: float) -> void:
	if sprite != null and sprite.material is ShaderMaterial:
		(sprite.material as ShaderMaterial).set_shader_parameter(&"rage_amount", value)

func reset_to_home(reset_hp: bool = true) -> void:
	super.reset_to_home(reset_hp)
	if reset_hp:
		_set_rage(0.0)

# --- 연출 ---
func _play(anim: StringName, restart: bool = false) -> void:
	if sprite == null or sprite.sprite_frames == null or not sprite.sprite_frames.has_animation(anim):
		return
	if restart or sprite.animation != anim or not sprite.is_playing():
		sprite.play(anim)
		if restart:
			sprite.set_frame_and_progress(0, 0.0)

func _wait_frame(frame: int) -> void:
	var waited := 0.0
	while _still_fighting() and sprite != null and sprite.frame < frame and waited < 3.0:
		await Wait.seconds(self, 0.016)
		waited += 0.016

func _wait_anim_end(anim: StringName) -> void:
	if sprite == null or sprite.sprite_frames == null or not sprite.sprite_frames.has_animation(anim):
		return
	var last := sprite.sprite_frames.get_frame_count(anim) - 1
	var waited := 0.0
	while _still_fighting() and sprite.animation == anim and sprite.is_playing() \
			and not (sprite.frame >= last and sprite.frame_progress >= 0.99) and waited < 3.0:
		await Wait.seconds(self, 0.016)
		waited += 0.016

func _flash_eyes() -> void:
	if eye_glint == null:
		return
	create_tween().tween_method(_set_glint, 1.0, 0.0, 0.35)

func _set_glint(value: float) -> void:
	_glint = value
	if eye_glint != null:
		eye_glint.queue_redraw()

func _draw_eye_glint() -> void:
	if _glint <= 0.0:
		return
	var s := 3.0 + 5.0 * _glint
	var c := Color(1.0, 0.95, 0.6, _glint)
	eye_glint.draw_line(Vector2(-s, 0), Vector2(s, 0), c, 1.5)
	eye_glint.draw_line(Vector2(0, -s), Vector2(0, s), c, 1.5)
	eye_glint.draw_circle(Vector2.ZERO, 1.5 + _glint, c)

func _charge_flash(time: float) -> void:
	var mat := sprite.material as ShaderMaterial if sprite != null else null
	var elapsed := 0.0
	var on := false
	while elapsed < time and _still_fighting():
		on = not on
		if mat != null:
			mat.set_shader_parameter(&"flash_modifier", 0.6 if on else 0.0)
		await Wait.seconds(self, 0.08)
		elapsed += 0.08
	if mat != null:
		mat.set_shader_parameter(&"flash_modifier", 0.0)

func _shake(amount: float) -> void:
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("apply_camera_shake"):
		scene.apply_camera_shake(amount)
