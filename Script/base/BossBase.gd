extends EnemyBase
class_name Boss

enum State {INTRO, IDLE, COMBAT, DEAD}
var current_state = State.INTRO

@export_file("*.json") var dialogue_file: String = ""
@export_file("*.json") var outro_dialogue_file: String = ""
@export var bgm_player : AudioStreamPlayer
@export var boss_sprite : AnimatedSprite2D
@export var boss_door_group: String = "boss_doors" # 보스 방 문들이 속한 그룹 이름
@export var reward_item: ItemData # 처치 보상 아이템 (비우면 골드만)

@export_group("Phase 2")
@export_range(0.0, 1.0) var phase2_hp_ratio: float = 0.5 # 체력이 이 비율 아래로 떨어지면 페이즈 2 (0이면 페이즈 2 없음)
@export var phase2_shake: float = 4.0 # 페이즈 2 진입 때 화면 흔들림 세기
@export var phase2_speech_key: String = "" # 페이즈 2 진입 대사 (ui.csv 키). 비우면 대사 없음

@export_group("Full Moon Rematch")
# 잡은 보스도 해치를 열고 보름달 밤에 다시 오면 강해져서 다시 나타난다 (이번 보름달 회차에 이기면 다음 보름달까지 안 나온다).
# 보상은 금화만 (아이템은 처음 한 번). 대기 시간 줄이기는 각 보스의 패턴 루프가 idle_cut()으로 반영한다
@export var rematch_enabled: bool = true
@export var rematch_stat_mult: float = 1.25 # 달빛 배율 위에 체력·주는 피해를 이만큼 더
@export var rematch_idle_cut: float = 0.5 # 패턴 사이 대기 시간을 이만큼(초) 줄인다

@export_group("Speech")
@export var speech_offset: Vector2 = Vector2(0, -50) # 대사 아랫변 가운데 위치 (보스 원점 기준)
@export var speech_duration: float = 2.5 # 대사가 떠 있는 시간 (그 뒤 사라진다)

const FIELD_ITEM_SCENE: PackedScene = preload("res://Scenes/Item/field_item.tscn")
const SPEECH_FADE_TIME := 0.4

var boss_started: bool = false # 인트로/전투 시작 여부 확인용
var phase: int = 1
var is_rematch: bool = false # 보름달 재도전으로 나온 (이미 잡은) 보스
var _player_hit: bool = false # 이번 전투에서 플레이어가 피해를 입었는가 (노히트 기록용)
var _last_player_hp: int = -1
var _speech_label: Label
var _speech_tween: Tween

# 보스는 절대 변이하지 않는다 (씬의 mutation_enabled 값·그룹 등록 순서와 상관없이)
func _can_mutate() -> bool:
	return false

func apply_mutation(kind: MobMutation.Kind) -> void:
	if kind != MobMutation.Kind.NONE:
		return
	super.apply_mutation(kind)

func _ready() -> void:
	mutation_enabled = false
	super._ready() # 부모(EnemyBase)의 _ready 실행 (체력 설정 등)
	DialogueManager.dialogue_event.connect(_on_dialogue_event)
	# 코드에서도 다시 한번 그룹 확인
	if not is_in_group("bosses"):
		add_to_group("bosses")
	
	var id = get_persist_id()
	
	GameManager.hp_changed.connect(_on_player_hp_changed)
	if id != "" and GameManager.defeated_bosses.get(id, false) and rematch_enabled and GameManager.can_rematch(id):
		_become_rematch()
		return
	if id != "" and GameManager.defeated_bosses.get(id, false):
		# 보상 아이템이 생기기 전에 잡은 세이브: 다시 올 때 한 번 채워 준다.
		# 받은 기록(collected_items의 reward_key)이 있으면 주지 않는다 — 없으면 마시거나 판 보상이 씬을 열 때마다 되살아났다
		if reward_item != null and not GameManager.collected_items.has(reward_key()) and not Inventory.has_item(reward_item.id):
			if Inventory.add_item(reward_item):
				GameManager.add_collected_item(reward_key())
		queue_free()
		return

func _on_dialogue_event(event_name: String) -> void:
	if event_name == "play_boss_bgm":
		_play_boss_music()
# 보름달 재도전: 달빛(_apply_moonlight)이 이미 반영된 체력·피해에 rematch_stat_mult를 더 곱한다. 인트로는 건너뛴다
func _become_rematch() -> void:
	is_rematch = true
	max_hp = maxi(1, roundi(max_hp * rematch_stat_mult))
	hp = max_hp
	moon_damage_mult *= rematch_stat_mult

# 패턴 사이 대기에서 뺄 시간 (재도전이면 rematch_idle_cut)
func idle_cut() -> float:
	return rematch_idle_cut if is_rematch else 0.0

# 전투 중에 플레이어 체력이 줄면 노히트 실패
func _on_player_hp_changed(current: int, _max_hp: int) -> void:
	if boss_started and current_state != State.DEAD and _last_player_hp >= 0 and current < _last_player_hp:
		_player_hit = true
	_last_player_hp = current

func is_nohit_so_far() -> bool:
	return boss_started and not _player_hit

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
		PlayLog.boss_entered(PlayLog.describe_source(self))
		
		if not boss_started:
			boss_started = true
			if is_rematch:
				TutorialPopup.show_once(&"TUTORIAL_REMATCH")
			_player_hit = false
			_last_player_hp = GameManager.player_current_hp
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
		PlayLog.boss_left(PlayLog.describe_source(self))
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
	if HitData.landed(result):
		_check_phase()
	return result

func _on_status_damaged(amount: int) -> void:
	super._on_status_damaged(amount)
	if HUD.has_method("show_boss_health"):
		HUD.show_boss_health(self)
	_check_phase()

