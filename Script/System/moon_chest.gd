extends Chest
class_name MoonChest

# 달의 위상에 따라서만 나타나는 상자 (기본: 그믐달 전용). 체크한 위상(appear_on_full / appear_on_half / appear_on_new)인 밤에만
# 보이고 열 수 있다. requires_passage가 켜져 있으면 지상 통로가 열려 달빛이 들어올 때만 (MoonGate와 같은 규칙).
# 위상이 바뀌면(기다리기·휴식) 흐려지며 사라지거나 다시 나타난다. 열었으면 일반 상자처럼 저장된다 (chest:<persist_id>).
# 나머지(보상·잠금·연출)는 Chest와 같다. 씬: Scenes/System/MoonChest.tscn (Chest.tscn을 상속).

const FADE_TIME := 0.6

@export var appear_on_full: bool = false
@export var appear_on_half: bool = false
@export var appear_on_new: bool = true
@export var requires_passage: bool = true

var is_present: bool = false
var _fade: Tween

func _ready() -> void:
	super()
	if is_queued_for_deletion():
		return
	GameManager.moon_changed.connect(refresh)
	refresh(true)

func appears_on(phase: MoonPhase.Phase) -> bool:
	match phase:
		MoonPhase.Phase.FULL: return appear_on_full
		MoonPhase.Phase.HALF: return appear_on_half
		MoonPhase.Phase.NEW: return appear_on_new
	return false

func should_appear() -> bool:
	if _opened:
		return true # 연 상자는 (아이템을 안 주웠으면) 위상과 상관없이 남는다
	if requires_passage and not GameManager.moon_passage_open:
		return false
	return appears_on(GameManager.moon_phase())

# 지금 위상에 맞게 보이기·숨기기. instant면 연출 없이 바로
func refresh(instant: bool = false) -> void:
	var present := should_appear()
	if present == is_present and not instant:
		return
	is_present = present
	set_deferred("monitoring", present and not _opened)
	if present:
		add_to_group("minimap_chest")
	else:
		remove_from_group("minimap_chest")
		if player_in_range:
			_hide_prompt()
	if _fade and _fade.is_valid():
		_fade.kill()
	if instant:
		visible = present
		modulate.a = 1.0
		return
	visible = true
	_fade = create_tween()
	_fade.tween_property(self, "modulate:a", 1.0 if present else 0.0, FADE_TIME).from(0.0 if present else 1.0)
	if not present:
		_fade.tween_callback(func(): visible = false)

func _on_player_entered(_body: Node) -> void:
	if is_present:
		Tutorials.show_once(self, &"TUTORIAL_MOON_CHEST")

func _show_prompt() -> void:
	if is_present:
		super()

func _can_interact() -> bool:
	return is_present and super()
