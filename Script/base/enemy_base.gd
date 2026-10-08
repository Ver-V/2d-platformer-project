extends CombatBody2D
class_name EnemyBase

# [시스템 필수] 적이 죽었을 때 Stage 스크립트에게 알리는 신호
signal died(enemy: EnemyBase)

@export var drop_gold_amount: int = 10 # 기본값
@export var coin_scene: PackedScene

@export_group("Identity")
# [시스템 필수] 세이브/로드 시 나를 구별하는 ID (Stage에서 자동 할당함)
@export var persist_id: StringName = &"" 

@export_group("Enemy Stats")
@export var max_hp_base: int = 10
@export var contact_damage_base: int = 1
@export var move_speed_base: float = 80.0
@export var contact_knockback_x: float = 320.0
@export var contact_knockback_y: float = -240.0

@export_group("Enemy Combat")
@export var invuln_time: float = 0.7
@export var blink_interval: float = 0.05
@export var knockback_resist: float = 0.0 # 1 = 안 밀림, 0.5 = 절반, 0 = 그대로, 음수 = 더 멀리 (-1이면 2배)
@export var knockback_cooldown: float = 0.7
@export var knockback_decay: float = 2600.0
@export var contact_tick: float = 1.0
# 접촉 피해가 실제로 들어갔을 때 contact_status_chance 확률로 거는 상태이상 (비우면 없음)
@export var contact_status: StatusEffect
@export_range(0.0, 1.0) var contact_status_chance: float = 1.0

@export_group("Enemy Health Bar")
@export var show_health_bar: bool = true
@export var health_bar_x_offset: float = 0.0
@export var health_bar_gap: float = 3.0 # 보이는 몸 맨 위와 체력바 사이 간격
@export var health_bar_size: Vector2 = Vector2(24.0, 4.0)

@export_group("Behavior")
@export var disable_when_inactive: bool = true

@export_group("Hit / Death Motion")
# 보스는 자체 연출이 있으므로 둘 다 적용하지 않는다
@export var hit_squash_enabled: bool = true
@export var hit_squash_scale: Vector2 = Vector2(1.2, 0.8) # 맞은 순간 납작해지는 배율 (기본 크기 대비)
@export var hit_squash_time: float = 0.18 # 납작 → 살짝 늘어남 → 원래 크기까지 걸리는 시간
@export var death_flip_enabled: bool = true
@export var death_bounce_height: float = 14.0 # 죽을 때 튀어오르는 높이(px)
@export var death_flip_time: float = 0.4 # 튀어올라 뒤집혀 떨어지기까지 걸리는 시간

@export_group("Mutation")
# 스테이지에 놓인 잡몹은 MobMutation.CHANCE 확률로 변이체가 된다 (보스·분열로 생긴 작은 몹 제외)
@export var mutation_enabled: bool = true
@export var can_split: bool = false # 분열 변이가 나올 수 있는 몹 (슬라임)

@export_group("Patrol Idle")
# 순찰(타겟 없음) 중 가끔 멈춰서 idle 동작을 취한다
@export var patrol_idle_enabled: bool = true
@export var patrol_walk_time: Vector2 = Vector2(2.0, 5.0) # 걷는 시간 범위(초)
@export var patrol_idle_time: Vector2 = Vector2(1.0, 2.5) # 멈춰 있는 시간 범위(초)
@export_range(0.0, 1.0) var patrol_turn_chance: float = 0.35 # 멈춤이 끝날 때 뒤돌아설 확률
@export var walk_animation: StringName = &"walk" # 없으면 걸을 때도 idle_animation 재생
@export var idle_animation: StringName = &"idle"

@onready var hurtbox: Hurtbox = $Hurtbox
@onready var hitbox: Area2D = $Hitbox
@onready var body_shape: CollisionShape2D = $CollisionShape2D
@onready var detect_area: Area2D = $DetectArea
@onready var sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D")
@onready var floor_ray: RayCast2D = get_node_or_null("FloorRay")
@onready var hit_sound: AudioStreamPlayer2D = $HitSound

var contact_damage: int = 0
var move_speed: float = 0.0
var _touching: Dictionary = {}

