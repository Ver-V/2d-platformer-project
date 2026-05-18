extends AudioStreamPlayer2D


func play_random():
	pitch_scale = randf_range(0.9, 1.1)
	play()
	
