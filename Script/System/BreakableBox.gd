extends StaticBody2D
class_name BreakableBox

@export var max_hp: int = 30
@export var hit_sound: AudioStream = preload("res://Assets/sounds/EH.wav")

const HIT_DUST_SHADER: Shader = preload("res://resources/Shaders/box_hit_dust.gdshader")

var hp: int
var _hit_dust_material: ShaderMaterial

func _ready() -> void:
	add_to_group("breakables")
	add_to_group("object")
	hp = max_hp

func apply_damage(amount: int, _knockback: Vector2 = Vector2.ZERO) -> bool:
	if amount <= 0 or hp <= 0:
		return false
	hp = max(0, hp - amount)
	_play_hit_effects()
	if hp == 0:
		queue_free()
	return true

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
	scene.add_child(dust)
	dust.global_position = global_position + Vector2(0, -12)
	dust.emitting = true
	get_tree().create_timer(dust.lifetime).timeout.connect(func():
		if is_instance_valid(dust):
			dust.queue_free()
	)
	if hit_sound != null:
		var sound := AudioStreamPlayer2D.new()
		scene.add_child(sound)
		sound.global_position = global_position
		sound.bus = &"SFX"
		sound.stream = hit_sound
		sound.finished.connect(sound.queue_free)
		sound.play()
