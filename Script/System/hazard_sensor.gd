extends Area2D
class_name HazardSensor

@export var knockback_force: float = 300.0
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
					_hurt_parent(data.get_custom_data("damage"))
					_damage_timer = damage_invuln_time
					return 

# 부모(플레이어)에게 데미지 주는 함수
func _hurt_parent(amount: int) -> void:
	var parent = get_parent()
	if parent.has_method("apply_damage"):
		# [추가] 이미 죽었으면 데미지 무시
		if "hp" in parent and parent.hp <= 0:
			return
		
		# 넉백 계산 (위로 띄우거나, 0으로 하거나 취향대로)
		var final_kb = Vector2.ZERO 
		if "velocity" in parent and parent.velocity.y >= 0:
			final_kb = Vector2(0, -1).normalized() * knockback_force

		# [수정] 4번째 자리에 damage_invuln_time을 넣어줍니다!
		# apply_damage(데미지, 넉백, 넉백쿨무시여부, 무적시간)
		parent.apply_damage(amount, final_kb, false, damage_invuln_time)
