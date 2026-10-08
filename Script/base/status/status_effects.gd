extends Node
class_name StatusEffects

# CombatBody2D에 붙는 상태이상 관리자. 플레이어·적 공통.
# 거는 쪽(적 접촉, 나중에 무기 등)은 apply()만 부르고, 진행·피해·해제는 여기서 처리한다.
# 몸체에서 CombatBody2D.get_status_effects()로 필요할 때 만들어진다.

signal effect_added(effect: StatusEffect)
signal effect_removed(id: StringName)

var _effects: Dictionary = {} # id -> StatusEffect (대상별 사본)

func _host() -> CombatBody2D:
	return get_parent() as CombatBody2D

# template은 공유 설정이므로 그대로 쓰지 않고 사본을 만든다. 걸린(또는 갱신된) 사본을 돌려준다.
func apply(template: StatusEffect) -> StatusEffect:
	var host := _host()
	if template == null or host == null or host.hp <= 0:
		return null
	if template.id == &"":
		push_warning("StatusEffect without id: %s" % template.resource_path)
		return null

	var current: StatusEffect = _effects.get(template.id)
	if current != null:
		current.reapply(template)
		_drop_if_finished(current)
		return current

	var effect: StatusEffect = template.duplicate()
	_effects[effect.id] = effect
	effect.setup(host)
	effect_added.emit(effect)
	_drop_if_finished(effect)
	return effect

func has(id: StringName) -> bool:
	return _effects.has(id)

func get_effect(id: StringName) -> StatusEffect:
	return _effects.get(id)

func get_ids() -> Array:
	return _effects.keys()

func get_effects() -> Array:
	return _effects.values()

func remove(id: StringName) -> void:
	var effect: StatusEffect = _effects.get(id)
	if effect == null:
		return
	_effects.erase(id)
	effect.remove()
	effect_removed.emit(id)

# 씬 이동용: 진행 중인 효과를 해제 처리(_on_removed) 없이 떼어 내 돌려준다
func detach_all() -> Array[StatusEffect]:
	var out: Array[StatusEffect] = []
	for effect: StatusEffect in _effects.values():
		effect.detach()
		out.append(effect)
	_effects.clear()
	return out

# detach_all()로 떼어 낸 효과를 진행 상태 그대로 다시 붙인다
func attach_all(effects: Array[StatusEffect]) -> void:
	var host := _host()
	if host == null or host.hp <= 0:
		return
	for effect in effects:
		if effect == null or effect.id == &"" or _effects.has(effect.id):
			continue
		_effects[effect.id] = effect
		effect.attach(host)
		effect_added.emit(effect)

func clear_all() -> void:
	for id in _effects.keys():
		remove(id)

func _physics_process(delta: float) -> void:
	if _effects.is_empty():
		return
	var host := _host()
	if host == null or not host.can_tick_status_effects():
		return
	for effect: StatusEffect in _effects.values():
		if not _effects.has(effect.id):
			continue # 앞선 효과의 피해로 사망해 clear된 경우
		effect.advance(delta)
		_drop_if_finished(effect)

func _drop_if_finished(effect: StatusEffect) -> void:
	if _effects.get(effect.id) == effect and effect.is_finished():
		remove(effect.id)
