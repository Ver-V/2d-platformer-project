extends SceneTree
# Run with Godot --headless --path . --script res://tests/combat_regressions.gd
# 전투 동작 고정 테스트. 저장 파일은 건드리지 않는다.
# 리팩터링 전 동작 기준이며, 의도적으로 바꾼 것: 피격 후 무적 중인 플레이어에게 닿은 적 탄은 흡수된다.
#
# 피해 처리 리팩터링(HitData/Hurtbox, PlayerCombat 분리) 때 바뀌는 건 "어떻게 때리는가"뿐이어야 하므로,
# 때리는 방법은 아래 hit_* / take_* 도우미에만 모아 두었다. API가 바뀌면 도우미만 고치고 검사 내용은 그대로 둔다.

var failures: int = 0
var fixture: Node2D
var gm: Node
var hud: Node

const SLIME := "res://Scenes/Entitites/slime_1.tscn"
const BOX := "res://Scenes/System/BreakableBox.tscn"
const PROJECTILE := "res://Scenes/Projectile/projectilefire.tscn"

func _initialize() -> void:
	call_deferred("run_checks")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func run_checks() -> void:
	gm = root.get_node("GameManager")
	hud = root.get_node("HUD")
	fixture = Node2D.new()
	root.add_child(fixture)
	current_scene = fixture # 코인·먼지 등이 current_scene에 붙는다
	gm.carried_status_effects.clear()

	await check_player_takes_hit()
	await check_player_invulnerable()
	await check_hit_interrupts_attack_and_guard()
	await check_guard_projectile()
	await check_perfect_guard_projectile()
	await check_guard_from_behind()
	await check_guard_does_not_block_contact()
	await check_projectile_vs_player()
	await check_projectile_same_team()
	await check_reflected_projectile_waits_for_enemy()
	await check_enemy_contact()
	await check_contact_status_only_on_hit()
	await check_sword_hits_enemy()
	await check_sword_counter_bonus()
	await check_sword_enemy_invulnerable()
	await check_sword_after_parry()
	await check_sword_inactive_enemy()
	await check_sword_kills_enemy()
	await check_sword_hits_box()
	await check_hazard()
	await check_physics_layers()
	await check_wait_stops_with_node()
	await check_enemy_corpse_removed()
	await check_player_death() # 사망 화면·타이머가 남으므로 마지막

	Engine.time_scale = 1.0
	await create_timer(1.0, true, false, true).timeout
	fixture.queue_free()
	await process_frame
	print("Combat regression checks: ", "PASS" if failures == 0 else "FAIL", " (", failures, " failures)")
	quit(0 if failures == 0 else 1)

# -------------------------------------------------------------------------
# 준비
# -------------------------------------------------------------------------

func frames(n: int) -> void:
	for i in n:
		await process_frame

# 오른쪽을 보고 서 있는 플레이어 (물리·애니메이션 정지)
func spawn_player(pos: Vector2 = Vector2(500, 400)):
	var p = load("res://Scenes/Entitites/Player.tscn").instantiate()
	fixture.add_child(p)
	p.global_position = pos
	p.set_physics_process(false)
	p.anim_player.stop()
	p.max_hp = 100
	p.hp = 100
	p.combat.attack_damage = 10
	p.attack_pivot.scale.x = 1
	p.reset_combat_state()
	return p

func spawn_slime(pos: Vector2):
	var mob = load(SLIME).instantiate()
	mob.patrol_idle_enabled = false
	fixture.add_child(mob)
	mob.global_position = pos
	mob.home_position = pos
	mob.set_physics_process(false)
	mob.set_active(true)
	return mob

func spawn_projectile(dmg: int, vel: Vector2) -> Projectile:
	var proj: Projectile = load(PROJECTILE).instantiate()
	proj.damage = dmg
	fixture.add_child(proj)
	proj.set_physics_process(false)
	proj.velocity = vel
	return proj

