extends Node2D
class_name DeathDrop

# 죽은 자리 표시: 해골과 그 자리에 떨어뜨린 금화 (GameManager.death_drops 한 줄).
# 해골은 어둠(VisionLimit) 위에 그려서 멀리서도 보인다. 금화를 주울 때마다 남은 금액이 줄고, 다 주우면 해골도 사라진다.
# 다시 들어오면 남은 금액만큼 금화가 다시 깔린다. 원점 = 플레이어가 서 있던 발밑
const COIN_SCENE: PackedScene = preload("res://Scenes/Item/Coin.tscn")
const SKULL_TEXTURE: Texture2D = preload("res://Assets/sprites/death_skull.png")
const MINIMAP_GROUP := "minimap_death_drop"
const COIN_SPAWN_HEIGHT := 18.0 # 동전은 이만큼 위에서 튀어 올라 발밑 높이쯤에 내려앉는다
const BOB_RANGE := 2.0
const BOB_SPEED := 2.0

var scene_path: String = ""
var drop_id: String = ""
var gold: int = 0
var cause: String = "" # 사인 (DeathCause). 플레이어가 가까이 오면 해골 위에 뜬다
const CAUSE_SHOW_RANGE := 48.0
var _cause_label: Label
var _coins_left: int = 0
var _skull: Sprite2D
var _time: float = 0.0

func setup(p_scene_path: String, p_drop_id: String, p_gold: int, p_cause: String = "") -> void:
	scene_path = p_scene_path
	drop_id = p_drop_id
	gold = p_gold
	cause = p_cause

func _ready() -> void:
	add_to_group(MINIMAP_GROUP)
	_skull = Sprite2D.new()
	_skull.name = "Skull"
	_skull.texture = SKULL_TEXTURE
	_skull.offset = Vector2(0, -8)
	_skull.z_as_relative = false
	_skull.z_index = RenderingServer.CANVAS_ITEM_Z_MAX # 어둠 위 (GlowEyes와 같은 높이)
	add_child(_skull)
	if not cause.is_empty():
		_cause_label = Label.new()
		_cause_label.text = tr(&"DEATH_CAUSE").format({"cause": DeathCause.describe(cause)})
		_cause_label.add_theme_font_size_override("font_size", 8)
		_cause_label.modulate = Color(0.85, 0.8, 0.8)
		_cause_label.z_as_relative = false
		_cause_label.z_index = RenderingServer.CANVAS_ITEM_Z_MAX
		_cause_label.visible = false
		add_child(_cause_label)
	_spawn_coins.call_deferred()

func _process(delta: float) -> void:
	_time = wrapf(_time + delta, 0.0, TAU / BOB_SPEED)
	_skull.position.y = -absf(sin(_time * BOB_SPEED)) * BOB_RANGE
	if _cause_label != null:
		var player := get_tree().get_first_node_in_group("player") as Node2D
		_cause_label.visible = player != null and player.global_position.distance_to(global_position) <= CAUSE_SHOW_RANGE
		_cause_label.position = Vector2(-_cause_label.size.x * 0.5, -32)

func _spawn_coins() -> void:
	var parent := get_parent()
	if parent == null:
		return
	for amount in EnemyBase.split_gold_into_coins(gold):
		var coin = COIN_SCENE.instantiate()
		coin.position = position + Vector2(0, -COIN_SPAWN_HEIGHT)
		parent.add_child(coin)
		coin.setup(amount)
		coin.collected.connect(_on_coin_collected)
		_coins_left += 1
	if _coins_left == 0: # 동전으로 못 나눌 만큼 남은 기록은 정리한다
		GameManager.take_death_drop_gold(scene_path, drop_id, gold)
		_vanish()

func _on_coin_collected(amount: int) -> void:
	GameManager.take_death_drop_gold(scene_path, drop_id, amount)
	gold -= amount
	_coins_left -= 1
	if _coins_left <= 0:
		_vanish()

func _vanish() -> void:
	remove_from_group(MINIMAP_GROUP)
	var t := create_tween()
	t.tween_property(_skull, "modulate:a", 0.0, 0.4)
	t.tween_callback(queue_free)
