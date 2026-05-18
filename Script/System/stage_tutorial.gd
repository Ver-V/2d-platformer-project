extends BaseStage

@export var intro_dialogue_path: String = "res://resources/Dialogues/tutorial_intro.json"
@export var intro_delay: float = 0.5

func _ready() -> void:
	# 1. 부모 클래스의 _ready 실행 (플레이어 스폰 등)
	super._ready()
	
	# 2. 시작 시 화면을 즉시 검게 만듦
	if SceneTransition:
		SceneTransition.color_rect.modulate.a = 1.0
	
	# 3. 튜토리얼 인트로 컷신 시작
	start_tutorial_intro()

func start_tutorial_intro() -> void:
	if intro_dialogue_path == "" or not FileAccess.file_exists(intro_dialogue_path):
		if SceneTransition:
			SceneTransition.color_rect.modulate.a = 0.0
		return
		
	# 약간의 지연 후 대화 시작
	await get_tree().create_timer(intro_delay).timeout
	
	if DialogueManager:
		DialogueManager.start_dialogue(intro_dialogue_path)
		
		# 대화가 끝날 때까지 대기
		await DialogueManager.dialogue_finished
		
		# 4. 모든 대사가 끝나면 화면을 서서히 밝게 만듦 (Fade In)
		if SceneTransition:
			var tween = create_tween()
			tween.tween_property(SceneTransition.color_rect, "modulate:a", 0.0, 1.0)
