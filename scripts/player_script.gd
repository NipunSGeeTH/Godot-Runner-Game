extends CharacterBody3D

const PLAYER_MODEL: String = "res://models/boy/Rogue.glb"

@onready var audio_player: AudioStreamPlayer3D = $AudioStreamPlayer3D
var anim_player: AnimationPlayer

const JUMP_FORCE: float = 9.0
const GRAVITY: float = 22.0
const LANE_SWITCH_SPEED: float = 14.0      # how fast the player slides between lanes
const SWIPE_THRESHOLD: float = 40.0        # min finger travel (px) to count as a swipe

# 3 lanes, matching the obstacle/coin spawn positions in level.gd (road_spawnx)
const LANE_X: Array = [-2.0, 0.0, 2.0]

var ground_y: float = 0.0
var vertical_velocity: float = 0.0

var current_lane: int = 1                  # 0 = left, 1 = center, 2 = right
var jump_requested: bool = false

var run_anim: String = ""
var jump_anim: String = ""
var death_anim: String = ""
var is_jumping: bool = false

var is_dead: bool = false
var dying: bool = false
var game_over: bool = false
var coin_count: int = 0

var coin_label: Label
var score_label: Label
var overlay: Control
var result_label: Label
var hint_label: Label

var _finish_data: Dictionary = {}
var _finish_done: bool = false

# swipe tracking
var _touch_start: Vector2 = Vector2.ZERO
var _swiped: bool = false

func _ready() -> void:
	# keep running while the tree is paused so we can detect the restart tap
	process_mode = Node.PROCESS_MODE_ALWAYS

	# rocks look for an area in this group to know they hit the player
	$collision_area.add_to_group("player_skeleton")

	_spawn_character()
	_setup_hud()

	ground_y = global_transform.origin.y
	run_anim = _find_anim(["Running_A", "Run"])
	jump_anim = _find_anim(["Jump_Full_Long", "Jump"])
	death_anim = _find_anim(["Death_A", "Death"])
	if run_anim != "":
		anim_player.get_animation(run_anim).loop_mode = Animation.LOOP_LINEAR
	_play_run()
	if not RunSession.checkpoint_resolved.is_connected(_on_checkpoint_resolved):
		RunSession.checkpoint_resolved.connect(_on_checkpoint_resolved)
	if not RunSession.finish_resolved.is_connected(_on_finish_resolved):
		RunSession.finish_resolved.connect(_on_finish_resolved)
	_refresh_coin_hud()

# Load the boy model, turn it to face the camera, and wire its AnimationPlayer.
func _spawn_character() -> void:
	var model := (load(PLAYER_MODEL) as PackedScene).instantiate()
	model.name = "player"
	var s: float = 0.85
	# 180 deg about Y so the boy faces the camera (front toward viewer).
	model.transform = Transform3D(Basis(Vector3.UP, PI).scaled(Vector3(s, s, s)), Vector3.ZERO)
	add_child(model)
	anim_player = model.get_node("AnimationPlayer")

