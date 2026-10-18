extends Boss
class_name WolfBoss

# 숨겨진 늑대 보스 (스테이지3, 양치기의 열쇠로 여는 WolfDenDoor 안쪽 방).
# 인트로 (처음 한 번, 그동안 플레이어 조작은 막힌다):
#   양으로 변장(Disguise = 양 그림)한 채 문 반대쪽을 보고 있다 → dialogue_file 대사 → 문 쪽(door_marker,
#   없으면 플레이어 쪽)을 돌아보고 → 플레이어를 보며 눈이 번쩍 → 양 울음(bleat_sound)으로 울다가 털이 터지며
#   늑대로 변하고, 울음이 늑대 울음(howl_sound)으로 이어진다 → 전투.
#   인트로를 이미 본 세이브(talked_bosses)면 처음부터 늑대 모습으로 바로 싸운다.
# 패턴 (하나 끝나면 idle_time 대기, 페이즈 2에선 대기가 짧다):
#   페이즈 1: [1] 할퀴기 (다가가서)  [2] 돌진 박치기 (예고 → 벽이나 플레이어까지, 빗나가 벽에 박히면 잠깐 멈춤)
#             [3] 양 울음 흉내 (제자리, HowlArea 안에서 졸음이 보통 속도로 찬다 — 때릴 틈)
#   페이즈 2 (체력 phase2_hp_ratio 아래, 붉어짐): [1] 할퀴기 3연타  [2] 도약 덮치기 (플레이어 자리로 뛰어 착지 판정)
#             [3] 울부짖기 (HowlArea 안에서 졸음이 howl_drowsy_mult배 빠르게)
#   [4] 잠 탄환 (두 페이즈 모두): 작고 빠른 탄 sleep_shot_count발. 맞으면 개당 졸음 40 (가드해도 그대로, 퍼펙트 가드는 절반).
#       전부 패링해서 되돌려 보내면 보스에게 졸음이 쌓여 잠든다 (boss_sleep_time 2.5초, 받는 피해 asleep_damage_mult배) — 강공격을 꽂을 틈.
#   플레이어가 잠들어 있으면 다른 패턴 대신 달려가 강한 물기 (맞으면 깬다).
# 판정·범위는 씬의 Facing 아래 Area2D(MeleeRange, ClawHitbox, BiteHitbox, PounceHitbox)와 HowlArea로 조정한다.
# Facing은 바라보는 쪽으로 좌우 반전된다 (오른쪽을 볼 때 기준). 늑대 그림은 오른쪽, 양 그림(Disguise)은 왼쪽을 본다.
# 애니메이션 (없으면 건너뜀): 늑대 idle / walk / run / windup / attack / howl / jump / gethit / dead, 양 idle / bleat

signal move_finished

enum Move { NONE, WALK, RUSH, JUMP }

const DROWSY: StatusEffect = preload("res://resources/status_effects/drowsy.tres")
const RAGE_SHADER: Shader = preload("res://resources/Shaders/boss_rage.gdshader")
const MOVE_EPSILON := 2.0

@export_group("Intro")
@export var door_marker: Node2D # 플레이어가 들어오는 문 위치 (비우면 플레이어 쪽)
@export var save_after_intro: bool = true # 인트로를 본 뒤 저장 (BossBase와 같음. 테스트에서 끈다)
# 달빛이 든 보름달 밤(지상 통로 열림 + MoonPhase.FULL)에만 정체를 드러낸다. 그 외에는 그냥 양으로 서 있다 (문도 닫지 않고 맞지도 않음)
@export var requires_full_moon: bool = true
@export var bleat_sound: AudioStream # 양 울음 (인트로·양 울음 흉내)
@export var howl_sound: AudioStream  # 늑대 울음 (변신·울부짖기)
@export var intro_look_away_time: float = 0.6 # 대사 뒤 반대쪽을 보고 있는 시간
@export var intro_turn_time: float = 0.8      # 문 쪽을 보고 있는 시간
@export var intro_stare_time: float = 1.0     # 플레이어를 노려보는 시간
@export var intro_bleat_time: float = 1.2     # 양 울음 → 변신까지
@export var intro_howl_time: float = 1.5      # 변신 뒤 늑대 울음 → 전투까지
@export var sound_crossfade: float = 0.5      # 양 울음이 늑대 울음으로 넘어가는 시간
@export var transform_shake: float = 6.0

