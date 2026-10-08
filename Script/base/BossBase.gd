extends EnemyBase
class_name Boss

enum State {INTRO, IDLE, COMBAT, DEAD}
var current_state = State.INTRO

@export_file("*.json") var dialogue_file: String = ""
@export_file("*.json") var outro_dialogue_file: String = ""
@export var bgm_player : AudioStreamPlayer
@export var boss_sprite : AnimatedSprite2D
@export var boss_door_group: String = "boss_doors" # 보스 방 문들이 속한 그룹 이름


var boss_started: bool = false # 인트로/전투 시작 여부 확인용

func _ready() -> void:
	super._ready() # 부모(EnemyBase)의 _ready 실행 (체력 설정 등)
	DialogueManager.dialogue_event.connect(_on_dialogue_event)
	# 코드에서도 다시 한번 그룹 확인
	if not is_in_group("bosses"):
		add_to_group("bosses")
	
	var id = get_persist_id()
	
	if id != "" and GameManager.defeated_bosses.get(id, false):

		queue_free()
		return

func _on_dialogue_event(event_name: String) -> void:
	if event_name == "play_boss_bgm":
		_play_boss_music()
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
			if HUD.has_method("show_boss_health"):
				HUD.show_boss_health(self)
			
	elif not active and was_active:
		# 보스 방에서 나갔을 때 음악 정지
		_stop_boss_music()
		if HUD.has_method("hide_boss_health"):
			HUD.hide_boss_health(self)
		# 방을 나갔을 때 문을 열어줌
		_set_boss_doors(false)

# --- 음악 관리 함수 ---
func _play_boss_music():
	# 스테이지 배경음악 찾아서 끄기
	var stage_bgm := _stage_bgm()
	if stage_bgm:
		stage_bgm.stop()
		
	if bgm_player != null and not bgm_player.playing:
		bgm_player.play()

func _stop_boss_music():
	if bgm_player != null:
		bgm_player.stop()
		
	# 스테이지 배경음악 다시 켜기 (이미 재생 중이 아닐 때만)
	var stage_bgm := _stage_bgm()
	if stage_bgm and not stage_bgm.playing:
		stage_bgm.play()

# 스테이지 배경음악. 씬을 닫는 중(트리에서 빠졌거나 current_scene이 비었을 때)에는 null
func _stage_bgm() -> AudioStreamPlayer:
	if not is_inside_tree():
		return null
	var scene := get_tree().current_scene
	if scene == null:
		return null
	return scene.get_node_or_null("AudioStreamPlayer") as AudioStreamPlayer

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
	_play_boss_music()
	if HUD.has_method("show_boss_health"):
		HUD.show_boss_health(self)

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

func receive_hit(hit: HitData) -> HitData.Result:
	var result := super.receive_hit(hit)
	if result == HitData.Result.HIT and boss_sprite != null:
		boss_sprite.play("gethit")
	if HitData.landed(result) and HUD.has_method("show_boss_health"):
		HUD.show_boss_health(self)
	return result

func _on_status_damaged(amount: int) -> void:
	super._on_status_damaged(amount)
	if HUD.has_method("show_boss_health"):
		HUD.show_boss_health(self)

func _on_death() -> void:
	current_state = State.DEAD
	if HUD.has_method("hide_boss_health"):
		HUD.hide_boss_health(self)
	
	# 보스가 죽는 순간 플레이어를 무적으로 만듦
	if is_instance_valid(target) and target.has_method("start_invuln"):
		target.start_invuln(10.0) # 넉넉하게 10초 무적 부여
	
	_stop_boss_music()
	_set_boss_doors(false)
	
	if outro_dialogue_file != "":
		DialogueManager.start_dialogue(outro_dialogue_file)
		await DialogueManager.dialogue_finished

	# died 신호가 자동 저장을 실행하므로 보상을 먼저 반영한다.
	GameManager.update_gold(drop_gold_amount)
	super._on_death()

# 보스는 코인을 뿌리지 않고 바로 GameManager.update_gold로 지급하므로 부모의 spawn_gold를 덮어씁니다.
func spawn_gold() -> void:
	pass
