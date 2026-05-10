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
@export var knockback_resist: float = 0.0
@export var knockback_cooldown: float = 0.7
@export var knockback_decay: float = 2600.0
@export var contact_tick: float = 1.0

@export_group("Behavior")
@export var disable_when_inactive: bool = true

@onready var hurtbox: Area2D = $Hurtbox
@onready var hitbox: Area2D = $Hitbox
@onready var body_shape: CollisionShape2D = $CollisionShape2D
@onready var detect_area: Area2D = $DetectArea
@onready var sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D")
@onready var floor_ray: RayCast2D = get_node_or_null("FloorRay")

var contact_damage: int = 0
var move_speed: float = 0.0
var _touching: Dictionary = {}

# [시스템 필수] 원래 내 집 위치 (방 이동 후 돌아올 곳)
var home_position: Vector2 = Vector2.ZERO 
var _active: bool = true
var target: Node2D = null

func _ready() -> void:
	add_to_group("enemies")
	
	if GameManager.defeated_mobs.has(persist_id):
		queue_free()
		return
		
	# 태어난 위치를 집으로 기억
	home_position = global_position
	
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

# --- Overrides (CombatBody2D) ---
func get_invuln_time() -> float: return invuln_time
func get_blink_interval() -> float: return blink_interval
func get_knockback_decay() -> float: return knockback_decay
func get_knockback_resist() -> float: return knockback_resist
func get_knockback_cooldown() -> float: return knockback_cooldown
func get_blink_node() -> CanvasItem: return sprite

func _on_death() -> void:
	# [시스템 필수] 죽음 신호를 보내야 Stage가 장부에 기록
	died.emit(self)
	spawn_gold()
	
	# 충돌체 비활성화 (시체에 부딪히거나 데미지를 받지 않도록)
	if hitbox: hitbox.set_deferred("monitoring", false)
	if hurtbox: hurtbox.set_deferred("monitoring", false)
	
	# [수정] 충돌체 자체를 끄지 않고 레이어를 변경하여 바닥에 서 있게 함
	# 1번 레이어(World)만 남기고 나머지는 끔으로써 플레이어와는 겹쳐짐
	collision_layer = 0
	collision_mask = 1 # World 레이어하고만 충돌 유지
	
	# 스프라이트가 애니메이션을 재생 중이면 끝날 때까지 대기
	var anim_sprite = sprite
	if not anim_sprite and "boss_sprite" in self:
		anim_sprite = get("boss_sprite")
		
	if anim_sprite and anim_sprite.sprite_frames.has_animation("dead"):
		anim_sprite.play("dead")
		if not anim_sprite.sprite_frames.get_animation_loop("dead"):
			await anim_sprite.animation_finished

	await get_tree().create_timer(5.0).timeout
	queue_free()

func apply_damage(amount: int, knockback: Vector2 = Vector2.ZERO, ignore_cd: bool = false, or_invuln_time: float = -1.0) -> bool:
	if not _active: return false
	return super.apply_damage(amount, knockback, ignore_cd, or_invuln_time)

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
		
	move_with_knockback(delta)

func spawn_gold():
	# 코인 씬이 연결되어 있고, 드랍 금액이 0보다 클 때만 생성
	if not coin_scene or drop_gold_amount <= 0:
		return
		
	var remaining_gold = drop_gold_amount
	
	# 1. 금화 (1000원 단위) 계산
	var gold_count = remaining_gold / 1000  # 2500 / 1000 = 2개
	remaining_gold %= 1000  # 나머지 500원
	
	# 2. 은화 (100원 단위) 계산
	var silver_count = remaining_gold / 100 # 500 / 100 = 5개
	remaining_gold %= 100   # 나머지 0원
	
	# 3. 동화 (10원 단위) 계산 (나머지 전부)
	var bronze_count = remaining_gold / 10
	
	# --- 실제 생성 루프 ---
	
	# 금화 생성
	for i in range(gold_count):
		create_one_coin(1000)
		
	# 은화 생성
	for i in range(silver_count):
		create_one_coin(100)
		
	# 동화 생성
	for i in range(bronze_count):
		create_one_coin(10)
			
		
func create_one_coin(amount: int):
	var coin = coin_scene.instantiate()
	
	# 1. 위치 설정 (중요!)
	# position은 몬스터 발밑(Pivot)입니다.
	var random_offset = Vector2(randf_range(-20, 20), randf_range(-20, 0))
	coin.global_position = global_position + random_offset
	
	# 2. 씬 전환 중 null 에러 방지
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

# 1. ID 가져오기 (Stage가 자동 할당한 ID를 반환)
func get_persist_id() -> StringName:
	return persist_id if persist_id != &"" else StringName(str(get_path()))

# 2. 방 활성화/비활성화 (플레이어가 방에 들어오거나 나갈 때 호출됨)
func set_active(active: bool) -> void:
	_active = active
	
	# 비활성화되면 물리 연산, 프로세스, 충돌체 등을 꺼서 리소스 절약
	if disable_when_inactive:
		set_physics_process(active)
		set_process(active)
		
		# deferred로 안전하게 켜고 끄기
		if hurtbox: hurtbox.set_deferred("monitoring", active)
		if hitbox: hitbox.set_deferred("monitoring", active)
		if body_shape: body_shape.set_deferred("disabled", not active)
		
	# (선택) 비활성화되면 타겟을 잃어버리게 할지? -> 보통 유지하는 게 낫지만 상황따라 해제
	if not active:
		_touching.clear()

# 3. 홈으로 리셋 (플레이어가 다른 방으로 도망갔다가 다시 왔을 때 호출됨)
func reset_to_home(reset_hp: bool = true) -> void:
	global_position = home_position # 원래 위치로 이동
	velocity = Vector2.ZERO         # 속도 멈춤
	reset_combat_state()            # 넉백/무적 초기화
	
	target = null # [중요] 추격하던 타겟 잊어버리기 (안 그러면 리셋되자마자 벽보고 달림)
	
	if reset_hp: 
		hp = max_hp
