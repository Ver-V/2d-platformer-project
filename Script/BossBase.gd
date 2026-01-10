# Boss.gd
extends EnemyBase
class_name Boss

func _ready() -> void:
	super._ready() # 부모(EnemyBase)의 _ready 실행 (체력 설정 등)
	add_to_group("bosses") # 보스 그룹 추가 (필요 시 사용)

func _on_death() -> void:
	# [핵심] 보스는 죽을 때 매니저 장부에 자기 ID를 적고 죽습니다.
	# Stage 스크립트가 따로 검사할 필요 없이 보스가 스스로 신고하는 구조입니다.
	var id = get_persist_id()
	GameManager.defeated_enemies[id] = true
	
	# 즉시 파일 저장 (보스 잡고 튕기면 억울하니까)
	GameManager.save_game()
	
	print("보스 처치됨! 영구 저장 완료: ", id)
	
	super._on_death() # 부모의 사망 처리(신호 발송, 삭제) 실행
