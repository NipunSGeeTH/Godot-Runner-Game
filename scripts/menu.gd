extends Control

const TICKET_URL: String = "https://epilogue.moraspirit.com"

var _overlay: PanelContainer
var _overlay_title: Label
var _overlay_body: Label
var _overlay_close: Button
var _sound_btn: Button
var _play_btn: Button
var _user_label: Label
var _auth_panel: Control
var _login_btn: Button
var _logout_btn: Button


func _ready() -> void:
	GameSettings.apply_sound()
	_build_ui()
	_refresh_auth_ui()
	if SimConstants.API_BASE != "" and not AuthSession.is_logged_in():
		call_deferred("_show_auth_panel")
	if not ApiClient.request_finished.is_connected(_on_api_leaderboard):
		ApiClient.request_finished.connect(_on_api_leaderboard)


func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.07, 0.1, 0.16)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var gradient := ColorRect.new()
	add_child(gradient)
	gradient.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	gradient.color = Color(0.28, 0.1, 0.32, 0.35)
	gradient.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_user_label = Label.new()
	add_child(_user_label)
	_user_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_user_label.offset_top = 16
	_user_label.offset_bottom = 52
	_user_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_user_label.add_theme_font_size_override("font_size", 20)
	_user_label.add_theme_color_override("font_color", Color(0.75, 0.82, 0.95, 0.9))

	var margin := MarginContainer.new()
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 56)
	margin.add_theme_constant_override("margin_bottom", 48)

	var root := VBoxContainer.new()
	margin.add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 18)
	root.alignment = BoxContainer.ALIGNMENT_CENTER

	var title := Label.new()
	root.add_child(title)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 78)
	title.add_theme_color_override("font_color", Color(1, 0.86, 0.32))
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
	title.add_theme_constant_override("outline_size", 10)
	title.text = "EPILOGUE"

	var subtitle := Label.new()
	root.add_child(subtitle)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 34)
	subtitle.add_theme_color_override("font_color", Color(0.82, 0.9, 1.0))
	subtitle.text = "Runner"

	var tag := Label.new()
	root.add_child(tag)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.add_theme_font_size_override("font_size", 20)
	tag.add_theme_color_override("font_color", Color(0.72, 0.78, 0.92, 0.85))
	tag.text = "28 July Concert"

	root.add_child(_spacer(8))

	_login_btn = _add_menu_button(root, "LOGIN / REGISTER", Color(0.22, 0.38, 0.72), _show_auth_panel)
	_logout_btn = _add_menu_button(root, "LOGOUT", Color(0.35, 0.22, 0.22), _on_logout)
	_logout_btn.visible = false

	_play_btn = _add_menu_button(root, "PLAY", Color(0.16, 0.72, 0.4), _on_play)
	_add_menu_button(root, "LEADERBOARD", Color(0.55, 0.35, 0.12), _on_leaderboard)
	_add_menu_button(root, "BUY TICKET", Color(0.72, 0.48, 0.1), _on_buy_ticket)
	_add_menu_button(root, "HOW TO PLAY", Color(0.22, 0.38, 0.72), func(): _show_overlay(
		"How to Play",
		"Login with your index number first.\n\nSwipe left or right to change lane.\n\nSwipe up to jump over rocks.\n\nCollect coins — only coins count for score!"
	))
	_sound_btn = _add_menu_button(root, "", Color(0.28, 0.32, 0.42), _on_toggle_sound)
	_refresh_sound_label()
	_add_menu_button(root, "CREDITS", Color(0.28, 0.32, 0.42), func(): _show_overlay(
		"Credits",
		"moraspirit.com\n\nWeb & Technology Piler"
	))

	if not _is_mobile():
		_add_menu_button(root, "QUIT", Color(0.45, 0.18, 0.18), _on_quit)

	_build_overlay()

	_auth_panel = load("res://scripts/auth_panel.gd").new()
	add_child(_auth_panel)
	_auth_panel.visible = false
	_auth_panel.logged_in.connect(_on_logged_in)


func _refresh_auth_ui() -> void:
	var needs_auth := SimConstants.API_BASE != "" and not AuthSession.is_logged_in()
	_login_btn.visible = needs_auth
	_logout_btn.visible = AuthSession.is_logged_in()
	if _play_btn:
		_play_btn.disabled = needs_auth
		_play_btn.text = "LOGIN TO PLAY" if needs_auth else "PLAY"
	if AuthSession.is_logged_in():
		_user_label.text = "%s  ·  Best %d coins" % [AuthSession.username, AuthSession.best_coins]
	elif SimConstants.API_BASE != "":
		_user_label.text = "Login required to play online"
	else:
		_user_label.text = "Offline mode"


func _show_auth_panel() -> void:
	_auth_panel.visible = true


func _on_logged_in() -> void:
	_refresh_auth_ui()
	ApiClient.get_json("/v1/leaderboard/me")


func _on_logout() -> void:
	AuthSession.clear()
	RunSession.run_active = false
	_refresh_auth_ui()


var _lb_top: Array = []
var _lb_me: Dictionary = {}
var _lb_pending: int = 0


func _on_leaderboard() -> void:
	if SimConstants.API_BASE == "":
		_show_overlay("Leaderboard", "Connect to the server to view rankings.")
		return
	_lb_top = []
	_lb_me = {}
	_lb_pending = 1
	ApiClient.get_json("/v1/leaderboard")
	if AuthSession.is_logged_in():
		_lb_pending = 2
		ApiClient.get_json("/v1/leaderboard/me")


