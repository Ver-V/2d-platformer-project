extends Control
class_name MoonIcon

# HUD 구석의 달 아이콘. 지상 통로가 열려 달빛이 들어올 때만 보이고, 지금 위상(MoonPhase)을 그린다.
# 닫혀 있으면 위상이 아무 효과도 없으므로 숨긴다.
# 그림이 생기면 textures에 위상 순서(보름달, 반달, 그믐달)대로 넣으면 그걸 쓴다.

const SIZE := 18.0
const COLOR_LIGHT := Color(1.0, 0.96, 0.78)
const COLOR_DARK := Color(0.16, 0.17, 0.26)
const COLOR_GLOW := Color(1.0, 0.95, 0.7, 0.25)

@export var textures: Array[Texture2D] = []

func _ready() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gm := get_node_or_null("/root/GameManager")
	if gm != null:
		gm.moon_changed.connect(_refresh)
	_refresh()

func _refresh() -> void:
	var gm := get_node_or_null("/root/GameManager")
	var lit: bool = gm != null and gm.moon_passage_open
	visible = lit
	var phase: MoonPhase.Phase = gm.moon_phase() if gm != null else MoonPhase.Phase.FULL
	tooltip_text = tr(MoonPhase.NAME_KEYS[phase])
	queue_redraw()

func _draw() -> void:
	var gm := get_node_or_null("/root/GameManager")
	var phase: MoonPhase.Phase = gm.moon_phase() if gm != null else MoonPhase.Phase.FULL
	var idx := MoonPhase.CYCLE.find(phase)
	if idx >= 0 and idx < textures.size() and textures[idx] != null:
		draw_texture_rect(textures[idx], Rect2(Vector2.ZERO, size), false)
		return
	var c := size * 0.5
	var r := SIZE * 0.5 - 2.0
	draw_circle(c, r + 2.0, COLOR_GLOW)
	draw_circle(c, r, COLOR_DARK)
	match phase:
		MoonPhase.Phase.FULL:
			draw_circle(c, r, COLOR_LIGHT)
		MoonPhase.Phase.HALF:
			# 오른쪽 반만 밝다
			var pts := PackedVector2Array()
			for i in 17:
				var a := -PI * 0.5 + PI * float(i) / 16.0
				pts.append(c + Vector2(cos(a), sin(a)) * r)
			draw_colored_polygon(pts, COLOR_LIGHT)
		MoonPhase.Phase.NEW:
			# 거의 보이지 않는 가는 테두리만
			draw_arc(c, r, 0.0, TAU, 24, Color(COLOR_LIGHT, 0.35), 1.0)
