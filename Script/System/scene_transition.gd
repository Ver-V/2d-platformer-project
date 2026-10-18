extends CanvasLayer

@onready var color_rect = $ColorRect

# 어두워지기 시작해서 다시 밝아지기 시작할 때까지 true. 그동안 플레이어 조작을 막고, 겹쳐 들어온 전환은 무시한다
# (엘리베이터로 이동하는 중에 다시 블록을 박아 층 선택이 또 뜨던 버그 등)
var is_transitioning: bool = false

func _ready():
	# 도착한 씬에서 도움말 팝업이 트리를 일시정지해도 페이드가 끝까지 돌아야 한다 (멈추면 검은 화면에 갇힘)
	process_mode = Node.PROCESS_MODE_ALWAYS
	color_rect.modulate.a = 0.0

# action: 화면이 깜깜해졌을 때 실행할 '함수'를 받습니다.
func start_transition(action: Callable, duration: float = 1.0) -> void:
	if not _begin():
		return
	# 1. 트윈 생성
	var tween = create_tween()
	
	# 2. [Fade Out] 어두워짐
	tween.tween_property(color_rect, "modulate:a", 1.0, duration * 0.5)
	await tween.finished
	
	# 3. [핵심] 전달받은 행동(재시작 등)을 여기서 실행!
	# SceneTransition은 오토로드라서 씬이 바뀌어도 살아있으므로 이 코드를 실행해줄 수 있음.
	if action.is_valid():
		action.call()
	
	# 4. [Fade In] 다시 밝아짐
	# (씬이 로딩될 시간을 아주 조금 벌어주기 위해 0.1초 대기 추가 가능)
	await get_tree().create_timer(0.5).timeout 
	_end()
	
	tween = create_tween()
	tween.tween_property(color_rect, "modulate:a", 0.0, duration * 0.5)

# 엘리베이터: 출발할 때 덜컹 흔들리며 어두워지고, 새 층에서 다시 덜컹 멈추는 흔들림과 함께 밝아진다 (Fade In)
func start_elevator_transition(action: Callable, duration: float = 1.4, shake_amount: float = 7.0, arrival_shake: float = 9.0) -> void:
	if not _begin():
		return
	_shake_current_scene(shake_amount)
	
	var tween = create_tween()
	tween.tween_property(color_rect, "modulate:a", 1.0, duration * 0.55)
	await tween.finished
	
	if action.is_valid():
		action.call()
	
	await get_tree().create_timer(0.35).timeout
	_end()
	
	_shake_current_scene(arrival_shake) # 바뀐 씬(도착한 층)의 카메라
	tween = create_tween()
	tween.tween_property(color_rect, "modulate:a", 0.0, duration * 0.6).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)

func _begin() -> bool:
	if is_transitioning:
		return false
	is_transitioning = true
	GameManager.ui_opened(self, false)
	return true

func _end() -> void:
	is_transitioning = false
	GameManager.ui_closed(self)

func _shake_current_scene(amount: float) -> void:
	var scene := get_tree().current_scene
	if scene and scene.has_method("apply_camera_shake"):
		scene.apply_camera_shake(amount)
