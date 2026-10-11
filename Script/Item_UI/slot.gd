extends Panel

# [추가 1] 인벤토리 UI에게 보낼 신호 정의
signal slot_clicked

# 애니메이션 있는 아이템(ItemData.anim_frames)은 슬롯에서도 프레임 재생 + 둥둥 효과
const BOB_SPEED := 3.0
const BOB_RANGE := 1.5

@onready var icon: TextureRect = $Icon

var _anim_item: ItemData = null
var _anim_time: float = 0.0
var _icon_offset_top: float
var _icon_offset_bottom: float

func _ready() -> void:
	_icon_offset_top = icon.offset_top
	_icon_offset_bottom = icon.offset_bottom
	set_process(false)

func _gui_input(event: InputEvent) -> void:
	# [추가 2] 마우스 좌클릭 감지
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			# "나 클릭됐어요!"라고 신호를 보냄
			slot_clicked.emit()

func set_item(item: ItemData, _inventory_index: int = -1): # 칸 번호는 예전 열쇠 횟수 표시용 (지금은 안 씀)
	_set_anim_item(item if item != null and item.has_animation() else null)
	if item != null:
		# [핵심 변경] load() 필요 없음! 리소스 안에 이미 이미지가 들어있음.
		icon.texture = _trimmed(item, item.get_frame_at(_anim_time))
		icon.visible = true

		if item.id == "health_flask":
			$AmountLabel.text = str(GameManager.flask_current_charges) + "/" + str(GameManager.flask_max_charges)
			$AmountLabel.show()
		else:
			$AmountLabel.hide()
	else:
		icon.texture = null
		icon.visible = false
		$AmountLabel.hide()

func _set_anim_item(item: ItemData) -> void:
	if item == _anim_item:
		return # 인벤토리 새로고침마다 애니메이션이 처음으로 튀지 않게
	_anim_item = item
	_anim_time = randf_range(0.0, 10.0) if item != null else 0.0
	set_process(item != null)
	_set_icon_bob(0.0)

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_anim_time += delta
	icon.texture = _trimmed(_anim_item, _anim_item.get_frame_at(_anim_time))
	_set_icon_bob(sin(_anim_time * BOB_SPEED) * BOB_RANGE)

func _set_icon_bob(dy: float) -> void:
	icon.offset_top = _icon_offset_top + dy
	icon.offset_bottom = _icon_offset_bottom + dy

# --- 아이콘 여백 자르기 ---
# 그림 파일의 투명 여백을 잘라 실제로 그려진 부분만 칸 가운데에 보이게 한다 (그림이 한쪽에 치우쳐 있어도 가운데로).
# 애니메이션 아이템은 모든 프레임에서 그려진 영역을 합쳐 같은 영역으로 잘라야 프레임마다 흔들리지 않는다
static var _used_rect_cache := {} # ItemData → 잘라낼 영역 (프레임 기준 픽셀)
static var _trimmed_cache := {} # [텍스처, 영역] → AtlasTexture

static func _used_rect_of(tex: Texture2D) -> Rect2i:
	var img := tex.get_image() if tex != null else null
	if img == null or img.is_empty():
		return Rect2i()
	if img.is_compressed():
		img.decompress()
	return img.get_used_rect()

static func _item_used_rect(item: ItemData) -> Rect2i:
	if not _used_rect_cache.has(item):
		var rect := Rect2i()
		if item.has_animation():
			for i in item.anim_frames.get_frame_count(item.anim_name):
				var r := _used_rect_of(item.anim_frames.get_frame_texture(item.anim_name, i))
				rect = r if rect.size == Vector2i.ZERO else rect.merge(r)
		else:
			rect = _used_rect_of(item.icon)
		_used_rect_cache[item] = rect
	return _used_rect_cache[item]

static func _trimmed(item: ItemData, tex: Texture2D) -> Texture2D:
	var rect := _item_used_rect(item)
	if tex == null or rect.size == Vector2i.ZERO or rect.size == Vector2i(tex.get_size()):
		return tex
	var key := [tex, rect]
	if not _trimmed_cache.has(key):
		var cut := AtlasTexture.new()
		if tex is AtlasTexture: # 시트에서 잘린 프레임이면 시트 기준 영역으로 바꿔서 자른다
			cut.atlas = tex.atlas
			cut.region = Rect2(tex.region.position + Vector2(rect.position), Vector2(rect.size))
		else:
			cut.atlas = tex
			cut.region = Rect2(rect)
		_trimmed_cache[key] = cut
	return _trimmed_cache[key]
