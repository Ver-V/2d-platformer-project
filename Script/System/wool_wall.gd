@tool
extends Interactable
class_name WoolWall

# 양털 벽: 칼로는 안 베이고, 랜턴(required_item_id)을 장착한 채 interact 키(E)로 불을 붙여야 타서 없어진다.
# 스테이지 2의 랜턴을 다시 쓰게 하는 메트로베니아식 길막.
# 루트(Area2D)는 상호작용 범위(벽보다 양옆으로 INTERACT_MARGIN 넓다), 자식 Body(StaticBody2D)가 길을 막는 몸, Hurtbox는 칼에 맞으면 힌트를 띄운다.
# 원점 = 벽 바닥 중앙. 크기는 width_tiles × height_tiles (세 충돌 모양이 같이 바뀐다).
# 그림(texture)이 타일 한 칸(16x16)이면 칸마다 반복해서 깔고, 그보다 크면 벽 크기에 맞춰 한 장으로 그린다. 비우면 임시 양털 벽을 그린다.
# 다 타면 GameManager.collected_items에 "wool:<persist_id>"로 남는다: 세이브하면 계속 없고, 세이브 전에 죽으면 되살아난다.

const TILE := 16.0
const INTERACT_MARGIN := 12.0
const HINT_COOLDOWN_MS := 2000
const COLOR_WOOL := Color(0.9, 0.88, 0.8)
const COLOR_WOOL_SHADE := Color(0.72, 0.69, 0.62)
const COLOR_FIRE := Color(1.0, 0.55, 0.15)

@export_range(1, 16) var width_tiles: int = 2:
	set(value):
		width_tiles = value
		_apply_size()
@export_range(1, 16) var height_tiles: int = 3:
	set(value):
		height_tiles = value
		_apply_size()
@export var required_item_id: String = "lantern"
@export var burn_time: float = 0.8 # 불이 붙고 다 타서 없어질 때까지
@export var texture: Texture2D:
	set(value):
		texture = value
		queue_redraw()
@export var burn_sound: AudioStream
@export var persist_id: String = ""
@export var tutorial_key: StringName = &"TUTORIAL_WOOL_WALL" # 처음 태웠을 때 한 번

var burning: bool = false
var _burn: float = 0.0 # 0 → 1: 타 들어간 정도
var _last_hint_ms: int = -HINT_COOLDOWN_MS
var _wall_shape := RectangleShape2D.new()
var _range_shape := RectangleShape2D.new()

func _ready() -> void:
	_apply_size()
	set_process(false)
	if Engine.is_editor_hint():
		return
	super._ready()
	if GameManager.collected_items.has(save_id()):
		queue_free()

func size() -> Vector2:
	return Vector2(width_tiles, height_tiles) * TILE

# 몸·Hurtbox는 벽 크기, 상호작용 범위는 양옆으로 조금 넓게 (씬에 저장되지 않는 런타임 shape)
func _apply_size() -> void:
	if not is_inside_tree():
		return
	_wall_shape.size = size()
	_range_shape.size = size() + Vector2(INTERACT_MARGIN * 2.0, 0)
	var center := Vector2(0, -size().y * 0.5)
	for path in [^"Body/CollisionShape2D", ^"Hurtbox/CollisionShape2D"]:
		var cs := get_node_or_null(path) as CollisionShape2D
		if cs:
			cs.shape = _wall_shape
			cs.position = center
	var range_cs := get_node_or_null(^"CollisionShape2D") as CollisionShape2D
	if range_cs:
		range_cs.shape = _range_shape
		range_cs.position = center
	queue_redraw()

func save_id() -> String:
	if not persist_id.is_empty():
		return "wool:" + persist_id
	if not is_inside_tree():
		return "wool:" + str(name)
	var scene := get_tree().current_scene
	return "wool:%s:%s" % [scene.scene_file_path if scene != null else "", get_path()]

# --- 불 붙이기 ---
func _can_interact() -> bool:
	return not burning

func _show_prompt() -> void:
	if not burning:
		super._show_prompt()

func _on_interact() -> void:
	if not get_node("/root/Inventory").is_equipped(required_item_id):
		_show_hint(current_player)
		return
	ignite()

