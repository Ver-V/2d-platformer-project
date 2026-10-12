extends Node
class_name PlayerCombat

# 플레이어 공격: 검 판정, 투사체 패링, 퍼펙트 가드 반격 보너스, 공격력·패링 배율.
# 상태 전환(ATTACK 진입/종료)은 Player가 하고, 여기서는 begin_attack / end_attack만 받는다.
# 나중에 무기를 주우면 여기서 HitData를 만드는 부분이 바뀐다.

@export var attack_cooldown: float = 0.5
@export var attack_damage: float = 10.0
@export var parry_damage_multiplier: float = 1.5
var attack_speed_mult: float = 1.0 # 장비 공격 속도 보너스 (쿨다운을 나누고 공격 애니메이션 재생 속도에 곱한다)

const PERFECT_GUARD_BONUS_DAMAGE: int = 10 # 퍼펙트 가드 후 다음 공격(검·패리)에 더하는 피해

# 강공격 (GameManager.heavy_attack_unlocked일 때): 공격 키를 HEAVY_CHARGE_TIME 이상 눌렀다 떼면 나간다.
# 모으는 동안은 휘두르기 직전 자세(Attack 애니메이션 HEAVY_POSE_TIME)에서 멈추고, 다 모이면 몸이 번쩍인다.
const HEAVY_CHARGE_TIME := 0.75
const HEAVY_POSE_TIME := 0.1 # Attack 애니메이션에서 칼을 들어 올린 프레임 (0.067~0.133초)
const HEAVY_DAMAGE_MULT := 2.5
const HEAVY_KNOCKBACK_MULT := 2.0
const HEAVY_REACH_SCALE := Vector2(1.4, 1.2) # 강공격 동안 칼 판정 크기
const HEAVY_HITSTOP_MULT := 1.5
const CHARGE_MOVE_RATIO := 0.3 # 모으는 동안 이동 속도 배율

var is_attacking: bool = false
var is_parry_success: bool = false   # 이번 휘두르기로 투사체를 패링했는가 (그러면 몸통은 안 때림)
var has_perfect_guard_bonus: bool = false
# 퍼펙트 가드 뒤 반격(카운터 공격·카운터 패리)은 히트스탑을 이 배수만큼 길게 (타격감)
const COUNTER_HITSTOP_MULT := 2.0
const HIT_HITSTOP := Vector2(0.25, 0.1) # (time_scale, 지속 시간)
const PARRY_HITSTOP := Vector2(0.15, 0.2)
var cooldown_left: float = 0.0
var is_heavy_attack: bool = false # 이번 휘두르기가 강공격인가
var charge_time: float = 0.0
var is_charging: bool = false

var player: Player
var sword_area: Area2D
var sword_shape: CollisionShape2D

func setup(p: Player) -> void:
	player = p
	sword_area = p.get_node("AttackPivot/SwordArea")
	sword_shape = sword_area.get_node("CollisionShape2D")
	# 적 투사체(패링)와 적·상자의 Hurtbox(타격)를 모두 area로 감지한다
	sword_area.area_entered.connect(_on_sword_area_entered)
	sword_shape.disabled = true
	sync_stats()
	Inventory.inventory_changed.connect(sync_stats) # 장비를 바꾸면 공격력·패링 배율 다시 계산

# 영구 스탯은 GameManager가 들고 있고, 장착한 장비(보석 등)의 보너스를 더한다
func sync_stats() -> void:
	attack_damage = GameManager.player_damage + Inventory.get_equipped_attack_bonus()
	parry_damage_multiplier = GameManager.player_parry_damage_multifac + Inventory.get_equipped_parry_bonus()
	attack_speed_mult = 1.0 + Inventory.get_equipped_attack_speed_bonus()

func tick(delta: float) -> void:
	if cooldown_left > 0.0:
		cooldown_left -= delta

func can_attack() -> bool:
	return cooldown_left <= 0.0

func begin_attack(heavy: bool = false) -> void:
	is_attacking = true
	is_parry_success = false
	is_heavy_attack = heavy
	sword_shape.scale = HEAVY_REACH_SCALE if heavy else Vector2.ONE
	sword_shape.disabled = false
	cooldown_left = attack_cooldown / attack_speed_mult
	if heavy:
		player.shake_camera(3.0)

func end_attack() -> void:
	is_attacking = false
	is_heavy_attack = false
	sword_shape.set_deferred("disabled", true)
	sword_shape.set_deferred("scale", Vector2.ONE)