@export_group("Timing")
@export var idle_time: float = 1.2
@export var phase2_idle_mult: float = 0.7
@export var melee_windup: float = 0.45
@export var combo_gap: float = 0.25
@export var melee_recover: float = 0.4
@export var rush_windup: float = 0.6
@export var rush_stun_time: float = 1.2
@export var pounce_windup: float = 0.5
@export var bite_windup: float = 0.5
@export var mimic_time: float = 2.5
@export var howl_time: float = 2.0
@export var approach_timeout: float = 4.0

@export_group("Movement")
@export var walk_speed: float = 70.0
@export var chase_speed: float = 140.0 # 잠든 플레이어에게 달려갈 때
@export var rush_speed: float = 320.0
@export var pounce_clearance: float = 40.0 # 덮치기 점프가 목표보다 이만큼 더 높이 오른다

@export_group("Damage")
@export var claw_damage: int = 18
@export var bite_damage: int = 45
@export var pounce_damage: int = 25
@export var rush_damage_mult: float = 1.5 # 돌진 중 접촉 피해 = 접촉 피해 × 이 값
@export var attack_knockback: Vector2 = Vector2(280, -200)
@export var crash_shake: float = 8.0
@export var pounce_shake: float = 5.0

@export_group("Drowsy")
@export var drowsy_effect: StatusEffect = DROWSY
@export var mimic_drowsy_mult: float = 1.0 # 양 울음 흉내: 양과 같은 속도 (초당 20)
@export var howl_drowsy_mult: float = 2.5  # 울부짖기: 초당 50

@export_group("Sleep Shot")
@export var sleep_shot_scene: PackedScene = preload("res://Scenes/Projectile/projectile_sleep.tscn")
@export var sleep_shot_count: int = 3
@export var sleep_shot_windup: float = 0.5
@export var sleep_shot_gap: float = 0.6 # 다음 탄까지 (예고음 포함)
@export var sleep_shot_ready_sound: AudioStream = preload("res://Assets/sounds/boss/boss02/flask_ready.wav") # 매 발 직전 예고음
@export var sleep_shot_ready_delay: float = 0.25 # 예고음 뒤 이만큼 있다가 쏜다
@export var sleep_shot_cue_color: Color = Color(0.8, 0.7, 1.0)
@export var asleep_damage_mult: float = 2.0 # 잠든 동안 받는 피해 배율

@export_group("Rage")
@export var rage_amount: float = 0.6
@export var rage_fade_time: float = 0.6

@onready var disguise: AnimatedSprite2D = get_node_or_null("Disguise")
@onready var facing: Node2D = get_node_or_null("Facing")
@onready var melee_range: Area2D = get_node_or_null("Facing/MeleeRange")
@onready var claw_box: Area2D = get_node_or_null("Facing/ClawHitbox")
@onready var bite_box: Area2D = get_node_or_null("Facing/BiteHitbox")
@onready var pounce_box: Area2D = get_node_or_null("Facing/PounceHitbox")
@onready var eye_glint: Node2D = get_node_or_null("Facing/EyeGlint")
@onready var howl_area: Area2D = get_node_or_null("HowlArea")

var disguised: bool = false
var dormant: bool = false # 보름달이 아니라 양 행세만 하는 중
var _move: Move = Move.NONE
var _move_dir: int = 1
var _walk_speed: float = 0.0
var _jump_airborne: bool = false
var _face_dir: int = 1
var _lock_face: bool = false
var _loop_running: bool = false
var _rush_hit_player: bool = false
var _howl_mult: float = 0.0 # 0보다 크면 울고 있다: HowlArea 안의 플레이어에게 졸음
var _cutscene_locked: bool = false
var _glint: float = 0.0
var _rng := RandomNumberGenerator.new()
var _was_asleep: bool = false

