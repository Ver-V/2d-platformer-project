extends CharacterBody2D
class_name CombatBody2D

# 기본 스탯
var max_hp: int = 1
var hp: int = 1

# [추가] 시각 효과 리소스
var hit_spark_scene: PackedScene = preload("res://Scenes/System/HitSpark.tscn")
var outline_shader: Shader = preload("res://resources/Shaders/outline.gdshader")

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

func _ready() -> void:
	_setup_outline_material()

# [추가] 쉐이더 마테리얼 자동 설정
func _setup_outline_material() -> void:
	var node = get_blink_node()
	if node and outline_shader:
		# 이미 올바른 쉐이더 마테리얼이 설정되어 있는지 확인
		if node.material is ShaderMaterial and node.material.shader == outline_shader:
			return # 이미 설정되어 있다면 재사용
			
		var mat = ShaderMaterial.new()
		mat.shader = outline_shader
		# 기본값 설정
		mat.set_shader_parameter("outline_color", Color(1, 1, 1, 1)) # 흰색 외곽선
		mat.set_shader_parameter("outline_width", 1.0)
		mat.set_shader_parameter("is_active", false)
		mat.set_shader_parameter("flash_modifier", 0.0) # 텔레포트 초기값
		node.material = mat

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

	if reset_y and is_on_floor():
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
func apply_damage(amount: int, knockback: Vector2 = Vector2.ZERO, ignore_cd: bool = false, or_invuln_time: float = -1.0, is_projectile: bool = false) -> bool:
	if amount <= 0: return false
	if hp <= 0: return false
	if is_invulnerable(): return false

	# [핵심 수정] 데미지 계산 및 사망 처리(hp <= 0) 전에 효과를 먼저 실행
	# 이렇게 해야 플레이어가 적을 죽이는 순간에도 피격 효과(스파크, 번쩍임)가 보입니다.
	_play_hit_effects()

	hp -= amount
	if hp <= 0:
		hp = 0
		velocity.x = 0
		_on_death()
		return true

	# 무적 시간 적용
	start_invuln(or_invuln_time)
	
	if knockback != Vector2.ZERO:
		apply_knockback_vec(knockback, ignore_cd, -1.0, true)
	
	return true

# [추가] 피격 시 시각 효과 처리
func _play_hit_effects() -> void:
	# 1. 파티클 소환 (스파크)
	if hit_spark_scene:
		var spark = hit_spark_scene.instantiate()
		var target_parent = get_parent()
		if target_parent == null:
			target_parent = get_tree().current_scene
			
		if target_parent:
			target_parent.add_child(spark)
			spark.global_position = global_position
			spark.z_index = 100 # 다른 오브젝트보다 앞에 보이도록 설정
			spark.emitting = true
			get_tree().create_timer(spark.lifetime).timeout.connect(func(): if is_instance_valid(spark): spark.queue_free())

	# 2. 쉐이더 플래시 효과 (하얗게 번쩍임)
	var node = get_blink_node()
	if node and node.material is ShaderMaterial:
		# 단순히 외곽선(is_active)만 켜는 게 아니라, 몸 전체를 하얗게(flash_modifier) 만듭니다.
		node.material.set_shader_parameter("flash_modifier", 1.0)
		# 아주 짧은 시간(0.1초) 후 원래대로 복구
		get_tree().create_timer(0.1).timeout.connect(func():
			if is_instance_valid(node) and node.material is ShaderMaterial:
				node.material.set_shader_parameter("flash_modifier", 0.0)
		)

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
