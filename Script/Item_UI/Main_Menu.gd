extends Control

# [설정] 새 게임 시작 시 이동할 첫 스테이지 경로 (반드시 수정하세요!)
const FIRST_LEVEL_PATH = "res://Scenes/Stage/Stage_01.tscn"

# [노드 참조] 씬 트리의 이름과 일치해야 합니다.
@onready var btn_load: Button = $VBoxContainer/BtnLoadGame
@onready var credits_panel: Panel = $CreditsPanel
@onready var options_ui: CanvasLayer = $OptionsUI

func _ready() -> void:
	CustomCursor.show_cursor()
	options_ui.visible = false

	# 옵션 창이 보낸 신호를 연결
	options_ui.close_requested.connect(_on_options_closed)
	
	# 1. 저장된 파일이 없으면 'Load Game' 버튼 비활성화 (클릭 불가)
	if not FileAccess.file_exists(GameManager.SAVE_PATH):
		btn_load.disabled = true
		btn_load.modulate = Color(1, 1, 1, 0.5) # 반투명하게 처리 (시각적 효과)

	# 2. 버튼 기능 연결 (에디터 시그널 대신 코드로 연결하면 관리하기 편함)
	$VBoxContainer/BtnNewGame.pressed.connect(_on_new_game_pressed)
	$VBoxContainer/BtnLoadGame.pressed.connect(_on_load_game_pressed)
	$VBoxContainer/BtnOptions.pressed.connect(_on_options_pressed)
	$VBoxContainer/BtnCredits.pressed.connect(_on_credits_pressed)
	$VBoxContainer/BtnExit.pressed.connect(_on_exit_pressed)

func _on_new_game_pressed() -> void:
	get_tree().change_scene_to_file("res://Scenes/Stage/Stage_tutorial.tscn")

func _on_continue_button_pressed() -> void: 
	if GameManager.load_game():
		var path = GameManager.last_scene_path
		if path == "" or not ResourceLoader.exists(path):
			path = "res://Scenes/Stage/Stage_tutorial.tscn"
		get_tree().change_scene_to_file(path)
	else:
		get_tree().change_scene_to_file("res://Scenes/Stage/Stage_tutorial.tscn")

func _on_load_game_pressed() -> void:
	_on_continue_button_pressed()

func _on_options_pressed() -> void:
	options_ui.visible = true
	
func _on_credits_pressed() -> void:
	credits_panel.visible = true

func _on_exit_pressed() -> void:
	get_tree().quit()
	
func _on_options_closed():
	options_ui.visible = false

func _close_panels() -> void:
	options_ui.visible = false
	credits_panel.visible = false
