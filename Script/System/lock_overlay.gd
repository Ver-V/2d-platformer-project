extends CanvasLayer
class_name LockOverlay

# 잠긴 문을 열려고 할 때 화면 정중앙에 자물쇠를 크게 띄우고 주변을 살짝 어둡게 하는 연출.
# 대사창(DialogueUI, layer 1100)보다 아래, HUD·팝업·스테이지 타이틀보다 위에 그린다.
# 자물쇠 그림은 열쇠 아이템의 lock_sprite_frames ("locked" / "unlock")를 받는다.

@export var dim_alpha: float = 0.45 # 주변 어두워지는 정도 (0 ~ 1)
@export var fade_time: float = 0.2
@export var lock_scale: float = 6.0 # 픽셀아트가 뭉개지지 않게 정수 배율 권장

var dim: ColorRect
var sprite: AnimatedSprite2D
var _tween: Tween
var _showing: bool = false

func _ready() -> void:
	layer = 150
	dim = ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.color = Color(0, 0, 0, 0)
	add_child(dim)
	sprite = AnimatedSprite2D.new()
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(sprite)
	visible = false

func is_showing() -> bool:
	return _showing

# 자물쇠를 띄우고 anim_name을 재생한다. 그림·애니메이션이 없으면 아무것도 안 하고 false
func show_lock(frames: SpriteFrames, anim_name: StringName) -> bool:
	if frames == null or not frames.has_animation(anim_name):
		return false
	sprite.sprite_frames = frames
	sprite.position = get_viewport().get_visible_rect().size * 0.5
	sprite.play(anim_name)
	if not _showing:
		_showing = true
		visible = true
		_kill_tween()
		sprite.scale = Vector2.ONE * lock_scale * 0.8
		sprite.modulate.a = 0.0
		_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_tween.tween_property(dim, "color:a", dim_alpha, fade_time)
		_tween.tween_property(sprite, "modulate:a", 1.0, fade_time)
		_tween.tween_property(sprite, "scale", Vector2.ONE * lock_scale, fade_time)
	return true

func hide_lock() -> void:
	if not _showing:
		return
	_showing = false
	_kill_tween()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(dim, "color:a", 0.0, fade_time)
	_tween.tween_property(sprite, "modulate:a", 0.0, fade_time)
	_tween.chain().tween_callback(func():
		if not _showing:
			visible = false
			sprite.stop()
	)

# "unlock" 한 번 재생이 끝날 때까지 기다린 뒤 사라진다. 그림이 없으면 바로 끝
func play_unlock(frames: SpriteFrames) -> void:
	if not show_lock(frames, &"unlock"):
		return
	var duration := 0.0
	var fps := frames.get_animation_speed(&"unlock")
	for i in frames.get_frame_count(&"unlock"):
		duration += frames.get_frame_duration(&"unlock", i) / maxf(fps, 0.001)
	await Wait.seconds(self, duration + 0.15) # 풀린 모습을 잠깐 보여준다
	hide_lock()

func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
