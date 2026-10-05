@tool
extends EditorPlugin

# 편집 중인 씬에 몹·박스·상자·문이 추가(배치·복제·씬 열기)되면 persist_id를 배정하고 중복을 정리한다.
# 저장 직전(_apply_changes)에도 한 번 더 정리하므로, 저장된 씬에는 항상 빈 ID·중복 ID가 없다.

var _pending: bool = false

func _enter_tree() -> void:
	get_tree().node_added.connect(_on_node_added)
	scene_changed.connect(_on_scene_changed)

func _exit_tree() -> void:
	if get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)
	if scene_changed.is_connected(_on_scene_changed):
		scene_changed.disconnect(_on_scene_changed)

func _on_node_added(node: Node) -> void:
	var root := EditorInterface.get_edited_scene_root()
	if root == null or node == root or not root.is_ancestor_of(node):
		return
	if PersistIdAssigner.prefix_for(node) == "":
		return
	_schedule()

func _on_scene_changed(_root: Node) -> void:
	_schedule()

# 복제·붙여넣기는 여러 노드가 한꺼번에 들어오므로 한 프레임 모아서 처리한다
func _schedule() -> void:
	if _pending:
		return
	_pending = true
	_fix_edited_scene.call_deferred()

func _fix_edited_scene() -> void:
	_pending = false
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return
	var changed := PersistIdAssigner.assign(root)
	if changed > 0:
		EditorInterface.mark_scene_as_unsaved()
		print("[Persist IDs] %s: %d개 ID 배정/중복 정리" % [root.scene_file_path, changed])

func _apply_changes() -> void:
	var root := EditorInterface.get_edited_scene_root()
	if root != null:
		PersistIdAssigner.assign(root)
