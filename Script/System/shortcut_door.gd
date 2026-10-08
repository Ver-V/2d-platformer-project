@tool
extends KeyDoor
class_name ShortcutDoor

# 열쇠 없는 지름길 문. 같은 link_id를 가진 A·B 한 쌍이 서로 이어진다.
# B는 처음부터 쓸 수 있고, B를 한 번 쓰면 지름길이 열려(세이브에 기록) 그 뒤로는 A에서도 B로 갈 수 있다.
# 짝이 다른 씬에 있으면 partner_scene에 그 씬을 지정한다 (비우면 같은 씬에서 짝을 찾는다).
# 그림·프롬프트·E키 입력·문 소리는 KeyDoor 것을 그대로 쓴다. 열쇠/대사 설정(item_key, dialogue_file 등)은 쓰지 않는다.

enum DoorSide { A, B }

const GROUP := &"shortcut_doors"

@export var link_id: String = "" # 한 쌍의 A·B에 같은 값. 쌍마다 겹치지 않게 (세이브 키로도 쓰인다)
@export var side: DoorSide = DoorSide.A
@export_file("*.tscn") var partner_scene: String = ""

func _ready() -> void:
	if Engine.is_editor_hint():
		super._ready()
		return
	locked = false
	add_to_group(GROUP)
	super._ready()

# A·B가 같은 열림 상태를 공유한다
func _save_id() -> String:
	return "shortcut:" + link_id

func is_unlocked() -> bool:
	return _opened

# 열리면 같은 씬에 있는 짝 문도 바로 열린 모습·상태로 바꾼다 (짝은 씬 시작 때 읽은 상태를 들고 있으므로)
func _open() -> void:
	super._open()
	for node in get_tree().get_nodes_in_group(GROUP):
		var door := node as ShortcutDoor
		if door != null and door != self and door.link_id == link_id and not door._opened:
			door._opened = true
			door._update_open_state()

func partner_side() -> DoorSide:
	return DoorSide.B if side == DoorSide.A else DoorSide.A

func _try_use_door(body: Player) -> void:
	if link_id.is_empty():
		push_warning("ShortcutDoor: link_id is empty: %s" % get_path())
		return
	if not _opened:
		if side == DoorSide.A:
			body.show_popup(tr(&"SHORTCUT_DOOR_LOCKED"), Color.YELLOW)
			return
		_open() # B를 처음 쓰면 지름길 개방
		_show_prompt()
	call_deferred("_travel", body)

func _travel(body: Player) -> void:
	if not is_instance_valid(body):
		return
	if int(body.get_meta("key_door_teleport_until", 0)) > Time.get_ticks_msec():
		return
	if _partner_in_other_scene():
		_busy = true
		GameManager.pending_shortcut_arrival = {"link_id": link_id, "side": partner_side()}
		SceneTransition.start_transition(func(): get_tree().change_scene_to_file(partner_scene))
		return
	var partner := find_door(get_tree(), link_id, partner_side())
	if partner == null:
		push_warning("ShortcutDoor: partner %s of '%s' not found" % [DoorSide.keys()[partner_side()], link_id])
		return
	partner.place_player(body)

func _partner_in_other_scene() -> bool:
	if partner_scene.is_empty():
		return false
	var scene := get_tree().current_scene
	return scene == null or scene.scene_file_path != partner_scene

# 도착 위치 = 문 그림의 바닥 중앙 (플레이어 원점은 발끝). 바닥에 박히지 않게 1px 띄운다.
# closed_texture로 그림을 바꾸면 바닥이 노드 원점에, 기본 그림이면 그림 아래 끝에 맞춰진다
func arrival_position() -> Vector2:
	if closed_sprite == null or closed_sprite.texture == null:
		return global_position
	var bottom := closed_sprite.to_global(Vector2(0.0, closed_sprite.get_rect().end.y))
	return Vector2(global_position.x, bottom.y - 1.0)

func place_player(body: Node2D) -> void:
	body.set_meta("key_door_teleport_until", Time.get_ticks_msec() + TELEPORT_COOLDOWN_MS)
	if body is CharacterBody2D:
		body.velocity = Vector2.ZERO
	body.global_position = arrival_position()

static func find_door(tree: SceneTree, id: String, door_side: int) -> ShortcutDoor:
	for node in tree.get_nodes_in_group(GROUP):
		var door := node as ShortcutDoor
		if door != null and door.link_id == id and door.side == door_side:
			return door
	return null