func cleanup(nodes: Array) -> void:
	for n in nodes:
		if is_instance_valid(n):
			n.queue_free()
	Engine.time_scale = 1.0
	await process_frame

# -------------------------------------------------------------------------
# 때리는 방법 (리팩터링 때 여기만 바뀐다)
# -------------------------------------------------------------------------

# 근접·일반 피해를 플레이어/적에게. 결과(HitData.Result)를 돌려준다
func take_hit(target, amount: int, knockback: Vector2 = Vector2.ZERO) -> HitData.Result:
	return HitData.deliver(target, HitData.new(amount, knockback))

func landed(result: HitData.Result) -> bool:
	return HitData.landed(result)

# 투사체가 몸에 닿음
func hit_with_projectile(proj: Projectile, body) -> void:
	proj.hit_target(body)

# 적이 몸으로 들이받음 (접촉 피해 1회)
func hit_with_contact(enemy, body) -> void:
	enemy._apply_contact_damage_once(body)

# 플레이어 검이 대상에 닿음 (판정은 이번 프레임 끝에 처리됨). 실제 게임에선 대상의 Hurtbox가 들어온다
func hit_with_sword(player, body) -> void:
	player.combat.on_sword_hurtbox_entered(body)
	await process_frame

# 가시 타일 센서가 감지함
func hit_with_hazard(player, amount: int) -> void:
	player.get_node("HazardSensor")._hurt_parent(amount)

# -------------------------------------------------------------------------
# 플레이어 피격
# -------------------------------------------------------------------------

func check_player_takes_hit() -> void:
	var p = spawn_player()
	var result := take_hit(p, 15, Vector2(200, -100))
	check(result == HitData.Result.HIT, "normal hit should land")
	check(p.hp == 85, "hit should reduce player hp (hp=%d)" % p.hp)
	check(gm.player_current_hp == 85, "player hp should sync to GameManager")
	check(p.is_invulnerable() and is_equal_approx(p._invuln_left, p.invuln_time), "hit should start player i-frames")
	check(p.knockback_vel.x > 0.0, "knockback should push the player")
	await cleanup([p])

func check_player_invulnerable() -> void:
	var p = spawn_player()
	take_hit(p, 10)
	var result := take_hit(p, 10)
	check(result == HitData.Result.INVULNERABLE and p.hp == 90, "hit during i-frames should be blocked")
	p.reset_combat_state()
	check(take_hit(p, 0) == HitData.Result.IGNORED and p.hp == 90, "zero damage should not land")
	# 회피 무적(대시 등)은 EVADED — 투사체가 통과한다
	p.start_invuln(0.3, p.InvulnKind.DODGE)
	check(take_hit(p, 10) == HitData.Result.EVADED and p.hp == 90, "dodge i-frames should evade")
	await cleanup([p])

func check_hit_interrupts_attack_and_guard() -> void:
	for state in ["ATTACK", "GUARD"]:
		var p = spawn_player()
		p.change_state(p.State[state])
		take_hit(p, 5)
		check(p.current_state != p.State[state], "taking a hit should cancel %s" % state)
		check(not p.combat.is_attacking and not p.guard.is_guarding, "flags should clear after a hit cancels %s" % state)
		await cleanup([p])

# -------------------------------------------------------------------------
# 가드 (투사체만 막는다)
# -------------------------------------------------------------------------

func _guarding_player(perfect: bool):
	var p = spawn_player()
	p.change_state(p.State.GUARD)
	p.guard.guard_timer = 0.1 if perfect else 0.3
	return p

