# play_log.gd (autoload: PlayLog)
extends Node

# 플레이어가 동의한 경우에만 플레이 로그를 개발자 디스코드 웹훅으로 보낸다 (버그 신고·밸런스용).
# - 오류: push_error / push_warning / 스크립트 오류를 Logger로 받아 적는다 (같은 오류는 MAX_SAME_ERROR번까지만)
# - 플레이 이벤트: event("player_death", {...}) 처럼 게임 코드가 직접 남긴다
# 전송 시점 (새로 쌓인 부분만 첨부파일로 보낸다):
#   오류가 생기면 (ERROR_UPLOAD_COOLDOWN에 한 번까지) / PERIODIC_UPLOAD마다 / 게임을 끌 때 (최대 QUIT_UPLOAD_TIMEOUT 기다림)
#   / 강제 종료·크래시로 못 보낸 부분은 다음 실행 때.
# 파일(user://logs/play_*.log)은 전송 대기용일 뿐이다: 다 보낸 세션은 지우고, 못 보낸 것도 MAX_PENDING개만 남긴다.
# 보낸 위치는 옆의 <파일>.sent (JSON: offset, part)에 적는다.
# 동의 여부는 SettingsManager.log_consent (설정 파일에 저장). 헤드리스(테스트)에서는 자동으로 켜지 않는다.
# 개인정보: 사용자 폴더 경로는 <home> 등으로 바꿔 적는다.

const WEBHOOK_URL := ""
const LOG_DIR := "user://logs"
const FILE_PREFIX := "play_"
const MAX_PENDING := 10
const MAX_LINES := 3000 # 한 세션 최대 줄 수 (오류가 매 프레임 나도 파일·전송이 커지지 않게)
const MAX_SAME_ERROR := 3 # 같은 위치·내용의 오류는 이 횟수까지만 적는다
const ERROR_UPLOAD_COOLDOWN := 60.0
const PERIODIC_UPLOAD := 600.0
const QUIT_UPLOAD_TIMEOUT := 4.0
const HTTP_TIMEOUT := 10.0

enum Consent {UNASKED = -1, DECLINED = 0, ALLOWED = 1}

# 테스트에서 바꿔 끼운다: func(file_name: String, content: String, bytes: PackedByteArray) -> bool (await 가능)
var sender: Callable

var _file: FileAccess
var _mutex := Mutex.new()
var _writing := false # 기록 중 생긴 오류가 다시 기록으로 들어오는 것 방지
var _start_msec: int = 0
var _logger: _ErrorLogger
var _path: String = ""
var _dir: String = LOG_DIR
var _line_count: int = 0
var _error_counts: Dictionary = {} # "위치 내용" -> 횟수
var _error_since_upload := false
var _uploading := false
var _since_upload: float = 0.0
var _quitting := false
var _boss_enter_msec: Dictionary = {} # 보스 이름 -> 이번 입장 시각
var _boss_attempts: Dictionary = {} # 보스 이름 -> 이번 세션 입장 횟수
var _active_boss: String = ""

func _init() -> void:
	sender = _send_to_webhook

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if DisplayServer.get_name() == "headless":
		return
	# 창 닫기를 직접 받아, 로그를 보낸 뒤 끈다 (quit_game)
	get_tree().set_auto_accept_quit(false)
	if SettingsManager.log_consent == Consent.ALLOWED:
		start_session()
		upload_pending() # 지난번에 못 보낸 로그

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		quit_game()

func _process(delta: float) -> void:
	if _file == null or _uploading:
		return
	_since_upload += delta
	var error_ready := _error_since_upload and _since_upload >= ERROR_UPLOAD_COOLDOWN
	if error_ready or _since_upload >= PERIODIC_UPLOAD:
		upload_pending()

func _exit_tree() -> void:
	stop_session()

func is_recording() -> bool:
	return _file != null

func get_current_path() -> String:
	return _path

func needs_consent_prompt() -> bool:
	return SettingsManager.log_consent == Consent.UNASKED

