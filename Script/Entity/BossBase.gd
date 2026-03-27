extends EnemyBase
class_name Boss

enum State {INTRO, IDLE, COMBAT, DEAD}
var current_state = State.INTRO

@export_file("*.json") var dialogue_file: String = ""
@export var bgm_player : AudioStreamPlayer
@export var boss_sprite : AnimatedSprite2D

func _ready() -> void:
	super._ready() # 부모(EnemyBase)의 _ready 실행 (체력 설정 등)
	
	# 코드에서도 다시 한번 그룹 확인
	if not is_in_group("bosses"):
		add_to_group("bosses")
	
	var id = get_persist_id()
	
	if id != "" and GameManager.defeated_bosses.get(id, false):
		queue_free()
		return
	
	if id != "" and GameManager.talked_bosses.get(id, false):
		_start_combat()
	else:
		_start_intro()
		
func _start_intro() -> void:
	current_state = State.INTRO
	velocity = Vector2.ZERO
	if dialogue_file != "":
		DialogueManager.start_dialogue(dialogue_file)
		
		await DialogueManager.dialogue_finished
		
		var id = get_persist_id()
		if id != "":
			GameManager.talked_bosses[id] = true
			GameManager.save_game()
			
	_start_combat()

func _start_combat() -> void:
	current_state = State.IDLE
	
	set_active(true)
	GameManager.is_menu_open = false
	
	# 스테이지 배경음악 끄기
	var stage_bgm = get_tree().current_scene.get_node_or_null("AudioStreamPlayer")
	if stage_bgm and stage_bgm is AudioStreamPlayer:
		stage_bgm.stop()
		
	if bgm_player != null:
		bgm_player.play()
		
	
func _physics_process(delta:float) -> void:
	if current_state != State.DEAD and is_instance_valid(target) and boss_sprite != null:
		boss_sprite.flip_h = target.global_position.x < global_position.x
		
	match current_state:
		State.INTRO:
			pass
		State.IDLE:
			_idle_state(delta)
			if boss_sprite and boss_sprite.animation != "idle" and boss_sprite.animation != "gethit":
				boss_sprite.play("idle")
		State.COMBAT:
			_combat_state(delta)
			if boss_sprite and not boss_sprite.is_playing():
				boss_sprite.play("idle")
			elif boss_sprite and boss_sprite.animation != "attack" and boss_sprite.animation != "gethit" and boss_sprite.animation != "dead":
				boss_sprite.play("idle")
		State.DEAD:
			_dead_state(delta)
	super._physics_process(delta)
	
func _idle_state(_delta: float) -> void:
	pass
	
func _combat_state(_delta:float) -> void:
	pass
	
func _dead_state(_delta:float) -> void:
	velocity = Vector2.ZERO

func apply_damage(amount: int, knockback: Vector2 = Vector2.ZERO, ignore_cd: bool = false, or_invuln_time: float = -1.0) -> bool:
	var took_damage = super.apply_damage(amount, knockback, ignore_cd, or_invuln_time)
	
	if took_damage and hp > 0 and boss_sprite != null:
		boss_sprite.play("gethit")
		
	return took_damage

func _on_death() -> void:
	current_state = State.DEAD
	
	if bgm_player != null:
		bgm_player.stop()
	
	if persist_id != "":
		GameManager.defeated_bosses[persist_id] = true
	
	# 즉시 파일 저장 (보스 잡고 튕기면 억울하니까)
	GameManager.save_game()
	
	super._on_death() # 부모의 사망 처리(신호 발송, 삭제) 실행
