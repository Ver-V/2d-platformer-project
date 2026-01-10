# MainMenu.gd

func _on_continue_button_pressed() -> void:
	# 1. 파일에서 데이터 불러오기
	GameManager.load_game()
	
	# 2. 저장된 씬이 있다면 거기로 이동 (GameManager가 알아서 함)
	# 만약 load_game 안에 respawn_player()가 없다면 여기서 직접 호출
	if GameManager.has_checkpoint:
		GameManager.respawn_player()
	else:
		print("저장된 데이터가 없어서 새 게임을 시작합니다.")
		get_tree().change_scene_to_file("res://Stage_01.tscn")

func _on_new_game_button_pressed() -> void:
	# 데이터 초기화 후 1스테이지로
	GameManager.reset_data()
	get_tree().change_scene_to_file("res://Stage_01.tscn")
