extends EnemyBase
class_name Boss

enum State {INTRO, IDLE, COMBAT, DEAD}
var current_state = State.INTRO

@export_file("*.json") var dialogue_file: String = ""
@export var bgm_player : AudioStreamPlayer

func _ready() -> void:
	super._ready() # 부모(EnemyBase)의 _ready 실행 (체력 설정 등)
	add_to_group("bosses") # 보스 그룹 추가 (필요 시 사용)
	if persist_id != "" and GameManager.defeated_bosses.get(persist_id, false):
		queue_free()
		return
	
	if persist_id != "" and GameManager.talked_bosses.get(persist_id, false):
		_start_combat()
	else:
		_start_intro()
		
func _start_intro() -> void:
	current_state = State.INTRO
	velocity = Vector2.ZERO
	if dialogue_file != "":
		DialogueManager.start_dialogue(dialogue_file)
		
		await DialogueManager.dialogue_finished
		
		if persist_id != "":
			GameManager.talked_bosses[persist_id] = true
			GameManager.save_game()
			
	_start_combat()

func _start_combat() -> void:
	current_state = State.IDLE
	
	set_active(true)
	GameManager.is_menu_open = false
	if bgm_player != null:
		bgm_player.play()
		
	
func _physics_process(delta:float) -> void:
	match current_state:
		State.INTRO:
			pass
		State.IDLE:
			_idle_state(delta)
		State.COMBAT:
			_combat_state(delta)
		State.DEAD:
			_dead_state(delta)
	super._physics_process(delta)
	
func _idle_state(_delta: float) -> void:
	pass
	
func _combat_state(_delta:float) -> void:
	pass
	
func _dead_state(_delta:float) -> void:
	velocity = Vector2.ZERO

func _on_death() -> void:
	current_state = State.DEAD
	
	if persist_id != "":
		GameManager.defeated_bosses[persist_id] = true
	
	# 즉시 파일 저장 (보스 잡고 튕기면 억울하니까)
	GameManager.save_game()
	
	super._on_death() # 부모의 사망 처리(신호 발송, 삭제) 실행