# 원래 내 집 위치 (방 이동 후 돌아올 곳)
var home_position: Vector2 = Vector2.ZERO 
var room_rect: Rect2 = Rect2() # 내가 속한 방의 영역
var _active: bool = true
var target: Node2D = null

var _patrol_idling: bool = false
var _patrol_timer: float = 0.0

# 스쿼시·뒤집기 연출용 스프라이트 기본 변형
var _sprite_base_scale: Vector2 = Vector2.ONE
var _sprite_base_pos: Vector2 = Vector2.ZERO
var _motion_tween: Tween
var _death_flip_ground_y: float = NAN # 뒤집기 기준 바닥 (_body_bottom_y), NAN이면 프레임 크기 기준
var _death_flip_start_offset: float = 0.0
var _health_bar_top_y: float = NAN # 체력바 기준 y (처음 그릴 때 계산)

# 체력바는 몸과 따로 이 노드에 그린다: 시야 제한(VisionLimit) 어둠보다 위(Z_MAX)에 보이도록
var _health_bar_layer: Node2D
const ABOVE_DARK_Z := RenderingServer.CANVAS_ITEM_Z_MAX

var mutation: MobMutation.Kind = MobMutation.Kind.NONE
var is_split_minion: bool = false # 분열 변이가 죽으며 낳은 작은 몹: 세이브에 기록 안 함, 방이 비활성화되면 사라짐
var _was_activated: bool = false

func _ready() -> void:
	add_to_group("enemies")
	
	# 레이캐스트 설정 강제화 (낭떠러지 감지용)
	if floor_ray:
		floor_ray.enabled = true
		floor_ray.position.y = 5 # 슬라임 발쪽으로 중심 이동
		floor_ray.target_position = Vector2(0, 30) # 충분한 길이로 설정하여 바닥을 확실히 감지
		floor_ray.collision_mask = 1 # World 레이어 감지
		floor_ray.force_raycast_update() # 시작하자마자 바닥 상태 갱신
		
	if GameManager.defeated_mobs.has(persist_id):
		queue_free()
		return

	if sprite:
		_sprite_base_scale = sprite.scale
		_sprite_base_pos = sprite.position

	_health_bar_layer = Node2D.new()
	_health_bar_layer.name = "HealthBarLayer"
	_health_bar_layer.z_as_relative = false
	_health_bar_layer.z_index = ABOVE_DARK_Z
	_health_bar_layer.draw.connect(_draw_health_bar)
	add_child(_health_bar_layer)
		
	# 태어난 위치를 집으로 기억
	home_position = global_position
	
	# [추가] 내가 속한 방의 경계 계산
	var stage = get_tree().current_scene
	if stage and stage.has_method("room_from_pos") and stage.has_method("room_center"):
		var r_coord = stage.room_from_pos(home_position)
		var r_center = stage.room_center(r_coord)
		var r_size = stage.room_size
		room_rect = Rect2(r_center - r_size / 2.0, r_size)
	
	max_hp = max_hp_base
	hp = max_hp
	contact_damage = contact_damage_base
	move_speed = move_speed_base
	
	if hitbox:
		# 접촉 피해는 플레이어 Hurtbox(레이어 9)에 닿았을 때
		hitbox.area_entered.connect(_on_hitbox_area_entered)
		hitbox.area_exited.connect(_on_hitbox_area_exited)

	if detect_area:
		detect_area.body_entered.connect(_on_detect_entered)
		detect_area.body_exited.connect(_on_detect_exited)

	# 시작 시 비활성 상태 (Stage가 알아서 켜줌)
	set_active(false)
	if sprite: sprite.play()
	_reset_patrol_idle()
	# persist_id는 스테이지 _ready(공식 배정)가 끝나야 확정되므로 그 뒤에 굴린다
	call_deferred("_roll_mutation")

# --- Overrides (CombatBody2D) ---
func get_invuln_time() -> float: return invuln_time
func get_blink_interval() -> float: return blink_interval
func get_knockback_decay() -> float: return knockback_decay
func get_knockback_resist() -> float: return knockback_resist
func get_knockback_cooldown() -> float: return knockback_cooldown
func get_blink_node() -> CanvasItem: return sprite
func can_tick_status_effects() -> bool: return _active and hp > 0
func _on_status_damaged(_amount: int) -> void: queue_redraw()

