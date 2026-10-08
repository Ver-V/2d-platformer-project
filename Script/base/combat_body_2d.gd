extends CharacterBody2D
class_name CombatBody2D

# 기본 스탯
var max_hp: int = 1
var hp: int = 1
# 점프뛰고나서 아래쪽으로 공격하면서 툭 튕기는거 있으면 좋겠다는 의견도 있네

# [추가] 시각 효과 리소스
var hit_spark_scene: PackedScene = preload("res://Scenes/System/HitSpark.tscn")
var outline_shader: Shader = preload("res://resources/Shaders/outline.gdshader")

# 무적 종류: 피격 후 무적은 적 투사체를 흡수하고, 회피 무적(대시 등)은 통과시킨다
enum InvulnKind { HURT, DODGE }

# 상태 변수
var _invuln_left: float = 0.0
var _invuln_kind: InvulnKind = InvulnKind.HURT
var _knockback_left: float = 0.0
var _blink_accum: float = 0.0
var knockback_vel: Vector2 = Vector2.ZERO
var _status_effects: StatusEffects # get_status_effects()로 접근

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

func start_invuln(duration: float = -1.0, kind: InvulnKind = InvulnKind.HURT) -> void:
	var t: float = duration if duration >= 0.0 else get_invuln_time()
	_invuln_left = t
	_invuln_kind = kind
	_blink_accum = 0.0
	_update_blink_visibility(true) # 무적 시작 시 바로 보이게(혹은 설정에 따라)

func reset_combat_state() -> void:
	knockback_vel = Vector2.ZERO
	_invuln_left = 0.0
	_knockback_left = 0.0
	_blink_accum = 0.0
	_update_blink_visibility(true)
	clear_status_effects()

# --- 상태이상 ---
# 처음 필요할 때 자식 노드로 만든다 (씬마다 노드를 따로 넣을 필요 없음)
func get_status_effects() -> StatusEffects:
	if _status_effects == null or not is_instance_valid(_status_effects):
		_status_effects = StatusEffects.new()
		_status_effects.name = "StatusEffects"
		add_child(_status_effects)
	return _status_effects

func apply_status_effect(effect: StatusEffect) -> StatusEffect:
	return get_status_effects().apply(effect)

func has_status_effect(id: StringName) -> bool:
	return _status_effects != null and is_instance_valid(_status_effects) and _status_effects.has(id)

func clear_status_effects() -> void:
	if _status_effects != null and is_instance_valid(_status_effects):
		_status_effects.clear_all()

# 상태이상이 진행(시간 흐름·틱)해도 되는지. 비활성 방의 적 등은 하위 클래스에서 false.
func can_tick_status_effects() -> bool:
	return hp > 0

# 상태이상 피해: 무적·가드·넉백·히트스탑을 무시하고 HP만 깎는다.
func apply_status_damage(amount: int) -> bool:
	if amount <= 0 or hp <= 0: return false
	hp = maxi(0, hp - amount)
	_on_status_damaged(amount)
	if hp <= 0:
		velocity.x = 0
		_on_death()
	return true

func _on_status_damaged(_amount: int) -> void: pass
	
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

	# 1 = 안 밀림, 0 = 그대로, 음수 = 더 멀리 밀림 (-1이면 2배)
	var resist: float = minf(get_knockback_resist(), 1.0)
	knockback_vel = kb * (1.0 - resist)

# 편의를 위한 방향+힘 버전
func apply_knockback(knock_dir: Vector2, kb_x: float, kb_y: float = 0.0, ignore_cooldown: bool = false, cooldown: float = -1.0, reset_y: bool = true) -> void:
	if knock_dir == Vector2.ZERO: return
	var d: Vector2 = knock_dir.normalized()
	var final_vec := Vector2(d.x * kb_x, kb_y)
	apply_knockback_vec(final_vec, ignore_cooldown, cooldown, reset_y)

# --- 피격 처리 ---
# 모든 타격은 HitData.deliver(대상, hit) → receive_hit(hit)로 들어온다.
# 하위 클래스는 receive_hit을 오버라이드해 앞뒤 처리(가드, 비활성, 효과음 등)를 붙이고 super를 부른다.
func receive_hit(hit: HitData) -> HitData.Result:
	var result := _take_hit(hit)
	if result == HitData.Result.HIT:
		for effect in hit.status_effects:
			apply_status_effect(effect)
	return result

# 피해·무적·넉백만 처리한다 (상태이상 제외). 가드로 깎인 피해처럼 결과를 따로 정할 때 직접 쓴다.
func _take_hit(hit: HitData) -> HitData.Result:
	if hit.amount <= 0 or hp <= 0:
		return HitData.Result.IGNORED
	if is_invulnerable():
		return HitData.Result.EVADED if _invuln_kind == InvulnKind.DODGE else HitData.Result.INVULNERABLE

	# 사망 처리 전에 효과를 먼저 실행해야 쓰러뜨리는 타격에도 스파크·번쩍임이 보인다
	_play_hit_effects()

	hp -= hit.amount
	if hp <= 0:
		hp = 0
		velocity.x = 0
		_on_death()
		return HitData.Result.KILLED

	start_invuln(hit.invuln_time)
	if hit.knockback != Vector2.ZERO:
		apply_knockback_vec(hit.knockback, hit.ignore_knockback_cooldown, -1.0, true)
	return HitData.Result.HIT

# [추가] 피격 시 시각 효과 처리
func _play_hit_effects() -> void:
	# 1. 파티클 소환 (스파크)
	if hit_spark_scene:
		var spark = hit_spark_scene.instantiate()
		var target_parent = get_parent()
		if target_parent == null:
			target_parent = get_tree().current_scene
			
		if target_parent:
			spark.z_index = 100 # 다른 오브젝트보다 앞에 보이도록 설정
			Effects.emit_once(spark, target_parent, global_position)

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
