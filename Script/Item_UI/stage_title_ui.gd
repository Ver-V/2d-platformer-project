extends CanvasLayer

@onready var label: Label = $Control/Label
@onready var control: Control = $Control

var _tween: Tween

func _ready() -> void:
	# 시작 시에는 숨겨둠
	control.modulate.a = 0.0
	visible = false

func play_title(title_key: StringName, duration: float = 3.0) -> void:
	# 번역 키를 그대로 넣으면 Label이 자동 번역하고, 표시 중에 언어를 바꿔도 바로 갱신된다.
	label.text = title_key
	visible = true
	
	# 이전 제목 연출이 아직 진행 중이면 끊고 새로 시작한다 (끝난 옛 트윈이 새 제목을 숨기지 않도록)
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	var tween := _tween
	
	# 1. 서서히 나타남 (Fade In)
	tween.tween_property(control, "modulate:a", 1.0, 1.0)
	
	# 2. 잠시 유지
	tween.tween_interval(duration)
	
	# 3. 서서히 사라짐 (Fade Out)
	tween.tween_property(control, "modulate:a", 0.0, 1.0)
	
	# 4. 완료 후 숨김 (await 대신 콜백: 실행 중 종료해도 트윈이 남지 않는다)
	tween.tween_callback(hide)
