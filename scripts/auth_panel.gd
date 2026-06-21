extends Control

signal logged_in()

var _mode: String = "login"
var _panel: PanelContainer
var _title: Label
var _index_field: LineEdit
var _username_field: LineEdit
var _password_field: LineEdit
var _contact_field: LineEdit
var _status: Label
var _submit_btn: Button
var _toggle_btn: Button
var _busy: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	if not ApiClient.request_finished.is_connected(_on_api_response):
		ApiClient.request_finished.connect(_on_api_response)


func _build_ui() -> void:
	var dim := ColorRect.new()
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.72)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP

	_panel = PanelContainer.new()
	add_child(_panel)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_panel.offset_left = -300
	_panel.offset_right = 300
	_panel.offset_top = -280
	_panel.offset_bottom = 280
	_panel.add_theme_stylebox_override("panel", _panel_style())

	var box := VBoxContainer.new()
	_panel.add_child(box)
	box.add_theme_constant_override("separation", 12)

	_title = Label.new()
	box.add_child(_title)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 36)
	_title.add_theme_color_override("font_color", Color(1, 0.88, 0.35))

	_index_field = _field(box, "Index number")
	_username_field = _field(box, "Username")
	_password_field = _field(box, "Password", true)
	_contact_field = _field(box, "Contact (optional)")

	_status = Label.new()
	box.add_child(_status)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 18)
	_status.add_theme_color_override("font_color", Color(1, 0.55, 0.5))

	_submit_btn = Button.new()
	box.add_child(_submit_btn)
	_submit_btn.custom_minimum_size = Vector2(0, 72)
	_submit_btn.add_theme_font_size_override("font_size", 28)
	_submit_btn.pressed.connect(_on_submit)

	_toggle_btn = Button.new()
	box.add_child(_toggle_btn)
	_toggle_btn.custom_minimum_size = Vector2(0, 56)
	_toggle_btn.add_theme_font_size_override("font_size", 20)
	_toggle_btn.pressed.connect(_toggle_mode)

	_set_mode("login")


func _field(parent: Control, placeholder: String, secret: bool = false) -> LineEdit:
	var f := LineEdit.new()
	parent.add_child(f)
	f.placeholder_text = placeholder
	f.custom_minimum_size = Vector2(0, 52)
	f.add_theme_font_size_override("font_size", 22)
	if secret:
		f.secret = true
	return f


func _panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.11, 0.17, 0.98)
	sb.set_corner_radius_all(24)
	sb.set_border_width_all(2)
	sb.border_color = Color(1, 0.85, 0.3, 0.45)
	sb.content_margin_left = 24
	sb.content_margin_right = 24
	sb.content_margin_top = 22
	sb.content_margin_bottom = 22
	return sb


func _pill(c: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(22)
	return sb


func _set_mode(mode: String) -> void:
	_mode = mode
	var is_login := mode == "login"
	_title.text = "Login" if is_login else "Register"
	_username_field.visible = not is_login
	_contact_field.visible = not is_login
	_submit_btn.text = "LOGIN" if is_login else "REGISTER"
	_submit_btn.add_theme_stylebox_override("normal", _pill(Color(0.16, 0.72, 0.4) if is_login else Color(0.22, 0.38, 0.72)))
	_toggle_btn.text = "Need an account? Register" if is_login else "Already registered? Login"
	_status.text = ""


func _toggle_mode() -> void:
	_set_mode("register" if _mode == "login" else "login")


func _on_submit() -> void:
	if _busy:
		return
	var index_num := _index_field.text.strip_edges()
	var password := _password_field.text
	if index_num == "" or password == "":
		_status.text = "Index number and password required."
		return

	_busy = true
	_submit_btn.disabled = true
	_status.text = "Please wait…"

	if _mode == "login":
		ApiClient.post_unsigned("/v1/auth/login", {
			"index_number": index_num,
			"password": password,
		})
	else:
		var username := _username_field.text.strip_edges()
		if username == "":
			_status.text = "Username required."
			_busy = false
			_submit_btn.disabled = false
			return
		var body := {
			"index_number": index_num,
			"username": username,
			"password": password,
		}
		var contact := _contact_field.text.strip_edges()
		if contact != "":
			body["contact_number"] = contact
		ApiClient.post_unsigned("/v1/auth/register", body)


func _on_api_response(path: String, success: bool, status: int, body: Dictionary) -> void:
	if path != "/v1/auth/login" and path != "/v1/auth/register":
		return
	_busy = false
	_submit_btn.disabled = false
	if success:
		AuthSession.set_auth(body)
		visible = false
		logged_in.emit()
	else:
		var err := str(body.get("error", body.get("message", body.get("raw", "Request failed"))))
		_status.text = "%s (%d)" % [err, status]
