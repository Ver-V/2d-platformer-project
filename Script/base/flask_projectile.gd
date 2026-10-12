extends Projectile
class_name FlaskProjectile

# 2탄 보스의 과학자 쥐가 던지는 플라스크. 포물선(gravity)으로 날아간다.
# - 플레이어에게 직격: 직격 피해 + 직격 상태이상 (플라스크는 깨지고 끝, 스플래시 없음)
# - 땅·벽에 닿으면(빗나감): 물이 터지는 이펙트와 함께 splash_radius(3타일) 안의 플레이어에게 스플래시 피해 + 스플래시 상태이상
# - 패링하면 중력 없이 던진 쪽(보스)으로 날아가 직격 피해(× 플레이어 패링 배율, 다른 탄과 같다)와 직격 상태이상을 준다.
# 종류(kind): 출혈 / 독 / 화염(피해만 큼) / 산성(공격력 -5). 그림은 AnimatedSprite2D의 종류별 애니메이션
# (KIND_ANIMS: bleed=빨강, poison=보라, fire=주황, acid=청록)을 쓰고, 없으면 종류 색 동그라미로 그린다.
# 날아가는 동안 spin_speed로 빙글빙글 돈다 (0이면 똑바로 선 채 날아간다).

enum Kind { BLEED, POISON, FIRE, ACID }

const KIND_COLORS := {
	Kind.BLEED: Color(0.85, 0.1, 0.15),
	Kind.POISON: Color(0.6, 0.2, 0.9),
	Kind.FIRE: Color(1.0, 0.5, 0.1),
	Kind.ACID: Color(0.3, 0.82, 0.78),
}

const KIND_ANIMS := {
	Kind.BLEED: &"bleed",
	Kind.POISON: &"poison",
	Kind.FIRE: &"fire",
	Kind.ACID: &"acid",
}

@export var kind: Kind = Kind.BLEED:
	set(value):
		kind = value
		_apply_kind_visual() # 보스는 트리에 넣은 뒤에 종류를 정한다
@export var throw_gravity: float = 600.0
@export var spin_speed: float = 540.0 # 도는 속도 (도/초). 진행 방향(왼쪽·오른쪽)으로 굴러간다
@export var splash_radius: float = 48.0 # 3타일
@export var direct_damage: int = 20
@export var splash_damage: int = 10
@export var fire_direct_damage: int = 30
@export var fire_splash_damage: int = 15
@export_group("Status")
@export var bleed_direct: StatusEffect = preload("res://resources/status_effects/flask_bleed.tres")
@export var bleed_splash: StatusEffect = preload("res://resources/status_effects/flask_bleed_splash.tres")
@export var poison_direct: StatusEffect = preload("res://resources/status_effects/flask_poison.tres")
@export var poison_splash: StatusEffect = preload("res://resources/status_effects/flask_poison_splash.tres")
@export var acid: StatusEffect = preload("res://resources/status_effects/flask_acid.tres")

const PLAYER_HURTBOX_MASK := 256 # 레이어 9

var _launch_velocity: Vector2 = Vector2.ZERO
var _has_launch: bool = false
var _burst: bool = false

func _ready() -> void:
	super._ready()
	damage = _direct_damage()
	set_collision_mask_value(1, true) # 지형(World)에 닿으면 터진다
	body_entered.connect(_on_body_entered)
	if _has_launch:
		velocity = _launch_velocity
	_apply_kind_visual()

# from에서 to에 flight_time초 뒤 닿는 포물선으로 던진다 (트리에 들어가기 전에 불러도 된다)
func launch_toward(from: Vector2, to: Vector2, flight_time: float) -> void:
	var t := maxf(flight_time, 0.1)
	var d := to - from
	_launch_velocity = Vector2(d.x / t, (d.y - 0.5 * throw_gravity * t * t) / t)
	_has_launch = true
	velocity = _launch_velocity
	direction = _launch_velocity.normalized()
	damage = _direct_damage()

func _physics_process(delta: float) -> void:
	if _reflected:
		var spin_angle := rotation
		super._physics_process(delta) # 이동은 그대로 (반사탄은 진행 방향으로 돌려 놓으므로 회전만 되돌린다)
		rotation = spin_angle
		_spin(delta)
		return
	velocity.y += throw_gravity * delta
	global_position += velocity * delta
	_spin(delta)
	_current_life -= delta
	if _current_life <= 0.0:
		queue_free()

func _spin(delta: float) -> void:
	if spin_speed == 0.0:
		rotation = 0.0
		return
	rotation += deg_to_rad(spin_speed) * delta * (-1.0 if velocity.x < 0.0 else 1.0)

