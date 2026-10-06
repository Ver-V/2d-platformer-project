class_name DebugLog

# 개발용 진행 로그 (스폰 위치, 몹 처치, 대화 로드 등). ENABLED가 false면 아무것도 찍지 않는다.
# 오류·경고는 여기 말고 push_error / push_warning을 쓴다 (항상 보여야 하므로).
#
# 켜기: 아래 ENABLED를 true로 바꾸거나, 실행 인자에 --verbose-logs 를 붙인다
#   예) godot --path . -- --verbose-logs

const ENABLED: bool = false

static var _enabled: bool = ENABLED or OS.get_cmdline_user_args().has("--verbose-logs")

static func info(message: String) -> void:
	if _enabled:
		print(message)

static func is_enabled() -> bool:
	return _enabled