func _ready() -> void:
	super._ready()
	if is_queued_for_deletion():
		return
	_rng.randomize()
	if sprite != null and sprite.material == null:
		var mat := ShaderMaterial.new()
		mat.shader = RAGE_SHADER
		sprite.material = mat
	if eye_glint != null:
		eye_glint.z_index = 60
		eye_glint.draw.connect(_draw_eye_glint)
	GameManager.moon_changed.connect(_update_dormant)
	_update_dormant()

func _update_dormant() -> void:
	if boss_started and not dormant:
		return # 이미 싸우는 중이면 그대로
	dormant = requires_full_moon and not GameManager.is_moonlit(MoonPhase.Phase.FULL)
	if dormant:
		_set_disguised(true)
	else:
		var id := get_persist_id()
		_set_disguised(not (id != &"" and GameManager.talked_bosses.get(id, false)))

# 보름달이 아니면 방에 들어와도 깨어나지 않는다 (다시 들어오면 그때 다시 본다)
func set_active(active: bool) -> void:
	if dormant and active:
		return
	super.set_active(active)

func _exit_tree() -> void:
	_set_cutscene_lock(false)

# --- 변장 ---
func _set_disguised(on: bool) -> void:
	disguised = on
	if disguise != null:
		disguise.visible = on
		if on and disguise.sprite_frames != null and disguise.sprite_frames.has_animation(&"idle"):
			disguise.play(&"idle")
	if sprite != null:
		sprite.visible = not on
	_update_facing()

# --- 인트로 ---
func _start_intro() -> void:
	current_state = State.INTRO
	velocity = Vector2.ZERO
	_acquire_target()
	_set_disguised(true)
	_set_cutscene_lock(true)
	var door_x := door_marker.global_position.x if door_marker != null else \
		(target.global_position.x if is_instance_valid(target) else global_position.x - 1.0)
	var door_dir := 1 if door_x >= global_position.x else -1
	_face(-door_dir) # 문 반대쪽을 보고 있다
	if dialogue_file != "" and DialogueManager.start_dialogue(dialogue_file):
		await DialogueManager.dialogue_finished
	if not await _intro_wait(intro_look_away_time):
		return
	_face(door_dir) # 문 쪽을 돌아본다
	if not await _intro_wait(intro_turn_time):
		return
	_face(_dir_to_target()) # 주인공을 노려본다
	_flash_eyes()
	if not await _intro_wait(intro_stare_time):
		return
	# 양 울음으로 울다가 털이 터지며 늑대로 변하고, 울음이 늑대 울음으로 넘어간다
	if disguise != null and disguise.sprite_frames != null and disguise.sprite_frames.has_animation(&"bleat"):
		disguise.play(&"bleat")
	var bleat := _play_sound(bleat_sound)
	if not await _intro_wait(intro_bleat_time):
		return
	transform_to_wolf()
	_crossfade(bleat, _play_sound(howl_sound, -40.0), sound_crossfade)
	_play(&"howl", true)
	if not await _intro_wait(intro_howl_time):
		return
	var id := get_persist_id()
	if id != &"":
		GameManager.talked_bosses[id] = true
		if save_after_intro:
			GameManager.save_game()
	_set_cutscene_lock(false)
	_start_combat()

# 인트로 중 기다리기. 그사이 방을 나가거나(비활성) 죽는 등 인트로가 끊겼으면 false (조작 잠금도 푼다)
func _intro_wait(time: float) -> bool:
	if time > 0.0:
		await Wait.seconds(self, time)
	var ok := is_inside_tree() and hp > 0 and current_state == State.INTRO and _active
	if not ok:
		_set_cutscene_lock(false)
		if current_state == State.INTRO and hp > 0:
			boss_started = false # 다시 들어오면 인트로를 처음부터
	return ok

func _set_cutscene_lock(on: bool) -> void:
	if on == _cutscene_locked:
		return
	_cutscene_locked = on
	if on:
		GameManager.ui_opened(self, false)
	else:
		GameManager.ui_closed(self)

