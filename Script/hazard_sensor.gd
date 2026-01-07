extends Area2D
class_name HazardSensor

@export var knockback_force: float = 300.0

func _physics_process(_delta: float) -> void:
	var bodies = get_overlapping_bodies()
	if bodies.size() == 0: return 
		
	for body in bodies:
		if body is TileMapLayer or body is TileMap:
			
			# [여기에 추가!] ---------------------------------------------------
			# 부딪힌 타일맵 설정에 'damage'라는 데이터 층이 아예 없으면 무시합니다.
			# (일반 벽이나 바닥 타일맵 때문에 게임이 튕기는 것을 막아줍니다)
			if body.tile_set.get_custom_data_layer_by_name("damage") == -1:
				continue 
			# ----------------------------------------------------------------
			
			# 점 하나만 찌르지 말고, 센서 주변 5군데(중앙 + 상하좌우)를 검사함
			var check_offsets = [
				Vector2.ZERO,    # 중앙
				Vector2(0, 8),   # 아래 (가장 중요)
				Vector2(0, -4),  # 위
				Vector2(4, 4),   # 오른쪽 아래 대각선
				Vector2(-4, 4)   # 왼쪽 아래 대각선
			]
			
			for offset in check_offsets:
				# 센서 위치 + 오프셋 위치를 타일맵 로컬 좌표로 변환
				var check_pos = body.to_local(global_position + offset)
				var cell = body.local_to_map(check_pos)
				var data = body.get_cell_tile_data(cell)
				
				if data:
					# 위에서 검사했으므로 이제 안전하게 가져올 수 있음
					var dmg = data.get_custom_data("damage")
					if dmg > 0:
						_hurt_parent(dmg)
						return # 한 번 찾았으면 루프 종료

func _hurt_parent(amount: int) -> void:
	var parent = get_parent()
	if parent.has_method("apply_damage"):
		var final_kb = Vector2(0, -1).normalized() * knockback_force
		parent.apply_damage(amount, final_kb)
