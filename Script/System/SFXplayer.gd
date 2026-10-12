extends AudioStreamPlayer2D

# --- 사운드 리소스 로드 ---
const SND_ATTACK = preload("res://Assets/sounds/player/PA.wav")
const SND_GUARD = preload("res://Assets/sounds/player/PG.wav")
const SND_JUMP = preload("res://Assets/sounds/player/jump.wav") # 점프·더블 점프 공용
const SND_PARRY = preload("res://Assets/sounds/player/PP.wav")
const SND_PERFECT_GUARD = preload("res://Assets/sounds/player/PPG.wav")
const SND_HURT = preload("res://Assets/sounds/player/hurt.mp3")
const SND_ENTER_WATER = preload("res://Assets/sounds/environment/enter_water.wav")

# 발소리 배열 (1~5)
const SND_WALK = [
	preload("res://Assets/sounds/player/PW1.wav"),
	preload("res://Assets/sounds/player/PW2.wav"),
	preload("res://Assets/sounds/player/PW3.wav"),
	preload("res://Assets/sounds/player/PW4.wav"),
	preload("res://Assets/sounds/player/PW5.wav")
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

func play_hurt():
	_play_sfx(SND_HURT)

func play_enter_water():
	_play_sfx(SND_ENTER_WATER)

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
