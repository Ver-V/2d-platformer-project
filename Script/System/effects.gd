class_name Effects

# 한 번 터지고 끝나는 파티클을 parent에 붙여 재생하고, 다 끝나면(finished) 스스로 지운다.
# 파티클 자신에 묶여 있으므로 만든 쪽(맞은 적, 부서진 상자 등)이 먼저 사라져도 남지 않는다.
static func emit_once(particles: CPUParticles2D, parent: Node, global_pos: Vector2) -> void:
	particles.one_shot = true
	particles.finished.connect(particles.queue_free)
	parent.add_child(particles)
	particles.global_position = global_pos
	particles.emitting = true
