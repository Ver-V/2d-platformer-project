extends GroundEnemy
class_name Sheep

# 양 (스테이지3): 순찰하다가 플레이어를 발견하면(DetectArea) 어떻게 할지 한 번 정한다.
#  - charge_chance(75%): 쫓아가서 몸으로 박는다 (몸통 접촉 피해, 쫓을 때 chase_speed_multiplier배 빠르게)
#  - 나머지(25%): 제자리에서 bleat_time초 동안 운다. 그동안 BleatArea 안에 있는 플레이어는 졸음(DrowsyEffect)이
#    초당 buildup_per_sec(20)씩 차고, 100이 되면 잠든다. 울고 나면 bleat_cooldown초 서 있다가, 플레이어가 아직
#    보이면 다시 정한다. 쫓던 플레이어를 놓쳐도 다시 정한다.
# 울음 범위는 씬의 BleatArea(Area2D)의 CollisionShape2D로 정한다 (원이면 우는 동안 퍼지는 파동도 그 반지름까지).
# 애니메이션: idle / walk / bleat (bleat가 없으면 idle).

enum Mode { NONE, CHARGE, BLEAT, REST }

const DROWSY: StatusEffect = preload("res://resources/status_effects/drowsy.tres")

@export_group("Sheep")
@export_range(0.0, 1.0) var charge_chance: float = 0.75
@export var bleat_time: float = 3.0
@export var bleat_cooldown: float = 1.5
@export var drowsy_effect: StatusEffect = DROWSY
@export var bleat_animation: StringName = &"bleat"
@export var bleat_sound: AudioStream
@export var bleat_wave_color: Color = Color(0.85, 0.85, 0.95, 0.5)
@export var bleat_wave_count: int = 3
@export var bleat_wave_speed: float = 0.8 # 파동이 범위 끝까지 퍼지는 횟수/초

@onready var bleat_area: Area2D = $BleatArea

var mode: Mode = Mode.NONE
var _mode_timer: float = 0.0
var _wave_time: float = 0.0
var _waves: Node2D

func _ready() -> void:
	super._ready()
	if is_queued_for_deletion():
		return
	_waves = Node2D.new()
	_waves.name = "BleatWaves"
	_waves.draw.connect(_draw_waves)
	add_child(_waves)

func _physics_process(delta: float) -> void:
	if _active and hp > 0 and not is_asleep():
		_update_mode(delta)
	elif mode != Mode.NONE:
		_end_mode()
	super._physics_process(delta)

func _update_mode(delta: float) -> void:
	match mode:
		Mode.NONE:
			if target != null and is_on_floor():
				_decide()
		Mode.CHARGE:
			if target == null:
				mode = Mode.NONE
		Mode.BLEAT:
			_mode_timer -= delta
			_wave_time += delta
			_expose_players(delta)
			_waves.queue_redraw()
			if _mode_timer <= 0.0:
				mode = Mode.REST
				_mode_timer = bleat_cooldown
				_waves.queue_redraw()
		Mode.REST:
			_mode_timer -= delta
			if _mode_timer <= 0.0:
				mode = Mode.NONE

# 테스트에서 확률 대신 정해서 부를 수 있게 roll을 받는다
func _decide(roll: float = randf()) -> void:
	if roll < effective_charge_chance():
		mode = Mode.CHARGE
	else:
		_start_bleat()

# 달빛(MoonPhase madness)에 미친 양은 울지 않고 돌진한다: madness 1이면 항상 돌진
func effective_charge_chance() -> float:
	var madness := float(MoonPhase.current(self, "madness"))
	return lerpf(charge_chance, 1.0, clampf(madness, 0.0, 1.0))

func _start_bleat() -> void:
	mode = Mode.BLEAT
	_mode_timer = bleat_time
	_wave_time = 0.0
	if bleat_sound != null:
		var sound := AudioStreamPlayer2D.new()
		sound.stream = bleat_sound
		sound.bus = &"SFX"
		add_child(sound)
		sound.finished.connect(sound.queue_free)
		sound.play()

func _end_mode() -> void:
	mode = Mode.NONE
	_mode_timer = 0.0
	if _waves:
		_waves.queue_redraw()

func is_bleating() -> bool:
	return mode == Mode.BLEAT

# 울음 범위 안의 플레이어와 다른 적(근처 양 포함, 보스 제외)에게 졸음을 쌓는다
func _expose_players(delta: float) -> void:
	if drowsy_effect == null or bleat_area == null:
		return
	for body in bleat_area.get_overlapping_bodies():
		if not body.is_in_group("player") or not body is CombatBody2D or body.hp <= 0:
			continue
		_expose(body, delta)
	for e in get_tree().get_nodes_in_group("enemies"):
		if e == self or not e is EnemyBase or e.hp <= 0 or not e._active or e.is_in_group("bosses"):
			continue
		if in_bleat_range((e as Node2D).global_position):
			_expose(e, delta)

func _expose(body: CombatBody2D, delta: float) -> void:
	var effect := body.apply_status_effect(drowsy_effect) as DrowsyEffect
	if effect != null:
		effect.expose(delta)

# 울음 범위(BleatArea의 원·사각형) 안인가. 몹은 몸 층이 달라 영역으로 못 잡으므로 모양으로 잰다
func in_bleat_range(point: Vector2) -> bool:
	var cs := bleat_area.get_node_or_null(^"CollisionShape2D") as CollisionShape2D
	if cs == null or cs.shape == null:
		return false
	var local := cs.global_transform.affine_inverse() * point
	if cs.shape is CircleShape2D:
		return local.length() <= (cs.shape as CircleShape2D).radius
	if cs.shape is RectangleShape2D:
		return Rect2(-(cs.shape as RectangleShape2D).size * 0.5, (cs.shape as RectangleShape2D).size).has_point(local)
	return false

# 우는 동안·운 뒤 쉬는 동안은 제자리에 서서 플레이어 쪽을 본다
func wants_hold_position() -> bool:
	return mode == Mode.BLEAT or mode == Mode.REST

func play_move_animation(moving: bool) -> void:
	if mode == Mode.BLEAT and sprite != null and sprite.sprite_frames != null and sprite.sprite_frames.has_animation(bleat_animation):
		if sprite.animation != bleat_animation:
			sprite.play(bleat_animation)
		return
	super.play_move_animation(moving)

func set_active(active: bool) -> void:
	super.set_active(active)
	if not active and mode != Mode.NONE:
		_end_mode()

func reset_to_home(reset_hp: bool = true) -> void:
	super.reset_to_home(reset_hp)
	_end_mode()

func _on_death() -> void:
	_end_mode()
	super._on_death()

# --- 우는 동안 범위 끝까지 퍼지는 동그란 파동 (범위가 원일 때) ---
func _bleat_shape() -> CollisionShape2D:
	return bleat_area.get_node_or_null("CollisionShape2D") as CollisionShape2D if bleat_area else null

func _draw_waves() -> void:
	if mode != Mode.BLEAT:
		return
	var cs := _bleat_shape()
	if cs == null or not cs.shape is CircleShape2D:
		return
	var radius: float = (cs.shape as CircleShape2D).radius
	var center := bleat_area.position + cs.position
	for i in bleat_wave_count:
		var t := fmod(_wave_time * bleat_wave_speed + float(i) / bleat_wave_count, 1.0)
		var color := bleat_wave_color
		color.a *= 1.0 - t
		_waves.draw_arc(center, radius * t, 0.0, TAU, 32, color, 1.5)
