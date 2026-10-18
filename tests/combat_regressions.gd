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
	await check_reflected_projectile_absorbed_by_invulnerable_enemy()
	await check_enemy_contact()
	await check_contact_status_only_on_hit()
	await check_sword_hits_enemy()
	await check_sword_counter_bonus()
	await check_sword_enemy_invulnerable()
	await check_sword_after_parry()
	await check_sword_inactive_enemy()
	await check_sword_kills_enemy()
	await check_sword_hits_box()
	await check_cracked_wall()
	await check_heavy_attack()
	await check_hazard()
	await check_physics_layers()
	await check_wait_stops_with_node()
	await check_enemy_corpse_removed()
	await check_respawn_input_delay()
	await check_death_drop()
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
	check(p.hp == 90, "normal guard should reduce projectile damage by 10 (hp=%d)" % p.hp)
	check(proj.is_queued_for_deletion(), "guarded projectile should be consumed")
	check(p.status_label.text == TranslationServer.translate(&"COMBAT_GUARD"), "guard should show guard popup")
	check(not p.combat.has_perfect_guard_bonus, "normal guard should not grant the counter bonus")
	await cleanup([p, proj])
	# 가드는 피해만 줄이고 상태이상은 그대로 받는다. 퍼펙트 가드는 절반 (독 = 지속시간 절반)
	var p2 = _guarding_player(false)
	var poison := PoisonEffect.new()
	poison.duration = 10.0
	var hit := HitData.new(20, Vector2(-150, 0))
	hit.is_projectile = true
	hit.status_effects.append(poison)
	check(HitData.deliver(p2, hit) == HitData.Result.GUARDED, "guarded projectile should report GUARDED")
	var guarded_poison = p2.get_status_effects().get_effect(&"poison")
	check(p2.hp == 90 and guarded_poison != null and is_equal_approx(guarded_poison.duration, 10.0), "a normal guard should still take the full status effect")
	await cleanup([p2])
	var p2b = _guarding_player(true)
	var perfect_hit := hit.duplicate_hit()
	check(HitData.deliver(p2b, perfect_hit) == HitData.Result.PERFECT_GUARD, "perfect guard should report PERFECT_GUARD")
	var half_poison = p2b.get_status_effects().get_effect(&"poison")
	check(p2b.hp == 100 and half_poison != null and is_equal_approx(half_poison.duration, 5.0) and is_equal_approx(poison.duration, 10.0),
		"a perfect guard should take half the status effect (without changing the original)")
	await cleanup([p2b])
	# 경감량 이하의 투사체는 피해 없이 막히고, 경감량은 소모품으로 오른다
	var p3 = _guarding_player(false)
	var weak := HitData.new(8, Vector2(-150, 0))
	weak.is_projectile = true
	check(HitData.deliver(p3, weak) == HitData.Result.GUARDED and p3.hp == 100, "a projectile weaker than the guard reduction should do no damage")
	gm.add_guard_reduction(5)
	var strong := HitData.new(20, Vector2(-150, 0))
	strong.is_projectile = true
	HitData.deliver(p3, strong)
	check(p3.hp == 95, "raised guard reduction (15) should cut a 20 projectile to 5 (hp=%d)" % p3.hp)
	gm.guard_reduction = 10
	await cleanup([p3])

func check_perfect_guard_projectile() -> void:
	var p = _guarding_player(true)
	var proj := spawn_projectile(20, Vector2.LEFT * 150)
	hit_with_projectile(proj, p)
	check(p.hp == 100, "perfect guard should block all damage")
	check(proj.is_queued_for_deletion(), "perfect-guarded projectile should be consumed")
	check(p.combat.has_perfect_guard_bonus, "perfect guard should grant the counter bonus")
	check(p.is_invulnerable() and p._invuln_left <= p.guard.PERFECT_GUARD_INVULN + 0.001, "perfect guard should give short i-frames")
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

