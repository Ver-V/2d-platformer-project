extends Area2D

@export_file("*.json") var dialogue_file: String = ""
@export var bounce_height: float = 10.0
@export var bounce_speed: float = 0.2
# 이 아이템을 "장착"하고 있어야 층 선택지가 나온다. 없으면 locked_block (석판 글귀 뒤에 탑승 거부)을 띄운다. 비우면 항상 탑승 가능
@export var required_item_id: String = "gatekeepers_ring"
@export var locked_block: String = "locked"
# 엘리베이터로 이 층에 도착했을 때 플레이어가 나타날 자리 (블록 기준. 블록 바로 아래 바닥쪽 — 거기서 떨어져 내려선다)
@export var arrival_offset: Vector2 = Vector2(0, 24)

const GROUP := &"minimap_elevator"

var is_active: bool = true
var original_pos: Vector2

func _ready() -> void:
	add_to_group(GROUP)
	original_pos = position
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	# 층을 골라 화면이 바뀌는 중에도 다시 박으면 선택지가 또 뜨지 않게
	if not is_active or DialogueManager.is_dialogue_active or SceneTransition.is_transitioning: return
	
	if body.is_in_group("player"):
		var p = body as CharacterBody2D
		if p == null: return
		
		# [디버그] 어떤 상태로 부딪혔는지 확인
		DebugLog.info(str("ElevatorBlock 접촉! 플레이어 Y 속도: ", p.velocity.y))
		
		# 1. 플레이어가 위로 상승 중이거나, 거의 정지 상태(박은 직후)인 경우
		# 2. 플레이어의 위치가 블록의 중심보다 아래에 있는 경우 (아래에서 위로 박음)
		# velocity.y 체크를 -10.0 정도로 넉넉하게 잡거나, 
		# 이미 박아서 0이 된 경우를 대비해 위치 조건을 우선시합니다.
		if p.global_position.y > global_position.y:
			# 박치기 판정: 상승 중이거나, 점프 상태에서 머리가 닿았을 때
			if p.velocity.y < 50.0: # 떨어지는 중만 아니면 됨
				_hit_block()

func arrival_position() -> Vector2:
	return global_position + arrival_offset

func dialogue_block() -> String:
	if required_item_id.is_empty() or Inventory.is_equipped(required_item_id):
		return "start"
	return locked_block

func _hit_block() -> void:
	DebugLog.info("ElevatorBlock 작동!")
	# 블록 튕김 연출
	var tween = create_tween()
	# ... rest of the code
	tween.tween_property(self, "position:y", original_pos.y - bounce_height, bounce_speed / 2).set_trans(Tween.TRANS_SINE)
	tween.tween_property(self, "position:y", original_pos.y, bounce_speed / 2).set_trans(Tween.TRANS_SINE)
	
	if dialogue_file != "":
		DialogueManager.start_dialogue(dialogue_file, dialogue_block())
	
	# 필요하다면 일정 시간 쿨다운
	is_active = false
	await Wait.seconds(self, 1.0)
	is_active = true
