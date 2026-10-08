class_name Wait

# 노드에 묶인 대기: await Wait.seconds(self, 0.5)
#
# 노드의 자식 Timer로 기다린다. 그래서
# - 노드가 사라지면(씬 전환, 사망 후 삭제 등) 타이머도 같이 사라지고, 기다리던 함수는 이어서 실행되지 않는다.
#   (get_tree().create_timer()는 트리가 들고 있어서, 노드가 사라진 뒤에도 시간이 다 될 때까지 남아 있다)
# - 노드의 일시정지 설정(process_mode)을 따른다 — 트리가 멈추면(튜토리얼 팝업 등) 같이 멈춘다.
#   create_timer()의 기본값은 일시정지와 상관없이 흐른다.

static func seconds(node: Node, time: float) -> Signal:
	# 트리 밖 노드에 붙인 Timer는 시작되지 않아 영원히 기다리게 된다 → 경고 후 트리 타이머로 대신 기다린다
	if not node.is_inside_tree():
		push_warning("Wait.seconds: %s is not in the scene tree; falling back to a tree timer" % node)
		var tree := Engine.get_main_loop() as SceneTree
		return tree.create_timer(time).timeout
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = maxf(time, 0.001) # Timer는 0초를 받지 않는다
	timer.timeout.connect(timer.queue_free)
	node.add_child(timer)
	timer.start()
	return timer.timeout
