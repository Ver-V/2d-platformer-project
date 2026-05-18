extends CanvasLayer

@onready var label: Label = $Control/Label
@onready var control: Control = $Control

func _ready() -> void:
	# 시작 시에는 숨겨둠
	control.modulate.a = 0.0
	visible = false

func play_title(title_text: String, duration: float = 3.0) -> void:
	label.text = title_text
	visible = true
	
	var tween = create_tween()
	
	# 1. 서서히 나타남 (Fade In)
	tween.tween_property(control, "modulate:a", 1.0, 1.0)
	
	# 2. 잠시 유지
	tween.tween_interval(duration)
	
	# 3. 서서히 사라짐 (Fade Out)
	tween.tween_property(control, "modulate:a", 0.0, 1.0)
	
	# 4. 완료 후 숨김
	await tween.finished
	visible = false
