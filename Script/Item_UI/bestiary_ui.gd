extends CanvasLayer
class_name BestiaryUI

# 몬스터 도감 ([B]): 한 번이라도 잡은 몹·보스는 이름·처치 수·스탯(체력·몸통 피해·속도·금화)·맞으면 거는 상태이상·보스 보상,
# 맞지 않고 잡은 보스는 ★ 노히트가 보인다. 아직 못 잡은 종류는 ???. 목록 순서·이름은 Bestiary.
# HUD가 자식으로 만든다 (오토로드 추가 없이). 스테이지(BaseStage) 안에서만 열린다.

const ACTION := &"bestiary"
const LAYER := 90

var is_open: bool = false
var _panel: PanelContainer
var _list: VBoxContainer

func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_action()
	_build()
	visible = false

# 프로젝트 설정을 건드리지 않고 [B] 키를 등록한다 (이미 있으면 그대로)
static func _ensure_action() -> void:
	if InputMap.has_action(ACTION):
		return
	InputMap.add_action(ACTION)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_B
	InputMap.action_add_event(ACTION, key)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(ACTION):
		if is_open:
			close()
		elif not GameManager.is_menu_open and get_tree().current_scene is BaseStage:
			open()
		get_viewport().set_input_as_handled()
	elif is_open and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

func open() -> void:
	refresh()
	visible = true
	is_open = true
	GameManager.ui_opened(self, true)

func close() -> void:
	if not is_open:
		return
	visible = false
	is_open = false
	GameManager.ui_closed(self)

func _exit_tree() -> void:
	if is_open:
		GameManager.ui_closed(self)

# 목록을 지금 기록으로 다시 채운다
func refresh() -> void:
	for c in _list.get_children():
		c.queue_free()
	for kind in Bestiary.KINDS:
		_list.add_child(_entry(Bestiary.kind_path(kind)))

func _entry(path: String) -> Control:
	var box := VBoxContainer.new()
	var kills := GameManager.kill_count(path)
	var title := Label.new()
	title.add_theme_font_size_override("font_size", 16)
	box.add_child(title)
	if kills <= 0:
		title.text = tr(&"BESTIARY_UNKNOWN")
		title.modulate = Color(0.5, 0.5, 0.5)
		return box
	var info := Bestiary.info(path)
	var head: String = info.get("name", path.get_file())
	head += "    " + tr(&"BESTIARY_KILLS").format({"n": kills})
	if info.get("is_boss", false) and GameManager.nohit_bosses.get(str(info.get("persist_id", "")), false):
		head += "    " + tr(&"BESTIARY_NOHIT")
	title.text = head
	var stats := Label.new()
	stats.text = tr(&"BESTIARY_STATS").format({
		"hp": info.get("hp", 0), "damage": info.get("damage", 0), "speed": int(info.get("speed", 0.0)), "gold": info.get("gold", 0),
	})
	stats.modulate = Color(0.8, 0.8, 0.85)
	box.add_child(stats)
	var status: StringName = info.get("status", &"")
	if status != &"":
		var s := Label.new()
		s.text = tr(&"BESTIARY_STATUS").format({
			"status": DeathCause.describe("status:" + String(status)), "chance": roundi(float(info.get("status_chance", 0.0)) * 100.0),
		})
		s.modulate = Color(0.8, 0.8, 0.85)
		box.add_child(s)
	if String(info.get("reward", "")) != "":
		var r := Label.new()
		r.text = tr(&"BESTIARY_REWARD").format({"item": info.reward})
		r.modulate = Color(1.0, 0.85, 0.5)
		box.add_child(r)
	return box

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.offset_left = 160
	_panel.offset_right = -160
	_panel.offset_top = 60
	_panel.offset_bottom = -60
	add_child(_panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	_panel.add_child(margin)
	var col := VBoxContainer.new()
	margin.add_child(col)
	var title := Label.new()
	title.text = "BESTIARY_TITLE"
	title.add_theme_font_size_override("font_size", 22)
	col.add_child(title)
	var hint := Label.new()
	hint.text = "BESTIARY_HINT"
	hint.modulate = Color(0.7, 0.7, 0.7)
	col.add_child(hint)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 10)
	scroll.add_child(_list)
