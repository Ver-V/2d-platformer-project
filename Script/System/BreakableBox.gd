extends StaticBody2D
class_name BreakableBox

@export var max_hp: int = 40
@export var hit_sound: AudioStream = preload("res://Assets/sounds/EH.wav")

# 체력 단계별 그림. [0] = 멀쩡(100%), 이후 체력이 줄수록 다음 그림.
# 4장이면 75% 이하 → [1], 50% 이하 → [2], 25% 이하 → [3]. 비워두면 Sprite2D 그림 그대로
@export var damage_textures: Array[Texture2D] = []

@export_group("Reward")
@export var reward_item: ItemData # 지정하면 항상 이 아이템. 비워두면 loot_table에서 랜덤
@export var loot_table: LootTable = preload("res://resources/loot/default_box.tres") # 비우면 아무것도 안 떨어뜨림
@export var persist_id: String = "" # 비워두면 씬 경로 + 노드 경로로 자동 생성

const HIT_DUST_SHADER: Shader = preload("res://resources/Shaders/box_hit_dust.gdshader")
const FIELD_ITEM_SCENE: PackedScene = preload("res://Scenes/Item/field_item.tscn")
const COIN_SCENE: PackedScene = preload("res://Scenes/Item/Coin.tscn")

var hp: int
var _hit_dust_material: ShaderMaterial

@onready var sprite: Sprite2D = get_node_or_null("Sprite2D")

func _ready() -> void:
	# 부순 기록이 있으면 다시 만들지 않는다
	if GameManager.collected_items.has(_save_id()):
		queue_free()
		return
	add_to_group("breakables")
	add_to_group("object")
	hp = max_hp
	_update_damage_texture()

# 남은 체력 비율로 몇 번째 그림인지: n장이면 비율이 (n-1)/n 이하일 때 [1], ... 1/n 이하일 때 [n-1]
func damage_stage() -> int:
	var n := damage_textures.size()
	if n <= 1 or max_hp <= 0:
		return 0
	var ratio := clampf(float(hp) / float(max_hp), 0.0, 1.0)
	return clampi(n - ceili(ratio * n - 0.0001), 0, n - 1)

func _update_damage_texture() -> void:
	if sprite == null or damage_textures.is_empty():
		return
	var tex := damage_textures[damage_stage()]
	if tex != null:
		sprite.texture = tex

func _save_id() -> String:
	if not persist_id.is_empty():
		return "box:" + persist_id
	var scene := get_tree().current_scene if is_inside_tree() else null
	var scene_path := scene.scene_file_path if scene != null else ""
	return "box:%s:%s" % [scene_path, get_path()]

# 지정 아이템이 있으면 그것, 없으면 랜덤 목록에서 한 줄(아이템 또는 골드)을 뽑는다.
# rng를 주면 그걸로 뽑는다 (세이브 시드로 결과 고정). 아무것도 없으면 빈 LootEntry.
func _roll_reward(rng: RandomNumberGenerator = null) -> LootEntry:
	if reward_item != null:
		var fixed := LootEntry.new()
		fixed.item = reward_item
		return fixed
	var picked: LootEntry = loot_table.pick(rng) if loot_table != null else null
	return picked if picked != null else LootEntry.new()

# 부서질 때 보상을 바닥에 떨어뜨린다.
# 아이템: 떨어진 아이템의 id를 박스 저장 id와 같게 두어, 주웠을 때 박스도 '부순 상태'로 저장된다.
#         줍기 전에 다시 들어오면 박스가 되살아나 아이템을 잃지 않는다.
# 골드만: 코인을 뿌리고 박스는 바로 '부순 상태'로 저장한다.
func _drop_reward() -> void:
	var save_id := _save_id()
	var rng := GameManager.make_loot_rng(_save_id()) # 같은 세이브에서는 같은 상자 = 같은 결과
	var reward := _roll_reward(rng)
	var scene := get_tree().current_scene
	var parent: Node = scene if scene != null else get_parent()
	if parent == null:
		return
	var drop_pos := global_position + Vector2(0, -8)
	if reward.item != null:
		var drop = FIELD_ITEM_SCENE.instantiate()
		drop.id = save_id
		drop.item_resource = reward.item
		drop.position = drop_pos
		parent.call_deferred("add_child", drop)
	else:
		GameManager.add_collected_item(save_id)
	for amount in EnemyBase.split_gold_into_coins(reward.roll_gold(rng)):
		var coin = COIN_SCENE.instantiate()
		coin.position = drop_pos
		parent.call_deferred("add_child", coin)
		coin.call_deferred("setup", amount)

# 상자는 무적·넉백·상태이상 없이 피해만 받는다
func receive_hit(hit: HitData) -> HitData.Result:
	if hit.amount <= 0 or hp <= 0:
		return HitData.Result.IGNORED
	hp = max(0, hp - hit.amount)
	_update_damage_texture()
	_play_hit_effects()
	if hp == 0:
		_drop_reward()
		queue_free()
		return HitData.Result.KILLED
	return HitData.Result.HIT

func _play_hit_effects() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	if _hit_dust_material == null:
		_hit_dust_material = ShaderMaterial.new()
		_hit_dust_material.shader = HIT_DUST_SHADER
	var dust := CPUParticles2D.new()
	dust.emitting = false
	dust.material = _hit_dust_material
	dust.amount = 14
	dust.lifetime = 0.45
	dust.one_shot = true
	dust.explosiveness = 1.0
	dust.direction = Vector2.UP
	dust.spread = 160.0
	dust.gravity = Vector2(0, 160)
	dust.initial_velocity_min = 40.0
	dust.initial_velocity_max = 85.0
	dust.scale_amount_min = 2.0
	dust.scale_amount_max = 4.0
	Effects.emit_once(dust, scene, global_position + Vector2(0, -8))
	if hit_sound != null:
		var sound := AudioStreamPlayer2D.new()
		scene.add_child(sound)
		sound.global_position = global_position
		sound.bus = &"SFX"
		sound.stream = hit_sound
		sound.finished.connect(sound.queue_free)
		sound.play()
