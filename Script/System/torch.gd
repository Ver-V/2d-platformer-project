extends Interactable
class_name Torch

# 횃불: 랜턴(required_item_id)을 장착한 채 interact 키(E)로 불을 붙이면 주변 light_radius_tiles(8타일)를 밝힌다.
# 시야 제한(VisionLimit)이 있는 스테이지용 — 켜진 횃불은 VisionLimit.LIGHT_GROUP에 들어가 어둠에 빛 원을 하나 더 뚫는다.
# 붙인 기록은 GameManager.collected_items에 "torch:<persist_id>"로 남는다: 세이브하면 계속 켜져 있고,
# 세이브 전에 죽으면(세이브를 다시 불러오므로) 꺼진 상태로 돌아간다.
# 원점 = 바닥 중앙. 그림: Sprite(AnimatedSprite2D)에 "unlit" / "lit" 애니메이션을 넣으면 그걸 쓰고,
# 비어 있으면 Placeholder(임시 도형, 켜지면 Flame이 보인다)를 그린다.

const TILE := 16.0
const HINT_COOLDOWN_MS := 2000

@export var light_radius_tiles: float = 8.0
@export var required_item_id: String = "lantern" # 이 아이템을 장착하고 있어야 불을 붙일 수 있다
@export var light_offset: Vector2 = Vector2(0, -24) # 빛의 중심 (불꽃 위치)
@export var light_grow_time: float = 0.8 # 불을 붙였을 때 빛이 다 퍼지는 시간
@export var flicker_px: float = 2.0 # 켜진 빛 반지름이 일렁이는 폭
@export var persist_id: String = ""
@export var tutorial_key: StringName = &"TUTORIAL_TORCH" # 처음 불을 붙였을 때 한 번

@onready var sprite: AnimatedSprite2D = get_node_or_null("Sprite")
@onready var placeholder: Node2D = get_node_or_null("Placeholder")
@onready var flame: CanvasItem = get_node_or_null("Placeholder/Flame")
@onready var light_sound: AudioStreamPlayer2D = get_node_or_null("LightSound")

var lit: bool = false
var _grow: float = 0.0 # 0 → 1: 빛이 퍼진 정도
var _time: float = 0.0
var _last_hint_ms: int = -HINT_COOLDOWN_MS

func _ready() -> void:
	super._ready()
	add_to_group(VisionLimit.LIGHT_GROUP)
	lit = GameManager.collected_items.has(save_id())
	_grow = 1.0 if lit else 0.0 # 이미 켜 둔 횃불은 들어오자마자 다 밝혀져 있다
	_update_visual()
	set_process(lit)

func _process(delta: float) -> void:
	_time += delta
	if light_grow_time > 0.0:
		_grow = move_toward(_grow, 1.0, delta / light_grow_time)
	else:
		_grow = 1.0

func save_id() -> String:
	if not persist_id.is_empty():
		return "torch:" + persist_id
	if not is_inside_tree():
		return "torch:" + str(name)
	var scene := get_tree().current_scene
	return "torch:%s:%s" % [scene.scene_file_path if scene != null else "", get_path()]

# --- 빛 (VisionLimit이 매 프레임 읽는다) ---
func get_light_center() -> Vector2:
	return global_position + light_offset

func get_light_radius() -> float:
	if not lit:
		return 0.0
	var flicker := (sin(_time * 7.3) + 0.5 * sin(_time * 13.1)) / 1.5 * flicker_px
	return light_radius_tiles * TILE * ease(_grow, 0.4) + flicker * _grow

# --- 불 붙이기 ---
func light() -> void:
	if lit:
		return
	lit = true
	_grow = 0.0
	_time = 0.0
	GameManager.add_collected_item(save_id())
	Tutorials.show_once(self, tutorial_key)
	_hide_prompt()
	if light_sound != null and light_sound.stream != null:
		light_sound.play()
	_update_visual()
	set_process(true)

func _can_interact() -> bool:
	return not lit

func _show_prompt() -> void:
	if not lit:
		super._show_prompt()

func _on_interact() -> void:
	if not get_node("/root/Inventory").is_equipped(required_item_id):
		_show_hint()
		return
	light()

func _show_hint() -> void:
	var now := Time.get_ticks_msec()
	if now - _last_hint_ms < HINT_COOLDOWN_MS:
		return
	_last_hint_ms = now
	if is_instance_valid(current_player) and current_player.has_method("show_popup"):
		current_player.show_popup(tr(&"TORCH_NEEDS_LANTERN"), Color.LIGHT_GRAY)

func _update_visual() -> void:
	var anim := &"lit" if lit else &"unlit"
	var has_art := sprite != null and sprite.sprite_frames != null and sprite.sprite_frames.has_animation(anim)
	if sprite != null:
		sprite.visible = has_art
		if has_art:
			sprite.play(anim)
	if placeholder != null:
		placeholder.visible = not has_art
	if flame != null:
		flame.visible = lit