# 반사탄도 무적인 적에게 닿으면 데미지 없이 흡수된다 (무적 타이밍의 반사는 헛친다)
func check_reflected_projectile_absorbed_by_invulnerable_enemy() -> void:
	var mob = spawn_slime(Vector2(300, 400))
	var hp0: int = mob.hp
	mob.start_invuln(1.0)
	var proj := spawn_projectile(20, Vector2.LEFT * 150)
	proj.shooter = mob
	proj.is_parryable = true
	proj.attempt_parry(proj.global_position + Vector2(10, 0))
	hit_with_projectile(proj, mob)
	check(mob.hp == hp0 and proj.is_queued_for_deletion(), "reflected projectile should be absorbed by an invulnerable enemy")
	await cleanup([mob, proj])
	# 무적이 아니면 반사탄이 명중한다
	var mob3 = spawn_slime(Vector2(300, 400))
	var hp3: int = mob3.hp
	var proj3 := spawn_projectile(20, Vector2.LEFT * 150)
	proj3.shooter = mob3
	proj3.is_parryable = true
	proj3.attempt_parry(proj3.global_position + Vector2(10, 0))
	hit_with_projectile(proj3, mob3)
	check(mob3.hp < hp3 and proj3.is_queued_for_deletion(), "reflected projectile should hit a vulnerable enemy")
	await cleanup([mob3, proj3])
	# 처음부터 플레이어 팀인 탄(나중의 무기 탄 등)도 무적인 적에게 흡수된다
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
	await wait_hitstop_clear()
	var p = spawn_player()
	var mob = spawn_slime(p.global_position + Vector2(20, 0))
	var hp0: int = mob.hp
	await hit_with_sword(p, mob)
	check(mob.hp == hp0 - 10, "sword should deal attack_damage (hp=%d)" % mob.hp)
	check(mob.knockback_vel.x > 0.0, "sword knockback should push the enemy away")
	check(mob.is_invulnerable(), "enemy should get i-frames after a sword hit")
	check(Engine.time_scale < 1.0, "sword hit should start hitstop")
	var left := hitstop_left_ms()
	check(left > 0 and left <= 100, "plain sword hit hitstop should be 0.1s (left %d ms)" % left)
	await cleanup([p, mob])

# 앞선 검사의 히트스탑이 끝날 때까지 (겹치면 더 늦게 끝나는 쪽을 따르므로 측정 전에 비운다)
func wait_hitstop_clear() -> void:
	while hitstop_left_ms() > 0:
		await create_timer(0.05, true, false, true).timeout
	Engine.time_scale = 1.0

# 지금 걸린 히트스탑이 끝날 때까지 남은 시간(ms, 실제 시간)
func hitstop_left_ms() -> int:
	var gm = root.get_node("GameManager")
	return gm._hitstop_end_ms - Time.get_ticks_msec() if gm._hitstop_end_ms > 0 else 0

func check_sword_counter_bonus() -> void:
	await wait_hitstop_clear()
	var p = spawn_player()
	var mob = spawn_slime(p.global_position + Vector2(20, 0))
	var hp0: int = mob.hp
	p.combat.has_perfect_guard_bonus = true
	await hit_with_sword(p, mob)
	check(mob.hp == hp0 - 20, "counter bonus should add 10 damage (hp=%d)" % mob.hp)
	check(not p.combat.has_perfect_guard_bonus, "counter bonus should be consumed on hit")
	check(p.status_label.text == TranslationServer.translate(&"COMBAT_COUNTER_HIT"), "counter hit popup should show")
	var left := hitstop_left_ms()
	check(left > 120 and left <= 200, "counter hit hitstop should be doubled to 0.2s (left %d ms)" % left)
	await cleanup([p, mob])
	# 카운터 패리도 패링 히트스탑(0.2초)의 2배
	await wait_hitstop_clear()
	var p2 = spawn_player()
	p2.combat._hitstop(p2.combat.PARRY_HITSTOP, true)
	left = hitstop_left_ms()
	check(left > 350 and left <= 400, "counter parry hitstop should be doubled to 0.4s (left %d ms)" % left)
	await create_timer(0.5, true, false, true).timeout
	await cleanup([p2])

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