# 몸을 다시 그릴 때(queue_redraw) 체력바 노드도 같이 다시 그린다
func _draw() -> void:
	if is_instance_valid(_health_bar_layer):
		_health_bar_layer.queue_redraw()

func _draw_health_bar() -> void:
	if not show_health_bar: return
	if is_in_group("bosses"): return
	if not _active: return
	if hp <= 0 or max_hp <= 0: return
	if health_bar_size.x <= 2.0 or health_bar_size.y <= 2.0: return
	
	var ratio: float = clampf(float(hp) / float(max_hp), 0.0, 1.0)
	var center := _get_health_bar_center()
	var top_left := center - health_bar_size * 0.5
	var bg_rect := Rect2(top_left, health_bar_size)
	var fill_rect := Rect2(top_left + Vector2.ONE, Vector2((health_bar_size.x - 2.0) * ratio, health_bar_size.y - 2.0))
	
	_health_bar_layer.draw_rect(bg_rect, Color.BLACK)
	_health_bar_layer.draw_rect(fill_rect, Color(0.1, 0.9, 0.2, 1.0))

func _get_health_bar_center() -> Vector2:
	if sprite == null:
		return Vector2(health_bar_x_offset, -health_bar_gap - health_bar_size.y * 0.5)
	if is_nan(_health_bar_top_y):
		_health_bar_top_y = _visible_sprite_top_y()
	return Vector2(
		_sprite_base_pos.x + sprite.offset.x + health_bar_x_offset,
		_health_bar_top_y - health_bar_gap - health_bar_size.y * 0.5
	)

# 기본 자세(idle 첫 프레임)에서 실제로 보이는 픽셀의 맨 위 y (몸 로컬 좌표)
# 프레임 캔버스의 투명 여백 위가 아니라 몸 바로 위에 체력바를 붙이기 위해 한 번만 계산한다
func _visible_sprite_top_y() -> float:
	var top := 0.0
	if sprite.sprite_frames == null:
		return top
	var anim := idle_animation if sprite.sprite_frames.has_animation(idle_animation) else sprite.animation
	var tex := sprite.sprite_frames.get_frame_texture(anim, 0)
	if tex == null:
		return top
	var canvas_top := sprite.offset.y - (tex.get_size().y * 0.5 if sprite.centered else 0.0)
	var used_top := 0.0
	var img := tex.get_image()
	if img != null and not img.is_empty():
		if img.is_compressed():
			img.decompress()
		var used := img.get_used_rect()
		if used.size.y > 0:
			used_top = used.position.y
	return _sprite_base_pos.y + (canvas_top + used_top) * absf(_sprite_base_scale.y)

func _on_death() -> void:
	queue_redraw()
	_play_death_flip()
	if mutation != MobMutation.Kind.NONE:
		_try_drop_reward_chest()
		if mutation == MobMutation.Kind.SPLIT:
			call_deferred("_spawn_split_minions")
	# 죽음 신호를 보내야 Stage가 장부에 기록
	died.emit(self)
	spawn_gold()
	
	# 충돌체 비활성화 (시체에 부딪히거나 데미지를 받지 않도록)
	if hitbox: hitbox.set_deferred("monitoring", false)
	if hurtbox: hurtbox.set_enabled(false)
	
	# 충돌체 자체를 끄지 않고 레이어를 변경하여 바닥에 서 있게 함
	# 1번 레이어(World)만 남기고 나머지는 끔으로써 플레이어와는 겹쳐짐
	collision_layer = 0
	collision_mask = 1 # World 레이어하고만 충돌 유지
	
	# 스프라이트가 애니메이션을 재생 중이면 끝날 때까지 대기
	var anim_sprite = sprite
	if not anim_sprite and "boss_sprite" in self:
		anim_sprite = get("boss_sprite")
		
	var death_anim := death_animation(anim_sprite)
	if death_anim != &"":
		anim_sprite.play(death_anim)
		if not anim_sprite.sprite_frames.get_animation_loop(death_anim):
			# 사망 애니메이션이 끝나면 사라지기 시작
			anim_sprite.animation_finished.connect(_fade_out_and_free, CONNECT_ONE_SHOT)
			return
	_fade_out_and_free()

