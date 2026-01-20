extends Panel

# [추가 1] 인벤토리 UI에게 보낼 신호 정의
signal slot_clicked

@onready var icon: TextureRect = $Icon

func _gui_input(event: InputEvent) -> void:
	# [추가 2] 마우스 좌클릭 감지
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			# "나 클릭됐어요!"라고 신호를 보냄
			slot_clicked.emit()

func set_item(item_data):
	if item_data != null:
		# 주의: item_data가 리소스인지 딕셔너리인지에 따라 접근법이 다릅니다.
		# 딕셔너리(JSON) 방식이라면 아래가 맞습니다.
		if item_data.has("icon_path"):
			icon.texture = load(item_data["icon_path"])
		icon.visible = true
	else:
		icon.visible = false