# 금 간 벽: 그냥 칼로는 막히고(반격 보너스는 그대로, 힌트), 강공격으로만 부서지며 세이브에 남는다
func check_cracked_wall() -> void:
	await wait_hitstop_clear()
	gm.reset_data()
	var p = spawn_player()
	var wall = load("res://Scenes/System/CrackedWall.tscn").instantiate()
	wall.persist_id = "W-combattest"
	fixture.add_child(wall)
	wall.global_position = p.global_position + Vector2(20, 0)
	check(PersistIdAssigner.prefix_for(wall) == "W", "Cracked walls should get W- persist ids")
	check(wall.get_node("Hurtbox").collision_layer == 512 and wall.get_node("CollisionShape2D").shape.size == wall.size()
		and wall.get_node("Hurtbox/CollisionShape2D").shape.size == wall.size(),
		"Cracked wall should be hittable (enemy_hurtbox layer) with body and hurtbox matching width_tiles x height_tiles")
	await hit_with_sword(p, wall)
	check(is_instance_valid(wall) and not wall.is_queued_for_deletion(), "A normal sword hit should not break a cracked wall")
	check(p.status_label.text == TranslationServer.translate(&"WALL_NEEDS_COUNTER"), "Hitting a cracked wall should show the hint")
	p.combat.has_perfect_guard_bonus = true
	var plain := HitData.new(10, Vector2.ZERO, p)
	check(wall.receive_hit(plain) == HitData.Result.GUARDED and p.combat.has_perfect_guard_bonus, "A blocked hit should not use up the counter bonus")
	await hit_with_sword(p, wall) # 반격 보너스가 있어도 강공격이 아니면 안 부서진다
	check(is_instance_valid(wall) and not wall.is_queued_for_deletion(), "A counter hit that is not heavy should not break the wall")
	p.combat.is_heavy_attack = true
	await hit_with_sword(p, wall)
	check(not is_instance_valid(wall) or wall.is_queued_for_deletion(), "A heavy attack should break the cracked wall")
	check(gm.collected_items.has("wall:W-combattest"), "Breaking the wall should be saved")
	await process_frame
	var again = load("res://Scenes/System/CrackedWall.tscn").instantiate()
	again.persist_id = "W-combattest"
	fixture.add_child(again)
	check(again.is_queued_for_deletion(), "A broken wall should stay broken after reload")
	await create_timer(0.5, true, false, true).timeout
	await cleanup([p])
	gm.reset_data()

# 강공격: 배우기 전엔 바로 일반 공격. 배운 뒤엔 누르는 동안 칼 든 자세로 멈춰 모으고(CHARGE),
# 0.75초 전에 떼면 일반 공격, 다 모이면 번쩍이고 떼면 강공격(피해 2.5배·판정 확대). 맞으면 모으기가 끊긴다
func check_heavy_attack() -> void:
	await wait_hitstop_clear()
	gm.reset_data()
	var p = spawn_player()
	p._menu_exit_cooldown = 0.0
	check(not p.combat.can_charge(), "Heavy attack should be locked on a new game")
	gm.heavy_attack_unlocked = true
	check(p.combat.can_charge(), "Unlocked heavy attack should allow charging")
	var dt := 1.0 / 60.0
	Input.action_press("attack")
	p.change_state(p.State.CHARGE)
	check(p.current_state == p.State.CHARGE and not p.anim_player.is_playing() and p.sprite.animation == &"Attack" and p.sprite.frame == 1,
		"Charging should hold the raised-sword frame (frame %d)" % p.sprite.frame)
	for i in 6:
		p._process_charge(dt)
	Input.action_release("attack")
	p._process_charge(dt)
	check(p.current_state == p.State.ATTACK and not p.combat.is_heavy_attack, "A short press should swing a normal attack")
	p.change_state(p.State.IDLE)
	p.combat.cooldown_left = 0.0

	Input.action_press("attack")
	p.change_state(p.State.CHARGE)
	for i in roundi(p.combat.HEAVY_CHARGE_TIME / dt) + 3:
		p._process_charge(dt)
	check(p.combat.is_charge_ready() and p.visuals._charge_flash, "A full charge should be ready and flash")
	Input.action_release("attack")
	p._process_charge(dt)
	check(p.current_state == p.State.ATTACK and p.combat.is_heavy_attack and p.combat.sword_shape.scale == p.combat.HEAVY_REACH_SCALE and not p.visuals._charge_flash,
		"Releasing a full charge should swing a heavy attack with a bigger hitbox")
	var mob = spawn_slime(p.global_position + Vector2(20, 0))
	var hp0: int = mob.hp
	await hit_with_sword(p, mob)
	check(mob.hp == hp0 - int(round(10 * p.combat.HEAVY_DAMAGE_MULT)), "Heavy attack should deal 2.5x damage (hp=%d)" % mob.hp)
	await wait_hitstop_clear()
	p.change_state(p.State.IDLE)
	p.combat.cooldown_left = 0.0

	Input.action_press("attack")
	p.change_state(p.State.CHARGE)
	for i in roundi(p.combat.HEAVY_CHARGE_TIME / dt) + 3:
		p._process_charge(dt)
	take_hit(p, 5)
	Input.action_release("attack")
	check(p.current_state != p.State.CHARGE and not p.combat.is_charging and not p.visuals._charge_flash, "Getting hit should cancel the charge")
	await wait_hitstop_clear()
	await cleanup([p, mob])
	gm.reset_data()

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
	await check_directional_spikes()
	await check_hazard_respawn()
	await check_hazard_respawn_first_tutorial()