# 2초간 시체로 남았다가 3초 동안 디졸브로 증발한 뒤 삭제. 적에 묶인 트윈이라 적이 먼저 사라지면 같이 멈춘다
func _fade_out_and_free() -> void:
	var tween := create_tween()
	tween.tween_interval(2.0)
	if sprite and sprite.material is ShaderMaterial:
		tween.tween_property(sprite.material, "shader_parameter/dissolve_value", 1.1, 3.0)
	else:
		tween.tween_interval(3.0)
	tween.tween_callback(queue_free)

func receive_hit(hit: HitData) -> HitData.Result:
	if not _active:
		return HitData.Result.IGNORED
	var result := super.receive_hit(hit)
	if HitData.landed(result):
		queue_redraw()
		if hit_sound:
			hit_sound.pitch_scale = randf_range(0.9, 1.1)
			hit_sound.play()
	return result

func _play_hit_effects() -> void:
	super._play_hit_effects()
	_play_hit_squash()

# -------------------------------------------------------------------------
# 피격 스쿼시 / 사망 뒤집기 — 프레임 없이 스프라이트 변형으로 연출한다
# -------------------------------------------------------------------------

func _can_play_sprite_motion() -> bool:
	return sprite != null and not is_in_group("bosses")

# 스프라이트 원본 텍스처 기준 세로 범위 (scale 적용 전, 스프라이트 로컬 y)
func _sprite_v_extent() -> Vector2:
	var h := 0.0
	if sprite.sprite_frames != null:
		var tex := sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
		if tex != null:
			h = tex.get_size().y
	var top := sprite.offset.y - (h * 0.5 if sprite.centered else 0.0)
	return Vector2(top, top + h)

# 세로 배율 k(1=원래, 음수=뒤집힘)에서 발끝이 원래 바닥에 붙어 있도록 하는 y 위치
# 사망 애니메이션으로 바뀌어도 맞도록 매번 현재 프레임 크기로 계산한다
func _grounded_sprite_y(k: float) -> float:
	var extent := _sprite_v_extent()
	var s := _sprite_base_scale.y
	var base_bottom := maxf(extent.x * s, extent.y * s)
	var bottom_now := maxf(extent.x * s * k, extent.y * s * k)
	return _sprite_base_pos.y + base_bottom - bottom_now

func _kill_motion_tween() -> void:
	if _motion_tween != null and _motion_tween.is_valid():
		_motion_tween.kill()
	_motion_tween = null

func _reset_sprite_motion() -> void:
	_kill_motion_tween()
	if sprite:
		sprite.scale = _sprite_base_scale
		sprite.position = _sprite_base_pos

func _play_hit_squash() -> void:
	if not hit_squash_enabled or not _can_play_sprite_motion() or hp <= 0:
		return
	_kill_motion_tween()
	var stretch := Vector2(2.0, 2.0) - hit_squash_scale # 납작의 반대로 살짝 늘어남
	stretch = Vector2.ONE + (stretch - Vector2.ONE) * 0.4
	_motion_tween = create_tween()
	_motion_tween.tween_method(_apply_squash, hit_squash_scale, stretch, hit_squash_time * 0.45) 		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_motion_tween.tween_method(_apply_squash, stretch, Vector2.ONE, hit_squash_time * 0.55) 		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _apply_squash(factor: Vector2) -> void:
	if sprite == null:
		return
	sprite.scale = _sprite_base_scale * factor
	sprite.position = Vector2(_sprite_base_pos.x, _grounded_sprite_y(factor.y))

func _play_death_flip() -> void:
	if not death_flip_enabled or not _can_play_sprite_motion():
		return
	_reset_sprite_motion()
	_prepare_death_flip()
	_motion_tween = create_tween()
	_motion_tween.tween_method(_apply_death_flip, 0.0, 1.0, death_flip_time)

# 뒤집기 기준 = 몸 충돌체 바닥(땅). 시작 자세와 바닥 맞춘 자세의 차이를 기억해 뒤집는 동안 서서히 없앤다 (시작할 때 튀지 않게)
func _prepare_death_flip() -> void:
	_death_flip_ground_y = _body_bottom_y()
	_death_flip_start_offset = 0.0
	if not is_nan(_death_flip_ground_y):
		_death_flip_start_offset = _sprite_base_pos.y - _flip_grounded_y(1.0)