# --- 강공격 모으기 (Player의 CHARGE 상태가 부른다) ---
func can_charge() -> bool:
	return GameManager.heavy_attack_unlocked and can_attack()

func begin_charge() -> void:
	is_charging = true
	charge_time = 0.0

func tick_charge(delta: float) -> void:
	charge_time += delta

func is_charge_ready() -> bool:
	return is_charging and charge_time >= HEAVY_CHARGE_TIME

func end_charge() -> void:
	is_charging = false
	charge_time = 0.0

func grant_counter_bonus() -> void:
	has_perfect_guard_bonus = true

func _counter_bonus() -> int:
	return PERFECT_GUARD_BONUS_DAMAGE if has_perfect_guard_bonus else 0

# --- 스탯 강화 (아이템) ---
func update_damage(amount: int) -> void:
	GameManager.add_player_damage(amount)
	sync_stats()
	if amount > 0:
		player.show_popup(tr(&"COMBAT_DAMAGE_UP"), Color.RED)

func update_parry_ratio(amount: float) -> void:
	GameManager.add_parry_ratio(amount)
	sync_stats()
	if amount > 0:
		player.show_popup(tr(&"COMBAT_PARRY_POWER_UP"), Color.CYAN)

# --- 검 판정 ---
func _on_sword_area_entered(area: Area2D) -> void:
	if area is Hurtbox:
		on_sword_hurtbox_entered(area)
	elif area is Projectile:
		_try_parry(area)

func _try_parry(p: Projectile) -> void:
	# 반격 보너스는 패링이 성공했을 때만 소모한다 (패링 불가 탄이면 그대로 두고 몸통 타격에 쓰임)
	if not p.attempt_parry(player.global_position, _counter_bonus(), parry_damage_multiplier):
		return
	is_parry_success = true
	player.sfx_player.play_parry()
	var countered := has_perfect_guard_bonus
	if countered:
		has_perfect_guard_bonus = false
		player.show_popup(tr(&"COMBAT_COUNTER_PARRY"), Color.CYAN)
	player.shake_camera(3.0)
	# 성공했을 때만 잠깐 대기 후 히트스탑
	await Wait.seconds(self, 0.05)
	_hitstop(PARRY_HITSTOP, countered)

# target: 적·상자의 Hurtbox (테스트 등에서는 몸 노드를 직접 줘도 된다)
# 판정은 이번 물리 단계가 끝난 뒤(call_deferred)에 한다: 같은 단계에서 투사체 패링이 먼저 처리되어,
# 같은 휘두르기로 패링했다면 몸통은 때리지 않는다. 그 사이 플레이어가 사라지면 호출 자체가 취소된다.
func on_sword_hurtbox_entered(target: Node) -> void:
	_resolve_sword_hit.call_deferred(target)

func _resolve_sword_hit(target: Node) -> void:
	if is_parry_success or not is_instance_valid(target):
		return
	var victim: Node = target.receiver if target is Hurtbox else target
	if not is_instance_valid(victim) or not victim is Node2D:
		return

	var knock_dir: Vector2 = (victim.global_position - player.global_position).normalized()
	var heavy := is_heavy_attack
	var debuffed := maxf(1.0, attack_damage + player.get_status_effects().get_attack_modifier()) # 산성 디버프 등
	var base_damage := int(round(debuffed * (HEAVY_DAMAGE_MULT if heavy else 1.0)))
	var knock := Vector2(knock_dir.x * 400, -200) * (HEAVY_KNOCKBACK_MULT if heavy else 1.0)
	var hit := HitData.new(base_damage + _counter_bonus(), knock, player)
	hit.status_effects = Inventory.roll_equipped_hit_statuses() # 장착한 보석의 타격 상태이상
	hit.is_heavy = heavy
	var result := HitData.deliver(target, hit)
	if not HitData.landed(result):
		return
	# 실제로 피해가 들어갔을 때만 반격 보너스 소모
	var countered := has_perfect_guard_bonus
	if countered:
		has_perfect_guard_bonus = false
		player.show_popup(tr(&"COMBAT_COUNTER_HIT"), Color.ORANGE)
	_hitstop(HIT_HITSTOP * Vector2(1.0, HEAVY_HITSTOP_MULT if heavy else 1.0), countered)
	player.shake_camera(4.0 if heavy else 2.0)

func _hitstop(stop: Vector2, countered: bool) -> void:
	GameManager.apply_hitstop(stop.x, stop.y * (COUNTER_HITSTOP_MULT if countered else 1.0))