func check_guard_projectile() -> void:
	var p = _guarding_player(false)
	var proj := spawn_projectile(20, Vector2.LEFT * 150) # 정면(오른쪽)에서 날아옴
	hit_with_projectile(proj, p)
	check(p.hp == 95, "normal guard should cap projectile damage at 5 (hp=%d)" % p.hp)
	check(proj.is_queued_for_deletion(), "guarded projectile should be consumed")
	check(p.status_label.text == TranslationServer.translate(&"COMBAT_GUARD"), "guard should show guard popup")
	check(not p.combat.has_perfect_guard_bonus, "normal guard should not grant the counter bonus")
	await cleanup([p, proj])
	# 가드는 상태이상을 막는다 (깎인 피해만 들어감)
	var p2 = _guarding_player(false)
	var hit := HitData.new(20, Vector2(-150, 0))
	hit.is_projectile = true
	hit.status_effects.append(PoisonEffect.new())
	check(HitData.deliver(p2, hit) == HitData.Result.GUARDED, "guarded projectile should report GUARDED")
	check(p2.hp == 95 and not p2.has_status_effect(&"poison"), "guard should block status effects")
	await cleanup([p2])

func check_perfect_guard_projectile() -> void:
	var p = _guarding_player(true)
	var proj := spawn_projectile(20, Vector2.LEFT * 150)
	hit_with_projectile(proj, p)
	check(p.hp == 100, "perfect guard should block all damage")
	check(proj.is_queued_for_deletion(), "perfect-guarded projectile should be consumed")
	check(p.combat.has_perfect_guard_bonus, "perfect guard should grant the counter bonus")
	check(p.is_invulnerable() and p._invuln_left <= 0.2 + 0.001, "perfect guard should give short i-frames")
	check(p.current_state == p.State.GUARD, "perfect guard should keep guarding")
	var again := spawn_projectile(20, Vector2.LEFT * 150)
	check(HitData.deliver(p, again._make_hit(p, Vector2(-150, 0))) == HitData.Result.INVULNERABLE, "right after a perfect guard the player is invulnerable")
	again.queue_free()
	await cleanup([p, proj])

func check_guard_from_behind() -> void:
	var p = _guarding_player(false)
	var proj := spawn_projectile(20, Vector2.RIGHT * 150) # 등 뒤(왼쪽)에서 날아옴
	hit_with_projectile(proj, p)
	check(p.hp == 80, "guard should not block projectiles from behind (hp=%d)" % p.hp)
	await cleanup([p, proj])

# 현재 동작: 가드는 투사체 전용이라 몸통 접촉 공격은 그대로 들어온다
func check_guard_does_not_block_contact() -> void:
	var p = _guarding_player(false)
	var mob = spawn_slime(p.global_position + Vector2(20, 0)) # 정면
	hit_with_contact(mob, p)
	check(p.hp == 100 - mob.contact_damage, "guard should not reduce contact damage (current behavior, hp=%d)" % p.hp)
	await cleanup([p, mob])

# -------------------------------------------------------------------------
# 투사체
# -------------------------------------------------------------------------

func check_projectile_vs_player() -> void:
	var p = spawn_player()
	var proj := spawn_projectile(20, Vector2.LEFT * 150)
	hit_with_projectile(proj, p)
	check(p.hp == 80, "enemy projectile should damage the player")
	check(proj.is_queued_for_deletion(), "projectile should be consumed on hit")
	check(p.knockback_vel.x < 0.0, "projectile knockback should follow its direction")
	# 피격 후 무적 중에 닿은 적 탄은 흡수된다 (무적이 끝나자마자 겹쳐 있던 탄에 맞지 않도록)
	var second := spawn_projectile(20, Vector2.LEFT * 150)
	hit_with_projectile(second, p)
	check(p.hp == 80 and second.is_queued_for_deletion(), "enemy projectile should be absorbed by a hurt-invulnerable player")
	# 회피 무적(대시)이면 통과한다
	p.start_invuln(0.3, p.InvulnKind.DODGE)
	var third := spawn_projectile(20, Vector2.LEFT * 150)
	hit_with_projectile(third, p)
	check(p.hp == 80 and not third.is_queued_for_deletion(), "enemy projectile should pass through a dodging player")
	await cleanup([p, proj, second, third])

