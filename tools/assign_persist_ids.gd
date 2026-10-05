extends SceneTree
# 기존 씬 전체에 persist_id를 일괄 배정한다 (에디터 플러그인과 같은 규칙).
# Godot --headless --path . --script res://tools/assign_persist_ids.gd            → 바꿀 개수만 출력 (dry run)
# Godot --headless --path . --script res://tools/assign_persist_ids.gd -- --write → 실제로 씬 파일 저장
# 저장 전에 에디터에서 해당 씬을 닫아 둘 것 (열려 있으면 에디터가 덮어쓴다).
# 씬을 통째로 다시 저장하면 uid가 빠지므로, .tscn 텍스트에서 해당 노드의 persist_id 줄만 넣거나 바꾼다.

func _initialize() -> void:
	call_deferred("run")

func _scene_paths(dir: String, out: Array[String]) -> void:
	for f in ResourceLoader.list_directory(dir):
		var path := dir.path_join(f)
		if f.ends_with("/"):
			if not path.begins_with("res://addons") and not path.begins_with("res://.godot"):
				_scene_paths(path.trim_suffix("/"), out)
		elif f.ends_with(".tscn"):
			out.append(path)

func run() -> void:
	var write := OS.get_cmdline_user_args().has("--write")
	var paths: Array[String] = []
	_scene_paths("res://", paths)
	var total := 0
	for path in paths:
		var packed := load(path) as PackedScene
		if packed == null:
			continue
		var root := packed.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
		var before := _ids(root)
		var changed := PersistIdAssigner.assign(root)
		if changed > 0:
			total += changed
			print("%s: %d" % [path, changed])
			if write:
				_write_ids(path, root, before)
		root.free()
	print("total: %d%s" % [total, "" if write else " (dry run)"])
	quit()

func _ids(root: Node) -> Dictionary:
	var out := {}
	for node in PersistIdAssigner.targets(root):
		out[node] = str(node.get("persist_id"))
	return out

# 노드 경로 → .tscn 헤더의 (name, parent) 로 찾아 persist_id 줄을 넣는다
func _write_ids(path: String, root: Node, before: Dictionary) -> void:
	var lines := FileAccess.get_file_as_string(path).split("
")
	for node in PersistIdAssigner.targets(root):
		var id := str(node.get("persist_id"))
		if before.get(node, "") == id:
			continue
		var rel := str(root.get_path_to(node))
		var parent := "." if rel.find("/") == -1 else rel.get_base_dir()
		var header_start := '[node name="%s"' % node.name
		var parent_attr := 'parent="%s"' % parent
		var idx := -1
		for i in lines.size():
			if lines[i].begins_with(header_start) and lines[i].contains(parent_attr):
				idx = i
				break
		if idx == -1:
			push_error("node header not found: %s %s" % [path, rel])
			continue
		# 같은 노드 블록 안의 기존 persist_id 줄은 교체, 없으면 헤더 바로 아래에 추가
		var j := idx + 1
		var replaced := false
		while j < lines.size() and not lines[j].begins_with("[") and not lines[j].strip_edges().is_empty():
			if lines[j].begins_with("persist_id = "):
				lines[j] = 'persist_id = "%s"' % id
				replaced = true
				break
			j += 1
		if not replaced:
			lines.insert(idx + 1, 'persist_id = "%s"' % id)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("
".join(lines))
	f.close()