# 털이 터지며 늑대 모습으로
func transform_to_wolf() -> void:
	_set_disguised(false)
	_shake(transform_shake)
	_emit_wool_burst()

func _emit_wool_burst() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var wool := CPUParticles2D.new()
	wool.emitting = false
	wool.amount = 40
	wool.lifetime = 0.9
	wool.one_shot = true
	wool.explosiveness = 0.9
	wool.direction = Vector2.UP
	wool.spread = 120.0
	wool.gravity = Vector2(0, 160)
	wool.initial_velocity_min = 60.0
	wool.initial_velocity_max = 160.0
	wool.scale_amount_min = 2.0
	wool.scale_amount_max = 5.0
	wool.color = Color(0.95, 0.93, 0.86)
	wool.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	wool.emission_rect_extents = Vector2(14, 8)
	Effects.emit_once(wool, scene, global_position)

func _play_sound(stream: AudioStream, volume_db: float = 0.0) -> AudioStreamPlayer2D:
	if stream == null:
		return null
	var player := AudioStreamPlayer2D.new()
	player.stream = stream
	player.bus = &"SFX"
	player.volume_db = volume_db
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()
	return player

# from은 줄이고 to는 키운다 (둘 중 없는 쪽은 건너뜀)
func _crossfade(from: AudioStreamPlayer2D, to: AudioStreamPlayer2D, time: float) -> void:
	var tween := create_tween().set_parallel(true)
	if is_instance_valid(from):
		tween.tween_property(from, "volume_db", -40.0, time)
	if is_instance_valid(to):
		tween.tween_property(to, "volume_db", 0.0, time)
	if not is_instance_valid(from) and not is_instance_valid(to):
		tween.kill()

func _face(dir: int) -> void:
	_face_dir = dir
	_update_facing()

# --- 상태 ---
func _idle_state(_delta: float) -> void:
	_acquire_target()
	current_state = State.COMBAT
	if not _loop_running:
		_run_loop()

func _still_fighting() -> bool:
	return hp > 0 and current_state != State.DEAD and is_inside_tree()

# 패턴을 이어 가도 되는가: 싸우는 중이고 잠들지 않았다 (잠들면 하던 패턴을 그 자리에서 멈춘다)
func _can_act() -> bool:
	return _still_fighting() and not is_asleep()


func _acquire_target() -> void:
	if is_instance_valid(target):
		return
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		target = players[0]

func _target_asleep() -> bool:
	return is_instance_valid(target) and target.has_method("is_asleep") and target.is_asleep()

# --- 물리 ---
func _physics_process(delta: float) -> void:
	if current_state == State.INTRO:
		# 인트로 중엔 BossBase처럼 플레이어 쪽으로 돌아보지 않고 제자리에 서 있는다
		if not is_on_floor():
			velocity += get_gravity() * delta
		velocity.x = 0.0
		move_in_room(delta)
		return
	if current_state != State.COMBAT:
		super._physics_process(delta)
		return
	if _update_sleep(delta):
		return
	if not _active:
		return
	_acquire_target()
	if not is_on_floor():
		velocity += get_gravity() * delta
	match _move:
		Move.NONE:
			velocity.x = move_toward(velocity.x, 0.0, 2000.0 * delta)
		Move.WALK:
			velocity.x = _dir_to_target() * _walk_speed
		Move.RUSH:
			velocity.x = _move_dir * rush_speed
	if _move == Move.JUMP and not is_on_floor():
		_jump_airborne = true
	move_in_room(delta)
	match _move:
		Move.RUSH:
			if _rush_hit_player or _at_wall(_move_dir):
				_end_move()
		Move.JUMP:
			if _jump_airborne and is_on_floor():
				_end_move()
	_update_facing()
	if _howl_mult > 0.0:
		_expose_howl(delta)

