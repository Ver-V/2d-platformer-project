extends StatusEffect
class_name PoisonEffect

# 독: tick_interval마다 tick_damage씩, 총 duration 동안. 다시 걸리면 지속시간만 처음부터.
# 플레이어가 걸려 있는 동안 화면 가장자리가 보라색으로 점멸한다(screen_tint).

@export var tick_damage: int = 1
@export_range(0.0, 1.0) var warn_below: float = 0.25 # 남은 시간이 이 비율 아래면 게이지 깜빡임

func _init() -> void:
	id = &"poison"
	popup_key = &"STATUS_POISONED"
	popup_color = Color.PURPLE
	duration = 20.0
	tick_interval = 1.0
	screen_tint = Color(0.55, 0.1, 0.8)
	bar_color = Color(0.7, 0.25, 1.0)

func _on_applied() -> void:
	_popup(popup_key, popup_color)

func _on_tick() -> void:
	host.apply_status_damage(tick_damage)

func is_bar_warning() -> bool:
	return get_progress() < warn_below
