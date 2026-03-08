@tool
extends Area2D

# 1. 수동 ID 및 돈/아이템 설정
@export var id: String = "" 
@export var gold_amount: int = 0 
@export var item_resource: ItemData:
	set(value):
		item_resource = value
		if Engine.is_editor_hint():
			_update_texture()

# [추가] 둥둥 떠다니는 설정
var time_passed: float = 0.0
var float_speed: float = 5.0
var float_range: float = 5.0

func _ready():
	_update_texture()
	
	if not Engine.is_editor_hint():
		# 1. 랜덤한 시간으로 시작 (아이템마다 서로 다르게 꿀렁거림)
		time_passed = randf_range(0.0, 10.0)
		
		# 2. ID 자동 생성 및 중복 확인
		if id == "":
			id = get_tree().current_scene.name + "/" + str(get_path())
		
		if GameManager.collected_items.has(id):
			queue_free() # 이미 먹은 거면 삭제
			return

func _process(delta):
	# 에디터에서는 움직이지 않게 함 (정신 사나움 방지)
	if Engine.is_editor_hint(): return
	
	# [핵심] 끊기지 않는 무한 둥둥 효과
	if has_node("Sprite2D"):
		time_passed = wrapf(time_passed + delta, 0.0, PI * 2.0)
		$Sprite2D.position.y = sin(time_passed * float_speed) * float_range

func _update_texture():
	if has_node("Sprite2D"):
		if item_resource != null:
			$Sprite2D.texture = item_resource.icon
		# (옵션) 코인일 경우, 에디터에 설정된 이미지가 있다면 건드리지 않음

func _on_body_entered(body: Node):
	if body.is_in_group("player"):
		
		var collected_success = false
		
		# [분기 1] 돈일 경우
		if gold_amount > 0:
			GameManager.update_gold(gold_amount)
			collected_success = true
			
		# [분기 2] 아이템일 경우
		elif item_resource != null:
			if GameManager.add_item(item_resource):
				collected_success = true
			else:
				if body.has_method("show_status"):
					body.show_status("full")
		# 획득 성공 시 처리
		if collected_success:
			GameManager.add_collected_item(id)
			queue_free()
