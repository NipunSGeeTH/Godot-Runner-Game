extends Node

signal request_finished(path: String, success: bool, status: int, body: Dictionary)

var _http: HTTPRequest
var _pending_paths: Array[String] = []


func _ready() -> void:
	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)


func post_unsigned(path: String, body_dict: Dictionary = {}) -> void:
	post_with_headers(path, body_dict, PackedStringArray(["Content-Type: application/json"]))


func post_with_jwt(path: String, body_dict: Dictionary = {}) -> void:
	if not AuthSession.is_logged_in():
		request_finished.emit(path, false, 0, {"error": "not_logged_in"})
		return
	var headers: PackedStringArray = [
		"Content-Type: application/json",
		"Authorization: Bearer " + AuthSession.token,
	]
	post_with_headers(path, body_dict, headers)


func post_with_headers(path: String, body_dict: Dictionary, headers: PackedStringArray) -> void:
	var body := JSON.stringify(body_dict)
	var url := _full_url(path)
	_log("POST %s -> %s" % [path, url])
	_pending_paths.append(path)
	var err := _http.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		_pop_pending()
		_log("POST %s failed to start (err %d)" % [path, err])
		request_finished.emit(path, false, 0, {"error": "request_failed", "code": err})


func post_signed(path: String, body_dict: Dictionary) -> void:
	if not RunSession.has_session():
		_log("POST %s blocked — no session yet" % path)
		request_finished.emit(path, false, 0, {"error": "no_session"})
		return

	var body := JSON.stringify(body_dict)
	var ts := str(int(Time.get_unix_time_from_system() * 1000.0))
	var nonce := _uuid()
	var sig := HmacSign.sign(RunSession.signing_secret, "POST", path, ts, nonce, body)
	var url := _full_url(path)
	_log("POST %s (signed) -> %s" % [path, url])
	_pending_paths.append(path)
	var headers: PackedStringArray = [
		"Content-Type: application/json",
		"X-Session-Id: " + RunSession.session_id,
		"X-Timestamp: " + ts,
		"X-Nonce: " + nonce,
		"X-Signature: " + sig,
	]
	var err := _http.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		_pop_pending()
		_log("POST %s failed to start (err %d)" % [path, err])
		request_finished.emit(path, false, 0, {"error": "request_failed", "code": err})


func get_json(path: String) -> void:
	var url := _full_url(path)
	_log("GET %s -> %s" % [path, url])
	_pending_paths.append(path)
	var headers: PackedStringArray = []
	if AuthSession.is_logged_in():
		headers.append("Authorization: Bearer " + AuthSession.token)
	var err := _http.request(url, headers)
	if err != OK:
		_pop_pending()
		_log("GET %s failed to start (err %d)" % [path, err])
		request_finished.emit(path, false, 0, {"error": "request_failed", "code": err})


func _full_url(path: String) -> String:
	var base := SimConstants.API_BASE.rstrip("/")
	if path.begins_with("/"):
		return base + path
	return base + "/" + path


func _on_request_completed(result: int, code: int, _headers: PackedStringArray, body_bytes: PackedByteArray) -> void:
	var path := _pop_pending()
	var parsed: Dictionary = {}
	var raw := ""
	if body_bytes.size() > 0:
		raw = body_bytes.get_string_from_utf8()
		var json := JSON.new()
		if json.parse(raw) == OK and json.data is Dictionary:
			parsed = json.data
		else:
			parsed = {"raw": raw}

	var ok := result == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300
	if SimConstants.DEBUG_API:
		if ok:
			_log("OK %s HTTP %d -> %s" % [path, code, _truncate(raw)])
		else:
			_log("FAIL %s result=%d HTTP %d -> %s" % [path, result, code, _truncate(raw)])

	request_finished.emit(path, ok, code, parsed)


func _pop_pending() -> String:
	if _pending_paths.is_empty():
		return ""
	return _pending_paths.pop_front()


func _log(msg: String) -> void:
	if SimConstants.DEBUG_API:
		print("[ApiClient] ", msg)


func _truncate(s: String, max_len: int = 240) -> String:
	if s.length() <= max_len:
		return s
	return s.substr(0, max_len) + "…"


func _uuid() -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return "%08x-%04x-%04x-%04x-%012x" % [
		rng.randi(),
		rng.randi() & 0xFFFF,
		(rng.randi() & 0x0FFF) | 0x4000,
		(rng.randi() & 0x3FFF) | 0x8000,
		rng.randi() & 0xFFFFFFFFFFFF,
	]
