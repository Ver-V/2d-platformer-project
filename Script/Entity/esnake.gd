extends GroundEnemy
class_name Esnake

# 뱀: 공통 지상 이동 + 근접 공격 + 접촉 시 20% 확률 독. 스탯·공격 설정은 esnake.tscn에서.

@export var poison_chance: float = 0.20
@export var poison_ticks: int = 2
@export var poison_damage: int = 5

func _apply_contact_damage_once(b: Node) -> void:
	super._apply_contact_damage_once(b)
	
	if b.is_in_group("player") and b is CombatBody2D:
		if randf() <= poison_chance:
			apply_poison(b)

func apply_poison(player_node: CombatBody2D) -> void:
	if player_node.has_method("show_popup"):
		player_node.show_popup("Poisoned!", Color.PURPLE)
	_poison_routine(player_node)

func _poison_routine(player_node: Node) -> void:
	for i in range(poison_ticks):
		await get_tree().create_timer(1.0).timeout
		if not is_inside_tree():
			return
		if is_instance_valid(player_node) and player_node.hp > 0:
			if player_node.has_method("apply_damage"):
				player_node.apply_damage(poison_damage, Vector2.ZERO, true, 0.0)