# 동의 결과를 저장하고 바로 켜거나 끈다. 거부하면 아직 안 보낸 로그도 지운다
func set_consent(allowed: bool) -> void:
	SettingsManager.log_consent = Consent.ALLOWED if allowed else Consent.DECLINED
	SettingsManager.save_settings()
	if allowed:
		if DisplayServer.get_name() != "headless":
			start_session()
	else:
		stop_session()
		delete_pending(_dir)

# 게임 종료: 남은 로그를 보내고 (최대 QUIT_UPLOAD_TIMEOUT초) 끈다. 창 닫기와 메인 메뉴 종료 버튼이 부른다
func quit_game() -> void:
	if _quitting:
		return
	_quitting = true
	if _file != null:
		stop_session()
		upload_pending()
		var deadline := Time.get_ticks_msec() + int(QUIT_UPLOAD_TIMEOUT * 1000.0)
		while _uploading and Time.get_ticks_msec() < deadline:
			await get_tree().process_frame
	get_tree().quit()

# dir은 테스트용 (기본: user://logs)
func start_session(dir: String = LOG_DIR) -> bool:
	if _file != null:
		return true
	_dir = dir
	DirAccess.make_dir_recursive_absolute(dir)
	_prune_old_files(dir, MAX_PENDING - 1)
	var stamp := Time.get_datetime_string_from_system().replace(":", "").replace("-", "").replace("T", "_")
	_path = dir.path_join("%s%s_%03d.log" % [FILE_PREFIX, stamp, Time.get_ticks_msec() % 1000])
	_file = FileAccess.open(_path, FileAccess.WRITE)
	if _file == null:
		push_warning("PlayLog: 로그 파일을 만들지 못했습니다 (오류 %s)" % FileAccess.get_open_error())
		_path = ""
		return false
	_start_msec = Time.get_ticks_msec()
	_line_count = 0
	_error_counts.clear()
	_error_since_upload = false
	_since_upload = 0.0
	_boss_enter_msec.clear()
	_boss_attempts.clear()
	_active_boss = ""
	event("session_start", {
		"version": str(ProjectSettings.get_setting("application/config/version", "")),
		"date": Time.get_datetime_string_from_system(),
	})
	_logger = _ErrorLogger.new(self)
	OS.add_logger(_logger)
	return true

func stop_session() -> void:
	if _logger != null:
		OS.remove_logger(_logger)
		_logger = null
	if _file == null:
		return
	event("session_end", {"play_time": _elapsed_seconds()})
	_mutex.lock()
	_file.close()
	_file = null
	_mutex.unlock()

# 플레이 이벤트 기록. data 값은 JSON으로 적는다 (Vector2는 [x, y]로 바꾼다)
func event(event_name: String, data: Dictionary = {}) -> void:
	if _file == null:
		return
	var clean := {}
	for key in data:
		clean[key] = _to_json_value(data[key])
	_write_line("EVENT %s %s" % [event_name, JSON.stringify(clean)])

# --- 게임 코드에서 부르는 이벤트 ---

func stage_entered(scene_path: String) -> void:
	event("stage_enter", {"scene": scene_path.get_file().get_basename()})

func player_died(scene_path: String, pos: Vector2, cause: String) -> void:
	var data := {"scene": scene_path.get_file().get_basename(), "pos": pos, "cause": cause}
	if _active_boss != "":
		data["boss"] = _active_boss
	event("player_death", data)

func boss_entered(boss_name: String) -> void:
	if _file == null:
		return
	_active_boss = boss_name
	_boss_enter_msec[boss_name] = Time.get_ticks_msec()
	_boss_attempts[boss_name] = int(_boss_attempts.get(boss_name, 0)) + 1
	event("boss_enter", {"boss": boss_name, "attempt": _boss_attempts[boss_name]})

func boss_left(boss_name: String) -> void:
	if _active_boss == boss_name:
		_active_boss = ""

func boss_defeated(boss_name: String) -> void:
	if _file == null:
		return
	var data := {"boss": boss_name, "attempts": int(_boss_attempts.get(boss_name, 0))}
	if _boss_enter_msec.has(boss_name):
		data["fight_time"] = snappedf((Time.get_ticks_msec() - int(_boss_enter_msec[boss_name])) / 1000.0, 0.01)
	boss_left(boss_name)
	event("boss_defeated", data)