# 종류에 맞는 애니메이션을 튼다. 그림이 없으면 _draw의 색 동그라미
func _apply_kind_visual() -> void:
	var sprite := get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if sprite != null:
		sprite.visible = _has_art()
		if sprite.visible:
			sprite.play(KIND_ANIMS[kind])
	queue_redraw()

func _has_art() -> bool:
	var sprite := get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if sprite == null or sprite.sprite_frames == null:
		return false
	var anim: StringName = KIND_ANIMS[kind]
	return sprite.sprite_frames.has_animation(anim) and sprite.sprite_frames.get_frame_count(anim) > 0

func _direct_damage() -> int:
	return fire_direct_damage if kind == Kind.FIRE else direct_damage

func _splash_damage() -> int:
	return fire_splash_damage if kind == Kind.FIRE else splash_damage

func _direct_status() -> StatusEffect:
	match kind:
		Kind.BLEED: return bleed_direct
		Kind.POISON: return poison_direct
		Kind.ACID: return acid
	return null

func _splash_status() -> StatusEffect:
	match kind:
		Kind.BLEED: return bleed_splash
		Kind.POISON: return poison_splash
		Kind.ACID: return acid
	return null

# 직격(플레이어 또는 패링 후 보스)에 상태이상을 얹는다. 상태이상은 HIT일 때만 걸린다
func _make_hit(body: Node, knockback: Vector2) -> HitData:
	var hit := super._make_hit(body, knockback)
	var status := _direct_status()
	if status != null:
		hit.status_effects.append(status)
	return hit

# 직격으로 소모될 때도 깨지는 이펙트만 (피해는 이미 들어갔다)
func _destroy_projectile() -> void:
	_spawn_splash_effect()
	queue_free()

func _on_body_entered(_body: Node) -> void:
	if _burst or is_queued_for_deletion():
		return
	_burst = true
	_spawn_splash_effect()
	if not _reflected: # 되돌린 플라스크가 벽에 깨지면 피해 없이 끝
		_apply_splash()
	queue_free()

# 스플래시: 반지름 안의 플레이어 Hurtbox에 피해 + 스플래시 상태이상 (가드로 못 막는 범위 피해)
func apply_splash_at(center: Vector2) -> void:
	var space := get_world_2d().direct_space_state
	var query := PhysicsShapeQueryParameters2D.new()
	var circle := CircleShape2D.new()
	circle.radius = splash_radius
	query.shape = circle
	query.transform = Transform2D(0.0, center)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	query.collision_mask = PLAYER_HURTBOX_MASK
	for result in space.intersect_shape(query, 8):
		var area := result.collider as Hurtbox
		if area == null:
			continue
		var victim := area.receiver as Node2D
		var dir := 1.0 if victim == null or victim.global_position.x >= center.x else -1.0
		var hit := HitData.new(_splash_damage(), Vector2(dir * 200.0, -160.0), self)
		var status := _splash_status()
		if status != null:
			hit.status_effects.append(status)
		HitData.deliver(area, hit)

func _apply_splash() -> void:
	apply_splash_at(global_position)

func _spawn_splash_effect() -> void:
	var scene := get_tree().current_scene if is_inside_tree() else null
	if scene == null:
		return
	var color: Color = KIND_COLORS[kind]
	var particles := CPUParticles2D.new()
	particles.amount = 28
	particles.lifetime = 0.5
	particles.explosiveness = 1.0
	particles.direction = Vector2.UP
	particles.spread = 80.0
	particles.initial_velocity_min = 80.0
	particles.initial_velocity_max = 170.0
	particles.gravity = Vector2(0, 500)
	particles.scale_amount_min = 1.5
	particles.scale_amount_max = 3.0
	particles.color = color
	particles.z_index = 50
	Effects.emit_once(particles, scene, global_position)
	# 스플래시 범위를 잠깐 보여주는 고리 (범위 조정·테스트용으로도)
	var ring := Node2D.new()
	ring.z_index = 50
	var radius := splash_radius
	ring.draw.connect(func(): ring.draw_arc(Vector2.ZERO, radius, 0.0, TAU, 32, Color(color, 0.8), 1.5))
	scene.add_child(ring)
	ring.global_position = global_position
	var tween := ring.create_tween()
	tween.tween_property(ring, "modulate:a", 0.0, 0.35)
	tween.tween_callback(ring.queue_free)

# 그림이 없을 때 종류 색 플라스크
func _draw() -> void:
	if _has_art():
		return
	var color: Color = KIND_COLORS[kind]
	draw_circle(Vector2.ZERO, 4.0, color)
	draw_rect(Rect2(-1.5, -7.0, 3.0, 4.0), Color(0.85, 0.85, 0.9))
