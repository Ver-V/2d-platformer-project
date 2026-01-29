# HeartIcon.gd
extends Control

@onready var texture_rect: TextureRect = $TextureRect

# [설정] 아까 에디터에서 확인한 X 좌표값들을 여기에 적어주세요!
# (이미지 크기에 따라 숫자가 다를 수 있으니 꼭 확인하세요)
const POS_FULL = 16.0    # 1번째 그림 (꽉참)
const POS_HALF = 32.0   # 2번째 그림 (반)
const POS_EMPTY = 64.0  # 4번째 그림 (비어있음)

func _ready() -> void:
	# [중요] 모든 하트가 같은 리소스를 공유하면 하나만 바껴도 다 바뀝니다.
	# 그래서 "나만의 복제본"을 만들어서 써야 합니다.
	if texture_rect.texture:
		texture_rect.texture = texture_rect.texture.duplicate()

func update_visual(value: int):
	# texture_rect 자체가 아니라, 그 안에 든 'AtlasTexture'를 가져옵니다.
	var atlas = texture_rect.texture as AtlasTexture
	
	if atlas == null:
		return # 텍스쳐가 없거나 아틀라스가 아니면 패스

	# 현재 설정된 자르기 영역(Region)을 가져옵니다.
	var new_rect = atlas.region
	
	# X 좌표(가로 위치)만 바꿉니다.
	if value >= 20:
		new_rect.position.x = POS_FULL
	elif value >= 10:
		new_rect.position.x = POS_HALF
	else:
		new_rect.position.x = POS_EMPTY
	
	# 변경된 영역을 다시 적용합니다.
	atlas.region = new_rect
