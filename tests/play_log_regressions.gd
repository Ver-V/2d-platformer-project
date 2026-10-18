extends SceneTree
# Run with Godot --headless --path . --script res://tests/play_log_regressions.gd
# 플레이 로그(PlayLog) 검사. 실제 로그 폴더·설정 파일은 건드리지 않고 (테스트 폴더·경로 사용),
# 웹훅으로 보내지 않는다 (sender를 가짜로 바꿔 끼움).

const TEST_DIR := "user://test_play_logs"
const TEST_SETTINGS := "user://test_play_log_settings.json"

var failures: int = 0
var play_log: Node
var sent: Array[Dictionary] = [] # 가짜 sender가 받은 것 {name, content, text}
var sender_ok := true

func _initialize() -> void:
	call_deferred("run_checks")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func run_checks() -> void:
	play_log = root.get_node("/root/PlayLog")
	play_log.sender = _fake_send
	_clear_dir()
	check_not_started_headless()
	check_session_writes_events_and_errors()
	check_boss_and_death_events()
	check_repeated_errors_and_line_limit()
	check_sanitize_hides_home()
	check_prunes_old_files()
	await check_uploads_only_new_parts()
	await check_failed_upload_is_retried()
	check_delete_pending()
	check_consent_saved_in_settings()
	check_consent_text_translated()
	play_log.sender = play_log._send_to_webhook
	_clear_dir()
	DirAccess.remove_absolute(TEST_DIR)
	DirAccess.remove_absolute(TEST_SETTINGS)
	print("Play log regression checks: ", "PASS" if failures == 0 else "FAIL", " (", failures, " failures)")
	quit(0 if failures == 0 else 1)

func _fake_send(file_name: String, content: String, bytes: PackedByteArray) -> bool:
	if sender_ok:
		sent.append({"name": file_name, "content": content, "text": bytes.get_string_from_utf8()})
	return sender_ok

func _clear_dir() -> void:
	if not DirAccess.dir_exists_absolute(TEST_DIR):
		return
	for f in DirAccess.get_files_at(TEST_DIR):
		DirAccess.remove_absolute(TEST_DIR.path_join(f))

func _read_session() -> String:
	var path: String = play_log.get_current_path()
	play_log.stop_session()
	return FileAccess.get_file_as_string(path)

func check_not_started_headless() -> void:
	check(not play_log.is_recording(), "PlayLog should not record by itself in headless runs")
	check(auto_accept_quit, "Headless runs should keep the default quit behavior")
	play_log.event("ignored", {"a": 1}) # 기록 중이 아니면 아무것도 안 해야 한다

func check_session_writes_events_and_errors() -> void:
	_clear_dir()
	check(play_log.start_session(TEST_DIR), "start_session should create a log file")
	check(play_log.is_recording(), "PlayLog should be recording after start_session")
	play_log.event("test_event", {"pos": Vector2(12.4, -3.6), "name": &"slime"})
	push_warning("play log capture test")
	var text := _read_session()
	check(not play_log.is_recording(), "stop_session should stop recording")
	check(text.contains("EVENT session_start"), "Log should start with session_start")
	check(text.contains('EVENT test_event {"name":"slime","pos":[12,-4]}'),
		"Events should be written as JSON with Vector2 rounded to [x, y]")
	check(text.contains("WARNING") and text.contains("play log capture test"), "push_warning should be captured")
	check(text.contains("res://tests/play_log_regressions.gd:"), "Errors should point at the script line, not the engine")
	check(text.contains("EVENT session_end"), "Log should end with session_end")
	var lines := text.strip_edges().split("\n")
	check(lines.size() >= 4 and lines[0].begins_with("[+"), "Every line should start with the elapsed time")
	# 끈 뒤의 오류는 적지 않는다
	push_warning("after stop")
	var files := DirAccess.get_files_at(TEST_DIR)
	check(files.size() == 1 and not FileAccess.get_file_as_string(TEST_DIR.path_join(files[0])).contains("after stop"),
		"Errors after stop_session should not be written")