func _setup_hud() -> void:
	# Put the HUD on a CanvasLayer so it always fills the screen.
	var layer := CanvasLayer.new()
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)

	# ---- coin chip (top-left): rounded panel + gold coin icon + count ----
	var coin_panel := Panel.new()
	layer.add_child(coin_panel)
	coin_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	coin_panel.position = Vector2(18, 18)
	coin_panel.size = Vector2(168, 58)
	coin_panel.add_theme_stylebox_override("panel", _chip_style())

	var coin_icon := Panel.new()
	coin_panel.add_child(coin_icon)
	coin_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	coin_icon.position = Vector2(13, 13)
	coin_icon.size = Vector2(32, 32)
	coin_icon.add_theme_stylebox_override("panel", _circle_style(Color(1, 0.82, 0.16)))

	coin_label = Label.new()
	coin_panel.add_child(coin_label)
	coin_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	coin_label.position = Vector2(58, 9)
	coin_label.add_theme_font_size_override("font_size", 30)
	coin_label.add_theme_color_override("font_color", Color(1, 0.96, 0.78))
	coin_label.text = "0"

	# ---- score chip (top-right) ----
	var score_panel := Panel.new()
	layer.add_child(score_panel)
	score_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	score_panel.anchor_left = 1.0
	score_panel.anchor_right = 1.0
	score_panel.offset_left = -210.0
	score_panel.offset_right = -18.0
	score_panel.offset_top = 18.0
	score_panel.offset_bottom = 76.0
	score_panel.add_theme_stylebox_override("panel", _chip_style())

	score_label = Label.new()
	score_panel.add_child(score_label)
	score_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	score_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	score_label.add_theme_font_size_override("font_size", 28)
	score_label.add_theme_color_override("font_color", Color(0.85, 0.93, 1.0))
	score_label.text = "COINS 0"

	# ---- controls hint (bottom-center, fades out) ----
	hint_label = Label.new()
	layer.add_child(hint_label)
	hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_label.anchor_top = 1.0
	hint_label.anchor_bottom = 1.0
	hint_label.anchor_right = 1.0
	hint_label.offset_top = -90.0
	hint_label.offset_bottom = -40.0
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint_label.add_theme_font_size_override("font_size", 24)
	hint_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	hint_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	hint_label.add_theme_constant_override("outline_size", 5)
	hint_label.text = "Swipe  <  >  lane     Swipe  ^  jump     Collect coins!"
	var tw := create_tween()
	tw.tween_interval(4.0)
	tw.tween_property(hint_label, "modulate:a", 0.0, 1.2)

	# ---- full-screen game-over overlay (dim + centered card) ----
	overlay = Control.new()
	layer.add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.visible = false

	var bg := ColorRect.new()
	overlay.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0, 0, 0, 0.66)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var card := Panel.new()
	overlay.add_child(card)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.anchor_left = 0.5
	card.anchor_right = 0.5
	card.anchor_top = 0.5
	card.anchor_bottom = 0.5
	card.offset_left = -220.0
	card.offset_right = 220.0
	card.offset_top = -180.0
	card.offset_bottom = 180.0
	card.add_theme_stylebox_override("panel", _card_style())

	var title := Label.new()
	card.add_child(title)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.position = Vector2(0, 34)
	title.size = Vector2(440, 70)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 58)
	title.add_theme_color_override("font_color", Color(1, 0.32, 0.28))
	title.text = "GAME OVER"

	result_label = Label.new()
	card.add_child(result_label)
	result_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result_label.position = Vector2(0, 138)
	result_label.size = Vector2(440, 50)
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label.add_theme_font_size_override("font_size", 30)
	result_label.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0))
	result_label.text = "Score 0     Coins 0"

	var play_again := Button.new()
	card.add_child(play_again)
	play_again.position = Vector2(50, 218)
	play_again.size = Vector2(340, 58)
	play_again.add_theme_font_size_override("font_size", 26)
	play_again.text = "Play"
	play_again.add_theme_stylebox_override("normal", _pill_style(Color(0.92, 0.95, 1.0)))
	play_again.add_theme_color_override("font_color", Color(0.08, 0.1, 0.14))
	play_again.pressed.connect(_restart)

	var menu_btn := Button.new()
	card.add_child(menu_btn)
	menu_btn.position = Vector2(50, 286)
	menu_btn.size = Vector2(340, 52)
	menu_btn.add_theme_font_size_override("font_size", 22)
	menu_btn.add_theme_color_override("font_color", Color(0.85, 0.72, 0.35))
	menu_btn.text = "Menu"
	menu_btn.add_theme_stylebox_override("normal", _pill_style(Color(0.12, 0.14, 0.2)))
	menu_btn.pressed.connect(_go_menu)

func _refresh_coin_hud() -> void:
	coin_label.text = str(coin_count)
	score_label.text = "COINS %d" % coin_count


