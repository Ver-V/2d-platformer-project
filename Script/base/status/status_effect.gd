extends Resource
class_name StatusEffect

# 상태이상 하나의 설정 + 진행 상태. 적·무기·아이템에는 "설정"으로 붙여 두고,
# 걸릴 때 StatusEffects가 duplicate()한 사본이 대상마다 따로 진행된다.
# 새 상태이상은 이 클래스를 상속해 _on_* 훅만 구현하면 된다.

const TICK_EPSILON := 0.0001
const SAVE_SCRIPT_DIR := "res://Script/base/status/" # 세이브에서 불러올 수 있는 상태이상 스크립트 위치

@export var id: StringName = &""
@export var popup_key: StringName = &""          # 걸렸을 때 머리 위에 띄울 번역 키 (비우면 없음)
@export var popup_color: Color = Color.WHITE
@export var duration: float = 0.0                # 0 이하면 시간 제한 없음 (is_finished로 끝을 정함)
@export var tick_interval: float = 0.0           # 0 이하면 틱 없음
@export var screen_tint: Color = Color(0, 0, 0, 0) # 플레이어가 걸려 있는 동안 화면 가장자리 점멸 색 (알파 0이면 없음)
@export var bar_color: Color = Color.WHITE        # 플레이어 옆 상태이상 게이지 색 (get_progress 만큼 채움)

var host: CombatBody2D
var elapsed: float = 0.0
var _tick_accum: float = 0.0

func setup(target: CombatBody2D) -> void:
	host = target
	elapsed = 0.0
	_tick_accum = 0.0
	_on_applied()

# 씬 이동 때 진행 상태(경과 시간·틱 누적·게이지)를 그대로 둔 채 새 몸체로 옮긴다. _on_applied는 다시 부르지 않는다.
func attach(target: CombatBody2D) -> void:
	host = target

func detach() -> void:
	host = null

# 같은 id가 이미 걸려 있을 때 새로 들어온 설정(incoming)으로 갱신. 기본은 지속시간 리셋.
func reapply(incoming: StatusEffect) -> void:
	elapsed = 0.0
	_on_reapplied(incoming)

func advance(delta: float) -> void:
	elapsed += delta
	_on_process(delta)
	if tick_interval > 0.0:
		_tick_accum += delta
		# 만료되는 프레임의 마지막 틱도 들어가도록 지속시간이 아니라 대상 생존만 본다 (오차 허용)
		while _tick_accum >= tick_interval - TICK_EPSILON and _host_alive():
			_tick_accum -= tick_interval
			_on_tick()

func _host_alive() -> bool:
	return host != null and is_instance_valid(host) and host.hp > 0

func is_finished() -> bool:
	if not _host_alive():
		return true
	return duration > 0.0 and elapsed >= duration - TICK_EPSILON

func remove() -> void:
	_on_removed()
	host = null

# 0~1, HUD 등에서 남은 양 표시용
func get_progress() -> float:
	return 1.0 - clampf(elapsed / duration, 0.0, 1.0) if duration > 0.0 else 1.0

# true면 플레이어 옆 게이지가 깜빡인다 (곧 끝남·곧 터짐 등 주의 표시)
func is_bar_warning() -> bool:
	return false

# --- 세이브 ---
# {"script": 스크립트 경로, "props": export 설정값, "state": 진행 상태}. JSON에 들어갈 수 있는 값만 쓴다.
func to_save() -> Dictionary:
	var props := {}
	for p in get_property_list():
		if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and p.usage & PROPERTY_USAGE_STORAGE:
			var v: Variant = _encode_value(get(p.name))
			if v != null:
				props[p.name] = v
	return {"script": get_script().resource_path, "props": props, "state": _get_save_state()}

# 잘못된 데이터면 null. 스크립트는 SAVE_SCRIPT_DIR 안의 StatusEffect만 허용한다.
static func from_save(data: Dictionary) -> StatusEffect:
	var path: Variant = data.get("script")
	if not path is String or not path.begins_with(SAVE_SCRIPT_DIR) or not ResourceLoader.exists(path):
		return null
	var script := load(path) as GDScript
	if script == null or not script.can_instantiate():
		return null
	var effect = script.new()
	if not effect is StatusEffect:
		return null
	var props: Variant = data.get("props", {})
	if props is Dictionary:
		for key in props:
			if key is String and key in effect:
				var v: Variant = _decode_value(props[key], typeof(effect.get(key)))
				if v != null:
					effect.set(key, v)
	var state: Variant = data.get("state", {})
	if state is Dictionary:
		effect._apply_save_state(state)
	return effect

func _get_save_state() -> Dictionary:
	return {"elapsed": elapsed, "tick_accum": _tick_accum}

func _apply_save_state(state: Dictionary) -> void:
	elapsed = _num(state.get("elapsed"), 0.0)
	_tick_accum = _num(state.get("tick_accum"), 0.0)

static func _num(v: Variant, fallback: float) -> float:
	return float(v) if v is float or v is int else fallback

static func _encode_value(v: Variant) -> Variant:
	match typeof(v):
		TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING:
			return v
		TYPE_STRING_NAME:
			return String(v)
		TYPE_COLOR:
			return [v.r, v.g, v.b, v.a]
	return null

# 저장된 값을 현재 속성 타입(want)에 맞춰 되돌린다. 맞지 않으면 null (기본값 유지)
static func _decode_value(v: Variant, want: int) -> Variant:
	match want:
		TYPE_BOOL:
			return v if v is bool else null
		TYPE_INT:
			return int(v) if v is float or v is int else null
		TYPE_FLOAT:
			return float(v) if v is float or v is int else null
		TYPE_STRING:
			return v if v is String else null
		TYPE_STRING_NAME:
			return StringName(v) if v is String else null
		TYPE_COLOR:
			if v is Array and v.size() == 4:
				for c in v:
					if not (c is float or c is int):
						return null
				return Color(v[0], v[1], v[2], v[3])
	return null

# --- 하위 클래스 훅 ---
func _on_applied() -> void: pass
func _on_reapplied(_incoming: StatusEffect) -> void: pass
func _on_process(_delta: float) -> void: pass
func _on_tick() -> void: pass
func _on_removed() -> void: pass

func _popup(key: StringName, color: Color) -> void:
	if key != &"" and host != null and host.has_method("show_popup"):
		host.show_popup(TranslationServer.translate(key), color)