# 피해를 준 쪽의 이름 (씬 파일 이름 우선, 없으면 노드 이름)
static func describe_source(source: Node) -> String:
	if not is_instance_valid(source):
		return "unknown"
	if source.scene_file_path != "":
		return source.scene_file_path.get_file().get_basename()
	return String(source.name)

# --- 전송 ---

# 대기 중인 로그 파일들의 새로 쌓인 부분을 오래된 것부터 보낸다. 다 보낸 지난 세션 파일은 지운다
func upload_pending() -> void:
	if _uploading:
		return
	_uploading = true
	_since_upload = 0.0
	_error_since_upload = false
	for f in _list_logs(_dir):
		var ok: bool = await _upload_file(_dir.path_join(f))
		if not ok:
			break # 오프라인 등: 다음 기회에 다시
	_uploading = false

func _upload_file(path: String) -> bool:
	var state := _read_sent_state(path)
	var bytes := FileAccess.get_file_as_bytes(path)
	var finished := path != _path or _file == null
	var offset: int = clampi(int(state.get("offset", 0)), 0, bytes.size())
	if offset < bytes.size():
		var part: int = int(state.get("part", 0)) + 1
		var chunk := bytes.slice(offset)
		var session := path.get_file().get_basename()
		var content := "`%s` part %d%s" % [session, part, " (end)" if finished else ""]
		var errors := chunk.get_string_from_utf8().count("] ERROR ")
		if errors > 0:
			content += " — errors: %d" % errors
		var sent: bool = await sender.call("%s_part%d.log" % [session, part], content, chunk)
		if not sent:
			return false
		_write_sent_state(path, {"offset": bytes.size(), "part": part})
	if finished:
		DirAccess.remove_absolute(path)
		DirAccess.remove_absolute(path + ".sent")
	return true

func _send_to_webhook(file_name: String, content: String, bytes: PackedByteArray) -> bool:
	if WEBHOOK_URL.is_empty():
		return false # 공개 저장소 사본: tools/publish_showcase.sh가 주소를 지운다
	var boundary := "LunarLog%08x%08x" % [randi(), Time.get_ticks_msec()]
	var payload := JSON.stringify({
		"username": "Lunar Log",
		"content": content,
		"allowed_mentions": {"parse": []},
	})
	var body := PackedByteArray()
	body.append_array(("--%s\r\nContent-Disposition: form-data; name=\"payload_json\"\r\nContent-Type: application/json\r\n\r\n%s\r\n" % [boundary, payload]).to_utf8_buffer())
	body.append_array(("--%s\r\nContent-Disposition: form-data; name=\"files[0]\"; filename=\"%s\"\r\nContent-Type: text/plain\r\n\r\n" % [boundary, file_name]).to_utf8_buffer())
	body.append_array(bytes)
	body.append_array(("\r\n--%s--\r\n" % boundary).to_utf8_buffer())
	var http := HTTPRequest.new()
	http.timeout = HTTP_TIMEOUT
	add_child(http)
	var err := http.request_raw(WEBHOOK_URL, ["Content-Type: multipart/form-data; boundary=" + boundary], HTTPClient.METHOD_POST, body)
	if err != OK:
		http.queue_free()
		return false
	var result: Array = await http.request_completed
	http.queue_free()
	var code: int = result[1]
	if result[0] != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300:
		DebugLog.info("PlayLog: 전송 실패 (result %d, HTTP %d)" % [result[0], code])
		return false
	return true

static func _read_sent_state(path: String) -> Dictionary:
	if not FileAccess.file_exists(path + ".sent"):
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(path + ".sent"))
	return data if typeof(data) == TYPE_DICTIONARY else {}

static func _write_sent_state(path: String, state: Dictionary) -> void:
	var f := FileAccess.open(path + ".sent", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(state))

# 아직 안 보낸 로그와 전송 위치 파일을 모두 지운다 (동의 철회)
static func delete_pending(dir: String) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.begins_with(FILE_PREFIX) and (f.ends_with(".log") or f.ends_with(".log.sent")):
			DirAccess.remove_absolute(dir.path_join(f))