func _on_checkpoint_resolved(accepted: bool, data: Dictionary) -> void:
	if accepted:
		coin_count = int(data.get("run_total_coins", coin_count))
		_refresh_coin_hud()


func _on_finish_resolved(_success: bool, data: Dictionary) -> void:
	_finish_data = data
	_finish_done = true


func _chip_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.03, 0.04, 0.62)
	sb.set_corner_radius_all(16)
	sb.set_border_width_all(1)
	sb.border_color = Color(1, 1, 1, 0.16)
	sb.shadow_size = 6
	sb.shadow_color = Color(0, 0, 0, 0.35)
	return sb

func _circle_style(c: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(16)
	sb.set_border_width_all(2)
	sb.border_color = Color(1, 0.95, 0.6, 0.9)
	return sb

func _card_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.09, 0.14, 0.97)
	sb.set_corner_radius_all(28)
	sb.set_border_width_all(3)
	sb.border_color = Color(1, 0.35, 0.3, 0.7)
	sb.shadow_size = 16
	sb.shadow_color = Color(0, 0, 0, 0.5)
	return sb

func _pill_style(c: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(32)
	return sb

func _find_anim(targets: Array) -> String:
	for target in targets:
		var t: String = String(target).to_lower()
		for a in anim_player.get_animation_list():
			if t in String(a).to_lower():
				return a
	return ""

func _play_run() -> void:
	if run_anim != "":
		anim_player.play(run_anim)

# --- input: swipe to change lane / jump, tap to restart ---------------------
func _unhandled_input(event: InputEvent) -> void:
	if game_over:
		return

	if event is InputEventScreenTouch:
		if event.pressed:
			_touch_start = event.position
			_swiped = false
	elif event is InputEventScreenDrag:
		_evaluate_swipe(event.position)
	# mouse fallback (for testing on desktop)
	elif event is InputEventMouseButton:
		if event.pressed:
			_touch_start = event.position
			_swiped = false
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		_evaluate_swipe(event.position)

func _evaluate_swipe(pos: Vector2) -> void:
	if _swiped:
		return
	var d: Vector2 = pos - _touch_start
	if absf(d.x) > SWIPE_THRESHOLD and absf(d.x) >= absf(d.y):
		_change_lane(1 if d.x > 0.0 else -1)
		_swiped = true
	elif d.y < -SWIPE_THRESHOLD:
		jump_requested = true
		_swiped = true

func _change_lane(dir: int) -> void:
	var old_lane: int = current_lane
	current_lane = clampi(current_lane + dir, 0, LANE_X.size() - 1)
	if old_lane == current_lane:
		return
	var level := get_tree().get_first_node_in_group("level")
	if level and level.has_method("get_segment_distance") and MoveLog.can_log_lane_change():
		MoveLog.log_lane_change(old_lane, current_lane, level.get_segment_distance())

func _restart() -> void:
	get_tree().paused = false
	if SimConstants.API_BASE.is_empty():
		RunSession.restart_run()
		get_tree().reload_current_scene()
		return
	if RunSession.run_ready.is_connected(_on_restart_run_ready):
		RunSession.run_ready.disconnect(_on_restart_run_ready)
	RunSession.run_ready.connect(_on_restart_run_ready, CONNECT_ONE_SHOT)
	RunSession.restart_run()


func _on_restart_run_ready(success: bool, _error_message: String) -> void:
	if success:
		get_tree().reload_current_scene()


func _go_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/menu.tscn")

func _physics_process(delta: float) -> void:
	if game_over:
		return

	if is_dead:
		# Hit a rock: play the death animation and crumple onto the road,
		# THEN show the game-over card (instead of freezing instantly).
		if not dying:
			_start_death()
		return

	# coins-only score — distance does not count
	_refresh_coin_hud()

	# keyboard fallback so it's also playable on desktop
	if Input.is_action_just_pressed("move_left"):
		_change_lane(-1)
	if Input.is_action_just_pressed("move_right"):
		_change_lane(1)
	if Input.is_action_just_pressed("jump"):
		jump_requested = true

	var pos: Vector3 = global_transform.origin

	# slide toward the target lane
	var target_x: float = LANE_X[current_lane]
	pos.x = move_toward(pos.x, target_x, LANE_SWITCH_SPEED * delta)

	# jump only when on the ground
	var on_ground: bool = pos.y <= ground_y + 0.01
	if on_ground and jump_requested:
		vertical_velocity = JUMP_FORCE
		is_jumping = true
		var level := get_tree().get_first_node_in_group("level")
		if level and level.has_method("get_segment_distance"):
			MoveLog.log_jump_start(level.get_segment_distance())
		if jump_anim != "":
			anim_player.play(jump_anim)
	jump_requested = false

	# gravity + vertical move (no floor collider, handled manually)
	vertical_velocity -= GRAVITY * delta
	pos.y += vertical_velocity * delta
	if pos.y <= ground_y:
		pos.y = ground_y
		vertical_velocity = 0.0
		if is_jumping:
			is_jumping = false
			var level := get_tree().get_first_node_in_group("level")
			if level and level.has_method("get_segment_distance"):
				MoveLog.log_jump_land(level.get_segment_distance())
			_play_run()

	global_transform.origin = pos

func _start_death() -> void:
	dying = true
	_finish_done = RunSession.offline_mode
	_finish_data = {}
	if death_anim != "":
		var a := anim_player.get_animation(death_anim)
		if a:
			a.loop_mode = Animation.LOOP_NONE
		anim_player.play(death_anim)
	else:
		# No death clip on this rig: just stop running and topple over on the road.
		anim_player.stop()
		var m := get_node_or_null("player") as Node3D
		if m:
			m.rotate_x(-PI / 2.0)
	# Let the death play out on the road before the game-over card appears.
	await get_tree().create_timer(1.2).timeout
	if not RunSession.offline_mode:
		var waited: float = 0.0
		while not _finish_done and waited < 3.0:
			await get_tree().create_timer(0.1).timeout
			waited += 0.1
	_trigger_game_over()


func _trigger_game_over() -> void:
	game_over = true
	var lines: PackedStringArray = PackedStringArray()
	var display_coins: int = coin_count
	if _finish_data.has("final_coins"):
		display_coins = int(_finish_data.get("final_coins", coin_count))
	lines.append("Coins %d" % display_coins)
	if _finish_data.has("rank") or _finish_data.has("best_coins"):
		var rank: int = int(_finish_data.get("rank", 0))
		var best: int = int(_finish_data.get("best_coins", AuthSession.best_coins))
		if rank > 0:
			lines.append("Rank #%d  ·  Best %d" % [rank, best])
		else:
			lines.append("Best %d coins" % best)
	result_label.text = "\n".join(lines)
	overlay.visible = true
	overlay.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(overlay, "modulate:a", 1.0, 0.35)
	get_tree().paused = true

func _on_collision_area_entered(area):
	var parent = area.get_parent()
	if parent.is_in_group("coins"):
		audio_player.play()
		coin_count += 1
		_refresh_coin_hud()
		var level := get_tree().get_first_node_in_group("level")
		if level and level.has_method("get_segment_distance"):
			var oid: int = int(parent.get_meta("object_id", -1))
			var lane: int = int(parent.get_meta("spawn_lane", current_lane))
			var dist: float = float(parent.get_meta("map_distance", level.get_segment_distance()))
			MoveLog.log_coin(oid, lane, dist)
		# little pop on the counter for feedback
		coin_label.pivot_offset = coin_label.size * 0.5
		var t := create_tween()
		t.tween_property(coin_label, "scale", Vector2(1.5, 1.5), 0.08)
		t.tween_property(coin_label, "scale", Vector2(1, 1), 0.12)
		parent.queue_free()
