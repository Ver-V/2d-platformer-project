extends Node2D
class_name PlayerVisuals

# 플레이어 연출: 머리 위 팝업, 먼지, 찌그러짐, 반격 보너스 오라, 몸 옆 게이지(상태이상·가드),
# 상태이상 화면 점멸 연동. 게임 규칙은 없고 보여주기만 한다. Player의 원점에 겹쳐 그린다.

@export var dust_particles_scene: PackedScene = preload("res://Scenes/System/DustParticles.tscn")

@export_group("Guard Cooldown Bar")
@export var show_guard_cooldown_bar: bool = true
@export var guard_bar_size: Vector2 = Vector2(34.0, 5.0)
@export var guard_bar_gap: float = 4.0
@export var guard_bar_x_offset: float = 0.0

@export_group("Status Effect Bar")
# 상태이상마다 몸 왼쪽에 세로 게이지 하나 (남은 양이 위에서 아래로 줄어듦). 여러 개면 왼쪽으로 나란히
@export var show_status_bars: bool = true
@export var status_bar_size: Vector2 = Vector2(5.0, 20.0) # 가드 게이지와 같은 두께, 몸 높이 정도
@export var status_bar_gap: float = 4.0     # 몸 왼쪽 끝과 첫 게이지 사이
@export var status_bar_spacing: float = 2.0 # 게이지끼리 간격
@export var status_bar_blink_period: float = 0.3 # 주의 상태(is_bar_warning)일 때 깜빡이는 주기(초)

var player: Player
var sprite: AnimatedSprite2D
var status_label: Label
var _status_tween: Tween
var _squash_tween: Tween
var _base_sprite_scale: Vector2 = Vector2.ONE

func setup(p: Player) -> void:
	player = p
	sprite = p.sprite
	status_label = p.status_label
	if sprite:
		_base_sprite_scale = sprite.scale
	var status := p.get_status_effects()
	status.effect_added.connect(_on_status_effect_added)
	status.effect_removed.connect(_on_status_effect_removed)

func _process(_delta: float) -> void:
	queue_redraw()
	# 반격 보너스 오라 (쉐이더)
	if sprite and sprite.material is ShaderMaterial:
		var bonus := player.combat.has_perfect_guard_bonus
		sprite.material.set_shader_parameter("glow_active", bonus)
		sprite.material.set_shader_parameter("glow_intensity", 2.0 if bonus else 0.0)

# --- 팝업 ---
func show_popup(text: String, color: Color = Color.YELLOW) -> void:
	if status_label == null: return
	if _status_tween:
		_status_tween.kill()
	status_label.text = text
	status_label.modulate = color
	status_label.visible = true
	status_label.position.y = -45.0
	status_label.modulate.a = 1.0

	_status_tween = create_tween()
	_status_tween.set_parallel(true)
	_status_tween.tween_property(status_label, "position:y", -75.0, 1.0).set_trans(Tween.TRANS_SINE)
	_status_tween.tween_property(status_label, "modulate:a", 0.0, 1.5).set_ease(Tween.EASE_IN)
	_status_tween.chain().tween_callback(func(): status_label.visible = false)

# 상황별 정해진 문구·색 (저장, 회복 등)
const STATUS_MESSAGES := {
	"save": [&"STATUS_SAVED", Color(0.347, 0.824, 0.885, 1.0)],
	"heal": [&"STATUS_HEALED", Color(1.0, 0.3, 0.3)],
	"mana": [&"STATUS_MANA_UP", Color(0.3, 0.3, 1.0)],
	"key": [&"STATUS_KEY_FOUND", Color(0.8, 0.8, 0.8)],
	"rest": [&"STATUS_RESTED", Color(0.429, 0.793, 0.33, 1.0)],
	"full": [&"STATUS_INVENTORY_FULL", Color.ORANGE],
}

func show_status(action_type: String) -> void:
	if STATUS_MESSAGES.has(action_type):
		var entry: Array = STATUS_MESSAGES[action_type]
		show_popup(tr(entry[0]), entry[1])
	else:
		show_popup("!", Color.WHITE)

