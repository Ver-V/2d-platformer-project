extends Panel

# [추가 1] 인벤토리 UI에게 보낼 신호 정의
signal slot_clicked

# 애니메이션 있는 아이템(ItemData.anim_frames)은 슬롯에서도 프레임 재생 + 둥둥 효과
const BOB_SPEED := 3.0
const BOB_RANGE := 1.5

@onready var icon: TextureRect = $Icon

var _anim_item: ItemData = null
var _anim_time: float = 0.0
var _icon_offset_top: float
var _icon_offset_bottom: float
var _icon_stretch_mode: TextureRect.StretchMode

func _ready() -> void:
	_icon_offset_top = icon.offset_top
	_icon_offset_bottom = icon.offset_bottom
	_icon_stretch_mode = icon.stretch_mode
	set_process(false)

func _gui_input(event: InputEvent) -> void:
	# [추가 2] 마우스 좌클릭 감지
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			# "나 클릭됐어요!"라고 신호를 보냄
			slot_clicked.emit()

func set_item(item: ItemData, inventory_index: int = -1):
	_set_anim_item(item if item != null and item.has_animation() else null)
	if item != null:
		# [핵심 변경] load() 필요 없음! 리소스 안에 이미 이미지가 들어있음.
		icon.texture = item.get_frame_at(_anim_time)
		icon.visible = true

		if item.id == "health_flask":
			$AmountLabel.text = str(GameManager.flask_current_charges) + "/" + str(GameManager.flask_max_charges)
			$AmountLabel.show()
		elif item.key_uses > 0 and inventory_index >= 0:
			$AmountLabel.text = str(Inventory.get_key_uses_for_slot(inventory_index))
			$AmountLabel.show()
		else:
			$AmountLabel.hide()
	else:
		icon.texture = null
		icon.visible = false
		$AmountLabel.hide()

func _set_anim_item(item: ItemData) -> void:
	if item == _anim_item:
		return # 인벤토리 새로고침마다 애니메이션이 처음으로 튀지 않게
	_anim_item = item
	_anim_time = randf_range(0.0, 10.0) if item != null else 0.0
	set_process(item != null)
	# 정사각형이 아닌 프레임(열쇠 18x29)이 찌그러지지 않게 비율 유지
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED if item != null else _icon_stretch_mode
	_set_icon_bob(0.0)

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_anim_time += delta
	icon.texture = _anim_item.get_frame_at(_anim_time)
	_set_icon_bob(sin(_anim_time * BOB_SPEED) * BOB_RANGE)

func _set_icon_bob(dy: float) -> void:
	icon.offset_top = _icon_offset_top + dy
	icon.offset_bottom = _icon_offset_bottom + dy
