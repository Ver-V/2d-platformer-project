extends CanvasLayer

@onready var menu_container: Control = $CenterContainer
@onready var options_ui: CanvasLayer = $OptionsUI
@onready var colorR: ColorRect = $ColorRect
var is_open: bool = false

func _ready():
	visible = false
	options_ui.visible = false
	is_open = false # 초기화
	options_ui.close_requested.connect(_on_options_closed)
		
func _on_options_closed():
	colorR.visible = true
	options_ui.visible = false
	menu_container.visible = true
	var resume_btn: Button = menu_container.get_node_or_null("CenterContainer/VBoxContainer/BtnResume")
	if resume_btn:
		resume_btn.grab_focus()
	
func _input(event):
	if event.is_action_pressed("ui_cancel"): # ESC 키
		
		# 1. 옵션 창이 열려있다면 옵션 창만 닫기
		if options_ui.visible:
			# ⭐ [핵심 3] 여기서 직접 코드를 쓰지 말고 위의 함수를 불러서 포커스까지 한방에 처리!
			_on_options_closed() 
			get_viewport().set_input_as_handled() # 입력 삼키기
			return
			
		# 2. 일시정지 창이 닫혀있는데, 다른 UI(인벤토리 등)가 열려있다면?
		if not is_open and GameManager.active_ui_count > 0:
			return # 아무것도 하지 않고 무시함
			
		# 3. 그 외의 상황 (정상적으로 일시정지 창 켜기/끄기)
		toggle_menu()
		get_viewport().set_input_as_handled() # 입력 삼키기

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
		var path = GameManager.last_scene_path
		# [수정] 경로가 유효하지 않으면 1번 스테이지(Stage_01)를 기본값으로 사용
		if path == "" or not ResourceLoader.exists(path):
			path = GameManager.get_stage_path(1)
			
		get_tree().paused = false
		get_tree().change_scene_to_file(path)

func _on_btn_exit_pressed():
	get_tree().change_scene_to_file("res://Scenes/System/MainMenu.tscn")
