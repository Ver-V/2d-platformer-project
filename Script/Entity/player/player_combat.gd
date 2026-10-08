extends Node
class_name PlayerCombat

# 플레이어 공격: 검 판정, 투사체 패링, 퍼펙트 가드 반격 보너스, 공격력·패링 배율.
# 상태 전환(ATTACK 진입/종료)은 Player가 하고, 여기서는 begin_attack / end_attack만 받는다.
# 나중에 무기를 주우면 여기서 HitData를 만드는 부분이 바뀐다.

@export var attack_cooldown: float = 0.8
@export var attack_damage: float = 10.0
@export var parry_damage_multiplier: float = 1.5

const PERFECT_GUARD_BONUS_DAMAGE: int = 10 # 퍼펙트 가드 후 다음 공격(검·패리)에 더하는 피해

var is_attacking: bool = false
var is_parry_success: bool = false   # 이번 휘두르기로 투사체를 패링했는가 (그러면 몸통은 안 때림)
var has_perfect_guard_bonus: bool = false
var cooldown_left: float = 0.0

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

# 영구 스탯은 GameManager가 들고 있다
func sync_stats() -> void:
	attack_damage = GameManager.player_damage
	parry_damage_multiplier = GameManager.player_parry_damage_multifac

func tick(delta: float) -> void:
	if cooldown_left > 0.0:
		cooldown_left -= delta

func can_attack() -> bool:
	return cooldown_left <= 0.0

func begin_attack() -> void:
	is_attacking = true
	is_parry_success = false
	sword_shape.disabled = false
	cooldown_left = attack_cooldown

func end_attack() -> void:
	is_attacking = false
	sword_shape.set_deferred("disabled", true)

func grant_counter_bonus() -> void:
	has_perfect_guard_bonus = true

func _counter_bonus() -> int:
	return PERFECT_GUARD_BONUS_DAMAGE if has_perfect_guard_bonus else 0

# --- 스탯 강화 (아이템) ---
func update_damage(amount: int) -> void:
	GameManager.add_player_damage(amount)
	attack_damage = GameManager.player_damage
	if amount > 0:
		player.show_popup(tr(&"COMBAT_DAMAGE_UP"), Color.RED)

func update_parry_ratio(amount: float) -> void:
	GameManager.add_parry_ratio(amount)
	parry_damage_multiplier = GameManager.player_parry_damage_multifac
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
	if has_perfect_guard_bonus:
		has_perfect_guard_bonus = false
		player.show_popup(tr(&"COMBAT_COUNTER_PARRY"), Color.CYAN)
	player.shake_camera(3.0)
	# 성공했을 때만 잠깐 대기 후 히트스탑
	await Wait.seconds(self, 0.05)
	GameManager.apply_hitstop(0.15, 0.2)

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
	var hit := HitData.new(int(attack_damage) + _counter_bonus(), Vector2(knock_dir.x * 400, -200), player)
	var result := HitData.deliver(target, hit)
	if not HitData.landed(result):
		return
	# 실제로 피해가 들어갔을 때만 반격 보너스 소모
	if has_perfect_guard_bonus:
		has_perfect_guard_bonus = false
		player.show_popup(tr(&"COMBAT_COUNTER_HIT"), Color.ORANGE)
	GameManager.apply_hitstop(0.25, 0.1)
	player.shake_camera(2.0)