# 가시에 맞고 살아 있으면: 조작이 잠깐 막히고, 화면이 어두워진 사이 마지막 안전한 땅으로 옮겨진다
func check_hazard_respawn() -> void:
	var gm = root.get_node("GameManager")
	var p = spawn_player(Vector2(-5000, 400))
	p.last_safe_position = Vector2(-5200, 300)
	p.has_safe_position = true
	p.velocity = Vector2(0, 50)
	hit_with_hazard(p, 10)
	check(p.hp == 90 and p.is_hazard_respawning() and gm.is_menu_open, "A spike hit should damage, then lock control while respawning")
	# 맞는 순간부터 무적: 되돌아가는 사이 가시에 또 닿아도(센서 두 개 포함) 피해는 한 번뿐
	check(p.is_invulnerable(), "A spike hit should make the player invulnerable right away")
	hit_with_hazard(p, 10)
	p.get_node("HazardSensor2")._hurt_parent(10)
	check(p.hp == 90, "Touching spikes again during the respawn should not hurt (hp %d)" % p.hp)
	await create_timer(p.hazard_respawn_fade * 0.5 + 0.1).timeout
	check(p.global_position.is_equal_approx(Vector2(-5200, 300)) and p.knockback_vel == Vector2.ZERO, "The player should be moved to the last safe ground (at %s)" % p.global_position)
	check(p.is_invulnerable(), "The player should still be invulnerable after arriving")
	await create_timer(0.6).timeout
	check(not p.is_hazard_respawning() and not gm.is_menu_open, "Control should come back after the respawn")
	# 죽으면 되돌리지 않는다 (사망 처리로)
	p.reset_combat_state()
	p.hp = 5
	p.global_position = Vector2(-5000, 400)
	hit_with_hazard(p, 10)
	check(not p.is_hazard_respawning(), "A lethal spike hit should not respawn")
	await create_timer(1.2).timeout
	await cleanup([p])

# 처음 가시에 찔려 돌아오면 도움말이 트리를 일시정지한다. 그래도 화면은 다시 밝아져야 한다 (검은 화면에 갇히던 버그)
func check_hazard_respawn_first_tutorial() -> void:
	var gm = root.get_node("GameManager")
	var popup = root.get_node("TutorialPopup")
	var rect: ColorRect = root.get_node("SceneTransition/ColorRect")
	var old_scene := current_scene
	var old_seen: Array = gm.seen_tutorials.duplicate()
	gm.seen_tutorials.erase("TUTORIAL_SPIKES")
	var stage := Node2D.new()
	root.add_child(stage) # current_scene은 root 바로 아래여야 한다
	stage.set_script(load("res://Script/base/stage_base.gd")) # show_once는 BaseStage 안에서만 띄운다 (_ready는 안 돈다)
	current_scene = stage
	var p = spawn_player(Vector2(-5000, 400))
	p.last_safe_position = Vector2(-5200, 300)
	p.has_safe_position = true
	hit_with_hazard(p, 10)
	await create_timer(p.hazard_respawn_fade * 1.5 + 1.0, true).timeout
	check(paused and popup.is_active, "The first spike respawn should show the spike tutorial (paused %s)" % paused)
	check(is_equal_approx(rect.modulate.a, 0.0), "Spike respawn fade stuck dark under the tutorial pause (alpha %s)" % rect.modulate.a)
	popup.hide_popup()
	await create_timer(0.6, true).timeout
	check(not paused, "Closing the tutorial should unpause")
	paused = false
	rect.modulate.a = 0.0
	gm.seen_tutorials = old_seen
	current_scene = old_scene
	stage.queue_free()
	await cleanup([p])

