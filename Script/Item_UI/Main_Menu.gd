extends Control

# [설정] 새 게임 시작 시 이동할 첫 스테이지 경로 (반드시 수정하세요!)
const FIRST_LEVEL_PATH = "res://Stage_01.tscn"

# [노드 참조] 씬 트리의 이름과 일치해야 합니다.
@onready var btn_load: Button = $VBoxContainer/BtnLoadGame
@onready var options_panel: Panel = $OptionsPanel
@onready var credits_panel: Panel = $CreditsPanel

func _ready() -> void:
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

# --- [기능 1] 새 게임 (New Game) ---
func _on_new_game_pressed() -> void:
	print("✨ 새 게임 시작")
	
	# 1. 이전 데이터(돈, 아이템 등) 싹 초기화
	GameManager.reset_data()
	
	# 2. 첫 스테이지로 이동
	get_tree().change_scene_to_file(FIRST_LEVEL_PATH)

# --- [기능 2] 이어하기 (Load Game) ---
func _on_continue_button_pressed() -> void: # 혹은 _on_load_game_pressed
	print("📂 불러오기 시도...")
	
	# 1. 파일 로드 시도
	if GameManager.load_game():
		# 로드 성공!
		if GameManager.last_scene_path != "":
			print("✅ 저장된 위치로 이동: ", GameManager.last_scene_path)
			
			# 저장된 씬으로 이동 (플레이어 위치는 각 씬의 _ready에서 GameManager.last_checkpoint_pos를 보고 잡음)
			get_tree().change_scene_to_file(GameManager.last_scene_path)
		else:
			# 저장된 씬 정보가 이상하면 그냥 첫 스테이지로 (안전장치)
			print("⚠️ 씬 정보 없음. 첫 스테이지로 이동")
			get_tree().change_scene_to_file(FIRST_LEVEL_PATH)
	else:
		# 로드 실패 (파일 깨짐 등)
		print("❌ 로드 실패! 새 게임을 시작합니다.")
		GameManager.reset_data()
		get_tree().change_scene_to_file(FIRST_LEVEL_PATH)
		
# --- 이어하기 버튼과 이름 통일용 (함수 연결) ---
func _on_load_game_pressed() -> void:
	_on_continue_button_pressed()

# --- [기능 3] 옵션 (Options) ---
func _on_options_pressed() -> void:
	options_panel.visible = true

# --- [기능 4] 크레딧 (Credits) ---
func _on_credits_pressed() -> void:
	credits_panel.visible = true

# --- [기능 5] 종료 (Exit) ---
func _on_exit_pressed() -> void:
	print("👋 게임 종료")
	get_tree().quit()

# (보너스) 패널 닫기 버튼용 함수 (옵션 창 안의 '닫기' 버튼에 연결하세요)
func _close_panels() -> void:
	options_panel.visible = false
	credits_panel.visible = false