# --- 페이즈 ---
func _check_phase() -> void:
	if phase != 1 or phase2_hp_ratio <= 0.0 or hp <= 0 or current_state == State.DEAD:
		return
	if float(hp) < float(max_hp) * phase2_hp_ratio:
		_enter_phase_2()

func _enter_phase_2() -> void:
	phase = 2
	var stage := get_tree().current_scene
	if phase2_shake > 0.0 and stage and stage.has_method("apply_camera_shake"):
		stage.apply_camera_shake(phase2_shake)
	if phase2_speech_key != "":
		say(tr(phase2_speech_key))
	_on_phase_2()

# 보스별 페이즈 2 연출·변화 (패턴 속도 등)
func _on_phase_2() -> void:
	pass

func reset_to_home(reset_hp: bool = true) -> void:
	super.reset_to_home(reset_hp)
	if reset_hp:
		phase = 1
		_hide_speech()

# --- 머리 위 대사 ---
# 보스 머리 위에 한 줄 대사를 띄운다. duration < 0이면 speech_duration을 쓴다.
func say(text: String, duration: float = -1.0) -> void:
	if text == "":
		return
	if _speech_label == null:
		_speech_label = Label.new()
		var settings := LabelSettings.new()
		settings.outline_size = 4
		settings.outline_color = Color.BLACK
		_speech_label.label_settings = settings
		_speech_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_speech_label.z_index = 10
		add_child(_speech_label)
	if _speech_tween:
		_speech_tween.kill()
	_speech_label.text = text
	_speech_label.reset_size()
	_speech_label.position = speech_offset - Vector2(_speech_label.size.x * 0.5, _speech_label.size.y)
	_speech_label.modulate.a = 1.0
	_speech_label.visible = true
	_speech_tween = create_tween()
	_speech_tween.tween_interval(speech_duration if duration < 0.0 else duration)
	_speech_tween.tween_property(_speech_label, "modulate:a", 0.0, SPEECH_FADE_TIME)
	_speech_tween.tween_callback(_hide_speech)

func _hide_speech() -> void:
	if _speech_tween:
		_speech_tween.kill()
		_speech_tween = null
	if _speech_label:
		_speech_label.visible = false

# 막타 연출: 시간이 멈추고 카메라가 보스로 당겨졌다가, 풀리면서 쓰러진다 (실제 시간 기준)
@export_group("Final Blow")
@export var final_blow_freeze: float = 0.8 # 0이면 연출 없음
@export var final_blow_zoom: float = 1.4 # 지금 카메라 확대에 곱한다
@export var final_blow_return_time: float = 0.5

func _play_final_blow() -> void:
	if final_blow_freeze <= 0.0:
		return
	GameManager.apply_hitstop(0.0, final_blow_freeze)
	var stage := get_tree().current_scene
	var has_cam := stage != null and stage.has_method("focus_camera")
	if has_cam:
		stage.focus_camera(global_position + Vector2(0, -20), final_blow_zoom, final_blow_freeze * 0.5)
	await Wait.real_seconds(self, final_blow_freeze)
	if has_cam and is_instance_valid(stage):
		stage.release_camera_focus(final_blow_return_time)

func _on_death() -> void:
	current_state = State.DEAD
	PlayLog.boss_defeated(PlayLog.describe_source(self))
	_hide_speech()
	if HUD.has_method("hide_boss_health"):
		HUD.hide_boss_health(self)
	
	# 보스가 죽는 순간 플레이어를 무적으로 만듦
	if is_instance_valid(target) and target.has_method("start_invuln"):
		target.start_invuln(10.0) # 넉넉하게 10초 무적 부여
	
	_stop_boss_music()
	_set_boss_doors(false)
	var nohit := is_nohit_so_far()
	if nohit:
		GameManager.record_nohit(str(get_persist_id()))
		if is_instance_valid(target) and target.has_method("show_popup"):
			target.show_popup(tr(&"BOSS_NO_HIT"), Color(1.0, 0.85, 0.3))
	if is_rematch:
		GameManager.record_rematch_win(str(get_persist_id()))
	await _play_final_blow()
	
	if outro_dialogue_file != "":
		DialogueManager.start_dialogue(outro_dialogue_file)
		await DialogueManager.dialogue_finished

	# died 신호가 자동 저장을 실행하므로 보상을 먼저 반영한다.
	GameManager.update_gold(drop_gold_amount)
	HUD.log_pickup_gold(drop_gold_amount)
	_give_reward_item()
	super._on_death()

# 보상을 받았다는 기록 (collected_items). 가방이 차서 떨어뜨린 보상(FieldItem)도 같은 키로 주운 걸 기록한다
func reward_key() -> String:
	return "boss_reward:" + str(get_persist_id())

# 보상 아이템은 바로 넣는다 (장비면 빈 장비 칸에 장착). 가방·장비 칸이 가득 차면 그 자리에 떨어뜨린다.
func _give_reward_item() -> void:
	if reward_item == null or is_rematch:
		return
	if Inventory.add_item(reward_item):
		GameManager.add_collected_item(reward_key())
		HUD.log_pickup_item(reward_item)
		return
	var drop = FIELD_ITEM_SCENE.instantiate()
	drop.id = reward_key() # 주우면 FieldItem이 이 키를 collected_items에 남긴다
	drop.item_resource = reward_item
	drop.position = get_parent().to_local(global_position)
	get_parent().add_child.call_deferred(drop)

# 보스는 코인을 뿌리지 않고 바로 GameManager.update_gold로 지급하므로 부모의 spawn_gold를 덮어씁니다.
func spawn_gold() -> void:
	pass
