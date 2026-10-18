@tool
extends StaticBody2D
class_name MoonGate

# 달의 위상에 따라 열리는 벽: 체크한 위상(open_on_full / open_on_half / open_on_new)인 밤에만 길이 열린다.
# requires_passage가 켜져 있으면 지상 통로가 열려 달빛이 들어올 때만 열린다 (GameManager.moon_passage_open).
# 히든 보상을 숨겨 두는 용도. 열림 상태는 저장하지 않는다 — 위상(휴식·부활)이 바뀌면 다시 닫히거나 열린다.
# 원점 = 벽 바닥 중앙. 크기는 width_tiles × height_tiles. 그림(texture)이 16x16이면 칸마다 반복, 비우면 임시 그림.

const TILE := 16.0
const COLOR_PLACEHOLDER := Color(0.2, 0.22, 0.36)
const COLOR_RUNE := Color(0.95, 0.9, 0.6)
const OPEN_ALPHA := 0.18 # 열렸을 때 남는 흔적
const FADE_TIME := 0.6

@export_range(1, 16) var width_tiles: int = 1:
	set(value):
		width_tiles = value
		_apply_size()
@export_range(1, 16) var height_tiles: int = 3:
	set(value):
		height_tiles = value
		_apply_size()
@export var texture: Texture2D:
	set(value):
		texture = value
		queue_redraw()
@export var open_on_full: bool = true
@export var open_on_half: bool = false
@export var open_on_new: bool = false
@export var requires_passage: bool = true
@export var tutorial_key: StringName = &"TUTORIAL_MOON_GATE" # 플레이어가 처음 가까이 왔을 때 한 번
const TUTORIAL_RANGE := 96.0 # 이 거리(px, 6타일) 안에 들어오면

var is_open: bool = false
var _shape := RectangleShape2D.new()
var _tween: Tween

func _ready() -> void:
	_apply_size()
	if Engine.is_editor_hint():
		return
	GameManager.moon_changed.connect(refresh)
	refresh(true)
	set_physics_process(tutorial_key != &"" and not GameManager.has_seen_tutorial(String(tutorial_key)))

# 처음 다가오면 도움말 (한 번 띄우면 더 확인하지 않는다)
func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null or player.global_position.distance_to(global_position + Vector2(0, -size().y * 0.5)) > TUTORIAL_RANGE:
		return
	Tutorials.show_once(self, tutorial_key)
	set_physics_process(false)

func size() -> Vector2:
	return Vector2(width_tiles, height_tiles) * TILE

func _apply_size() -> void:
	if not is_inside_tree():
		return
	_shape.size = size()
	var cs := get_node_or_null(^"CollisionShape2D") as CollisionShape2D
	if cs:
		cs.shape = _shape
		cs.position = Vector2(0, -size().y * 0.5)
	queue_redraw()

func opens_on(phase: MoonPhase.Phase) -> bool:
	match phase:
		MoonPhase.Phase.FULL: return open_on_full
		MoonPhase.Phase.HALF: return open_on_half
		MoonPhase.Phase.NEW: return open_on_new
	return false

func should_open() -> bool:
	if requires_passage and not GameManager.moon_passage_open:
		return false
	return opens_on(GameManager.moon_phase())

func refresh(instant: bool = false) -> void:
	var open := should_open()
	if open == is_open and not instant:
		return
	is_open = open
	var cs := get_node_or_null(^"CollisionShape2D") as CollisionShape2D
	if cs:
		cs.set_deferred("disabled", open)
	var alpha := OPEN_ALPHA if open else 1.0
	if _tween:
		_tween.kill()
	if instant or not is_inside_tree():
		modulate.a = alpha
	else:
		_tween = create_tween()
		_tween.tween_property(self, "modulate:a", alpha, FADE_TIME)

func _draw() -> void:
	var rect := Rect2(Vector2(-size().x * 0.5, -size().y), size())
	if texture != null:
		if texture.get_size() == Vector2(TILE, TILE):
			for y in height_tiles:
				for x in width_tiles:
					draw_texture_rect(texture, Rect2(rect.position + Vector2(x, y) * TILE, Vector2(TILE, TILE)), false)
		else:
			draw_texture_rect(texture, rect, false)
		return
	draw_rect(rect, COLOR_PLACEHOLDER)
	draw_rect(rect, COLOR_RUNE * Color(1, 1, 1, 0.5), false, 1.0)
	# 가운데 초승달 문양
	var c := rect.get_center()
	var r := minf(rect.size.x, rect.size.y) * 0.25
	draw_circle(c, r, COLOR_RUNE)
	draw_circle(c + Vector2(r * 0.45, -r * 0.2), r * 0.85, COLOR_PLACEHOLDER)