# 잠들어 있으면 제자리에 쓰러져 있고 true. 잠드는/깨는 순간 연출과 접촉 피해를 바꾼다
func _update_sleep(delta: float) -> bool:
	var sleeping := is_asleep()
	if sleeping and not _was_asleep:
		_was_asleep = true
		_howl_mult = 0.0
		if _move != Move.NONE:
			_end_move()
		contact_damage = 0 # 자는 늑대에 다가가 때려도 몸에 닿아 다치지 않게
		_play(&"gethit", true)
		var drowsy := get_status_effects().get_effect(&"drowsy") as DrowsyEffect
		say("Zzz...", drowsy.sleep_left if drowsy != null else 2.5)
	elif not sleeping and _was_asleep:
		_was_asleep = false
		contact_damage = contact_damage_base
		_hide_speech()
		_play(&"idle", true)
	if not sleeping:
		return false
	if not is_on_floor():
		velocity += get_gravity() * delta
	velocity.x = move_toward(velocity.x, 0.0, 2000.0 * delta)
	move_in_room(delta)
	return true

func _end_move() -> void:
	_move = Move.NONE
	velocity.x = 0.0
	move_finished.emit()

func _dir_to_target() -> int:
	if not is_instance_valid(target):
		return _face_dir
	return 1 if target.global_position.x >= global_position.x else -1

func _update_facing() -> void:
	if current_state == State.COMBAT:
		if not _lock_face and (_move == Move.NONE or _move == Move.WALK):
			_face_dir = _dir_to_target()
		if _move == Move.RUSH:
			_face_dir = _move_dir
	if sprite != null:
		sprite.flip_h = _face_dir < 0
	if disguise != null:
		disguise.flip_h = _face_dir > 0 # 양 그림은 왼쪽을 본다
	if facing != null:
		facing.scale.x = _face_dir

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

# --- 패턴 루프 ---
func _run_loop() -> void:
	_loop_running = true
	while _still_fighting():
		if not _active:
			await Wait.seconds(self, 0.2)
			continue
		_move = Move.NONE
		_lock_face = false
		_play(&"idle")
		await Wait.seconds(self, maxf(idle_time * (phase2_idle_mult if phase >= 2 else 1.0) - idle_cut(), 0.2))
		if not _still_fighting():
			break
		if not _active:
			continue
		while is_asleep() and _still_fighting():
			await Wait.seconds(self, 0.1)
		if not _still_fighting():
			break
		await _do_pattern()
		_lock_face = false
		_howl_mult = 0.0
		if _move != Move.NONE:
			_move = Move.NONE
	_loop_running = false

func _do_pattern() -> void:
	if _target_asleep():
		await _bite_pattern()
		return
	var pick := _rng.randi_range(1, 4)
	if pick == 4:
		await _sleep_shot_pattern()
		return
	if phase >= 2:
		match pick:
			1: await _claw_pattern(3)
			2: await _pounce_pattern()
			3: await _howl_pattern(howl_sound, howl_drowsy_mult, howl_time)
	else:
		match pick:
			1: await _claw_pattern(1)
			2: await _rush_pattern()
			3: await _howl_pattern(bleat_sound, mimic_drowsy_mult, mimic_time)

# 할퀴기 count번 (첫 타는 melee_windup, 다음 타부터 combo_gap 뒤)
func _claw_pattern(count: int) -> void:
	if not await _approach(melee_range, walk_speed):
		return
	_lock_face = true
	_flash_eyes()
	_play(&"windup", true)
	for i in count:
		await Wait.seconds(self, melee_windup if i == 0 else combo_gap)
		if not _can_act():
			return
		_play(&"attack", true)
		strike(claw_box, claw_damage)
	await Wait.seconds(self, melee_recover)
	_lock_face = false

# 잠든 플레이어에게 달려가 강하게 문다
func _bite_pattern() -> void:
	if not await _approach(melee_range, chase_speed):
		return
	_lock_face = true
	_flash_eyes()
	_play(&"windup", true)
	await Wait.seconds(self, bite_windup)
	if not _can_act():
		return
	_play(&"attack", true)
	strike(bite_box, bite_damage)
	await Wait.seconds(self, melee_recover)
	_lock_face = false