# 몸 충돌체 바닥 (스프라이트 부모 좌표). 충돌체가 없으면 NAN
func _body_bottom_y() -> float:
	var parent := sprite.get_parent() as Node2D if sprite != null else null
	if body_shape == null or body_shape.shape == null or parent == null:
		return NAN
	return parent.to_local(body_shape.to_global(body_shape.shape.get_rect().end)).y

# 세로 배율 k에서 실제로 그려진 픽셀의 맨 아래가 충돌체 바닥에 닿는 y 위치.
# 프레임 여백은 무시하므로, 쓰러진 시체처럼 그림이 프레임 아래쪽에 몰려 있어도 뒤집힌 뒤 땅에 붙는다
func _flip_grounded_y(k: float) -> float:
	var extent := _sprite_opaque_v_extent()
	var s := _sprite_base_scale.y
	return _death_flip_ground_y - maxf(extent.x * s * k, extent.y * s * k)

# 현재 프레임에서 투명하지 않은 픽셀의 세로 범위 (scale 적용 전, 스프라이트 로컬 y). 텍스처별로 한 번만 계산
static var _opaque_rows_cache := {}
func _sprite_opaque_v_extent() -> Vector2:
	var tex: Texture2D = null
	if sprite.sprite_frames != null:
		tex = sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
	if tex == null:
		return _sprite_v_extent()
	if not _opaque_rows_cache.has(tex):
		var rows := Vector2(0.0, tex.get_height())
		var img := tex.get_image()
		if img != null:
			if img.is_compressed():
				img.decompress()
			var used := img.get_used_rect()
			if used.size.y > 0:
				rows = Vector2(used.position.y, used.end.y)
		_opaque_rows_cache[tex] = rows
	var top := sprite.offset.y - (tex.get_height() * 0.5 if sprite.centered else 0.0)
	return Vector2(top, top) + _opaque_rows_cache[tex]

# t: 0 → 1. 세로 배율이 1 → -1로 넘어가며 뒤집히고, 그동안 포물선으로 튀었다 떨어진다.
func _apply_death_flip(t: float) -> void:
	if sprite == null:
		return
	var k := cos(t * PI)
	sprite.scale = Vector2(_sprite_base_scale.x, _sprite_base_scale.y * k)
	var y: float
	if is_nan(_death_flip_ground_y):
		y = _grounded_sprite_y(k) # 충돌체가 없으면 프레임 크기 기준으로 발끝을 바닥에 맞춘다
	else:
		y = _flip_grounded_y(k) + _death_flip_start_offset * (k + 1.0) * 0.5
	sprite.position = Vector2(_sprite_base_pos.x, y - death_bounce_height * sin(t * PI))

# --- Logic ---
func _process(delta: float) -> void:
	super._process(delta) 
	if not _active: return

	if contact_damage > 0 and contact_tick > 0.0:
		var removed_keys := []
		for b in _touching.keys():
			if not is_instance_valid(b):
				removed_keys.append(b)
				continue
			
			var t: float = float(_touching[b])
			t += delta
			if t >= contact_tick:
				t = 0.0
				_apply_contact_damage_once(b)
			_touching[b] = t
		
		for k in removed_keys:
			_touching.erase(k)

func _physics_process(delta: float) -> void:
	if not _active: return
	
	# 중력 적용
	if not is_on_floor():
		velocity += get_gravity() * delta
		
	move_in_room(delta)

# 넉백을 더해 이동하고, 방 경계 밖으로 나가지 못하게 막는다. (중력은 호출하는 쪽에서 처리)
func move_in_room(delta: float) -> void:
	move_with_knockback(delta)
	
	# [추가] 방 경계 밖으로 절대 나가지 못하게 강제로 위치 고정 (Hard Clamp)
	if room_rect.size != Vector2.ZERO:
		var margin = 8.0 # 경계에서 약간의 여유
		var old_x = global_position.x
		global_position.x = clamp(global_position.x, room_rect.position.x + margin, room_rect.end.x - margin)
		
		# [수정] 억지로 위치가 조정되었다면 (경계에 막혔다면) 방향을 틀어준다
		if global_position.x != old_x:
			if "dir" in self:
				set("dir", -get("dir"))