# 반사탄은 적이 무적이면 사라지지 않고, 무적이 끝난 뒤 명중한다 (패링이 헛되지 않도록)
func check_reflected_projectile_waits_for_enemy() -> void:
	var mob = spawn_slime(Vector2(300, 400))
	var hp0: int = mob.hp
	mob.start_invuln(1.0)
	var proj := spawn_projectile(20, Vector2.LEFT * 150)
	proj.shooter = mob
	proj.is_parryable = true
	proj.attempt_parry(proj.global_position + Vector2(10, 0))
	hit_with_projectile(proj, mob)
	check(mob.hp == hp0 and not proj.is_queued_for_deletion(), "reflected projectile should not vanish on an invulnerable enemy")
	mob.reset_combat_state()
	hit_with_projectile(proj, mob)
	check(mob.hp < hp0 and proj.is_queued_for_deletion(), "reflected projectile should hit once the enemy is vulnerable")
	await cleanup([mob, proj])
	# 기다리는 건 패링된 탄만: 처음부터 플레이어 팀인 탄(나중의 무기 탄 등)은 무적인 적에게 흡수된다
	var mob2 = spawn_slime(Vector2(300, 400))
	mob2.start_invuln(1.0)
	var shot := spawn_projectile(10, Vector2.RIGHT * 150)
	shot.team = "player"
	hit_with_projectile(shot, mob2)
	check(shot.is_queued_for_deletion(), "an unparried player projectile should be absorbed by an invulnerable enemy")
	await cleanup([mob2, shot])

func check_projectile_same_team() -> void:
	var mob = spawn_slime(Vector2(300, 400))
	var hp0: int = mob.hp
	var proj := spawn_projectile(20, Vector2.LEFT * 150)
	hit_with_projectile(proj, mob)
	check(mob.hp == hp0 and not proj.is_queued_for_deletion(), "enemy projectile should ignore enemies")
	await cleanup([mob, proj])

# -------------------------------------------------------------------------
# 적 접촉
# -------------------------------------------------------------------------

func check_enemy_contact() -> void:
	var p = spawn_player()
	var mob = spawn_slime(p.global_position + Vector2(-20, 0)) # 플레이어 왼쪽
	hit_with_contact(mob, p)
	check(p.hp == 100 - mob.contact_damage, "contact should deal contact_damage")
	check(p.knockback_vel.x > 0.0, "contact knockback should push away from the enemy")
	var hp_after: int = p.hp
	hit_with_contact(mob, p)
	check(p.hp == hp_after, "contact during i-frames should be ignored")
	await cleanup([p, mob])

func check_contact_status_only_on_hit() -> void:
	var p = spawn_player()
	var mob = spawn_slime(p.global_position + Vector2(-20, 0))
	var poison := PoisonEffect.new()
	mob.contact_status = poison
	mob.contact_status_chance = 1.0
	p.start_invuln(5.0)
	hit_with_contact(mob, p)
	check(not p.has_status_effect(&"poison"), "contact status should not apply when the hit is ignored")
	p.reset_combat_state()
	hit_with_contact(mob, p)
	check(p.has_status_effect(&"poison"), "contact status should apply when the hit lands")
	p.clear_status_effects()
	await cleanup([p, mob])

# -------------------------------------------------------------------------
# 플레이어 검
# -------------------------------------------------------------------------

func check_sword_hits_enemy() -> void:
	var p = spawn_player()
	var mob = spawn_slime(p.global_position + Vector2(20, 0))
	var hp0: int = mob.hp
	await hit_with_sword(p, mob)
	check(mob.hp == hp0 - 10, "sword should deal attack_damage (hp=%d)" % mob.hp)
	check(mob.knockback_vel.x > 0.0, "sword knockback should push the enemy away")
	check(mob.is_invulnerable(), "enemy should get i-frames after a sword hit")
	check(Engine.time_scale < 1.0, "sword hit should start hitstop")
	await cleanup([p, mob])

