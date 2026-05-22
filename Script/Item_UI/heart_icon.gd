# HeartIcon.gd
extends Control

@onready var texture_rect: TextureRect = $TextureRect
@onready var rect75: TextureRect = $TextureRect2
const POS_FULL = 16.0    # 1번째 그림 (꽉참)
const POS_HALF = 32.0   # 2번째 그림 (반)
const POS_QUARTER = 48.0 # 3번째 그림 (1/4)
const POS_EMPTY = 64.0  # 4번째 그림 (비어있음)
const POS_HALFQUARTER = 32.0

func _ready() -> void:
	if texture_rect.texture:
		texture_rect.texture = texture_rect.texture.duplicate()
	if rect75.texture:
		rect75.texture = rect75.texture.duplicate()

func update_visual(value: int):
	var atlas = texture_rect.texture as AtlasTexture
	var atlas2 = rect75.texture as AtlasTexture

	if atlas == null or atlas2 == null:
		return

	var new_rect = atlas.region
	var new_rect2 = atlas2.region

	texture_rect.visible = true
	rect75.visible = false

	if value >= 20:
		new_rect.position.x = POS_FULL
	elif value >= 15:
		texture_rect.visible = false
		rect75.visible = true
		new_rect2.position.x = POS_HALFQUARTER
	elif value >= 10:
		new_rect.position.x = POS_HALF
	elif value >= 5:
		new_rect.position.x = POS_QUARTER
	else:
		new_rect.position.x = POS_EMPTY

	atlas.region = new_rect
	atlas2.region = new_rect2