# 방향 가시: 칠한 타일의 회전·뒤집기로 방향을 알고, 가시 끝 쪽에서 다가올 때만 아프다 (받침판 쪽은 안전)
func check_directional_spikes() -> void:
	var layer: TileMapLayer = load("res://Scenes/Stage/HazardTileMap.tscn").instantiate()
	fixture.add_child(layer)
	layer.global_position = Vector2(-3000, 0)
	var T := TileSetAtlasSource.TRANSFORM_TRANSPOSE
	var H := TileSetAtlasSource.TRANSFORM_FLIP_H
	var V := TileSetAtlasSource.TRANSFORM_FLIP_V
	var cases := [[0, Vector2.DOWN, "unflipped (ceiling)"], [V, Vector2.UP, "flip V (floor)"], [T | H, Vector2.LEFT, "rotated right"], [T | V, Vector2.RIGHT, "rotated left"]]
	for i in cases.size():
		var cell := Vector2i(i * 3, 0)
		layer.set_cell(cell, 0, Vector2i(4, 0), cases[i][0])
		var dir := HazardSensor.spike_direction(layer, cell, layer.get_cell_tile_data(cell))
		check(dir.is_equal_approx(cases[i][1]), "Spike %s should point %s (got %s)" % [cases[i][2], cases[i][1], dir])

	var c := Vector2.ZERO
	check(HazardSensor.spike_hurts(Vector2.UP, c, c + Vector2(0, -10), Vector2(0, 100)), "Falling onto floor spikes should hurt")
	check(HazardSensor.spike_hurts(Vector2.UP, c, c + Vector2(0, -10), Vector2.ZERO), "Standing on floor spikes should hurt")
	check(not HazardSensor.spike_hurts(Vector2.UP, c, c + Vector2(0, -10), Vector2(0, -200)), "Jumping up away from floor spikes should not hurt")
	check(not HazardSensor.spike_hurts(Vector2.DOWN, c, c + Vector2(0, -10), Vector2.ZERO), "Standing on a ceiling spike's base should not hurt")
	check(HazardSensor.spike_hurts(Vector2.DOWN, c, c + Vector2(0, 14), Vector2(0, -200)), "Jumping into ceiling spikes should hurt")
	check(not HazardSensor.spike_hurts(Vector2.UP, c, c + Vector2(0, 14), Vector2(0, -200)), "Hitting a floor spike's base from below should not hurt")
	check(HazardSensor.spike_hurts(Vector2.ZERO, c, c + Vector2(0, 14), Vector2(0, -200)), "Spikes without a direction should always hurt")

	# 실제로: 천장 가시(받침판이 위)를 밟고 서 있으면 안 아프고, 바닥 가시(뒤집기) 위에 서면 아프다
	layer.clear()
	for x in range(-2, 3):
		layer.set_cell(Vector2i(x, 0), 0, Vector2i(4, 0), 0)      # 왼쪽: 받침판이 위인 천장 가시
		layer.set_cell(Vector2i(x + 10, 0), 0, Vector2i(4, 0), V) # 오른쪽: 바닥 가시
	var base_top: float = layer.to_global(layer.map_to_local(Vector2i(0, 0))).y - 8.0
	var on_base = spawn_player(Vector2(layer.to_global(layer.map_to_local(Vector2i(0, 0))).x, base_top - 2.0))
	on_base.set_physics_process(true)
	for i in 30:
		await physics_frame
	check(on_base.hp == 100 and on_base.is_on_floor(), "Standing on a ceiling spike's wooden base should not hurt (hp %d)" % on_base.hp)
	var on_spikes = spawn_player(Vector2(layer.to_global(layer.map_to_local(Vector2i(10, 0))).x, base_top - 12.0))
	on_spikes.set_physics_process(true)
	for i in 30:
		await physics_frame
	check(on_spikes.hp < 100, "Landing on floor spikes should hurt")
	layer.queue_free()
	await cleanup([on_base, on_spikes])

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
	# 사망 화면: 스테이지 BGM은 줄어들고, 사망 BGM 칸(death_bgm)에 넣은 곡이 같이 커진다
	var stage_bgm := AudioStreamPlayer.new()
	stage_bgm.bus = &"BGM"
	stage_bgm.stream = _silent_wav()
	fixture.add_child(stage_bgm)
	stage_bgm.play()
	var old_death_bgm = hud.death_bgm
	hud.death_bgm = _silent_wav()
	check(take_hit(p, 1000) == HitData.Result.KILLED, "lethal hit should report KILLED")
	await process_frame
	check(hud.is_death_screen_active() and not hud.Restart_Label.visible, "Death should show the dark screen, but not the restart prompt yet")
	hud.show_restart_prompt() # 스테이지가 respawn_input_delay 뒤에 부른다 (아래 check_respawn_input_delay)
	check(hud.Restart_Label.visible, "Restart prompt should show once the stage accepts the respawn key")
	check(hud.Restart_Label.get_node("RestartText").text == "HUD_RESTART_PROMPT", "Restart prompt should use a translation key")
	check(hud._death_dark_layer.layer < hud._death_actor_layer.layer and hud._death_actor_layer.layer < hud.Restart_Label.get_parent().layer
		and hud._death_actor_layer.follow_viewport_enabled, "Layers: dark < player copy (follows the camera) < restart prompt")
	check(hud._death_actor.visible and hud._death_actor.sprite_frames == p.sprite.sprite_frames
		and hud._death_actor.transform.origin.is_equal_approx(p.sprite.global_position), "Only a copy of the player sprite should be drawn above the dark screen")
	check(hud._death_bgm_player.playing and hud._death_bgm_player.stream == hud.death_bgm and hud._death_bgm_player.bus == &"BGM",
		"Death BGM should start playing on the BGM bus")
	await create_timer(1.0, true, false, true).timeout
	var a1: float = hud._death_dark.color.a
	check(a1 > 0.0 and a1 < hud.death_dark_alpha * 0.5, "Dark screen should fade in slowly over %.0fs (alpha %.2f after 1s)" % [hud.death_fade_time, a1])
	check(hud._death_bgm_player.volume_linear > 0.0 and hud._death_bgm_player.volume_linear < 0.5, "Death BGM should fade in with the screen")
	check(p.hp == 0, "lethal hit should bring hp to 0")
	check(p.current_state == p.State.DEAD, "lethal hit should enter DEAD")
	check(take_hit(p, 10) == HitData.Result.IGNORED, "dead player should not take more hits")
	# DEAD 진입 4초 뒤 died 신호 (스테이지가 부활 처리)
	for i in 300:
		if died[0]:
			break
		await create_timer(0.05, true, false, true).timeout
	check(died[0], "player should emit died after the death delay")
	check(hud._death_dark.color.a > 0.6, "Dark screen should be mostly black by the time the player can respawn")
	check(not stage_bgm.playing, "Stage BGM should fade out and stop when the player dies")
	hud._death_bgm_player.stop()
	hud._death_bgm_player.finished.emit() # 반복 설정이 없는 곡이 끝난 경우
	check(hud._death_bgm_player.playing, "Death BGM should keep playing until the player respawns")
	if hud.has_method("hide_death_screen"):
		hud.hide_death_screen()
	check(not hud.is_death_screen_active() and not hud.Restart_Label.visible and not hud._death_bgm_player.playing,
		"Respawning should clear the dark screen, the prompt and the death BGM")
	hud.death_bgm = old_death_bgm
	stage_bgm.queue_free()
	await cleanup([p])