func check_sword_counter_bonus() -> void:
	var p = spawn_player()
	var mob = spawn_slime(p.global_position + Vector2(20, 0))
	var hp0: int = mob.hp
	p.combat.has_perfect_guard_bonus = true
	await hit_with_sword(p, mob)
	check(mob.hp == hp0 - 20, "counter bonus should add 10 damage (hp=%d)" % mob.hp)
	check(not p.combat.has_perfect_guard_bonus, "counter bonus should be consumed on hit")
	check(p.status_label.text == TranslationServer.translate(&"COMBAT_COUNTER_HIT"), "counter hit popup should show")
	await cleanup([p, mob])

func check_sword_enemy_invulnerable() -> void:
	var p = spawn_player()
	var mob = spawn_slime(p.global_position + Vector2(20, 0))
	await hit_with_sword(p, mob)
	var hp1: int = mob.hp
	p.combat.has_perfect_guard_bonus = true
	await hit_with_sword(p, mob)
	check(mob.hp == hp1, "sword should not hit an invulnerable enemy")
	check(p.combat.has_perfect_guard_bonus, "counter bonus should stay when the hit does not land")
	await cleanup([p, mob])

func check_sword_after_parry() -> void:
	var p = spawn_player()
	var mob = spawn_slime(p.global_position + Vector2(20, 0))
	var hp0: int = mob.hp
	p.combat.is_parry_success = true
	await hit_with_sword(p, mob)
	check(mob.hp == hp0, "a swing that parried a projectile should not also hit bodies")
	await cleanup([p, mob])

func check_sword_inactive_enemy() -> void:
	var p = spawn_player()
	var mob = spawn_slime(p.global_position + Vector2(20, 0))
	mob.set_active(false)
	var hp0: int = mob.hp
	await hit_with_sword(p, mob)
	check(mob.hp == hp0, "enemies in inactive rooms should not take damage")
	await cleanup([p, mob])

func check_sword_kills_enemy() -> void:
	var p = spawn_player()
	var mob = spawn_slime(p.global_position + Vector2(20, 0))
	var deaths := [0]
	mob.died.connect(func(_e): deaths[0] += 1)
	mob.hp = 5
	await hit_with_sword(p, mob)
	check(mob.hp == 0, "lethal sword hit should bring hp to 0")
	check(deaths[0] == 1, "enemy should emit died once")
	mob.reset_combat_state()
	await hit_with_sword(p, mob)
	check(deaths[0] == 1, "dead enemy should not die twice")
	await cleanup([p, mob])

func check_sword_hits_box() -> void:
	var p = spawn_player()
	var box = load(BOX).instantiate()
	box.persist_id = "combat-test-box"
	fixture.add_child(box)
	box.global_position = p.global_position + Vector2(20, 0)
	var hp0: int = box.hp
	await hit_with_sword(p, box)
	check(box.hp == hp0 - 10, "sword should damage breakable boxes (hp=%d)" % box.hp)
	await cleanup([p, box])

# -------------------------------------------------------------------------
# 가시 타일
# -------------------------------------------------------------------------

func check_hazard() -> void:
	var p = spawn_player()
	p.velocity = Vector2(0, 50) # 떨어지는 중
	hit_with_hazard(p, 10)
	check(p.hp == 90, "hazard should damage the player")
	check(is_equal_approx(p._invuln_left, 2.5), "hazard should use its own longer i-frames")
	check(p.knockback_vel.y < 0.0, "hazard should bounce a falling player upward")
	p.reset_combat_state()
	p.hp = 0
	hit_with_hazard(p, 10)
	check(p.hp == 0, "hazard should ignore a dead player")
	await cleanup([p])

# -------------------------------------------------------------------------
# 실제 충돌 (레이어·마스크 설정 확인). 위 검사들은 판정 함수를 직접 부르므로 레이어 실수를 못 잡는다.
# -------------------------------------------------------------------------

