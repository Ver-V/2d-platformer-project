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
			
			# [안전장치] 'damage' 데이터 층이 없는 타일맵은 무시 (게임 튕김 방지)
			if body.tile_set.get_custom_data_layer_by_name("damage") == -1:
				continue 
			
			# [핵심 수정] 검사 지점(Offset)을 캐릭터 발바닥 너비만큼 넓게 잡아야 합니다!
			# 캐릭터 폭이 보통 10~16픽셀이라면, 좌우로 6~8픽셀 정도 벌려줘야 끝에 걸쳐도 인식합니다.
			var check_offsets = [
				Vector2.ZERO,      # 1. 정중앙
				Vector2(0, 8),     # 2. 발바닥 바로 아래 (가장 중요)
				Vector2(-7, 8),    # 3. 왼쪽 발끝 (넓힘!)
				Vector2(7, 8),     # 4. 오른쪽 발끝 (넓힘!)
				Vector2(0, -8)     # 5. 머리 위 (점프하다 박았을 때)
			]
			
			for offset in check_offsets:
				# 내 위치(global_position) + 오프셋을 -> 타일맵 기준 좌표로 변환
				var check_pos = body.to_local(global_position + offset)
				var cell = body.local_to_map(check_pos)
				
				# 해당 칸의 데이터 가져오기
				var data = body.get_cell_tile_data(cell)
				
				if data:
					var dmg = data.get_custom_data("damage")
					
					# 데미지가 있는 타일(가시 등)이라면?
					if dmg > 0:
						# 부모(Player)에게 데미지 전달
						_hurt_parent(dmg)
						_damage_timer = damage_invuln_time
						# 이번 프레임은 이미 아프니까 더 계산하지 않고 종료
						return 

# 부모(플레이어)에게 데미지 주는 함수
func _hurt_parent(amount: int) -> void:
	var parent = get_parent()
	if parent.has_method("apply_damage"):
		
		# 넉백 계산 (위로 띄우거나, 0으로 하거나 취향대로)
		var final_kb = Vector2.ZERO 
		if "velocity" in parent and parent.velocity.y >= 0:
			final_kb = Vector2(0, -1).normalized() * knockback_force

		# [수정] 4번째 자리에 damage_invuln_time을 넣어줍니다!
		# apply_damage(데미지, 넉백, 넉백쿨무시여부, 무적시간)
		parent.apply_damage(amount, final_kb, false, damage_invuln_time)