# --- 먼지·찌그러짐 ---
func spawn_dust(offset: Vector2 = Vector2.ZERO, scale_mult: float = 1.0) -> void:
	if dust_particles_scene == null:
		return
	var target_parent := player.get_parent()
	if target_parent == null:
		target_parent = get_tree().current_scene
	if target_parent == null:
		return
	var dust: CPUParticles2D = dust_particles_scene.instantiate()
	dust.scale *= scale_mult # 강도에 따라 크기 조절
	Effects.emit_once(dust, target_parent, player.global_position + offset)

func apply_squash(x: float, y: float) -> void:
	if sprite == null:
		return
	if _squash_tween:
		_squash_tween.kill()
	_squash_tween = create_tween()
	sprite.scale = Vector2(_base_sprite_scale.x * x, _base_sprite_scale.y * y)
	_squash_tween.tween_property(sprite, "scale", _base_sprite_scale, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

# --- 상태이상 화면 점멸 ---
func _on_status_effect_added(effect: StatusEffect) -> void:
	if effect.screen_tint.a > 0.0:
		HUD.add_status_tint(effect.id, effect.screen_tint)

func _on_status_effect_removed(id: StringName) -> void:
	HUD.remove_status_tint(id)

# --- 게이지 ---
func _draw() -> void:
	if player == null or player.hp <= 0:
		return
	_draw_status_bars()
	_draw_guard_bar()

func _body_rect() -> Rect2:
	var col := player.collision_stand
	if col == null or col.shape == null:
		return Rect2()
	var r: Rect2 = col.shape.get_rect()
	var s := Vector2(absf(col.scale.x), absf(col.scale.y))
	return Rect2(col.position + r.position * s, r.size * s)

func _draw_status_bars() -> void:
	if not show_status_bars or status_bar_size.x <= 2.0 or status_bar_size.y <= 2.0:
		return
	var rects := get_status_bar_rects()
	var effects := player.get_status_effects().get_effects()
	for i in rects.size():
		var effect: StatusEffect = effects[i]
		var r: Rect2 = rects[i]
		draw_rect(r, Color.BLACK)
		var inner_h := (r.size.y - 2.0) * clampf(effect.get_progress(), 0.0, 1.0)
		# 아래쪽에 붙여 채우므로 남은 양이 줄면 위에서부터 내려온다
		draw_rect(Rect2(r.position.x + 1.0, r.end.y - 1.0 - inner_h, r.size.x - 2.0, inner_h), get_status_bar_color(effect))

# 주의 상태면 원래 색과 밝은 색을 번갈아 (양은 계속 보이도록 끄지 않고 밝게만)
func get_status_bar_color(effect: StatusEffect) -> Color:
	if effect.is_bar_warning() and status_bar_blink_period > 0.0:
		var phase := fmod(Time.get_ticks_msec() / 1000.0, status_bar_blink_period)
		if phase < status_bar_blink_period * 0.5:
			return effect.bar_color.lightened(0.6)
	return effect.bar_color

# 걸려 있는 상태이상 순서대로, 몸(서 있는 충돌체) 왼쪽에 세로 중앙을 맞춘 게이지 위치
func get_status_bar_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	var count := player.get_status_effects().get_effects().size()
	if count == 0:
		return out
	var body := _body_rect()
	var x := body.position.x - status_bar_gap - status_bar_size.x
	var top := body.get_center().y - status_bar_size.y * 0.5
	for i in count:
		out.append(Rect2(Vector2(x, top), status_bar_size))
		x -= status_bar_size.x + status_bar_spacing
	return out

func _draw_guard_bar() -> void:
	var guard := player.guard
	if not show_guard_cooldown_bar or (not guard.is_guarding and guard.cooldown_timer <= 0.0):
		return
	if guard_bar_size.x <= 2.0 or guard_bar_size.y <= 2.0:
		return
	var top_left := get_guard_bar_center() - guard_bar_size * 0.5
	draw_rect(Rect2(top_left, guard_bar_size), Color.BLACK)
	draw_rect(
		Rect2(top_left + Vector2.ONE, Vector2((guard_bar_size.x - 2.0) * guard.get_recharge_ratio(), guard_bar_size.y - 2.0)),
		Color(0.15, 0.55, 1.0, 1.0)
	)

# 애니메이션의 투명 여백이나 스쿼시에 흔들리지 않도록 발밑 충돌체에 맞춘다
func get_guard_bar_center() -> Vector2:
	var body := _body_rect()
	return Vector2(body.get_center().x + guard_bar_x_offset, body.end.y + guard_bar_gap + guard_bar_size.y * 0.5)
