extends Control

# [설정] 새 게임 시작 시 이동할 첫 스테이지 경로 (반드시 수정하세요!)
const FIRST_LEVEL_PATH = "res://Scenes/Stage/Stage_tutorial.tscn"

# [노드 참조] 씬 트리의 이름과 일치해야 합니다.
@onready var btn_load: Button = $VBoxContainer/BtnLoadGame
@onready var credits_panel: Panel = $CreditsPanel
@onready var options_ui: CanvasLayer = $OptionsUI
@onready var new_game_dialog: ConfirmationDialog = $NewGameConfirmDialog

var slot_menu: SaveSlotMenu
var _pending_new_game_slot: int = 0 # 덮어쓰기 확인 중인 슬롯

func _ready() -> void:
	CustomCursor.show_cursor()
	options_ui.visible = false

	# 슬롯 도입 전 단일 세이브가 있으면 1번 슬롯으로 옮긴다
	SaveManager.migrate_legacy_save()

	# 옵션 창이 보낸 신호를 연결
	options_ui.close_requested.connect(_on_options_closed)
	new_game_dialog.confirmed.connect(_on_new_game_confirmed)

	# 세이브 슬롯 선택 화면 (메인 메뉴 버튼과 같은 글꼴)
	slot_menu = SaveSlotMenu.new()
	var menu_button: Button = $VBoxContainer/BtnNewGame
	slot_menu.font = menu_button.get_theme_font("font")
	slot_menu.font_size = menu_button.get_theme_font_size("font_size")
	add_child(slot_menu)
	move_child(slot_menu, new_game_dialog.get_index()) # 확인 창보다 아래에 그린다
	slot_menu.slot_chosen.connect(_on_slot_chosen)
	slot_menu.closed.connect(_on_slot_menu_closed)

	# 1. 저장된 슬롯이 하나도 없으면 'Load Game' 버튼 비활성화 (클릭 불가)
	_update_load_button()

	# 2. 버튼 기능 연결 (에디터 시그널 대신 코드로 연결하면 관리하기 편함)
	for button in $VBoxContainer.get_children():
		if button is Button:
			if not button.pressed.is_connected(GameManager.play_ui_click):
				button.pressed.connect(GameManager.play_ui_click)

	$VBoxContainer/BtnNewGame.pressed.connect(_on_new_game_pressed)
	$VBoxContainer/BtnLoadGame.pressed.connect(_on_load_game_pressed)
	$VBoxContainer/BtnOptions.pressed.connect(_on_options_pressed)
	$VBoxContainer/BtnCredits.pressed.connect(_on_credits_pressed)
	$VBoxContainer/BtnExit.pressed.connect(_on_exit_pressed)

func _update_load_button() -> void:
	var has_any := SaveManager.has_any_slot_save()
	btn_load.disabled = not has_any
	btn_load.modulate = Color(1, 1, 1, 1.0 if has_any else 0.5) # 반투명하게 처리 (시각적 효과)

func _on_new_game_pressed() -> void:
	slot_menu.open(SaveSlotMenu.Mode.NEW_GAME)

func _on_slot_chosen(slot: int, has_data: bool) -> void:
	if slot_menu.mode == SaveSlotMenu.Mode.LOAD:
		_load_slot(slot)
	elif has_data:
		# 저장된 슬롯이면 덮어쓰기 확인
		_pending_new_game_slot = slot
		new_game_dialog.dialog_text = tr(&"MAIN_MENU_SLOT_OVERWRITE_CONFIRM").format({"n": slot})
		new_game_dialog.popup_centered()
	else:
		_start_new_game(slot)

func _on_slot_menu_closed() -> void:
	$VBoxContainer/BtnNewGame.grab_focus()

func _on_new_game_confirmed() -> void:
	if _pending_new_game_slot <= 0:
		return
	SaveManager.delete_save(SaveManager.slot_path(_pending_new_game_slot))
	_start_new_game(_pending_new_game_slot)

func _start_new_game(slot: int) -> void:
	GameManager.current_slot = slot
	GameManager.reset_data()
	get_tree().change_scene_to_file(FIRST_LEVEL_PATH)

func _load_slot(slot: int) -> void:
	GameManager.current_slot = slot
	if GameManager.load_game():
		var path = GameManager.last_scene_path
		if path == "" or not ResourceLoader.exists(path):
			path = FIRST_LEVEL_PATH
		get_tree().change_scene_to_file(path)
	else:
		# 그 사이 파일이 지워졌거나 손상됨: 화면만 갱신
		slot_menu.refresh()
		_update_load_button()

func _on_load_game_pressed() -> void:
	slot_menu.open(SaveSlotMenu.Mode.LOAD)

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