# 사망 애니메이션 이름: dead → died 순서로 있는 것. 없으면 &""
func death_animation(anim_sprite: AnimatedSprite2D = null) -> StringName:
	if anim_sprite == null:
		anim_sprite = sprite
	if anim_sprite == null or anim_sprite.sprite_frames == null:
		return &""
	for anim_name in [&"dead", &"died"]:
		if anim_sprite.sprite_frames.has_animation(anim_name):
			return anim_name
	return &""

func spawn_gold():
	# 코인 씬이 연결되어 있고, 드랍 금액이 0보다 클 때만 생성
	var total := reward_gold()
	if not coin_scene or total <= 0:
		return
	for amount in split_gold_into_coins(total):
		create_one_coin(amount)

# 변이체는 MobMutation.REWARD_MULT배
func reward_gold() -> int:
	return drop_gold_amount * (MobMutation.REWARD_MULT if mutation != MobMutation.Kind.NONE else 1)

# 금액을 금화(1000)·은화(100)·동화(10) 단위로 나눈다. 10 미만 나머지는 버린다. (박스 드롭도 사용)
static func split_gold_into_coins(total: int) -> Array[int]:
	var coins: Array[int] = []
	if total <= 0:
		return coins
	for unit in [1000, 100, 10]:
		for i in range(total / unit):
			coins.append(unit)
		total %= unit
	return coins
		
func create_one_coin(amount: int):
	var coin = coin_scene.instantiate()
	
	# 위치 설정
	# position은 몬스터 발밑
	var random_offset = Vector2(randf_range(-20, 20), randf_range(-20, 0))
	coin.global_position = global_position + random_offset
	
	# 씬 전환 중 null 에러 방지
	var scene = get_tree().current_scene
	if is_instance_valid(scene):
		scene.call_deferred("add_child", coin)
		coin.call_deferred("setup", amount)
	else:
		coin.queue_free()

func _on_hitbox_area_entered(area: Area2D) -> void:
	if not _active or contact_damage <= 0 or not area is Hurtbox: return
	_touching[area] = 0.0
	_apply_contact_damage_once(area)

func _on_hitbox_area_exited(area: Area2D) -> void:
	if _touching.has(area): _touching.erase(area)

# b: 플레이어의 Hurtbox (테스트 등에서는 몸 노드를 직접 줘도 된다)
func _apply_contact_damage_once(b: Node) -> void:
	if not is_instance_valid(b): return
	var victim: Node = b.receiver if b is Hurtbox else b
	var dx: float = (victim as Node2D).global_position.x - global_position.x if victim is Node2D else 0.0
	var k_dir := 1.0 if dx >= 0.0 else -1.0
	var hit := HitData.new(contact_damage, Vector2(k_dir * contact_knockback_x, contact_knockback_y), self)
	# 상태이상은 피해가 실제로 들어갔을 때(HIT)만 걸린다
	if contact_status != null and randf() < contact_status_chance:
		hit.status_effects.append(contact_status)
	HitData.deliver(b, hit)

func _on_detect_entered(body: Node) -> void:
	if body.is_in_group("player") and body is Node2D:
		target = body

func _on_detect_exited(body: Node) -> void:
	if body == target:
		target = null

# -------------------------------------------------------------------------
# [시스템 연동용 필수 함수] - Stage 스크립트가 이 함수들을 호출합니다.
# -------------------------------------------------------------------------

# ID 가져오기
func get_persist_id() -> StringName:
	return persist_id if persist_id != &"" else StringName(str(get_path()))

# 방 활성화/비활성화
func set_active(active: bool) -> void:
	_active = active
	queue_redraw()
	if active:
		_was_activated = true
	elif is_split_minion and _was_activated:
		queue_free() # 분열로 생긴 몹은 화면 밖으로 나가면 사라진다
		return
	
	# 비활성화되면 물리 연산, 프로세스, 충돌체꺼서 리소스 절약
	if disable_when_inactive:
		set_physics_process(active)
		set_process(active)
		
		# deferred로 안전하게 켜고 끄기
		if hurtbox: hurtbox.set_enabled(active)
		if hitbox: hitbox.set_deferred("monitoring", active)
		if body_shape: body_shape.set_deferred("disabled", not active)
		
	# 비활성화되면 타겟을 잃어버리게 할지?
	if not active:
		_touching.clear()