func _rush_pattern() -> void:
	_face(_dir_to_target())
	_lock_face = true
	_flash_eyes()
	_play(&"windup", true)
	await Wait.seconds(self, rush_windup)
	if not _can_act():
		return
	_rush_hit_player = false
	contact_damage = int(round(contact_damage_base * rush_damage_mult))
	_move_dir = _face_dir
	_move = Move.RUSH
	_play(&"run", true)
	await move_finished
	contact_damage = contact_damage_base
	if not _can_act():
		return
	if not _rush_hit_player: # 피했다: 벽에 박혀 멈춘다
		_shake(crash_shake)
		_play(&"gethit", true)
		await Wait.seconds(self, rush_stun_time)
	_lock_face = false

func _pounce_pattern() -> void:
	if not is_instance_valid(target):
		return
	_lock_face = true
	_flash_eyes()
	_play(&"windup", true)
	await Wait.seconds(self, pounce_windup)
	if not _can_act() or not is_instance_valid(target):
		return
	await _jump_to(Vector2(target.global_position.x, _feet_y()))
	if not _can_act():
		return
	_shake(pounce_shake)
	strike(pounce_box, pounce_damage)
	await Wait.seconds(self, melee_recover)
	_lock_face = false

# 잠 탄환: 제자리에서 플레이어를 노려 작고 빠른 탄을 sleep_shot_count발. 매 발 예고음 → sleep_shot_ready_delay 뒤 발사.
# 모두 패링할 수 있다 (되돌아온 탄이 보스에게 졸음을 쌓는다)
func _sleep_shot_pattern() -> void:
	_face(_dir_to_target())
	_lock_face = true
	_flash_eyes()
	_play(&"windup", true)
	await Wait.seconds(self, sleep_shot_windup)
	for i in sleep_shot_count:
		if not _can_act() or not is_instance_valid(target):
			return
		_play_sound(sleep_shot_ready_sound)
		await Wait.seconds(self, sleep_shot_ready_delay)
		if not _can_act() or not is_instance_valid(target):
			return
		_face(_dir_to_target())
		_play(&"attack", true)
		fire_sleep_shot()
		await Wait.seconds(self, maxf(0.0, sleep_shot_gap - sleep_shot_ready_delay))
	await Wait.seconds(self, melee_recover)
	_lock_face = false

# 잠 탄환 한 발 (패링 가능). 테스트에서도 직접 부른다
func fire_sleep_shot() -> Projectile:
	if sleep_shot_scene == null or not is_instance_valid(target):
		return null
	var p := sleep_shot_scene.instantiate() as Projectile
	var spawn := global_position + Vector2(16 * _face_dir, -10)
	p.shooter = self
	p.team = "enemy"
	p.global_position = spawn
	p.direction = ((target.global_position + Vector2(0, -8)) - spawn).normalized()
	p.rotation = p.direction.angle()
	p.set_parryable_mode(true, sleep_shot_cue_color)
	var scene := get_tree().current_scene
	(scene if scene != null else get_parent()).add_child(p)
	return p

# 제자리에서 운다: 그동안 HowlArea 안의 플레이어에게 졸음 (초당 buildup_per_sec × mult)
func _howl_pattern(sound: AudioStream, mult: float, time: float) -> void:
	_play(&"howl", true)
	_play_sound(sound)
	_howl_mult = mult
	await Wait.seconds(self, time)
	_howl_mult = 0.0

func is_howling() -> bool:
	return _howl_mult > 0.0

func _expose_howl(delta: float) -> void:
	if drowsy_effect == null or howl_area == null:
		return
	for body in howl_area.get_overlapping_bodies():
		if not body.is_in_group("player") or not body is CombatBody2D or body.hp <= 0:
			continue
		var effect := (body as CombatBody2D).apply_status_effect(drowsy_effect) as DrowsyEffect
		if effect != null:
			effect.expose(delta * _howl_mult)

