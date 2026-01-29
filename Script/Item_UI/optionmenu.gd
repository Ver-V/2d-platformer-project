extends Node2D

func _input(event):
	if event.is_action_pressed("ui_cancel"): # ESC 키
		if visible:
			close_option()
		else:
			open_option()

func open_option():
	visible = true
	# get_tree().paused = true  <-- 삭제!
	
	# 마우스 커서 보이게 (메뉴 클릭해야 하니까)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func close_option():
	visible = false
	# get_tree().paused = false <-- 삭제!
	
	# 다시 게임 플레이 모드로 (마우스 숨김)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
