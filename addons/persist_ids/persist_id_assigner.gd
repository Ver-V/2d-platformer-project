@tool
extends RefCounted
class_name PersistIdAssigner

# 저장에 쓰이는 persist_id를 씬 단위로 배정·중복 정리한다.
# 에디터 플러그인(plugin.gd)과 일괄 배정 스크립트(tools/assign_persist_ids.gd), 테스트가 같은 규칙을 쓴다.
# 형식: <종류 글자>-<16진수 8자리>  예) B-7f3a2c91
#   M = 몹(EnemyBase, 보스 포함), B = 박스(BreakableBox), C = 상자(Chest), D = 문(KeyDoor)
# 이미 값이 있으면 그대로 둔다 (보스처럼 대사 조건에서 쓰는 ID는 직접 읽기 쉬운 이름으로 적어도 된다).

const KIND_PREFIX := {
	&"EnemyBase": "M",
	&"BreakableBox": "B",
	&"Chest": "C",
	&"KeyDoor": "D",
}

# 노드의 스크립트 상속 사슬에서 종류 글자를 찾는다. 대상이 아니면 "".
static func prefix_for(node: Node) -> String:
	var script: Script = node.get_script() as Script
	while script != null:
		var global_name := script.get_global_name()
		if KIND_PREFIX.has(global_name):
			return KIND_PREFIX[global_name]
		script = script.get_base_script()
	return ""

static func new_id(prefix: String, taken: Dictionary) -> String:
	while true:
		var id := "%s-%08x" % [prefix, randi()]
		if not taken.has(id):
			return id
	return ""

# root가 저장하는 씬에 직접 놓인 대상 노드들 (root 자신과, 다른 씬 안에 들어 있는 노드는 제외)
static func targets(root: Node) -> Array[Node]:
	var found: Array[Node] = []
	_collect(root, root, found)
	return found

static func _collect(node: Node, root: Node, found: Array[Node]) -> void:
	for child in node.get_children():
		if child.owner == root and prefix_for(child) != "":
			found.append(child)
		_collect(child, root, found)

# 빈 ID는 새로 배정하고, 같은 ID가 두 번 이상이면 트리에서 뒤에 있는 쪽을 새로 발급한다.
# 바뀐 노드 수를 돌려준다.
static func assign(root: Node) -> int:
	var nodes := targets(root)
	var taken: Dictionary = {}
	for node in nodes:
		var id := str(node.get("persist_id"))
		if not id.is_empty():
			taken[id] = taken.get(id, 0) + 1
	var seen: Dictionary = {}
	var changed := 0
	for node in nodes:
		var id := str(node.get("persist_id"))
		if not id.is_empty() and not seen.has(id):
			seen[id] = true
			continue
		var fresh := new_id(prefix_for(node), taken)
		taken[fresh] = 1
		seen[fresh] = true
		var current = node.get("persist_id")
		node.set("persist_id", StringName(fresh) if current is StringName else fresh)
		changed += 1
	return changed

# 검사용: 비어 있거나 중복된 ID 목록
static func problems(root: Node) -> Array[String]:
	var out: Array[String] = []
	var seen: Dictionary = {}
	for node in targets(root):
		var id := str(node.get("persist_id"))
		if id.is_empty():
			out.append("empty: %s" % root.get_path_to(node))
		elif seen.has(id):
			out.append("duplicate %s: %s / %s" % [id, seen[id], root.get_path_to(node)])
		else:
			seen[id] = str(root.get_path_to(node))
	return out
