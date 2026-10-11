extends StatusEffect
class_name BreathEffect

# 호흡: 물속(submerged)에 있으면 줄고, 다 떨어지면 drown_interval마다 drown_damage씩 입는다.
# 물 밖으로 나오면 refill_time 만에 가득 차고, 가득 차면 사라진다. 플레이어가 매 프레임 submerged를 정한다.
# 게이지는 다른 상태이상처럼 몸 왼쪽에 진한 파란색으로, warn_below 아래면 깜빡인다.

@export var max_breath: float = 10.0      # 물속에서 버티는 시간(초)
@export var refill_time: float = 2.0      # 물 밖에서 가득 차기까지(초)
@export var drown_damage: int = 5
@export var drown_interval: float = 1.0
@export_range(0.0, 1.0) var warn_below: float = 0.3

var breath: float = 10.0
var submerged: bool = true
var _drown_accum: float = 0.0

func _init() -> void:
	id = &"breath"
	duration = 0.0
	tick_interval = 0.0
	bar_color = Color(0.08, 0.2, 0.7)

func _on_applied() -> void:
	breath = max_breath
	_drown_accum = 0.0

func _on_process(delta: float) -> void:
	if submerged:
		var left_before := breath
		breath = maxf(0.0, breath - delta)
		if breath <= 0.0:
			_drown_accum += delta - left_before # 숨이 떨어진 뒤의 시간만 센다
			while _drown_accum >= drown_interval and _host_alive():
				_drown_accum -= drown_interval
				host.apply_status_damage(drown_damage)
	else:
		_drown_accum = 0.0
		breath = minf(max_breath, breath + max_breath / maxf(refill_time, 0.01) * delta)

func is_finished() -> bool:
	return super.is_finished() or (not submerged and breath >= max_breath)

func get_progress() -> float:
	return clampf(breath / max_breath, 0.0, 1.0) if max_breath > 0.0 else 0.0

func is_bar_warning() -> bool:
	return get_progress() < warn_below

func _get_save_state() -> Dictionary:
	var state := super._get_save_state()
	state["breath"] = breath
	state["submerged"] = submerged
	state["drown_accum"] = _drown_accum
	return state

func _apply_save_state(state: Dictionary) -> void:
	super._apply_save_state(state)
	breath = _num(state.get("breath"), max_breath)
	submerged = state.get("submerged", false) == true
	_drown_accum = _num(state.get("drown_accum"), 0.0)
