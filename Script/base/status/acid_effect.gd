extends StatusEffect
class_name AcidEffect

# 산성: duration초 동안 플레이어 검 공격력이 attack_modifier만큼 줄어든다 (2탄 보스 산성 플라스크).
# 다시 걸리면 지속시간만 처음부터.

func _init() -> void:
	id = &"acid"
	popup_key = &"STATUS_ACID"
	popup_color = Color(0.45, 0.9, 0.2)
	duration = 10.0
	tick_interval = 0.0
	attack_modifier = -5
	bar_color = Color(0.45, 0.9, 0.2)

func _on_applied() -> void:
	_popup(popup_key, popup_color)