func _on_api_leaderboard(path: String, success: bool, _status: int, body: Dictionary) -> void:
	if path == "/v1/leaderboard":
		if success:
			_lb_top = body.get("top", [])
		_lb_pending -= 1
		_try_show_leaderboard()
	elif path == "/v1/leaderboard/me":
		if success:
			_lb_me = body
			if body.has("best_coins"):
				AuthSession.best_coins = int(body.get("best_coins", AuthSession.best_coins))
				_refresh_auth_ui()
		_lb_pending -= 1
		_try_show_leaderboard()


func _try_show_leaderboard() -> void:
	if _lb_pending > 0:
		return
	var lines: PackedStringArray = PackedStringArray()
	lines.append("Top 10")
	lines.append("")
	for row in _lb_top:
		if row is Dictionary:
			lines.append("#%s  %s  —  %d coins" % [
				row.get("rank", "?"),
				row.get("username", "?"),
				row.get("coins", 0),
			])
	if AuthSession.is_logged_in() and not _lb_me.is_empty():
		lines.append("")
		var rank: int = int(_lb_me.get("rank", 0))
		if rank > 0:
			lines.append("You: #%d  ·  %d coins (best %d)" % [
				rank,
				int(_lb_me.get("coins", 0)),
				int(_lb_me.get("best_coins", 0)),
			])
		else:
			lines.append("You: no rank yet — collect coins!")
	_show_overlay("Leaderboard", "\n".join(lines))
	_lb_top = []
	_lb_me = {}


func _add_menu_button(parent: Control, text: String, col: Color, cb: Callable) -> Button:
	var btn := Button.new()
	parent.add_child(btn)
	btn.custom_minimum_size = Vector2(0, 80)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_font_size_override("font_size", 32)
	btn.text = text
	btn.add_theme_stylebox_override("normal", _pill(col))
	btn.add_theme_stylebox_override("hover", _pill(col.lightened(0.08)))
	btn.add_theme_stylebox_override("pressed", _pill(col.darkened(0.08)))
	btn.pressed.connect(cb)
	return btn


func _spacer(h: int) -> Control:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, h)
	return s


func _pill(c: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(22)
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	sb.shadow_size = 4
	sb.shadow_color = Color(0, 0, 0, 0.35)
	return sb


func _build_overlay() -> void:
	var dim := ColorRect.new()
	dim.name = "OverlayDim"
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.62)
	dim.visible = false
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(e: InputEvent):
		if e is InputEventScreenTouch and e.pressed:
			_hide_overlay()
		elif e is InputEventMouseButton and e.pressed:
			_hide_overlay()
	)

	_overlay = PanelContainer.new()
	_overlay.name = "OverlayPanel"
	add_child(_overlay)
	_overlay.visible = false
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_overlay.offset_left = -300
	_overlay.offset_right = 300
	_overlay.offset_top = -260
	_overlay.offset_bottom = 260
	_overlay.add_theme_stylebox_override("panel", _overlay_style())

	var box := VBoxContainer.new()
	_overlay.add_child(box)
	box.add_theme_constant_override("separation", 16)

	_overlay_title = Label.new()
	box.add_child(_overlay_title)
	_overlay_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_title.add_theme_font_size_override("font_size", 40)
	_overlay_title.add_theme_color_override("font_color", Color(1, 0.9, 0.45))

	_overlay_body = Label.new()
	box.add_child(_overlay_body)
	_overlay_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_overlay_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_body.add_theme_font_size_override("font_size", 22)
	_overlay_body.add_theme_color_override("font_color", Color(0.9, 0.94, 1.0))

	_overlay_close = Button.new()
	box.add_child(_overlay_close)
	_overlay_close.custom_minimum_size = Vector2(0, 72)
	_overlay_close.text = "CLOSE"
	_overlay_close.add_theme_font_size_override("font_size", 28)
	_overlay_close.add_theme_stylebox_override("normal", _pill(Color(0.2, 0.55, 0.85)))
	_overlay_close.pressed.connect(_hide_overlay)


func _overlay_style() -> StyleBoxFlat:
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


func _show_overlay(title: String, body: String) -> void:
	_overlay_title.text = title
	_overlay_body.text = body
	_overlay.visible = true
	get_node("OverlayDim").visible = true


func _hide_overlay() -> void:
	_overlay.visible = false
	get_node("OverlayDim").visible = false


func _refresh_sound_label() -> void:
	_sound_btn.text = "SOUND: ON" if GameSettings.sound_enabled else "SOUND: OFF"


func _on_play() -> void:
	if SimConstants.API_BASE != "" and not AuthSession.is_logged_in():
		_show_auth_panel()
		return
	if _play_btn:
		_play_btn.disabled = true
		_play_btn.text = "LOADING..."
	if RunSession.run_ready.is_connected(_on_run_ready):
		RunSession.run_ready.disconnect(_on_run_ready)
	RunSession.run_ready.connect(_on_run_ready, CONNECT_ONE_SHOT)
	RunSession.prepare_run()


func _on_run_ready(success: bool, error_message: String) -> void:
	_refresh_auth_ui()
	if not success:
		if _play_btn:
			_play_btn.disabled = SimConstants.API_BASE != "" and not AuthSession.is_logged_in()
		_show_overlay("Could not start", error_message if error_message != "" else "Try again later.")
		return
	get_tree().change_scene_to_file("res://scenes/level.tscn")


func _on_buy_ticket() -> void:
	OS.shell_open(TICKET_URL)


func _on_toggle_sound() -> void:
	GameSettings.toggle_sound()
	_refresh_sound_label()


func _on_quit() -> void:
	get_tree().quit()


func _is_mobile() -> bool:
	var os := OS.get_name()
	return os == "Android" or os == "iOS" or os == "Web"
