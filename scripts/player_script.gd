extends CharacterBody3D

@onready var audio_player: AudioStreamPlayer3D = $AudioStreamPlayer3D
@onready var anim_player: AnimationPlayer = $player/AnimationPlayer

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
var is_jumping: bool = false

var is_dead: bool = false
var game_over: bool = false
var coin_count: int = 0

var score: float = 0.0

var coin_label: Label
var score_label: Label
var overlay: Control
var result_label: Label
var hint_label: Label

# swipe tracking
var _touch_start: Vector2 = Vector2.ZERO
var _swiped: bool = false

func _ready() -> void:
	# keep running while the tree is paused so we can detect the restart tap
	process_mode = Node.PROCESS_MODE_ALWAYS

	# rocks look for an area in this group to know they hit the player
	$collision_area.add_to_group("player_skeleton")

	_detail_character()
	_setup_hud()

	ground_y = global_transform.origin.y
	run_anim = _find_anim("Man_Run")
	jump_anim = _find_anim("Man_Jump")
	if run_anim != "":
		anim_player.get_animation(run_anim).loop_mode = Animation.LOOP_LINEAR
	_play_run()

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
	score_label.text = "SCORE 0"

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
	hint_label.text = "Swipe  <  >  to change lane     Swipe  ^  to jump"
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
	card.offset_top = -160.0
	card.offset_bottom = 160.0
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

	var pill := Panel.new()
	card.add_child(pill)
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.position = Vector2(90, 218)
	pill.size = Vector2(260, 64)
	pill.add_theme_stylebox_override("panel", _pill_style(Color(0.18, 0.72, 0.42)))

	var pill_label := Label.new()
	pill.add_child(pill_label)
	pill_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pill_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pill_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pill_label.add_theme_font_size_override("font_size", 28)
	pill_label.add_theme_color_override("font_color", Color.WHITE)
	pill_label.text = "TAP TO RESTART"

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

# Give the character distinct, detailed colours per body part.
func _detail_character() -> void:
	var mi := _find_char_mesh(self)
	if mi == null or mi.mesh == null:
		return
	var palette := {
		"Hair": Color(0.04, 0.04, 0.05),   # near-black hair
		"Skin": Color(0.83, 0.62, 0.47),   # warm skin tone
		"Eyes": Color(0.06, 0.06, 0.08),   # dark eyes
		"Shirt": Color(0.85, 0.27, 0.16),  # bright red/orange jersey
		"Pants": Color(0.13, 0.17, 0.34),  # denim blue trousers
	}
	for i in mi.mesh.get_surface_count():
		var nm := String(mi.mesh.surface_get_name(i))
		var col: Color = palette.get(nm, Color(0.7, 0.7, 0.7))
		var sm := StandardMaterial3D.new()
		sm.albedo_color = col
		sm.roughness = 0.85
		sm.metallic = 0.0
		if nm == "Shirt":
			# subtle two-tone sheen so the top reads as a sporty fabric
			sm.roughness = 0.6
			sm.rim_enabled = true
			sm.rim = 0.4
		mi.set_surface_override_material(i, sm)

func _find_char_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh != null and mi.mesh.get_surface_count() >= 4:
			return mi
	for c in n.get_children():
		var r := _find_char_mesh(c)
		if r != null:
			return r
	return null

func _find_anim(target: String) -> String:
	for a in anim_player.get_animation_list():
		if target.to_lower() in String(a).to_lower():
			return a
	return ""

func _play_run() -> void:
	if run_anim != "":
		anim_player.play(run_anim)

# --- input: swipe to change lane / jump, tap to restart ---------------------
func _unhandled_input(event: InputEvent) -> void:
	if game_over:
		if (event is InputEventScreenTouch and event.pressed) \
		or (event is InputEventMouseButton and event.pressed):
			_restart()
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
	current_lane = clampi(current_lane + dir, 0, LANE_X.size() - 1)

func _restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()

func _physics_process(delta: float) -> void:
	if game_over:
		return

	if is_dead:
		_trigger_game_over()
		return

	# distance score keeps climbing while you run
	score += delta * 12.0
	score_label.text = "SCORE " + str(int(score))

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
			_play_run()

	global_transform.origin = pos

func _trigger_game_over() -> void:
	game_over = true
	result_label.text = "Score %d     Coins %d" % [int(score), coin_count]
	overlay.visible = true
	overlay.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(overlay, "modulate:a", 1.0, 0.35)
	if run_anim != "":
		anim_player.stop()
	get_tree().paused = true

func _on_collision_area_entered(area):
	var parent = area.get_parent()
	if parent.is_in_group("coins"):
		audio_player.play()
		coin_count += 1
		coin_label.text = str(coin_count)
		# little pop on the counter for feedback
		coin_label.pivot_offset = coin_label.size * 0.5
		var t := create_tween()
		t.tween_property(coin_label, "scale", Vector2(1.5, 1.5), 0.08)
		t.tween_property(coin_label, "scale", Vector2(1, 1), 0.12)
		parent.queue_free()
