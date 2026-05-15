# SaveManager.gd
extends Node

const SAVE_PATH = "user://save_game.json"

func save_game(data: Dictionary) -> void:
	# 플레이어 체력 0이하면 저장 안하기 (GameManager에서 체크하지만 여기서도 안전장치)
	if data.get("current_hp", 0) <= 0:
		return
	
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		var json_string = JSON.stringify(data)
		file.store_string(json_string)
		print("SaveManager: 게임 저장 완료!")
	else:
		print("SaveManager: 게임 저장 실패! 경로 오류: ", FileAccess.get_open_error())

func load_game() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		print("SaveManager: 저장된 파일이 없습니다.")
		return {}
	
	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		print("SaveManager: 파일 열기 실패! (에러 코드: ", FileAccess.get_open_error(), ")")
		return {}

	var json_string = file.get_as_text()
	var data = JSON.parse_string(json_string)
	
	if data and typeof(data) == TYPE_DICTIONARY:
		print("SaveManager: 데이터 로드 성공")
		return data
		
	return {}

func delete_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
		print("SaveManager: 세이브 파일 삭제됨")