# 죽고 respawn_input_delay(3초) 뒤에야 [R] 안내가 뜨고 부활 입력을 받는다
func check_respawn_input_delay() -> void:
	var stage := Node2D.new() # BaseStage는 Node2D
	fixture.add_child(stage)
	stage.set_script(load("res://Script/base/stage_base.gd")) # _ready(플레이어 소환 등) 없이 함수만 쓴다
	check(is_equal_approx(stage.respawn_input_delay, 3.0), "Respawn key should unlock 3s after death")
	stage.respawn_input_delay = 0.3
	hud.show_death_screen()
	stage._on_player_died()
	await create_timer(0.1, true, false, true).timeout
	check(not stage.is_waiting_respawn and not hud.Restart_Label.visible, "Right after death the respawn key and prompt should be locked")
	await create_timer(0.35, true, false, true).timeout
	check(stage.is_waiting_respawn and hud.Restart_Label.visible, "After the delay the prompt should show and the respawn key work")
	hud.hide_death_screen()
	stage.queue_free()
	await process_frame

# 죽으면 금화 절반(10 단위 내림)을 마지막 안전한 땅에 떨어뜨린다. 더미는 줍기 전까지 계속 남고(여러 번 죽으면 여러 개),
# 해골(DeathDrop)이 남은 금액만큼 동전을 깔고, 다 주우면 기록과 함께 사라진다. 테스트에서는 자동 저장이 꺼져 있다
func check_death_drop() -> void:
	check(not gm.autosave_enabled, "Autosave should be off headless so tests never write the real save")
	var saved_gold: int = gm.gold
	var saved_drops: Dictionary = gm.death_drops.duplicate(true)
	gm.death_drops.clear()
	const PATH := "res://test_death_drop.tscn"
	gm.gold = 375
	check(gm.drop_gold_on_death(PATH, Vector2(100, 200)) == 180 and gm.gold == 195, "Death should drop half the gold, rounded down to 10s")
	check(gm.drop_gold_on_death(PATH, Vector2(300, 200)) == 90 and gm.gold == 105, "A second death should drop half of what is left")
	check(gm.death_drops[PATH].size() == 2, "Earlier drops should stay until picked up")
	gm.gold = 15
	check(gm.drop_gold_on_death(PATH, Vector2.ZERO) == 0 and gm.gold == 15 and gm.death_drops[PATH].size() == 2, "Under 20 gold nothing drops")

	var sm = root.get_node("SaveManager")
	var data: Dictionary = JSON.parse_string(JSON.stringify(gm.get_data_for_save()))
	check(sm._is_valid_game(data), "Saves with death drops should be valid")
	var bad: Dictionary = data.duplicate(true)
	bad["death_drops"] = {PATH: {"drop_0": {"x": 1, "y": 2, "gold": -5}}}
	check(not sm._is_valid_game(bad), "Death drops with bad gold should be rejected")
	gm.death_drops.clear()
	gm.load_data_from_save(data)
	check(gm.death_drops.get(PATH, {}).size() == 2, "Death drops should load back from the save")
	gm.gold = 15

	# 테스트 스크립트가 오토로드보다 먼저 컴파일되므로 클래스 이름 대신 경로로 불러온다
	var stage_script = load("res://Script/base/stage_base.gd")
	var p = spawn_player(Vector2(500, 400))
	p.has_safe_position = false
	check(stage_script.death_drop_position(p) == p.global_position, "Without safe ground the drop stays where the player fell")
	p.last_safe_position = Vector2(40, 60)
	p.has_safe_position = true
	check(stage_script.death_drop_position(p) == Vector2(40, 60), "The drop should land on the last safe ground (not in spikes or a pit)")

	var coins_before: Array = fixture.get_children().filter(func(n): return n.has_signal("collected")) # 앞 검사에서 떨어진 동전
	var drop = load("res://Script/System/death_drop.gd").new()
	var first_id: String = gm.death_drops[PATH].keys()[0]
	drop.setup(PATH, first_id, 180)
	fixture.add_child(drop)
	drop.global_position = Vector2(500, 400)
	await frames(2)
	var coins: Array = fixture.get_children().filter(func(n): return n.has_signal("collected") and not coins_before.has(n))
	var total := 0
	for c in coins:
		total += c.gold_amount
	check(coins.size() == 9 and total == 180, "The skull should lay out coins worth the dropped gold (got %d coins, %d gold)" % [coins.size(), total])
	check(drop.get_node("Skull").z_index == RenderingServer.CANVAS_ITEM_Z_MAX and drop.is_in_group("minimap_death_drop"), "The skull should draw above the darkness and show on the minimap")
	coins[0]._on_body_entered(p)
	check(gm.gold == 15 + coins[0].gold_amount and int(gm.death_drops[PATH][first_id]["gold"]) == 180 - coins[0].gold_amount, "Picking up a coin should lower what is left in the drop")
	for c in coins.slice(1):
		c._on_body_entered(p)
	check(gm.gold == 195 and not gm.death_drops[PATH].has(first_id) and gm.death_drops[PATH].size() == 1, "Picking up every coin should clear that drop only")
	await create_timer(0.6, true, false, true).timeout
	check(not is_instance_valid(drop), "The skull should vanish once its gold is picked up")
	gm.reset_data()
	check(gm.death_drops.is_empty(), "New game should clear death drops")

	for c in coins:
		if is_instance_valid(c):
			c.queue_free()
	await cleanup([p])
	gm.gold = saved_gold
	gm.death_drops = saved_drops

func _silent_wav() -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_8_BITS
	wav.mix_rate = 8000
	var data := PackedByteArray()
	data.resize(8000)
	wav.data = data
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_end = 8000
	return wav