# 불이 붙어 burn_time 동안 타고 사라진다. 길은 다 타고 나서 열린다
func ignite() -> void:
	if burning:
		return
	burning = true
	_burn = 0.0
	GameManager.add_collected_item(save_id())
	_hide_prompt()
	_play_burn_sound()
	_emit_embers()
	Tutorials.show_once(self, tutorial_key)
	set_process(true)

func _process(delta: float) -> void:
	_burn = minf(_burn + (delta / burn_time if burn_time > 0.0 else 1.0), 1.0)
	queue_redraw()
	if _burn >= 1.0:
		set_process(false)
		var body_shape := get_node_or_null(^"Body/CollisionShape2D") as CollisionShape2D
		if body_shape:
			body_shape.set_deferred("disabled", true)
		queue_free()

# 칼로 베면 꿈쩍도 안 한다: 막힘(GUARDED → 반격 보너스는 그대로) + 힌트
func receive_hit(hit: HitData) -> HitData.Result:
	if burning or hit.amount <= 0:
		return HitData.Result.IGNORED
	_show_hint(hit.source)
	return HitData.Result.GUARDED

func _show_hint(target: Node) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_hint_ms < HINT_COOLDOWN_MS:
		return
	_last_hint_ms = now
	if is_instance_valid(target) and target.has_method("show_popup"):
		target.show_popup(tr(&"WOOL_NEEDS_FIRE"), Color.LIGHT_GRAY)

func _play_burn_sound() -> void:
	if burn_sound == null:
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	var sound := AudioStreamPlayer2D.new()
	scene.add_child(sound)
	sound.global_position = global_position
	sound.bus = &"SFX"
	sound.stream = burn_sound
	sound.finished.connect(sound.queue_free)
	sound.play()

func _emit_embers() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var embers := CPUParticles2D.new()
	embers.emitting = false
	embers.amount = 32
	embers.lifetime = 0.9
	embers.one_shot = true
	embers.explosiveness = 0.3
	embers.direction = Vector2.UP
	embers.spread = 30.0
	embers.gravity = Vector2(0, -60)
	embers.initial_velocity_min = 20.0
	embers.initial_velocity_max = 60.0
	embers.scale_amount_min = 1.5
	embers.scale_amount_max = 3.0
	embers.color = COLOR_FIRE
	embers.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	embers.emission_rect_extents = size() * 0.5
	Effects.emit_once(embers, scene, global_position + Vector2(0, -size().y * 0.5))

func _draw() -> void:
	var rect := Rect2(Vector2(-size().x * 0.5, -size().y), size())
	# 타는 동안 주황빛으로 물들며 위에서부터 사라진다
	var tint := COLOR_WOOL.lerp(COLOR_FIRE, minf(_burn * 2.0, 1.0)) if burning else Color.WHITE
	var alpha := 1.0 - _burn
	var shown := Rect2(rect.position + Vector2(0, rect.size.y * _burn), Vector2(rect.size.x, rect.size.y * (1.0 - _burn)))
	if texture != null:
		var mod := Color(tint, alpha)
		if texture.get_size() == Vector2(TILE, TILE):
			for y in height_tiles:
				for x in width_tiles:
					var cell := Rect2(rect.position + Vector2(x, y) * TILE, Vector2(TILE, TILE))
					if cell.end.y > shown.position.y:
						draw_texture_rect(texture, cell, false, mod)
		else:
			draw_texture_rect(texture, rect, false, mod)
		return
	var base := COLOR_WOOL if not burning else tint
	draw_rect(shown, Color(COLOR_WOOL_SHADE, alpha))
	# 몽글몽글한 털 뭉치를 칸마다 두 개씩
	for y in height_tiles * 2:
		for x in width_tiles * 2:
			var c := rect.position + Vector2(x + 0.5 + (0.5 if y % 2 == 1 else 0.0), y + 0.5) * (TILE * 0.5)
			if c.y < shown.position.y or c.x > rect.end.x:
				continue
			draw_circle(c, TILE * 0.32, Color(base, alpha))
