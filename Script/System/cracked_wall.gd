@tool
extends StaticBody2D
class_name CrackedWall

# 금 간 벽: 강공격(HitData.is_heavy — 수상한 과학자의 약물로 배운다)으로만 부서진다. 그냥 때리면 꿈쩍도 안 하고 힌트를 띄운다.
# 메트로베니아식 길막: 처음엔 못 부수고, 강공격을 배운 뒤 돌아와서 연다.
# 원점 = 벽 바닥 중앙. 크기는 width_tiles × height_tiles (몸 충돌과 Hurtbox가 같이 바뀐다).
# 그림(texture)이 타일 한 칸(16x16)이면 칸마다 반복해서 깔고(1x3이면 같은 그림 3장), 그보다 크면 벽 크기에 맞춰 한 장으로 그린다.
# 비워두면 금 간 회색 벽을 임시로 그린다.
# 부서지면 GameManager.collected_items에 "wall:<persist_id>"로 남아 다시 나오지 않는다.

const TILE := 16.0
const HINT_COOLDOWN_MS := 2000 # 그냥 때릴 때 힌트를 너무 자주 띄우지 않게
const COLOR_PLACEHOLDER := Color(0.42, 0.4, 0.45)
const COLOR_CRACK := Color(0.12, 0.1, 0.14)

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
@export var break_sound: AudioStream = preload("res://Assets/sounds/environment/brokenwall.wav")
@export var persist_id: String = ""
@export var tutorial_key: StringName = &"TUTORIAL_CRACKED_WALL" # 처음 부쉈을 때 한 번

const HIT_DUST_SHADER: Shader = preload("res://resources/Shaders/box_hit_dust.gdshader")

var _shape := RectangleShape2D.new()
var _last_hint_ms: int = -HINT_COOLDOWN_MS
var _broken: bool = false

func _ready() -> void:
	_apply_size()
	if Engine.is_editor_hint():
		return
	if GameManager.collected_items.has(save_id()):
		queue_free()

func size() -> Vector2:
	return Vector2(width_tiles, height_tiles) * TILE

# 몸 충돌과 Hurtbox가 같은 사각형을 쓴다 (씬에 저장되지 않는 런타임 shape)
func _apply_size() -> void:
	if not is_inside_tree():
		return
	_shape.size = size()
	for path in [^"CollisionShape2D", ^"Hurtbox/CollisionShape2D"]:
		var cs := get_node_or_null(path) as CollisionShape2D
		if cs:
			cs.shape = _shape
			cs.position = Vector2(0, -size().y * 0.5)
	queue_redraw()

func save_id() -> String:
	if not persist_id.is_empty():
		return "wall:" + persist_id
	var scene := get_tree().current_scene if is_inside_tree() else null
	return "wall:%s:%s" % [scene.scene_file_path if scene != null else "", get_path()]

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
	draw_rect(rect, COLOR_CRACK, false, 1.0)
	# 지그재그 금
	var x := rect.position.x + rect.size.x * 0.55
	var y := rect.position.y + 2.0
	var step := 0
	while y < rect.end.y - 2.0:
		var nx := x + (3.0 if step % 2 == 0 else -4.0)
		var ny := minf(y + 6.0, rect.end.y - 2.0)
		draw_line(Vector2(x, y), Vector2(nx, ny), COLOR_CRACK, 1.0)
		x = nx
		y = ny
		step += 1

# 강공격이면 부서진다(KILLED → 히트스탑, 반격 보너스가 있었으면 소모). 아니면 막힌다(GUARDED → 보너스는 그대로)
func receive_hit(hit: HitData) -> HitData.Result:
	if _broken or hit.amount <= 0:
		return HitData.Result.IGNORED
	if not hit.is_heavy:
		_show_hint(hit.source)
		_emit_dust(4)
		return HitData.Result.GUARDED
	_broken = true
	GameManager.add_collected_item(save_id())
	_emit_dust(24)
	_play_break_sound()
	Tutorials.show_once(self, tutorial_key)
	queue_free()
	return HitData.Result.KILLED

func _show_hint(source: Node) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_hint_ms < HINT_COOLDOWN_MS:
		return
	_last_hint_ms = now
	if is_instance_valid(source) and source.has_method("show_popup"):
		source.show_popup(tr(&"WALL_NEEDS_COUNTER"), Color.LIGHT_GRAY)

func _emit_dust(amount: int) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var mat := ShaderMaterial.new()
	mat.shader = HIT_DUST_SHADER
	mat.set_shader_parameter("dust_color", COLOR_PLACEHOLDER)
	var dust := CPUParticles2D.new()
	dust.emitting = false
	dust.material = mat
	dust.amount = amount
	dust.lifetime = 0.5
	dust.one_shot = true
	dust.explosiveness = 1.0
	dust.direction = Vector2.UP
	dust.spread = 180.0
	dust.gravity = Vector2(0, 200)
	dust.initial_velocity_min = 40.0
	dust.initial_velocity_max = 110.0
	dust.scale_amount_min = 2.0
	dust.scale_amount_max = 4.0
	dust.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	dust.emission_rect_extents = size() * 0.5
	Effects.emit_once(dust, scene, global_position + Vector2(0, -size().y * 0.5))

func _play_break_sound() -> void:
	var scene := get_tree().current_scene
	if scene == null or break_sound == null:
		return
	var sound := AudioStreamPlayer2D.new()
	scene.add_child(sound)
	sound.global_position = global_position
	sound.bus = &"SFX"
	sound.stream = break_sound
	sound.finished.connect(sound.queue_free)
	sound.play()
