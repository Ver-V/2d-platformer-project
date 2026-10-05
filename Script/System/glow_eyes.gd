extends Sprite2D
class_name GlowEyes

# 시야 제한(VisionLimit)의 어둠보다 위에 그려지는 눈.
# 몸통 시트와 같은 캔버스 크기·프레임 순서로 눈만 찍은 시트를 쓴다 (예: 32x32 4프레임 → 128x32, hframes = 4).
# 적 씬에서 몸통 AnimatedSprite2D의 형제로 두면 몸통의 위치·크기·좌우 반전·프레임을 매 프레임 그대로 따라간다.
# 따라서 걷기 중 위아래 흔들림, 피격 스쿼시, 피격 깜빡임에 자동으로 맞춰지고, 주인이 죽으면 꺼진다.

const Z_INDEX: int = RenderingServer.CANVAS_ITEM_Z_MAX # VisionLimit.Z_INDEX보다 한 칸 위

@export var body_sprite_path: NodePath = ^"../AnimatedSprite2D"
# 이 애니메이션들에서만 몸통 프레임을 따라간다. 비워두면 모든 애니메이션. 그 외 애니메이션에선 sync_fallback_frame 표시
@export var synced_animations: Array[StringName] = []
@export var sync_fallback_frame: int = 0
@export var blink_interval: Vector2 = Vector2(2.0, 5.0) # 눈 깜빡임 간격(초). y <= 0 이면 안 깜빡임
@export var blink_duration: float = 0.12

var _body: AnimatedSprite2D
var _owner_body: Node
var _blink_timer: float = 0.0
var _blink_closed_timer: float = 0.0

func _ready() -> void:
	z_index = Z_INDEX
	z_as_relative = false
	_body = get_node_or_null(body_sprite_path) as AnimatedSprite2D
	_owner_body = get_parent()
	_reset_blink()

func _process(delta: float) -> void:
	_follow_body()
	_update_blink(delta)
	visible = _should_show()

func _should_show() -> bool:
	if _owner_body != null and "hp" in _owner_body and int(_owner_body.get("hp")) <= 0:
		return false
	if _body != null and not _body.visible: # 피격 깜빡임 동기화
		return false
	return _blink_closed_timer <= 0.0

func _follow_body() -> void:
	if _body == null:
		return
	position = _body.position
	scale = _body.scale
	rotation = _body.rotation
	offset = _body.offset
	centered = _body.centered
	flip_h = _body.flip_h
	flip_v = _body.flip_v
	var total := hframes * vframes
	var f := _body.frame
	if not synced_animations.is_empty() and not synced_animations.has(_body.animation):
		f = sync_fallback_frame
	frame = clampi(f, 0, total - 1)

func _update_blink(delta: float) -> void:
	if _blink_closed_timer > 0.0:
		_blink_closed_timer -= delta
	if blink_interval.y <= 0.0:
		return
	_blink_timer -= delta
	if _blink_timer <= 0.0:
		_blink_closed_timer = blink_duration
		_reset_blink()

func _reset_blink() -> void:
	_blink_timer = randf_range(blink_interval.x, blink_interval.y)
