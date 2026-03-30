extends EnemyBase
class_name Boss

enum State {INTRO, IDLE, COMBAT, DEAD}
var current_state = State.INTRO

@export_file("*.json") var dialogue_file: String = ""
@export var bgm_player : AudioStreamPlayer
@export var boss_sprite : AnimatedSprite2D
@export var boss_door_group: String = "boss_doors" # [추가] 보스 방 문들이 속한 그룹 이름

var boss_started: bool = false # 인트로/전투 시작 여부 확인용

func _ready() -> void:
	super._ready() # 부모(EnemyBase)의 _ready 실행 (체력 설정 등)
	
	# 코드에서도 다시 한번 그룹 확인
	if not is_in_group("bosses"):
		add_to_group("bosses")
	
	var id = get_persist_id()
	
	if id != "" and GameManager.defeated_bosses.get(id, false):
		queue_free()
		return
	
	# [수정] _ready에서 즉시 시작하지 않고 set_active에서 처리합니다.

# 보스 방 문(Boss Doors)을 관리하는 함수
func _set_boss_doors(active: bool) -> void:
	if boss_door_group == "": return
	
	var doors = get_tree().get_nodes_in_group(boss_door_group)
	for door in doors:
		# StaticBody2D나 Area2D의 충돌체(CollisionShape2D)를 끄거나 켬
		if door is CollisionObject2D:
			for child in door.get_children():
				if child is CollisionShape2D:
					child.set_deferred("disabled", not active)
		
		# 시각적인 효과(문 애니메이션 등)가 있다면 여기서 추가 처리
		if door.has_method("set_open"):
			door.call("set_open", not active)

# 방 활성화 상태에 따라 음악 및 시작 로직 처리
func set_active(active: bool) -> void:
	var was_active = _active
	super.set_active(active) # EnemyBase의 활성화 로직 실행
	
	if active and not was_active:
		# 보스 방에 들어왔을 때
		if current_state == State.DEAD: return
		
		# [추가] 보스 방 진입 시 문 닫기
		_set_boss_doors(true)
		
		if not boss_started:
			boss_started = true
			var id = get_persist_id()
			if id != "" and GameManager.talked_bosses.get(id, false):
				_start_combat()
			else:
				_start_intro()
		else:
			# 이미 대화가 끝난 후 다시 들어온 경우 음악만 재생
			_play_boss_music()
			
	elif not active and was_active:
		# 보스 방에서 나갔을 때 음악 정지
		_stop_boss_music()
		# [추가] 방을 나갔을 때 문을 열어줌 (보통 보스전 중엔 못 나가게 하므로 필요 없을 수 있음)
		_set_boss_doors(false)

# --- 음악 관리 함수 ---
func _play_boss_music():
	# 스테이지 배경음악 찾아서 끄기
	var stage_bgm = get_tree().current_scene.get_node_or_null("AudioStreamPlayer")
	if stage_bgm and stage_bgm is AudioStreamPlayer:
		stage_bgm.stop()
		
	if bgm_player != null and not bgm_player.playing:
		bgm_player.play()

func _stop_boss_music():
	if bgm_player != null:
		bgm_player.stop()
		
	# 스테이지 배경음악 다시 켜기 (이미 재생 중이 아닐 때만)
	var stage_bgm = get_tree().current_scene.get_node_or_null("AudioStreamPlayer")
	if stage_bgm and stage_bgm is AudioStreamPlayer and not stage_bgm.playing:
		stage_bgm.play()

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
	_play_boss_music()

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
	
	_stop_boss_music()
	
	# [추가] 보스가 죽으면 문 열기!
	_set_boss_doors(false)
	
	if persist_id != "":
		GameManager.defeated_bosses[persist_id] = true
	
	# [수정] 골드 드랍 및 사망 처리를 먼저 수행 (돈이 먼저 생겨야 함)
	super._on_death() 
	
	# [수정] 그 후 저장 (그래야 늘어난 골드/보스 처치 기록이 동시에 저장됨)
	# 보스의 경우 골드 코인을 뿌리는 것보다 즉시 지급하는 것이 세이브 데이터 안정성에 더 좋습니다.
	GameManager.add_gold(drop_gold_amount)
	GameManager.save_game()
	print("보스 처치 완료 및 데이터 저장됨. 획득 골드: ", drop_gold_amount)
