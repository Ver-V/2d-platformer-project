extends Area2D

@export_file("*.json") var dialogue_file: String = ""
@export var bounce_height: float = 10.0
@export var bounce_speed: float = 0.2

var is_active: bool = true
var original_pos: Vector2

func _ready() -> void:
	original_pos = position
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if not is_active: return
	
	if body.is_in_group("player"):
		var p = body as CharacterBody2D
		# 1. 플레이어가 위로 상승 중인가? (velocity.y < 0)
		# 2. 플레이어가 블록보다 아래에 있는가?
		if p.velocity.y < 0 and p.global_position.y > global_position.y:
			_hit_block()

func _hit_block() -> void:
	# 블록 튕김 연출
	var tween = create_tween()
	tween.tween_property(self, "position:y", original_pos.y - bounce_height, bounce_speed / 2).set_trans(Tween.TRANS_SINE)
	tween.tween_property(self, "position:y", original_pos.y, bounce_speed / 2).set_trans(Tween.TRANS_SINE)
	
	if dialogue_file != "":
		DialogueManager.start_dialogue(dialogue_file)
	
	# 필요하다면 일정 시간 쿨다운
	is_active = false
	await get_tree().create_timer(1.0).timeout
	is_active = true
