@tool
extends Area2D

# 수동 ID 및 돈/아이템 설정
@export var id: String = "" 
@export var gold_amount: int = 0 
@export var item_resource: ItemData:
	set(value):
		item_resource = value
		if Engine.is_editor_hint():
			_update_texture()

@export var collection_tutorial_key: StringName = &"" # 획득 시 띄울 튜토리얼 번역 키

const ANIM_NODE_NAME := "ItemAnim"

# 둥둥 떠다니는 설정
var time_passed: float = 0.0
var float_speed: float = 5.0
var float_range: float = 5.0

func _ready():
	_update_texture()
	
	if not Engine.is_editor_hint():
		#  랜덤한 시간으로 시작 
		time_passed = randf_range(0.0, 10.0)
		
		#  ID 자동 생성 및 중복 확인
		if id == "":
			var current_scene = get_tree().current_scene
			if current_scene:
				id = current_scene.name + "/" + str(get_path())
			else:
				id = "unknown_scene/" + str(get_path())
		
		if GameManager.collected_items.has(id):
			queue_free() # 이미 먹은 거면 삭제
			return

func _process(delta):
	if Engine.is_editor_hint(): return
	
	# 끊기지 않는 무한 둥둥 효과
	if has_node("Sprite2D"):
		time_passed = wrapf(time_passed + delta, 0.0, PI * 2.0)
		$Sprite2D.position.y = sin(time_passed * float_speed) * float_range

func _update_texture():
	if not has_node("Sprite2D"):
		return
	var sprite: Sprite2D = $Sprite2D
	# 애니메이션은 Sprite2D 자식으로 붙여서 둥둥 효과·획득 시 숨김을 그대로 따라가게 한다 (씬에는 저장 안 됨)
	var anim := sprite.get_node_or_null(ANIM_NODE_NAME) as AnimatedSprite2D
	# ItemData는 @tool이 아니라 에디터에선 함수 호출이 안 된다 → 속성만 직접 확인
	var frames: SpriteFrames = item_resource.anim_frames if item_resource != null else null
	if frames != null and frames.has_animation(item_resource.anim_name):
		sprite.texture = null
		if anim == null:
			anim = AnimatedSprite2D.new()
			anim.name = ANIM_NODE_NAME
			sprite.add_child(anim)
		anim.sprite_frames = frames
		anim.play(item_resource.anim_name)
		return
	if anim != null:
		sprite.remove_child(anim)
		anim.queue_free()
	if item_resource != null:
		sprite.texture = item_resource.icon
	# 코인일 경우, 에디터에 설정된 이미지가 있다면 건드리지 않음

func _on_body_entered(body: Node):
	if body.is_in_group("player"):
		
		var collected_success = false
		
		# [분기 1] 돈일 경우
		if gold_amount > 0:
			GameManager.update_gold(gold_amount)
			collected_success = true
			
		# [분기 2] 아이템일 경우
		elif item_resource != null:
			if Inventory.add_item(item_resource):
				collected_success = true
			else:
				if body.has_method("show_status"):
					body.show_status("full")
		
		# 획득 성공 시 처리
		if collected_success:
			# 즉시 비활성화
			$CollisionShape2D.set_deferred("disabled", true)
			$Sprite2D.visible = false
			
			# 튜토리얼 텍스트가 설정되어 있다면 팝업 띄우기
			if collection_tutorial_key != &"":
				if has_node("/root/TutorialPopup"):
					get_node("/root/TutorialPopup").display(collection_tutorial_key)
			
			GameManager.add_collected_item(id)
			
			# 효과음 재생
			if has_node("SFX"):
				$SFX.play()
				await $SFX.finished
				
			if not is_instance_valid(self): return
			queue_free()