func physics_frames(n: int) -> void:
	for i in n:
		await physics_frame

func _hurtbox_center(node: Node2D) -> Vector2:
	var shape: CollisionShape2D = node.get_node("Hurtbox/CollisionShape2D")
	return shape.global_position

func check_physics_layers() -> void:
	# 검 영역이 적 Hurtbox에 겹치면 맞는다
	var p = spawn_player()
	var sword_shape: CollisionShape2D = p.combat.sword_shape
	var mob = spawn_slime(Vector2.ZERO)
	mob.global_position += sword_shape.global_position - _hurtbox_center(mob)
	var hp0: int = mob.hp
	sword_shape.disabled = false
	await physics_frames(4)
	check(mob.hp == hp0 - 10, "sword area should hit an overlapping enemy Hurtbox (hp=%d)" % mob.hp)
	sword_shape.disabled = true
	await cleanup([p, mob])

	# 검 영역이 상자 Hurtbox에 겹치면 부서진다
	p = spawn_player()
	var box = load(BOX).instantiate()
	box.persist_id = "combat-test-box-physics"
	fixture.add_child(box)
	box.global_position += p.combat.sword_shape.global_position - _hurtbox_center(box)
	var box_hp0: int = box.hp
	p.combat.sword_shape.disabled = false
	await physics_frames(4)
	check(box.hp == box_hp0 - 10, "sword area should hit an overlapping box Hurtbox (hp=%d)" % box.hp)
	p.combat.sword_shape.disabled = true
	await cleanup([p, box])

	# 적 탄이 플레이어 Hurtbox에 겹치면 맞고, 적 Hurtbox는 무시한다
	p = spawn_player()
	var proj := spawn_projectile(20, Vector2.LEFT * 150)
	proj.global_position = _hurtbox_center(p)
	await physics_frames(4)
	check(p.hp == 80 and (not is_instance_valid(proj) or proj.is_queued_for_deletion()), "enemy projectile should hit an overlapping player Hurtbox (hp=%d)" % p.hp)
	await cleanup([p, proj])
	mob = spawn_slime(Vector2(800, 400))
	hp0 = mob.hp
	proj = spawn_projectile(20, Vector2.LEFT * 150)
	proj.global_position = _hurtbox_center(mob)
	await physics_frames(4)
	check(mob.hp == hp0 and not proj.is_queued_for_deletion(), "enemy projectile should ignore enemy Hurtboxes")

	# 반사탄은 적 Hurtbox를 맞힌다
	proj.shooter = mob
	proj.is_parryable = true
	proj.global_position = Vector2(1200, 400)
	proj.attempt_parry(proj.global_position + Vector2(10, 0))
	await physics_frames(2)
	proj.global_position = _hurtbox_center(mob)
	await physics_frames(4)
	check(mob.hp < hp0, "reflected projectile should hit an overlapping enemy Hurtbox")
	await cleanup([mob, proj])

	# 적 접촉 Hitbox가 플레이어 Hurtbox에 겹치면 접촉 피해
	p = spawn_player()
	mob = spawn_slime(Vector2.ZERO)
	var hitbox_shape: CollisionShape2D = mob.get_node("Hitbox/CollisionShape2D")
	mob.global_position += _hurtbox_center(p) - hitbox_shape.global_position
	await physics_frames(4)
	check(p.hp == 100 - mob.contact_damage, "enemy Hitbox should hit an overlapping player Hurtbox (hp=%d)" % p.hp)
	await cleanup([p, mob])

	# 비활성 방의 적은 Hurtbox가 꺼져 검에 감지되지 않는다
	p = spawn_player()
	mob = spawn_slime(Vector2.ZERO)
	mob.global_position += p.combat.sword_shape.global_position - _hurtbox_center(mob)
	mob.set_active(false)
	hp0 = mob.hp
	await physics_frames(2)
	p.combat.sword_shape.disabled = false
	await physics_frames(4)
	check(mob.hp == hp0, "inactive enemy Hurtbox should not be hit")
	p.combat.sword_shape.disabled = true
	await cleanup([p, mob])

