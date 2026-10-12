extends AudioStreamPlayer
class_name AmbientLoop

# 스테이지 환경음: streams를 차례대로(1 → 2 → 1 → ...) 끝없이 이어 재생한다.
# 한 번 재생할 때마다 피치를 1 ± pitch_variation 안에서 무작위로 바꿔 단조롭지 않게 한다.
# 에코는 bus에 걸린 효과(기본 "Ambient" 버스: 리버브 + 딜레이, default_bus_layout.tres)로 낸다.
# Ambient 버스는 SFX 버스로 보내므로 옵션의 효과음 볼륨을 따른다.

@export var streams: Array[AudioStream] = []
@export_range(0.0, 0.5) var pitch_variation: float = 0.1
# bus를 비워 두면(Master) 이 버스를 쓴다. 에디터가 모르는 버스 이름(새로 추가된 버스)을 Master로 되돌려 저장하는 경우도 막는다.
# 다른 버스(예: 에코 없는 "SFX")를 쓰려면 노드의 bus를 직접 정한다
@export var default_bus: StringName = &"Ambient"

var _index: int = -1

func _ready() -> void:
	bus = effective_bus()
	finished.connect(play_next)
	play_next()

func effective_bus() -> StringName:
	if bus != &"Master":
		return bus
	return default_bus if AudioServer.get_bus_index(default_bus) >= 0 else &"SFX"

func play_next() -> void:
	if streams.is_empty():
		return
	_index = (_index + 1) % streams.size()
	stream = streams[_index]
	pitch_scale = randf_range(1.0 - pitch_variation, 1.0 + pitch_variation)
	play()