# 3. 홈으로 리셋
func reset_to_home(reset_hp: bool = true) -> void:
	global_position = home_position # 원래 위치로 이동
	velocity = Vector2.ZERO         # 속도 멈춤
	reset_combat_state()            # 넉백/무적 초기화
	
	target = null # 추격하던 타겟 잊어버리기
	_reset_patrol_idle()
	
	_reset_sprite_motion()
	if reset_hp: 
		hp = max_hp
		queue_redraw()

# 진행 방향에 낭떠러지가 있는지 확인하는 공용 함수
func is_ledge_ahead(move_dir: int, offset: float = 12.0) -> bool:
	if not floor_ray: return false
	
	# 레이캐스트 위치를 진행 방향 앞으로 살짝 옮김
	floor_ray.position.x = move_dir * offset
	floor_ray.force_raycast_update() # 즉시 갱신
	
	# 충돌하고 있지 않다면 낭떠러지임
	if not floor_ray.is_colliding():
		return true
		
	# 부딪힌 바닥이 가시밭(Hazard)인지 검사
	var collider = floor_ray.get_collider()
	if collider is TileMapLayer or collider is TileMap:
		# 해당 타일맵에 damage 레이어가 있는지 확인
		if collider.tile_set and collider.tile_set.get_custom_data_layer_by_name("damage") != -1:
			var hit_point = floor_ray.get_collision_point()
			# 충돌 지점에서 살짝 아래로 내려야 정확한 타일 칸을 구함
			var local_pos = collider.to_local(hit_point + Vector2(0, 5))
			var cell = collider.local_to_map(local_pos)
			var data
			if collider is TileMapLayer:
				data = collider.get_cell_tile_data(cell)
			elif collider is TileMap:
				data = collider.get_cell_tile_data(0, cell)
			
			# 타일에 데미지 데이터가 있다면 낭떠러지로 취급!
			if data and data.get_custom_data("damage") > 0:
				return true
				
	return false

# -------------------------------------------------------------------------
# 순찰 중 멈춤(idle) — 하위 클래스의 _physics_process에서 호출
# -------------------------------------------------------------------------

# 순찰 중 지금 멈춰 있어야 하면 true. 타겟이 있으면 멈춤을 풀고 걷기 상태로 되돌린다.
func update_patrol_idle(delta: float) -> bool:
	if not patrol_idle_enabled:
		return false
	if target != null:
		if _patrol_idling:
			_reset_patrol_idle()
		return false
	_patrol_timer -= delta
	if _patrol_timer <= 0.0:
		if _patrol_idling:
			_patrol_idling = false
			_patrol_timer = randf_range(patrol_walk_time.x, patrol_walk_time.y)
			if "dir" in self and randf() < patrol_turn_chance:
				set("dir", -int(get("dir")))
		else:
			_patrol_idling = true
			_patrol_timer = randf_range(patrol_idle_time.x, patrol_idle_time.y)
	return _patrol_idling

func is_patrol_idling() -> bool:
	return _patrol_idling

func _reset_patrol_idle() -> void:
	_patrol_idling = false
	_patrol_timer = randf_range(patrol_walk_time.x, patrol_walk_time.y)

# 걷기/서기 애니메이션 재생. walk_animation이 없으면 idle_animation으로 대체.
func play_move_animation(moving: bool) -> void:
	if sprite == null or sprite.sprite_frames == null:
		return
	var anim := idle_animation
	if moving and sprite.sprite_frames.has_animation(walk_animation):
		anim = walk_animation
	if sprite.sprite_frames.has_animation(anim) and sprite.animation != anim:
		sprite.play(anim)

# -------------------------------------------------------------------------
# 변이 (MobMutation)
# -------------------------------------------------------------------------