func check_boss_and_death_events() -> void:
	play_log.start_session(TEST_DIR)
	play_log.boss_entered("boss2")
	play_log.player_died("res://Scenes/Stage/Stage_02.tscn", Vector2(100, 200), "boss2")
	play_log.boss_entered("boss2")
	play_log.boss_defeated("boss2")
	play_log.player_died("res://Scenes/Stage/Stage_02.tscn", Vector2(5, 5), "slime")
	var text := _read_session()
	check(text.contains('EVENT player_death {"boss":"boss2","cause":"boss2","pos":[100,200],"scene":"Stage_02"}'),
		"A death during a boss fight should name the boss")
	check(text.contains('"attempt":2'), "Re-entering the boss room should count as another attempt")
	check(text.contains('EVENT boss_defeated {"attempts":2,"boss":"boss2","fight_time":'),
		"boss_defeated should record attempts and fight time")
	check(text.contains('EVENT player_death {"cause":"slime","pos":[5,5],"scene":"Stage_02"}'),
		"After the boss is defeated, deaths should not name it")

func check_repeated_errors_and_line_limit() -> void:
	_clear_dir()
	play_log.start_session(TEST_DIR)
	for i in 6:
		push_warning("same warning")
	for i in play_log.MAX_LINES + 50:
		play_log.event("spam")
	var text := _read_session()
	check(text.count("same warning") == play_log.MAX_SAME_ERROR,
		"The same error should be logged only %d times (got %d)" % [play_log.MAX_SAME_ERROR, text.count("same warning")])
	check(text.contains("not logged again"), "The last allowed repeat should say it will not be logged again")
	var lines := text.strip_edges().split("\n")
	check(lines.size() == play_log.MAX_LINES, "A session should stop at MAX_LINES lines (got %d)" % lines.size())
	check(lines[-1].contains("LOG LIMIT REACHED"), "The last line should say the limit was reached")
	_clear_dir()

func check_sanitize_hides_home() -> void:
	var home := OS.get_environment("USERPROFILE")
	if home == "":
		home = OS.get_environment("HOME")
	if home.length() < 4:
		return
	var out: String = play_log.sanitize("error at " + home + "\\Desktop\\x.gd and " + home.replace("\\", "/") + "/y")
	check(not out.contains(home) and not out.contains(home.replace("\\", "/")), "sanitize should remove the home path")
	check(out.contains("<home>"), "sanitize should replace the home path with <home>")
	var data_dir := OS.get_user_data_dir()
	check(play_log.sanitize(data_dir + "/save.json") == "<userdata>/save.json", "sanitize should hide the user data dir")

func check_prunes_old_files() -> void:
	_clear_dir()
	DirAccess.make_dir_recursive_absolute(TEST_DIR)
	for i in 15:
		var f := FileAccess.open(TEST_DIR.path_join("play_20000101_0000%02d_000.log" % i), FileAccess.WRITE)
		f.store_line("old")
		f.close()
	FileAccess.open(TEST_DIR.path_join("play_20000101_000000_000.log.sent"), FileAccess.WRITE).store_string("{}")
	FileAccess.open(TEST_DIR.path_join("keep_me.txt"), FileAccess.WRITE).close()
	play_log.start_session(TEST_DIR)
	play_log.stop_session()
	var logs := Array(DirAccess.get_files_at(TEST_DIR)).filter(func(f): return f.begins_with("play_") and f.ends_with(".log"))
	check(logs.size() == play_log.MAX_PENDING, "Only the newest %d unsent logs should be kept (got %d)" % [play_log.MAX_PENDING, logs.size()])
	check(not logs.has("play_20000101_000000_000.log"), "The oldest log should be deleted first")
	check(not FileAccess.file_exists(TEST_DIR.path_join("play_20000101_000000_000.log.sent")), "A pruned log's .sent file should go too")
	check(FileAccess.file_exists(TEST_DIR.path_join("keep_me.txt")), "Pruning should only touch play_* files")
	_clear_dir()

