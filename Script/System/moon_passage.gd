@tool
extends Interactable
class_name MoonPassage

# 지상층의 달빛 통로. interact로 열고 닫는다 (대화 선택지로 한 번 묻는다).
# 열려 있으면 달빛이 엘리베이터 갱도로 들어와 달의 위상(MoonPhase) 효과가 모든 층에 적용된다:
# 적이 강해지고 변이체·변이 상자 보상이 늘고, 위상별 MoonGate가 열리고, 보름달 밤에는 늑대가 정체를 드러낸다.
# 상태는 GameManager.moon_passage_open (저장됨). 원점 = 바닥 중앙. 그림이 없으면 임시 덮개를 그린다.

const EVENT_OPEN := "moon_passage_open"
const EVENT_CLOSE := "moon_passage_close"
const COLOR_HATCH := Color(0.35, 0.3, 0.26)
const COLOR_FRAME := Color(0.18, 0.15, 0.13)
const COLOR_LIGHT := Color(1.0, 0.96, 0.78, 0.35)

@export_file("*.json") var dialogue_file: String = "res://resources/Dialogues/en/moon_passage.json"
@export var block_ask_open: String = "ask_open"
@export var block_ask_close: String = "ask_close"
@export var width: float = 48.0:
	set(value):
		width = value
		queue_redraw()
@export var closed_texture: Texture2D
@export var open_texture: Texture2D
@export var toggle_sound: AudioStream
@export var tutorial_key: StringName = &"TUTORIAL_MOON_PASSAGE" # 처음 다가갔을 때 한 번

var _busy: bool = false

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	super._ready()
	GameManager.moon_changed.connect(queue_redraw)

func _on_player_entered(_body: Node) -> void:
	Tutorials.show_once(self, tutorial_key)

func _can_interact() -> bool:
	return not _busy and not DialogueManager.is_dialogue_active

func _on_interact() -> void:
	_busy = true
	var want_open := not GameManager.moon_passage_open
	var chosen := [false]
	var on_event := func(event_name: String) -> void:
		if event_name == (EVENT_OPEN if want_open else EVENT_CLOSE):
			chosen[0] = true
	DialogueManager.dialogue_event.connect(on_event)
	var asked := false
	if DialogueManager.has_dialogue_file(dialogue_file) and DialogueManager.start_dialogue(dialogue_file, block_ask_open if want_open else block_ask_close):
		asked = true
		await DialogueManager.dialogue_finished
	DialogueManager.dialogue_event.disconnect(on_event)
	if chosen[0] or not asked:
		set_open(want_open)
	_busy = false

func set_open(open: bool) -> void:
	GameManager.set_moon_passage(open)
	PlayLog.event("moon_passage", {"open": open})
	if toggle_sound != null:
		var sound := AudioStreamPlayer2D.new()
		sound.stream = toggle_sound
		sound.bus = &"SFX"
		add_child(sound)
		sound.finished.connect(sound.queue_free)
		sound.play()
	queue_redraw()

func _is_open() -> bool:
	return not Engine.is_editor_hint() and GameManager.moon_passage_open

func _draw() -> void:
	var open := _is_open()
	var tex := open_texture if open else closed_texture
	if tex != null:
		draw_texture(tex, Vector2(-tex.get_width() * 0.5, -tex.get_height()))
		return
	var frame := Rect2(-width * 0.5, -10.0, width, 10.0)
	draw_rect(frame, COLOR_FRAME)
	if open:
		# 위에서 들어오는 달빛 기둥
		draw_rect(Rect2(-width * 0.5 + 4.0, -200.0, width - 8.0, 190.0), COLOR_LIGHT)
		draw_rect(Rect2(-width * 0.5 + 2.0, -8.0, 6.0, 6.0), COLOR_HATCH)
		draw_rect(Rect2(width * 0.5 - 8.0, -8.0, 6.0, 6.0), COLOR_HATCH)
	else:
		draw_rect(Rect2(-width * 0.5 + 2.0, -8.0, width - 4.0, 6.0), COLOR_HATCH)