# --- 기록 ---

func _log_error_entry(kind: String, where: String, message: String) -> void:
	var key := where + " " + message
	_mutex.lock()
	var count: int = int(_error_counts.get(key, 0)) + 1
	_error_counts[key] = count
	_mutex.unlock()
	if count > MAX_SAME_ERROR:
		return
	var suffix := " (same error repeats; not logged again)" if count == MAX_SAME_ERROR else ""
	_write_line("%s %s %s%s" % [kind, where, message, suffix])
	if kind == "ERROR":
		_error_since_upload = true

func _write_line(text: String) -> void:
	_mutex.lock()
	if _file != null and not _writing and _line_count < MAX_LINES:
		_writing = true
		_line_count += 1
		if _line_count == MAX_LINES:
			text = "LOG LIMIT REACHED — nothing more is logged this session"
		_file.store_line("[+%.3fs] %s" % [_elapsed_seconds(), sanitize(text)])
		_file.flush() # 강제 종료돼도 직전 줄까지는 남아 다음 실행 때 보낼 수 있도록
		_writing = false
	_mutex.unlock()

func _elapsed_seconds() -> float:
	return (Time.get_ticks_msec() - _start_msec) / 1000.0

# 사용자 폴더 경로(실명이 들어갈 수 있음)를 지운다
static func sanitize(text: String) -> String:
	var replacements := {
		OS.get_user_data_dir(): "<userdata>",
		OS.get_environment("USERPROFILE"): "<home>",
		OS.get_environment("HOME"): "<home>",
	}
	for original in replacements:
		var path := str(original)
		if path.length() < 4:
			continue
		text = text.replace(path, replacements[original])
		text = text.replace(path.replace("\\", "/"), replacements[original])
		text = text.replace(path.replace("/", "\\"), replacements[original])
	return text

static func _to_json_value(value: Variant) -> Variant:
	if value is Vector2 or value is Vector2i:
		return [roundi(value.x), roundi(value.y)]
	if value is StringName or value is NodePath:
		return str(value)
	return value

# 파일 이름에 날짜·시간이 들어가 있어 이름순 = 시간순
static func _list_logs(dir: String) -> Array[String]:
	var files: Array[String] = []
	for f in DirAccess.get_files_at(dir):
		if f.begins_with(FILE_PREFIX) and f.ends_with(".log"):
			files.append(f)
	files.sort()
	return files

# 오래된 (못 보낸) 로그부터 지워 keep개만 남긴다
static func _prune_old_files(dir: String, keep: int) -> void:
	var files := _list_logs(dir)
	while files.size() > maxi(keep, 0):
		var path := dir.path_join(files.pop_front())
		DirAccess.remove_absolute(path)
		DirAccess.remove_absolute(path + ".sent")

# 엔진 오류를 받아 PlayLog에 넘긴다 (다른 스레드에서 불릴 수 있다 — 기록은 뮤텍스 안에서)
class _ErrorLogger extends Logger:
	var _owner: WeakRef

	func _init(owner: Node) -> void:
		_owner = weakref(owner)

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
		var log_owner = _owner.get_ref()
		if log_owner == null:
			return
		var kind := "WARNING" if error_type == ERROR_TYPE_WARNING else "ERROR"
		var message := rationale if rationale != "" else code
		# push_error 등은 엔진(C++) 위치가 오므로, 스크립트 호출 위치가 있으면 그쪽을 적는다 (최대 3단계)
		var where := "%s:%d %s()" % [file, line, function]
		for bt in script_backtraces:
			if bt.get_frame_count() == 0:
				continue
			var frames: Array[String] = []
			for i in mini(bt.get_frame_count(), 3):
				frames.append("%s:%d %s()" % [bt.get_frame_file(i), bt.get_frame_line(i), bt.get_frame_function(i)])
			where = " <- ".join(frames)
			break
		log_owner._log_error_entry(kind, where, message)

	func _log_message(message: String, error: bool) -> void:
		if not error:
			return # 일반 print는 적지 않는다
		var log_owner = _owner.get_ref()
		if log_owner != null:
			log_owner._log_error_entry("ERROR", "-", message.strip_edges())
