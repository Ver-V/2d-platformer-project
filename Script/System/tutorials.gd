extends RefCounted
class_name Tutorials

# 도움말을 처음 한 번만 띄운다 (TutorialPopup.show_once). 오토로드를 이름이 아니라 경로로 찾으므로
# 테스트가 클래스 이름으로 참조하는 스크립트(무너지는 블록, 트램펄린 등)에서도 써도 된다.
static func show_once(node: Node, text_key: StringName) -> void:
	if text_key == &"" or node == null or not node.is_inside_tree():
		return
	var popup := node.get_node_or_null("/root/TutorialPopup")
	if popup != null:
		popup.show_once(text_key)
