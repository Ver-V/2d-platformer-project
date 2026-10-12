extends Area2D
class_name Shockwave

# 땅을 따라 한쪽(dir)으로 퍼지는 충격파. 높이 height(기본 4타일)라 일반 점프로는 못 넘는다
# (더블 점프나 공중 발판으로 피한다). 지형에 막히거나 max_distance를 가면 사라진다. 그림 없이 그린다.

const PLAYER_HURTBOX_MASK := 256

var dir: int = 1
var speed: float = 260.0
var height: float = 64.0
var width: float = 14.0
var damage: int = 20
var max_distance: float = 640.0
var source: Node = null

var _traveled: float = 0.0
var _hit: bool = false

func _ready() -> void:
	collision_layer = 0
	collision_mask = PLAYER_HURTBOX_MASK
	monitorable = false
	z_index = 40
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(width, height)
	shape.shape = rect
	shape.position = Vector2(0, -height * 0.5)
	add_child(shape)
	area_entered.connect(_on_area_entered)

func _physics_process(delta: float) -> void:
	var step := dir * speed * delta
	global_position.x += step
	_traveled += absf(step)
	if _traveled >= max_distance or _blocked():
		queue_free()
		return
	queue_redraw()

# 앞쪽 발밑 바로 위가 지형이면 벽에 막힌 것
func _blocked() -> bool:
	var query := PhysicsPointQueryParameters2D.new()
	query.position = global_position + Vector2(dir * width * 0.5, -8.0)
	query.collision_mask = 1
	return not get_world_2d().direct_space_state.intersect_point(query, 1).is_empty()

func _on_area_entered(area: Area2D) -> void:
	if _hit or not area is Hurtbox:
		return
	_hit = true # 한 번만 맞힌다
	HitData.deliver(area, HitData.new(damage, Vector2(dir * 260.0, -220.0), source))

func _draw() -> void:
	var t := 1.0 - _traveled / max_distance
	draw_rect(Rect2(-width * 0.5, -height, width, height), Color(1.0, 0.85, 0.55, 0.35 * t + 0.15))
	draw_rect(Rect2(-width * 0.5 + dir * 3.0, -height, 3.0, height), Color(1.0, 0.95, 0.8, 0.8 * t))
