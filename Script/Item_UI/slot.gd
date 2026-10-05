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

func set_item(item: ItemData, inventory_index: int = -1):
	if item != null:
		# [핵심 변경] load() 필요 없음! 리소스 안에 이미 이미지가 들어있음.
		icon.texture = item.icon 
		icon.visible = true
		
		if item.id == "health_flask":
			$AmountLabel.text = str(GameManager.flask_current_charges) + "/" + str(GameManager.flask_max_charges)
			$AmountLabel.show()
		elif item.key_uses > 0 and inventory_index >= 0:
			$AmountLabel.text = str(GameManager.get_key_uses_for_slot(inventory_index))
			$AmountLabel.show()
		else:
			$AmountLabel.hide()
	else:
		icon.texture = null
		icon.visible = false
		$AmountLabel.hide()
