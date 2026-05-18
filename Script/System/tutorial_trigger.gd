extends Area2D

@export_multiline var tutorial_text: String = "설명 텍스트를 입력하세요."
@export var pause_game: bool = true
@export var one_shot: bool = true # 한 번만 보여줄지 여부

var _triggered: bool = false

func _ready() -> void:
	# body_entered 신호를 코드에서 연결 (에디터 실수 방지)
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D) -> void:
	if _triggered and one_shot: return
	
	# 플레이어인지 확인 (Player 클래스 이름이나 그룹 사용)
	if body is Player:
		_triggered = true
		
		# Autoload로 등록될 TutorialPopup을 사용
		if has_node("/root/TutorialPopup"):
			get_node("/root/TutorialPopup").display(tutorial_text, pause_game)
		else:
			push_error("TutorialPopup Autoload가 등록되지 않았습니다!")
		
		if one_shot:
			# 트리거 영역 비활성화 (충돌 레이어 제거)
			collision_mask = 0
