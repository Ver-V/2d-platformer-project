@tool
extends StaticBody2D
class_name WoolBounce

# 양털 트램펄린: 플레이어가 위에 내려앉으면 튕겨 올린다 (판정·튕기기는 Player._try_bounce가 한다).
# 튕김이 바닥 점프 몫이라 튕긴 직후엔 공중 점프(더블 점프)가 다시 한 번 채워진다.
# 높이는 1:1: 떨어지기 시작한 높이(체공 최고점)까지 그대로 되돌려 보낸다. 더블 점프 후 내려앉으면 더블 점프 높이만큼,
# 보통 점프 후면 보통 점프 높이만큼 솟는다. 점프 키 입력과 상관없고, 튕겨 오르는 동안은 점프 컷도 없다.
# 단, 점프 한 번 높이보다 낮게 떨어졌으면(위에 서 있기 포함) 점프 한 번만큼 튕기고, 마지막으로 밟은 땅에서
# 점프 + 더블 점프로 닿는 높이보다 높이는 보내지 않는다 (튕김 → 더블 점프 반복으로 끝없이 올라가지 않게. 최대 = 땅 + 점프 3번)
# 원점 = 바닥 중앙. 크기는 width_tiles × 한 칸 높이.
# 그림(texture)이 타일 한 칸(16x16)이면 칸마다 반복해서 깔고, 그보다 크면 크기에 맞춰 한 장으로 그린다. 비우면 임시 양털을 그린다.
# 오토로드를 쓰지 않는다 (테스트가 클래스 이름으로 참조)

const TILE := 16.0
const COLOR_WOOL := Color(0.93, 0.91, 0.84)
const COLOR_WOOL_SHADE := Color(0.78, 0.75, 0.68)
const SQUASH_TIME := 0.25 # 튕긴 뒤 눌렸던 모양이 돌아오는 시간

@export_range(1, 16) var width_tiles: int = 2:
	set(value):
		width_tiles = value
		_apply_size()
@export var texture: Texture2D:
	set(value):
		texture = value
		queue_redraw()
@export var bounce_sound: AudioStream
@export var tutorial_key: StringName = &"TUTORIAL_WOOL_BOUNCE" # 처음 튕겼을 때 한 번 (Player._try_bounce)

var _shape := RectangleShape2D.new()
var _squash: float = 0.0 # 1 → 0: 튕긴 직후 눌린 정도

func _ready() -> void:
	_apply_size()
	set_process(false) # 눌렸다 돌아오는 동안만 켠다

func size() -> Vector2:
	return Vector2(width_tiles * TILE, TILE)

func _apply_size() -> void:
	if not is_inside_tree():
		return
	_shape.size = size()
	var cs := get_node_or_null(^"CollisionShape2D") as CollisionShape2D
	if cs:
		cs.shape = _shape
		cs.position = Vector2(0, -TILE * 0.5)
	queue_redraw()

# 위쪽 속도 speed로 뛰었을 때 실제로 오르는 높이. 바닥에서 뛰면(from_floor) 첫 프레임은 중력 없이 움직여 v·dt/2만큼 더,
# 공중에서 뛰면(더블 점프) 중력을 먼저 빼고 움직여 그만큼 덜 오른다
static func rise_height(gravity: float, speed: float, dt: float, from_floor: bool) -> float:
	if gravity <= 0.0:
		return 0.0
	return speed * speed / (2.0 * gravity) + speed * dt * (0.5 if from_floor else -0.5)

# 높이 height(px)까지 솟게 하는 위쪽 속도. 튕기는 프레임은 바닥이라 중력 없이 한 번 움직이고 그다음부터 프레임마다
# 중력을 먼저 빼고 움직이므로, 실제로 오르는 거리는 v²/2g + v·dt/2. 이 값이 height가 되는 v를 푼다
static func launch_speed(gravity: float, height: float, dt: float) -> float:
	if gravity <= 0.0 or height <= 0.0:
		return 0.0
	var half := gravity * dt * 0.5
	return -half + sqrt(half * half + 2.0 * gravity * height)

# 튕길 때 연출: 눌렸다 돌아오는 모양 + 소리
func play_bounce() -> void:
	_squash = 1.0
	set_process(true)
	queue_redraw()
	if bounce_sound != null:
		var sound := AudioStreamPlayer2D.new()
		add_child(sound)
		sound.bus = &"SFX"
		sound.stream = bounce_sound
		sound.finished.connect(sound.queue_free)
		sound.play()

func _process(delta: float) -> void:
	_squash = move_toward(_squash, 0.0, delta / SQUASH_TIME)
	if _squash <= 0.0:
		set_process(false)
	queue_redraw()

func _draw() -> void:
	# 바닥 중앙을 기준으로 납작하게 눌렀다가 돌아온다
	var s := ease(_squash, 0.5)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0 + 0.12 * s, 1.0 - 0.4 * s))
	var rect := Rect2(Vector2(-size().x * 0.5, -TILE), size())
	if texture != null:
		if texture.get_size() == Vector2(TILE, TILE):
			for x in width_tiles:
				draw_texture_rect(texture, Rect2(rect.position + Vector2(x * TILE, 0), Vector2(TILE, TILE)), false)
		else:
			draw_texture_rect(texture, rect, false)
		return
	# 임시 그림: 아래는 납작한 덩어리, 위는 동글동글한 털 뭉치
	draw_rect(Rect2(rect.position + Vector2(0, 6), Vector2(rect.size.x, 10)), COLOR_WOOL_SHADE)
	var bumps := width_tiles * 2
	var step := rect.size.x / bumps
	for i in bumps:
		var c := Vector2(rect.position.x + step * (i + 0.5), rect.position.y + 7.0)
		draw_circle(c, step * 0.6, COLOR_WOOL_SHADE)
		draw_circle(c + Vector2(0, -1), step * 0.5, COLOR_WOOL)
