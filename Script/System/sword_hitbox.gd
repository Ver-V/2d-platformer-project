extends Area2D

# 플레이어 스크립트에 있는 공격력 변수를 가져오거나 직접 설정
@export var damage: int = 10 
@export var knockback_force: float = 430.0

# 적(EnemyBase)이 충돌 시 이 함수를 호출할 수 있음
func get_damage() -> int:
	var player = _find_player()
	if player and "attack_damage" in player:
		return player.attack_damage
	return damage

# 적(EnemyBase)이 넉백 계산을 위해 호출함
func get_knockback() -> Vector2:
	var dir = get_parent().scale.x # 1 또는 -1
	return Vector2(dir, 0) * knockback_force

func _find_player():
	var p = get_parent()
	while p != null:
		if p is Player:
			return p
		p = p.get_parent()
	return null
