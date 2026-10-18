extends StatusEffect
class_name DrowsyEffect

# 졸음: 양의 울음소리 범위(Sheep의 BleatArea) 안에 있는 동안 초당 buildup_per_sec씩 게이지가 찬다 (expose).
# threshold에 닿으면 sleep_time초 동안 잠든다 — 플레이어는 조작이 막히고 머리 위에 Zzz... 말풍선이 뜬다.
# 깨어나면(시간이 다 되거나, 자는 중에 맞으면 — wake) 게이지가 0이 되어 사라진다. 울음소리를 decay_delay초 넘게 안 들으면 decay_per_sec씩 줄고, 0이 되면 사라진다.
# 게이지: 깨어 있을 땐 쌓인 양, 자는 동안엔 남은 잠 시간. warn_above 이상이면 깜빡인다.

@export var buildup_per_sec: float = 20.0
@export var buildup_per_hit: float = 0.0 # 맞을 때마다 한 번에 쌓이는 양 (늑대의 잠 탄환 = 40). 0이면 울음소리(expose)로만 쌓인다
@export var threshold: float = 100.0
@export var sleep_time: float = 5.0
@export var boss_sleep_time: float = 2.5 # 보스("bosses" 그룹)가 잠들 때 (반사된 잠 탄환 등)
@export var decay_delay: float = 1.0
@export var decay_per_sec: float = 10.0
@export_range(0.0, 1.0) var warn_above: float = 0.7

var buildup: float = 0.0
var asleep: bool = false
var sleep_left: float = 0.0
var _since_exposed: float = 0.0
var _sleep_total: float = 0.0

func _init() -> void:
	tutorial_key = &"TUTORIAL_STATUS_DROWSY"
	id = &"drowsy"
	duration = 0.0
	tick_interval = 0.0
	bar_color = Color(0.72, 0.72, 0.82) # 옅은 회보라 (회색 바탕 게이지 칸과 구분되게 살짝 푸른 기)

# 울음소리를 delta초 동안 들었다. 자는 동안은 더 쌓이지 않는다
func expose(delta: float) -> void:
	_since_exposed = 0.0
	if asleep or not _host_alive():
		return
	_add(buildup_per_sec * delta)

func _on_applied() -> void:
	_add(buildup_per_hit)

func _on_reapplied(incoming: StatusEffect) -> void:
	if incoming is DrowsyEffect:
		_add(incoming.buildup_per_hit)

func _scale_strength(factor: float) -> void:
	buildup_per_hit *= factor

func _add(amount: float) -> void:
	_since_exposed = 0.0
	if amount <= 0.0 or asleep or not _host_alive():
		return
	buildup = minf(buildup + amount, threshold)
	if buildup >= threshold:
		asleep = true # 플레이어가 매 프레임 is_asleep()을 보고 조작을 막는다
		_sleep_total = boss_sleep_time if host.is_in_group("bosses") else sleep_time
		sleep_left = _sleep_total

func _on_process(delta: float) -> void:
	if asleep:
		sleep_left -= delta
		if sleep_left <= 0.0:
			asleep = false
			buildup = 0.0
		return
	_since_exposed += delta
	if _since_exposed > decay_delay:
		buildup = maxf(0.0, buildup - decay_per_sec * delta)

# 자는 중에 맞으면 바로 깬다 (Player._after_damaged). 독 같은 상태이상 피해로는 깨지 않는다
func wake() -> void:
	if not asleep:
		return
	asleep = false
	sleep_left = 0.0
	buildup = 0.0

func is_finished() -> bool:
	return super.is_finished() or (not asleep and buildup <= 0.0 and _since_exposed > 0.0)

func is_asleep() -> bool:
	return asleep

func get_progress() -> float:
	if asleep:
		return clampf(sleep_left / _sleep_total, 0.0, 1.0) if _sleep_total > 0.0 else 0.0
	return clampf(buildup / threshold, 0.0, 1.0) if threshold > 0.0 else 0.0

func is_bar_warning() -> bool:
	return not asleep and get_progress() >= warn_above

func _get_save_state() -> Dictionary:
	var state := super._get_save_state()
	state["buildup"] = buildup
	state["asleep"] = asleep
	state["sleep_left"] = sleep_left
	state["since_exposed"] = _since_exposed
	return state

func _apply_save_state(state: Dictionary) -> void:
	super._apply_save_state(state)
	buildup = _num(state.get("buildup"), 0.0)
	asleep = state.get("asleep", false) == true
	sleep_left = _num(state.get("sleep_left"), 0.0)
	_sleep_total = sleep_time
	_since_exposed = _num(state.get("since_exposed"), 0.0)
