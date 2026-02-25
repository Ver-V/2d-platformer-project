extends CanvasLayer

@onready var menu_container: Control = $CenterContainer
@onready var options_ui: CanvasLayer = $OptionsUI
@onready var colorR: ColorRect = $ColorRect
var is_open: bool = false

func _ready():
	visible = false
	options_ui.visible = false
	is_open = false # 초기화
	
	if options_ui.has_signal("close_requested"):
		options_ui.close_requested.connect(_on_options_closed)
		
func _on_options_closed():
	colorR.visible = true
	options_ui.visible = false
	menu_container.visible = true
	
func _input(event):
	if event.is_action_pressed("ui_cancel"): # ESC 키
		
		# 1. 옵션 창이 열려있다면 옵션 창만 닫기
		if options_ui.visible:
			options_ui.visible = false
			colorR.visible = true
			menu_container.visible = true
			get_viewport().set_input_as_handled() # [핵심] 입력 삼키기
			return
			
		# 2. 일시정지 창이 닫혀있는데, 다른 UI(인벤토리 등)가 열려있다면?
		if not is_open and GameManager.active_ui_count > 0:
			return # 아무것도 하지 않고 무시함 (인벤토리만 닫히게 둠)
			
		# 3. 그 외의 상황 (정상적으로 일시정지 창 켜기/끄기)
		toggle_menu()
		get_viewport().set_input_as_handled() # [핵심] 입력 삼키기

func toggle_menu():
	# GameManager 변수를 직접 건드리지 않고, 자기 자신의 변수만 뒤집음!
	is_open = !is_open 
	visible = is_open

	if is_open:
		colorR.visible = true
		menu_container.visible = true
		options_ui.visible = false
		GameManager.ui_opened() # "나 열렸으니까 마우스 커서 좀 켜줘!" (요청)
	else:
		GameManager.ui_closed() # "나 닫혔으니까 알아서 마우스 꺼줘!" (요청)


func _on_btn_resume_pressed():
	toggle_menu()

func _on_btn_options_pressed():
	colorR.visible = false
	menu_container.visible = false
	options_ui.visible = true

func _on_btn_load_pressed():
	if GameManager.load_game():
		if GameManager.last_scene_path != "":	
			get_tree().change_scene_to_file(GameManager.last_scene_path)

func _on_btn_exit_pressed():
	get_tree().change_scene_to_file("res://Scenes/System/MainMenu.tscn")