# -------------------------------------------------------------------------
# 노드에 묶인 대기 (Wait.seconds) / 시체 정리
# -------------------------------------------------------------------------

class Waiter extends Node:
	var finished := false
	var log: Array = [] # 밖에서 넘긴 배열: 노드가 사라진 뒤에도 기록을 볼 수 있다
	func run(t: float) -> void:
		await Wait.seconds(self, t)
		finished = true
		log.append("resumed")

func check_wait_stops_with_node() -> void:
	var w := Waiter.new()
	fixture.add_child(w)
	w.run(0.05)
	check(w.get_child_count() == 1 and w.get_child(0) is Timer, "Wait.seconds should wait on a Timer owned by the node")
	await create_timer(0.2, true, false, true).timeout
	check(w.finished, "Wait.seconds should resume after the time passes")
	check(w.get_child_count() == 0, "Wait.seconds should remove its timer afterwards")
	w.queue_free()

	# 기다리는 중에 노드가 사라지면 이어서 실행하지 않는다 (에러 없이 멈춤)
	var gone := Waiter.new()
	var gone_log: Array = []
	gone.log = gone_log
	fixture.add_child(gone)
	gone.run(0.1)
	gone.free()
	await create_timer(0.25, true, false, true).timeout
	check(gone_log.is_empty(), "a freed node's wait should not resume its function")

	# 노드의 일시정지 설정을 따른다: 트리가 멈추면 같이 멈췄다가 풀리면 이어간다
	var paused_waiter := Waiter.new()
	fixture.add_child(paused_waiter)
	paused_waiter.run(0.05)
	paused = true
	await create_timer(0.2, true, false, true).timeout
	check(not paused_waiter.finished, "Wait.seconds should not run while the tree is paused")
	paused = false
	await create_timer(0.2, true, false, true).timeout
	check(paused_waiter.finished, "Wait.seconds should resume after the pause ends")
	paused_waiter.queue_free()

	# 트리 밖 노드: 경고를 내고 트리 타이머로 대신 기다린다 (영원히 멈추지 않음)
	var outside := Waiter.new()
	outside.run(0.05)
	await create_timer(0.2, true, false, true).timeout
	check(outside.finished, "Wait.seconds on a node outside the tree should still resume")
	outside.free()

# 쓰러진 적은 사망 애니메이션 → 2초 → 3초 디졸브 뒤 사라진다 (빨리 감아서 확인)
func check_enemy_corpse_removed() -> void:
	var mob = spawn_slime(Vector2(300, 400))
	mob.coin_scene = null
	take_hit(mob, 9999)
	Engine.time_scale = 20.0
	for i in 200:
		if not is_instance_valid(mob):
			break
		await create_timer(0.05, true, false, true).timeout
	Engine.time_scale = 1.0
	check(not is_instance_valid(mob), "dead enemy should be removed after its death fade")
	await cleanup([mob])

# -------------------------------------------------------------------------
# 사망
# -------------------------------------------------------------------------

func check_player_death() -> void:
	var p = spawn_player()
	var died := [false]
	p.died.connect(func(): died[0] = true)
	check(take_hit(p, 1000) == HitData.Result.KILLED, "lethal hit should report KILLED")
	check(p.hp == 0, "lethal hit should bring hp to 0")
	check(p.current_state == p.State.DEAD, "lethal hit should enter DEAD")
	check(take_hit(p, 10) == HitData.Result.IGNORED, "dead player should not take more hits")
	# DEAD 진입 4초 뒤 died 신호 (스테이지가 부활 처리)
	for i in 300:
		if died[0]:
			break
		await create_timer(0.05, true, false, true).timeout
	check(died[0], "player should emit died after the death delay")
	if hud.has_method("hide_death_screen"):
		hud.hide_death_screen()
	await cleanup([p])
