# SavePoint.gd
extends Interactable

@onready var sprite = $AnimatedSprite2D 
@onready var sfx_player = $AudioStreamPlayer2D

var can_save: bool = true   # 쿨타임

func _ready() -> void:
	interact_msg = "save_mode"
	super()
	add_to_group("minimap_save")
	if sprite: sprite.play("default")

# 메뉴·대화 중 확인은 Interactable이 한다. 사망 화면의 재시작 입력(R)과 겹치지 않도록 막는다.
const TUTORIAL_KEY := &"TUTORIAL_SAVE_POINT" # 처음 다가갔을 때 한 번: 저장(E)과 휴식(R)의 차이

func _on_player_entered(_body: Node) -> void:
	Tutorials.show_once(self, TUTORIAL_KEY)

func _can_interact() -> bool:
	if not can_save:
		return false
	var player := get_tree().get_first_node_in_group("player")
	return player != null and player.hp > 0

# [선택 1] 기다리기 (E키): 달의 위상을 다음으로 넘긴다
func _on_interact() -> void:
	action_wait()

# [선택 2] 휴식 (R키): 회복 + 몹 부활, 달은 그대로
func _on_other_input(event: InputEvent) -> void:
	if event.is_action_pressed("rest"):
		action_rest()

# --- 기능 1: 기다리기 ---
# 달의 위상과 변이를 다음 회차로 넘기고(GameManager.reset_mobs: 몹도 되살아나 다시 굴린다) 저장한 뒤 다시 불러온다.
# 체력·플라스크는 회복하지 않는다 — 보름달·그믐달을 골라 맞추는 대가
func action_wait() -> void:
	can_save = false
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		GameManager.player_current_hp = players[0].hp
	GameManager.reset_mobs()
	_perform_save_file()
	if sfx_player:
		sfx_player.play()
	GameManager.pending_status = "wait"
	SceneTransition.start_transition(func(): get_tree().reload_current_scene())

# --- 기능 2: 휴식 (저장 + 회복 + 몹 리젠) ---
func action_rest() -> void:
	can_save = false
	
	# 1. 플레이어 체력 회복 및 에스트 병 충전
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		var p = players[0]
		# 지속 중인 상태이상(독·출혈 등) 해제 — 전환 연출 동안 틱 피해가 들어가지 않도록 회복보다 먼저
		if p.has_method("clear_status_effects"):
			p.clear_status_effects()
		p.hp = p.max_hp
		GameManager.update_hp(p.max_hp)
		
		# [추가됨] 플라스크 횟수 충전
		if GameManager.get("flask_current_charges") != null:
			GameManager.flask_current_charges = GameManager.flask_max_charges
			if GameManager.has_signal("flask_changed"):
				GameManager.flask_changed.emit()

	# 2. 쓰러뜨린 일반 몹을 되살린다 (달의 위상·변이는 그대로 — 넘기려면 기다리기)
	GameManager.revive_mobs()
	
	# 3. 저장 (깨끗해진 몹 기록 + 풀피 상태로 저장됨)
	_perform_save_file()
	
	if sfx_player:
		sfx_player.play()
		
	GameManager.pending_status = "rest"
	# 4. [핵심] 씬 재시작 (Reload)
	SceneTransition.start_transition(func(): get_tree().reload_current_scene())

# --- 공통 내부 함수들 ---
func _perform_save_file() -> void:
	# 위치 저장 (바닥 끼임 방지 위로 조금)
	GameManager.save_checkpoint(global_position)
	GameManager.save_game()

func _play_effect(color: Color) -> void:
	if sprite:
		var original = sprite.modulate
		sprite.modulate = color
		await Wait.seconds(self, 0.5)
		sprite.modulate = original

func _cooldown_and_reset() -> void:
	await Wait.seconds(self, 2.0)
	can_save = true
	if player_in_range:
		GameManager.interact_msg_requested.emit("save_mode")
