extends Node
class_name PlayerGuard

# 플레이어 가드: 가드 판정, 퍼펙트 가드, 재사용 대기시간.
# 가드는 앞에서 날아온 투사체만 막는다 (몸통 접촉·근접 공격은 막지 않음 — 의도된 동작).
# 상태 전환(GUARD 진입/종료)과 가드 중 이동은 Player가 하고, 여기서는 begin / end / tick만 받는다.

@export_range(0.0, 1.0) var move_speed_ratio: float = 0.2 # 가드 중 이동속도 배율

const PERFECT_GUARD_WINDOW: float = 0.2 # 퍼펙트 가드 판정 시간
const CHIP_DAMAGE_MAX: int = 5          # 일반 가드로 막은 투사체가 주는 최대 피해
const COOLDOWN_TIME: float = 1.5        # 가드 재사용 대기 시간

var is_guarding: bool = false
var guard_timer: float = 0.0     # 가드를 시작한 뒤 지난 시간 (퍼펙트 가드 판정)
var cooldown_timer: float = 0.0

var player: Player
var guard_area: Area2D
var guard_shape: CollisionShape2D

func setup(p: Player) -> void:
	player = p
	guard_area = p.get_node("AttackPivot/GuardArea")
	guard_shape = guard_area.get_node("CollisionShape2D")
	guard_area.area_entered.connect(_on_guard_area_entered)
	guard_shape.disabled = true

func can_start() -> bool:
	return cooldown_timer <= 0.0

func begin() -> void:
	is_guarding = true
	guard_timer = 0.0
	player.sfx_player.play_guard()
	guard_shape.set_deferred("disabled", false)

func end() -> void:
	is_guarding = false
	guard_shape.set_deferred("disabled", true)
	cooldown_timer = COOLDOWN_TIME

# 매 프레임 (가드 중이 아니어도) — 재사용 대기시간
func tick(delta: float) -> void:
	if cooldown_timer > 0.0:
		cooldown_timer = maxf(0.0, cooldown_timer - delta)

# 가드 중 매 프레임 — 퍼펙트 가드 판정용 시간
func tick_guarding(delta: float) -> void:
	guard_timer += delta

func get_recharge_ratio() -> float:
	if is_guarding:
		return 0.0
	return clampf(1.0 - cooldown_timer / COOLDOWN_TIME, 0.0, 1.0)

func can_block(hit: HitData) -> bool:
	if not is_guarding or not hit.is_projectile or hit.amount < 0:
		return false
	if player.hp <= 0 or player.is_invulnerable():
		return false
	return hit.knockback.x * player.attack_pivot.scale.x < 0

# can_block이 true일 때만 부른다. 튜토리얼의 피해량 0인 투사체도 가드 성공과 소멸을 처리한다.
func block(hit: HitData) -> HitData.Result:
	if guard_timer <= PERFECT_GUARD_WINDOW:
		_perfect_guard()
		return HitData.Result.PERFECT_GUARD
	player.show_popup(tr(&"COMBAT_GUARD"), Color.GRAY)
	player.sfx_player.play_guard()
	var chip := hit.duplicate_hit()
	chip.amount = mini(hit.amount, CHIP_DAMAGE_MAX)
	if chip.amount <= 0:
		return HitData.Result.GUARDED # 연습용 탄환은 피해 없이 소모한다
	# 깎인 피해는 들어가지만 상태이상은 막는다
	var chip_result := player.take_damage_only(chip)
	return HitData.Result.GUARDED if chip_result == HitData.Result.HIT else chip_result

func _perfect_guard() -> void:
	player.show_popup(tr(&"COMBAT_PERFECT_GUARD"), Color.CYAN)
	GameManager.apply_hitstop(0.15, 0.1)
	player.sfx_player.play_perfect_guard()
	player.shake_camera(3.0)
	player.combat.grant_counter_bonus()
	player.start_invuln(0.2)

# 가드 판정 영역에 앞쪽에서 투사체가 들어오면, 몸에 닿기 전에 막는다
func _on_guard_area_entered(area: Area2D) -> void:
	if is_guarding and area is Projectile:
		if area.velocity.x * player.attack_pivot.scale.x < 0:
			area.hit_target(player)
