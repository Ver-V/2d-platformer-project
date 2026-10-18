extends Area2D

@export_file("*.tscn") var target_scene_path: String = ""

@export var transition_duration: float = 1.5

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D) -> void:
	if body is Player and body.hp > 0: # 공중에서 죽은 시체가 떨어져 들어온 건 무시 (죽은 채로 씬이 바뀌면 부활할 수 없다)
		_start_fall_transition()

func _start_fall_transition() -> void:
	if target_scene_path == "" or not ResourceLoader.exists(target_scene_path):
		return

	set_deferred("monitoring", false)

	if SceneTransition:
		SceneTransition.start_transition(func():
			if GameManager.can_travel():
				get_tree().change_scene_to_file(target_scene_path)
			else:
				set_deferred("monitoring", true)
		, transition_duration)
	else:
		get_tree().change_scene_to_file(target_scene_path)
