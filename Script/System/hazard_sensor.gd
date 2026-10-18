extends Area2D
class_name HazardSensor

# 플레이어 몸에 붙은 가시 감지 영역. 영역 안 몇 군데를 찍어 "damage" 데이터가 있는 타일이면 피해를 준다.
# 방향 가시: 타일셋에 "spike_dir"(Vector2i, 그림에서 가시 끝이 향하는 쪽) 데이터가 있으면, 칠한 타일의 회전·뒤집기를
# 반영한 방향 n으로 판정한다 (셀레스트식) — 플레이어 몸 중심이 가시 끝 쪽에 있고((중심 - 타일 중심)·n > 0)
# 가시에서 멀어지는 중이 아닐 때(속도·n ≤ 0)만 아프다. 받침판(등) 쪽에 닿거나, 가시를 따라 뛰어오르며 스치면 안전.
# spike_dir가 없거나 (0, 0)이면 예전처럼 닿기만 해도 아프다.

@export var knockback_force: float = 300.0
@export var respawn_on_hit: bool = true # 맞고 살아 있으면 부모의 respawn_from_hazard()로 마지막 안전한 땅에서 다시 시작
@export var damage_invuln_time: float = 2.5 # [추가] 가시 전용 무적 시간 (에디터에서 수정 가능)

var _damage_timer: float = 0.0

# 1초에 60번 실행되는 물리 업데이트 함수입니다.
func _physics_process(delta: float) -> void:
	if _damage_timer > 0.0:
		_damage_timer -= delta
		return
		
	# 1. 센서 영역(CollisionShape)에 들어온 물체들을 다 가져옵니다.
	var bodies = get_overlapping_bodies()
	if bodies.size() == 0: 
		return 
		
	for body in bodies:
		# 타일맵인지 확인
		if body is TileMapLayer or body is TileMap:
			
			# [안전장치] 'damage' 데이터 층이 없는 타일맵은 무시
			if body.tile_set.get_custom_data_layer_by_name("damage") == -1:
				continue 
			
			# [핵심 수정] 개별 센서의 위치와 영역을 존중하도록 로직 변경
			# CollisionShape2D의 영역 내부에 있는 타일들만 정밀하게 체크합니다.
			
			# 1. 현재 센서 노드의 CollisionShape을 가져옴
			var shape_node = get_child(0) as CollisionShape2D
			if not shape_node: continue
			
			# 2. 쉐이프의 영역(Rect)을 계산
			var shape_rect = shape_node.shape.get_rect()
			var global_rect = Rect2(shape_node.global_position + shape_rect.position, shape_rect.size)
			
			# 3. 해당 영역 안의 포인트 몇 군데를 샘플링하여 타일 검사
			# (머리 센서든 발 센서든 상관없이 자기 영역 안만 감시함)
			var samples = [
				global_rect.position + global_rect.size * 0.5, # 중앙
				global_rect.position, # 좌상단
				global_rect.position + Vector2(global_rect.size.x, 0), # 우상단
				global_rect.position + Vector2(0, global_rect.size.y), # 좌하단
				global_rect.position + global_rect.size # 우하단
			]
			
			for pos in samples:
				var local_pos = body.to_local(pos)
				var cell = body.local_to_map(local_pos)
				var data
				if body is TileMapLayer:
					data = body.get_cell_tile_data(cell)
				elif body is TileMap:
					data = body.get_cell_tile_data(0, cell)
				
				if data and data.get_custom_data("damage") > 0:
					var spike_dir := spike_direction(body, cell, data)
					var cell_center: Vector2 = body.to_global(body.map_to_local(cell))
					if not spike_hurts(spike_dir, cell_center, _parent_center(), _parent_velocity()):
						continue
					_hurt_parent(data.get_custom_data("damage"), spike_dir)
					_damage_timer = damage_invuln_time
					return 

# 칠한 타일의 가시 방향 (월드 기준, 길이 1). 방향 데이터가 없으면 Vector2.ZERO.
# 회전·뒤집기는 셀의 대체 타일 번호에 섞인 플래그로 들어 있다: 전치(transpose) → 좌우 뒤집기 → 상하 뒤집기 순으로 적용
# (에디터의 "오른쪽으로 회전" = 전치 + 좌우 뒤집기 → 아래를 향한 가시가 왼쪽을 향한다)
static func spike_direction(layer: Node, cell: Vector2i, data: TileData) -> Vector2:
	var tile_set: TileSet = layer.get("tile_set")
	if data == null or tile_set == null or tile_set.get_custom_data_layer_by_name("spike_dir") == -1:
		return Vector2.ZERO
	var base: Vector2i = data.get_custom_data("spike_dir")
	if base == Vector2i.ZERO:
		return Vector2.ZERO
	var alt: int = layer.get_cell_alternative_tile(cell) if layer is TileMapLayer else layer.get_cell_alternative_tile(0, cell)
	var d := Vector2(base)
	if alt & TileSetAtlasSource.TRANSFORM_TRANSPOSE:
		d = Vector2(d.y, d.x)
	if alt & TileSetAtlasSource.TRANSFORM_FLIP_H:
		d.x = -d.x
	if alt & TileSetAtlasSource.TRANSFORM_FLIP_V:
		d.y = -d.y
	return d.normalized()

# 방향 가시가 아픈가: 몸 중심이 가시 끝 쪽에 있고, 가시에서 멀어지는 중이 아닐 때만. 방향이 없으면 늘 아프다
static func spike_hurts(dir: Vector2, cell_center: Vector2, body_center: Vector2, velocity: Vector2) -> bool:
	if dir == Vector2.ZERO:
		return true
	if (body_center - cell_center).dot(dir) <= 0.0:
		return false # 받침판(등) 쪽
	return velocity.dot(dir) <= 0.0

func _parent_center() -> Vector2:
	var parent := get_parent() as Node2D
	if parent == null:
		return global_position
	for child in parent.get_children():
		if child is CollisionShape2D and not child.disabled:
			return child.global_position
	return parent.global_position

func _parent_velocity() -> Vector2:
	var parent := get_parent() as CharacterBody2D
	return parent.velocity if parent != null else Vector2.ZERO

# 부모(플레이어)에게 데미지 주는 함수. spike_dir가 있으면 가시 끝 쪽으로 튕겨 낸다
func _hurt_parent(amount: int, spike_dir: Vector2 = Vector2.ZERO) -> void:
	var parent = get_parent()
	# 방향 없는 가시: 떨어지는 중이면 위로 튕겨 올린다
	var kb := Vector2.ZERO
	if spike_dir != Vector2.ZERO:
		kb = spike_dir * knockback_force
	elif parent is CharacterBody2D and parent.velocity.y >= 0:
		kb = Vector2.UP * knockback_force
	var hit := HitData.new(amount, kb, self)
	hit.invuln_time = damage_invuln_time # 가시 전용 (더 긴) 무적시간
	var result := HitData.deliver(parent, hit)
	# Player 클래스를 직접 쓰지 않는다 (테스트가 이 스크립트를 클래스 이름으로 참조하므로 오토로드 의존을 끌어오지 않게)
	if respawn_on_hit and result == HitData.Result.HIT and parent.has_method("respawn_from_hazard"):
		parent.respawn_from_hazard()
