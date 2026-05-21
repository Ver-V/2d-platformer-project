extends AudioStreamPlayer2D

# --- 사운드 리소스 로드 ---
const SND_ATTACK = preload("res://Assets/sounds/PA.wav")
const SND_GUARD = preload("res://Assets/sounds/PG.wav")
const SND_JUMP = preload("res://Assets/sounds/PJ.wav")
const SND_PARRY = preload("res://Assets/sounds/PP.wav")
const SND_PERFECT_GUARD = preload("res://Assets/sounds/PPG.wav")

# 발소리 배열 (1~5)
const SND_WALK = [
	preload("res://Assets/sounds/PW1.wav"),
	preload("res://Assets/sounds/PW2.wav"),
	preload("res://Assets/sounds/PW3.wav"),
	preload("res://Assets/sounds/PW4.wav"),
	preload("res://Assets/sounds/PW5.wav")
]

var _walk_idx = 0

# --- 재생 함수들 (AnimationPlayer에서 호출 가능) ---

func play_attack():
	_play_sfx(SND_ATTACK)

func play_guard():
	_play_sfx(SND_GUARD)

func play_jump():
	_play_sfx(SND_JUMP)

func play_parry():
	_play_sfx(SND_PARRY)

func play_perfect_guard():
	_play_sfx(SND_PERFECT_GUARD)

func play_walk():
	# 1~5 순차 재생 후 반복
	_play_sfx(SND_WALK[_walk_idx])
	_walk_idx = (_walk_idx + 1) % SND_WALK.size()

# --- 공용 내부 함수 ---

func _play_sfx(stream_resource: AudioStream, pitch_var: float = 0.1):
	stream = stream_resource
	if pitch_var > 0:
		pitch_scale = randf_range(1.0 - pitch_var, 1.0 + pitch_var)
	else:
		pitch_scale = 1.0
	play()

# 기존에 있던 함수 유지 (호환성)
func play_random():
	pitch_scale = randf_range(0.9, 1.1)
	play()
