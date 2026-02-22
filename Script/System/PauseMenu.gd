extends CanvasLayer

@onready var menu_container: Control = $CenterContainer
@onready var options_ui: CanvasLayer = $OptionsUI

func _ready():
	visible = false
	options_ui.visible = false
	
	# 시작할 때 메뉴 닫힘 상태
	GameManager.is_menu_open = false
	
	if options_ui.has_signal("close_requested"):
		options_ui.close_requested.connect(_on_options_closed)

func _on_options_closed():
	options_ui.visible = false
	menu_container.visible = true
	
func _input(event):
	if event.is_action_pressed("ui_cancel"): # ESC 키
		if options_ui.visible:
			options_ui.visible = false
			menu_container.visible = true
			return
		
		toggle_menu()

func toggle_menu():
	# 상태 뒤집기 (True <-> False)
	GameManager.is_menu_open = !GameManager.is_menu_open
	
	visible = GameManager.is_menu_open

	if visible:
		menu_container.visible = true
		options_ui.visible = false
		CustomCursor.show_cursor()
	else:
		CustomCursor.hide_cursor()


func _on_btn_resume_pressed():
	toggle_menu()

func _on_btn_options_pressed():
	menu_container.visible = false
	options_ui.visible = true

func _on_btn_load_pressed():
	if GameManager.load_game():
		if GameManager.last_scene_path != "":	
			get_tree().change_scene_to_file(GameManager.last_scene_path)

func _on_btn_exit_pressed():
	get_tree().change_scene_to_file("res://Scenes/Player/MainMenu.tscn")