# --- 다가가기 ---
func _approach(range_area: Area2D, speed: float) -> bool:
	var waited := 0.0
	_walk_speed = speed
	while _can_act() and not _in_range(range_area):
		_move = Move.WALK
		_play(&"run" if speed > walk_speed else &"walk")
		await Wait.seconds(self, 0.05)
		waited += 0.05
		if waited >= approach_timeout:
			break
	if _move == Move.WALK:
		_move = Move.NONE
	return _can_act() and _in_range(range_area)

func _in_range(area: Area2D) -> bool:
	if area == null or not is_instance_valid(target):
		return false
	return area.overlaps_body(target)

# --- 점프 (포물선으로 목표 발 위치까지) ---
func _jump_to(feet_target: Vector2) -> void:
	var g := get_gravity().y
	var from_feet := _feet_y()
	var rise := maxf(0.0, from_feet - feet_target.y) + pounce_clearance
	var vy := -sqrt(2.0 * g * rise)
	var t_up := -vy / g
	var fall := rise - (from_feet - feet_target.y)
	var t_down := sqrt(2.0 * maxf(fall, 0.0) / g)
	var total := maxf(t_up + t_down, 0.1)
	velocity = Vector2((feet_target.x - global_position.x) / total, vy)
	_move_dir = 1 if velocity.x >= 0.0 else -1
	if absf(velocity.x) > MOVE_EPSILON:
		_face_dir = _move_dir
	_jump_airborne = false
	_move = Move.JUMP
	_play(&"jump", true)
	await move_finished

func _feet_y() -> float:
	var offset := 0.0
	if body_shape != null and body_shape.shape != null:
		offset = body_shape.position.y + body_shape.shape.get_rect().end.y
	return global_position.y + offset

# --- 공격 판정 ---
func strike(box: Area2D, damage: int) -> int:
	if box == null or is_asleep():
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
	if disguised or current_state == State.INTRO:
		return
	if _move != Move.RUSH:
		super._apply_contact_damage_once(b)
		return
	if not is_instance_valid(b):
		return
	var hit := HitData.new(contact_damage, Vector2(_move_dir * contact_knockback_x, contact_knockback_y), self)
	if HitData.landed(HitData.deliver(b, hit)):
		_rush_hit_player = true

# 인트로 중엔 맞지 않는다. 맞아도 공격·돌진 동작을 끊지 않는다 (BossBase는 HIT 때 gethit을 튼다)
func receive_hit(hit: HitData) -> HitData.Result:
	if current_state == State.INTRO or disguised:
		return HitData.Result.IGNORED
	if is_asleep() and hit.amount > 0: # 자는 동안은 아프게 맞는다
		hit = hit.duplicate_hit()
		hit.amount = roundi(hit.amount * asleep_damage_mult)
	var anim := sprite.animation if sprite != null else &""
	var frame := sprite.frame if sprite != null else 0
	var progress := sprite.frame_progress if sprite != null else 0.0
	var result := super.receive_hit(hit)
	if result == HitData.Result.HIT and sprite != null and anim != &"idle" and anim != &"walk" and anim != &"":
		sprite.play(anim)
		sprite.set_frame_and_progress(frame, progress)
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
	_howl_mult = 0.0
	if reset_hp:
		_set_rage(0.0)

func _on_death() -> void:
	_howl_mult = 0.0
	_set_cutscene_lock(false)
	super._on_death()

# --- 연출 ---
func _play(anim: StringName, restart: bool = false) -> void:
	if sprite == null or sprite.sprite_frames == null or not sprite.sprite_frames.has_animation(anim):
		return
	if restart or sprite.animation != anim or not sprite.is_playing():
		sprite.play(anim)
		if restart:
			sprite.set_frame_and_progress(0, 0.0)

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
	var c := Color(1.0, 0.85, 0.3, _glint)
	eye_glint.draw_line(Vector2(-s, 0), Vector2(s, 0), c, 1.5)
	eye_glint.draw_line(Vector2(0, -s), Vector2(0, s), c, 1.5)
	eye_glint.draw_circle(Vector2.ZERO, 1.5 + _glint, c)

func _shake(amount: float) -> void:
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("apply_camera_shake"):
		scene.apply_camera_shake(amount)
