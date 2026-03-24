extends CharacterBody2D
class_name CombatBody2D

# 기본 스탯
var max_hp: int = 1
var hp: int = 1

# 상태 변수
var _invuln_left: float = 0.0
var _knockback_left: float = 0.0
var _blink_accum: float = 0.0
var knockback_vel: Vector2 = Vector2.ZERO

# --- 자식 클래스에서 오버라이드할 가상 함수들 ---
func get_invuln_time() -> float: return 0.0
func get_blink_interval() -> float: return 0.0
func get_knockback_decay() -> float: return 0.0
func get_knockback_resist() -> float: return 0.0
func get_knockback_cooldown() -> float: return -1.0 # -1이면 invuln_time을 따름
func get_blink_node() -> CanvasItem: return null
func _on_death() -> void: pass

# --- 상태 확인 및 조작 ---
func is_invulnerable() -> bool:
	return _invuln_left > 0.0

func start_invuln(duration: float = -1.0) -> void:
	var t: float = duration if duration >= 0.0 else get_invuln_time()
	_invuln_left = t
	_blink_accum = 0.0
	_update_blink_visibility(true) # 무적 시작 시 바로 보이게(혹은 설정에 따라)

func reset_combat_state() -> void:
	knockback_vel = Vector2.ZERO
	_invuln_left = 0.0
	_knockback_left = 0.0
	_blink_accum = 0.0
	_update_blink_visibility(true)
	
func reset_motion() -> void:
	velocity = Vector2.ZERO
	reset_combat_state()

func _effective_knockback_cooldown(fallback: float = -1.0) -> float:
	if fallback >= 0.0: return fallback
	var c: float = get_knockback_cooldown()
	return c if c >= 0.0 else get_invuln_time()

func move_with_knockback(delta:float) -> void:
	var kb: Vector2 = update_knockback(delta)
	kb.x = clamp(kb.x, -2000, 2000)
	kb.y = clamp(kb.y, -2000, 2000)
	velocity += kb
	move_and_slide()
	velocity -= kb

func apply_knockback_vec(kb: Vector2, ignore_cooldown: bool = false, cooldown: float = -1.0, reset_y: bool = true) -> void:
	if kb == Vector2.ZERO: return
	if not ignore_cooldown and _knockback_left > 0.0: return

	_knockback_left = _effective_knockback_cooldown(cooldown)

	if reset_y:
		velocity.y = 0.0

	var resist: float = clamp(get_knockback_resist(), 0.0, 1.0)
	knockback_vel = kb * (1.0 - resist)

# 편의를 위한 방향+힘 버전
func apply_knockback(knock_dir: Vector2, kb_x: float, kb_y: float = 0.0, ignore_cooldown: bool = false, cooldown: float = -1.0, reset_y: bool = true) -> void:
	if knock_dir == Vector2.ZERO: return
	var d: Vector2 = knock_dir.normalized()
	var final_vec := Vector2(d.x * kb_x, kb_y)
	apply_knockback_vec(final_vec, ignore_cooldown, cooldown, reset_y)

# --- 데미지 처리 (핵심) ---
# CombatBody2D.gd

# 기존 함수: func apply_damage(amount: int, knockback: Vector2 = Vector2.ZERO, ignore_knockback_cooldown: bool = false) -> bool:
# [수정된 함수] 맨 뒤에 'override_invuln_time' 추가 (기본값 -1.0)
func apply_damage(amount: int, knockback: Vector2 = Vector2.ZERO, ignore_cd: bool = false, or_invuln_time: float = -1.0) -> bool:
	if amount <= 0: return false
	if hp <= 0: return false
	if is_invulnerable(): return false

	hp -= amount
	if hp <= 0:
		hp = 0
		velocity.x = 0
		_on_death()
		return true

	# [핵심 수정] 여기에 받아온 시간을 넣어줍니다.
	# -1.0이면 원래대로 기본값을 쓰고, 값이 들어왔으면(예: 2.0) 그 시간을 씁니다.
	start_invuln(or_invuln_time)
	
	if knockback != Vector2.ZERO:
		apply_knockback_vec(knockback, ignore_cd, -1.0, true)
	
	return true

# --- 물리 프로세스 (넉백 감소) ---
func update_knockback(delta: float) -> Vector2:
	var decay: float = get_knockback_decay()
	if decay > 0.0 and knockback_vel != Vector2.ZERO:
		knockback_vel = knockback_vel.move_toward(Vector2.ZERO, decay * delta)
	return knockback_vel

# --- 프로세스 (무적 깜빡임) ---
func _process(delta: float) -> void:
	if _knockback_left > 0.0:
		_knockback_left = max(0.0, _knockback_left - delta)

	if _invuln_left > 0.0:
		_invuln_left -= delta
		
		var bi: float = get_blink_interval()
		if bi > 0.0:
			_blink_accum += delta
			if _blink_accum >= bi:
				_blink_accum = 0.0
				var n := get_blink_node()
				if n != null: n.visible = not n.visible

		if _invuln_left <= 0.0:
			_invuln_left = 0.0
			_update_blink_visibility(true)

func _update_blink_visibility(is_vis: bool) -> void:
	var n := get_blink_node()
	if n != null:
		n.visible = is_vis
