extends StatusEffect
class_name BleedEffect

# 출혈: 맞을 때마다 게이지(buildup)가 쌓이고, threshold에 닿으면 최대 HP 비례 피해가 한 번에 터진다.
# 안 맞으면 decay_per_sec만큼 줄고, 0이 되면 해제된다. 독과 달리 시간 제한이 아니라 게이지로 끝난다.

@export var buildup_per_hit: float = 35.0
@export var threshold: float = 100.0
@export var decay_per_sec: float = 10.0
@export_range(0.0, 1.0) var burst_ratio: float = 0.2   # 터질 때 최대 HP 비율 피해
@export var burst_min_damage: int = 10
@export var burst_popup_key: StringName = &"STATUS_BLEED_BURST"
@export_range(0.0, 1.0) var warn_above: float = 0.7 # 게이지가 이 비율 이상이면 곧 터진다는 뜻으로 깜빡임

var buildup: float = 0.0

func _init() -> void:
	id = &"bleed"
	popup_key = &""
	popup_color = Color(0.85, 0.05, 0.1)
	bar_color = Color(0.9, 0.1, 0.15)
	duration = 0.0
	tick_interval = 0.0

func _on_applied() -> void:
	_add(buildup_per_hit)

func _on_reapplied(incoming: StatusEffect) -> void:
	var amount: float = incoming.buildup_per_hit if incoming is BleedEffect else buildup_per_hit
	_add(amount)

func _on_process(delta: float) -> void:
	buildup = maxf(0.0, buildup - decay_per_sec * delta)

func is_finished() -> bool:
	return super.is_finished() or buildup <= 0.0

func get_progress() -> float:
	return clampf(buildup / threshold, 0.0, 1.0) if threshold > 0.0 else 0.0

func is_bar_warning() -> bool:
	return get_progress() >= warn_above

func get_burst_damage() -> int:
	return maxi(burst_min_damage, int(ceil(host.max_hp * burst_ratio)))

func _get_save_state() -> Dictionary:
	var state := super._get_save_state()
	state["buildup"] = buildup
	return state

func _apply_save_state(state: Dictionary) -> void:
	super._apply_save_state(state)
	buildup = _num(state.get("buildup"), 0.0)

func _add(amount: float) -> void:
	buildup += amount
	if buildup >= threshold:
		buildup = 0.0
		_popup(burst_popup_key, popup_color)
		host.apply_status_damage(get_burst_damage())
