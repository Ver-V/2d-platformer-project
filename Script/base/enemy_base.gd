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

@export_group("Patrol Idle")
# 순찰(타겟 없음) 중 가끔 멈춰서 idle 동작을 취한다
@export var patrol_idle_enabled: bool = true
@export var patrol_walk_time: Vector2 = Vector2(2.0, 5.0) # 걷는 시간 범위(초)
@export var patrol_idle_time: Vector2 = Vector2(1.0, 2.5) # 멈춰 있는 시간 범위(초)
@export_range(0.0, 1.0) var patrol_turn_chance: float = 0.35 # 멈춤이 끝날 때 뒤돌아설 확률
@export var walk_animation: StringName = &"walk" # 없으면 걸을 때도 idle_animation 재생
@export var idle_animation: StringName = &"idle"

@onready var hurtbox: Area2D = $Hurtbox
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
var _health_bar_top_y: float = NAN # 체력바 기준 y (처음 그릴 때 계산)

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
		hitbox.body_entered.connect(_on_hitbox_body_entered)
		hitbox.body_exited.connect(_on_hitbox_body_exited)

	if detect_area:
		detect_area.body_entered.connect(_on_detect_entered)
		detect_area.body_exited.connect(_on_detect_exited)

	# 시작 시 비활성 상태 (Stage가 알아서 켜줌)
	set_active(false)
	if sprite: sprite.play()
	_reset_patrol_idle()

# --- Overrides (CombatBody2D) ---
func get_invuln_time() -> float: return invuln_time
func get_blink_interval() -> float: return blink_interval
func get_knockback_decay() -> float: return knockback_decay
func get_knockback_resist() -> float: return knockback_resist
func get_knockback_cooldown() -> float: return knockback_cooldown
func get_blink_node() -> CanvasItem: return sprite

func _draw() -> void:
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
	
	draw_rect(bg_rect, Color.BLACK)
	draw_rect(fill_rect, Color(0.1, 0.9, 0.2, 1.0))

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
	# 죽음 신호를 보내야 Stage가 장부에 기록
	died.emit(self)
	spawn_gold()
	
	# 충돌체 비활성화 (시체에 부딪히거나 데미지를 받지 않도록)
	if hitbox: hitbox.set_deferred("monitoring", false)
	if hurtbox: hurtbox.set_deferred("monitoring", false)
	
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
			await anim_sprite.animation_finished

	# [추가] 쉐이더 디졸브 효과 (서서히 증발)
	if sprite and sprite.material is ShaderMaterial:
		var tween = create_tween()
		# 2초간 유지하다가 마지막 3초 동안 서서히 증발
		tween.tween_interval(2.0)
		tween.tween_property(sprite.material, "shader_parameter/dissolve_value", 1.1, 3.0)

	await get_tree().create_timer(5.0).timeout
	queue_free()

func apply_damage(amount: int, knockback: Vector2 = Vector2.ZERO, ignore_cd: bool = false, or_invuln_time: float = -1.0, is_projectile: bool = false) -> bool:
	if not _active: return false
	var took_damage = super.apply_damage(amount, knockback, ignore_cd, or_invuln_time, is_projectile)
	if took_damage:
		queue_redraw()
	if took_damage and hit_sound:
		hit_sound.pitch_scale = randf_range(0.9, 1.1)
		hit_sound.play()
	return took_damage

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
	_motion_tween = create_tween()
	_motion_tween.tween_method(_apply_death_flip, 0.0, 1.0, death_flip_time)

# t: 0 → 1. 세로 배율이 1 → -1로 넘어가며 뒤집히고, 그동안 포물선으로 튀었다 떨어진다.
func _apply_death_flip(t: float) -> void:
	if sprite == null:
		return
	var k := cos(t * PI)
	sprite.scale = Vector2(_sprite_base_scale.x, _sprite_base_scale.y * k)
	var y := _grounded_sprite_y(k) - death_bounce_height * sin(t * PI)
	sprite.position = Vector2(_sprite_base_pos.x, y)

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
	if not coin_scene or drop_gold_amount <= 0:
		return
	for amount in split_gold_into_coins(drop_gold_amount):
		create_one_coin(amount)

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

func _on_hitbox_body_entered(b: Node) -> void:
	if not _active or contact_damage <= 0 or b == null: return
	_touching[b] = 0.0
	_apply_contact_damage_once(b)

func _on_hitbox_body_exited(b: Node) -> void:
	if _touching.has(b): _touching.erase(b)

func _apply_contact_damage_once(b: Node) -> void:
	if not is_instance_valid(b): return
	
	var did_dmg: bool = false
	if b is CombatBody2D:
		var dx: float = b.global_position.x - global_position.x
		var k_dir := Vector2(1.0 if dx >= 0.0 else -1.0, 0.0)
		var k_vec := Vector2(k_dir.x * contact_knockback_x, contact_knockback_y)
		did_dmg = b.apply_damage(contact_damage, k_vec)
	elif b.has_method("apply_damage"):
		b.call("apply_damage", contact_damage)
		did_dmg = true
	
	if did_dmg and not (b is CombatBody2D) and b.has_method("apply_knockback") and b is Node2D:
		var dx: float = b.global_position.x - global_position.x
		var k_dir := Vector2(1.0 if dx >= 0.0 else -1.0, 0.0)
		b.call("apply_knockback", k_dir, contact_knockback_x, contact_knockback_y)

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
	
	# 비활성화되면 물리 연산, 프로세스, 충돌체꺼서 리소스 절약
	if disable_when_inactive:
		set_physics_process(active)
		set_process(active)
		
		# deferred로 안전하게 켜고 끄기
		if hurtbox: hurtbox.set_deferred("monitoring", active)
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
