extends BaseStage
class_name Stage02

func _ready() -> void:
	super._ready()
	stage_title = "Stage 02"
	stage_prefix = "S02"
	_setup_stage_02_gimmicks()

func _setup_stage_02_gimmicks() -> void:
	pass

func _process(delta: float) -> void:
	super._process(delta)
