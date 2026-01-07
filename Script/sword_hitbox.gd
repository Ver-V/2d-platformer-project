extends Area2D

# 플레이어 스크립트에 있는 공격력 변수를 가져오거나 직접 설정
@export var damage: int = 10 
@export var knockback_force: float = 430.0

# 적(EnemyBase)이 충돌 시 이 함수를 호출함
func get_damage() -> int:
	return damage

# 적(EnemyBase)이 넉백 계산을 위해 호출함
func get_knockback() -> Vector2:
	# 칼의 중심(Global Position)을 기준으로 바깥쪽으로 밀어냄
	# 혹은 플레이어가 바라보는 방향으로 밀고 싶다면:
	# return Vector2(get_parent().scale.x, 0) * knockback_force
	
	# 여기서는 간단하게 "AttackPivot"의 방향을 따라가도록 함 (부모가 Marker2D니까)
	var dir = get_parent().scale.x # 1 또는 -1
	return Vector2(dir, 0) * knockback_force