func check_uploads_only_new_parts() -> void:
	_clear_dir()
	sent.clear()
	sender_ok = true
	# 지난번에 끝까지 못 보낸 세션 (일부는 이미 보냄)
	DirAccess.make_dir_recursive_absolute(TEST_DIR)
	var old_path := TEST_DIR.path_join("play_20000101_000000_000.log")
	var old := FileAccess.open(old_path, FileAccess.WRITE)
	old.store_string("first line\nsecond line\n")
	old.close()
	FileAccess.open(old_path + ".sent", FileAccess.WRITE).store_string('{"offset":11,"part":1}')

	play_log.start_session(TEST_DIR)
	var path: String = play_log.get_current_path()
	push_error("upload test error")
	await play_log.upload_pending()
	check(sent.size() == 2, "Upload should send the leftover session and the current one (sent %d)" % sent.size())
	if sent.size() == 2:
		check(sent[0]["text"] == "second line\n" and sent[0]["name"].ends_with("_part2.log") and sent[0]["content"].contains("(end)"),
			"A leftover session should send only what was not sent yet, as the next part, marked as the end")
		check(sent[1]["text"].contains("session_start") and sent[1]["name"].ends_with("_part1.log")
			and not sent[1]["content"].contains("(end)") and sent[1]["content"].contains("errors: 1"),
			"The running session should be sent as part 1 with its error count")
	check(not FileAccess.file_exists(old_path) and not FileAccess.file_exists(old_path + ".sent"),
		"A finished session should be deleted once fully sent")
	check(FileAccess.file_exists(path), "The running session's file should stay until it ends")

	sent.clear()
	await play_log.upload_pending()
	check(sent.is_empty(), "Nothing new means nothing to send")

	play_log.event("after_first_upload")
	play_log.stop_session()
	await play_log.upload_pending()
	check(sent.size() == 1, "Ending the session should send the rest")
	if sent.size() == 1:
		check(sent[0]["text"].contains("after_first_upload") and not sent[0]["text"].contains("session_start"),
			"Later uploads should contain only new lines")
		check(sent[0]["name"].ends_with("_part2.log") and sent[0]["content"].contains("(end)"),
			"The final upload should be the next part and marked as the end")
	check(not FileAccess.file_exists(path), "The session file should be deleted after the final upload")

func check_failed_upload_is_retried() -> void:
	_clear_dir()
	sent.clear()
	play_log.start_session(TEST_DIR)
	play_log.event("keep_me")
	play_log.stop_session()
	sender_ok = false
	await play_log.upload_pending()
	var logs := Array(DirAccess.get_files_at(TEST_DIR)).filter(func(f): return f.ends_with(".log"))
	check(logs.size() == 1, "A failed upload should keep the log for later")
	sender_ok = true
	await play_log.upload_pending()
	check(sent.size() == 1 and sent[0]["text"].contains("keep_me") and sent[0]["name"].ends_with("_part1.log"),
		"The next upload should resend everything that failed")
	check(DirAccess.get_files_at(TEST_DIR).is_empty(), "Once resent, the log should be deleted")

func check_delete_pending() -> void:
	_clear_dir()
	play_log.start_session(TEST_DIR)
	play_log.stop_session()
	FileAccess.open(TEST_DIR.path_join("keep_me.txt"), FileAccess.WRITE).close()
	play_log.delete_pending(TEST_DIR)
	check(Array(DirAccess.get_files_at(TEST_DIR)) == ["keep_me.txt"], "Withdrawing consent should delete unsent logs only")
	_clear_dir()

func check_consent_saved_in_settings() -> void:
	var settings := root.get_node("/root/SettingsManager")
	var original: int = settings.log_consent
	settings.log_consent = 1
	settings.save_settings(TEST_SETTINGS)
	settings.log_consent = -1
	settings.load_settings(TEST_SETTINGS)
	check(settings.log_consent == 1, "log_consent should round-trip through the settings file")
	FileAccess.open(TEST_SETTINGS, FileAccess.WRITE).store_string('{"locale":"en","master_vol":1.0}')
	settings.load_settings(TEST_SETTINGS)
	check(settings.log_consent == -1, "Old settings files without log_consent should mean 'not asked yet'")
	settings.log_consent = original

func check_consent_text_translated() -> void:
	for locale in ["en", "ko"]:
		var t := TranslationServer.get_translation_object(locale)
		var text := String(t.get_message(&"LOG_CONSENT_TEXT")) if t else ""
		check(text != "" and text != "LOG_CONSENT_TEXT", "LOG_CONSENT_TEXT should exist in " + locale)
		check(text.contains("\n") and not text.contains("\\n"), "LOG_CONSENT_TEXT should have real line breaks in " + locale)
