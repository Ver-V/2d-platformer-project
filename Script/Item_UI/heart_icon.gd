# HeartIcon.gd
extends Control

@onready var texture_rect: TextureRect = $TextureRect
@onready var rect75: TextureRect = $TextureRect2
# [설정] 아까 에디터에서 확인한 X 좌표값들을 여기에 적어주세요!
# (이미지 크기에 따라 숫자가 다를 수 있으니 꼭 확인하세요)
const POS_FULL = 16.0    # 1번째 그림 (꽉참)
const POS_HALF = 32.0   # 2번째 그림 (반)
const POS_QUARTER = 48.0 # 3번째 그림 (1/4)
const POS_EMPTY = 64.0  # 4번째 그림 (비어있음)

const POS_HALFQUARTER = 32.0 # 3/4 하트 시트에서의 X 좌표 (임시)

func _ready() -> void:
	# [중요] 모든 하트가 같은 리소스를 공유하면 하나만 바껴도 다 바뀝니다.
	# 각각의 텍스쳐를 독립적으로 복제해줍니다.
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

	# 일단 두 텍스쳐를 모두 켭니다. 상황에 맞게 하나만 보이도록 할 것입니다.
	texture_rect.visible = true
	rect75.visible = false # 기본적으로 3/4 하트는 숨김

	# 체력 값에 따라 어떤 텍스쳐를 띄울지, X 좌표를 어디로 할지 결정합니다.
	if value >= 20:
		new_rect.position.x = POS_FULL
	elif value >= 15:
		# 체력이 15~19 일 때: 3/4 하트 전용 텍스쳐(TextureRect2)를 사용합니다.
		texture_rect.visible = false
		rect75.visible = true
		new_rect2.position.x = POS_HALFQUARTER
	elif value >= 10:
		new_rect.position.x = POS_HALF
	elif value >= 5:
		new_rect.position.x = POS_QUARTER
	else:
		new_rect.position.x = POS_EMPTY

	# 변경된 영역을 다시 적용합니다.
	atlas.region = new_rect
	atlas2.region = new_rect2