func _can_mutate() -> bool:
	if not mutation_enabled or is_split_minion or is_in_group("bosses") or hp <= 0 or not is_inside_tree():
		return false
	# 스테이지에 놓인 몹만 (테스트용 임시 배치 등은 제외)
	var stage := get_tree().current_scene
	return stage != null and stage.has_method("register_spawned_enemy")

func _roll_mutation() -> void:
	if mutation != MobMutation.Kind.NONE or not _can_mutate():
		return
	var gm := get_node("/root/GameManager")
	var rng: RandomNumberGenerator = gm.make_loot_rng(MobMutation.seed_key(get_persist_id(), gm.mutation_epoch))
	apply_mutation(MobMutation.roll(rng, can_split))

func apply_mutation(kind: MobMutation.Kind) -> void:
	mutation = kind
	match kind:
		MobMutation.Kind.TOUGH:
			max_hp = max_hp_base * MobMutation.TOUGH_HP_MULT
			hp = max_hp
			knockback_resist = 1.0
		MobMutation.Kind.SWIFT:
			move_speed = move_speed_base * MobMutation.SWIFT_SPEED_MULT
			if sprite:
				sprite.speed_scale = MobMutation.SWIFT_SPEED_MULT # 걷기·공격 애니메이션(=공격 속도)
		MobMutation.Kind.POISON:
			contact_status = load(MobMutation.POISON_EFFECT_PATH)
			contact_status_chance = 1.0
		MobMutation.Kind.BLEED:
			contact_status = load(MobMutation.BLEED_EFFECT_PATH) # 한 번에 게이지가 가득 차서 바로 터진다
			contact_status_chance = 1.0
	if sprite and kind != MobMutation.Kind.NONE:
		sprite.material = MobMutation.make_material(kind)
	queue_redraw()

# 변이체를 잡으면 MobMutation.CHEST_CHANCE 확률로 보상 상자. 다음 리롤(휴식·부활)까지 그 자리에 남는다
func _try_drop_reward_chest() -> void:
	var gm := get_node("/root/GameManager")
	var rng: RandomNumberGenerator = gm.make_loot_rng(MobMutation.chest_key(get_persist_id(), gm.mutation_epoch))
	if not MobMutation.rolls_chest(rng):
		return
	var stage := get_tree().current_scene if is_inside_tree() else null
	if stage == null or not stage.has_method("spawn_mutant_chest"):
		return
	var chest_id := "mutant:%s:%d" % [get_persist_id(), gm.mutation_epoch]
	var pos := _ground_point()
	gm.add_mutant_chest(stage.scene_file_path, chest_id, pos)
	stage.call_deferred("spawn_mutant_chest", chest_id, pos)

# 몸 충돌체 바닥 중앙 (전역 좌표). 상자 원점이 바닥 중앙이라 그대로 놓으면 땅에 붙는다
func _ground_point() -> Vector2:
	if body_shape == null or body_shape.shape == null:
		return global_position
	var bottom := body_shape.to_global(body_shape.shape.get_rect().end)
	return Vector2(global_position.x, bottom.y)

# 분열: 작고 약한 일반 몹 SPLIT_COUNT마리. 세이브에 남지 않는다
func _spawn_split_minions() -> void:
	var scene_res := load(scene_file_path) as PackedScene if not scene_file_path.is_empty() else null
	var parent := get_parent()
	if scene_res == null or parent == null:
		return
	var stage := get_tree().current_scene
	for i in MobMutation.SPLIT_COUNT:
		var minion := scene_res.instantiate() as EnemyBase
		if minion == null:
			continue
		minion.is_split_minion = true
		minion.persist_id = &""
		minion.max_hp_base = maxi(1, max_hp_base / MobMutation.SPLIT_HP_DIV)
		minion.drop_gold_amount = drop_gold_amount / MobMutation.SPLIT_HP_DIV
		minion.scale = Vector2.ONE * MobMutation.SPLIT_SCALE
		var offset := float(i - (MobMutation.SPLIT_COUNT - 1) * 0.5) * 12.0
		minion.position = position + Vector2(offset, -4.0)
		parent.add_child(minion)
		if stage != null and stage.has_method("register_spawned_enemy"):
			stage.register_spawned_enemy(minion)
		minion.velocity = Vector2(offset * 8.0, -160.0) # 사방으로 튀어 나온다
