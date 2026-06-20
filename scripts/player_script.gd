extends CharacterBody3D

@onready var audio_player: AudioStreamPlayer3D = $AudioStreamPlayer3D
@onready var anim_player: AnimationPlayer = $player/AnimationPlayer

const MOVE_SPEED: float = 4.0
const JUMP_FORCE: float = 9.0
const GRAVITY: float = 22.0
var starting_point: Vector3 = Vector3.ZERO
var ground_y: float = 0.0
var vertical_velocity: float = 0.0

var run_anim: String = ""
var jump_anim: String = ""
var is_jumping: bool = false

var is_dead: bool = false
var game_over: bool = false
var coin_count: int = 0

var coin_label: Label
var overlay: Control

func _ready() -> void:
	# keep running while the tree is paused so we can detect the restart key
	process_mode = Node.PROCESS_MODE_ALWAYS

	# rocks look for an area in this group to know they hit the player
	$collision_area.add_to_group("player_skeleton")

	_setup_hud()

	starting_point = global_transform.origin
	ground_y = global_transform.origin.y
	run_anim = _find_anim("Man_Run")
	jump_anim = _find_anim("Man_Jump")
	if run_anim != "":
		anim_player.get_animation(run_anim).loop_mode = Animation.LOOP_LINEAR
	_play_run()

func _setup_hud() -> void:
	# Put the HUD on a CanvasLayer so it always fills the screen,
	# regardless of the 3D player it's attached to.
	var layer := CanvasLayer.new()
	add_child(layer)

	coin_label = Label.new()
	layer.add_child(coin_label)
	coin_label.add_theme_font_size_override("font_size", 40)
	coin_label.add_theme_color_override("font_color", Color(1, 0.9, 0.2))
	coin_label.add_theme_color_override("font_outline_color", Color.BLACK)
	coin_label.add_theme_constant_override("outline_size", 6)
	coin_label.position = Vector2(24, 16)
	coin_label.text = "Coins: 0"

	# full-screen game-over overlay (dark background + centered text)
	overlay = Control.new()
	layer.add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.visible = false

	var bg := ColorRect.new()
	overlay.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0, 0, 0, 0.6)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var gameover_label := Label.new()
	overlay.add_child(gameover_label)
	gameover_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	gameover_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gameover_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	gameover_label.add_theme_font_size_override("font_size", 64)
	gameover_label.add_theme_color_override("font_color", Color(1, 0.25, 0.2))
	gameover_label.add_theme_color_override("font_outline_color", Color.BLACK)
	gameover_label.add_theme_constant_override("outline_size", 8)
	gameover_label.text = "GAME OVER\n\nPress SPACE to restart"

func _find_anim(target: String) -> String:
	for a in anim_player.get_animation_list():
		if target.to_lower() in String(a).to_lower():
			return a
	return ""

func _play_run() -> void:
	if run_anim != "":
		anim_player.play(run_anim)

func _physics_process(delta) -> void:
	if game_over:
		if Input.is_action_just_pressed("jump"):
			get_tree().paused = false
			get_tree().reload_current_scene()
		return

	if is_dead:
		_trigger_game_over()
		return

	var pos: Vector3 = global_transform.origin

	# left / right between lanes
	var dir_x: float = 0.0
	if Input.is_action_pressed("move_left"):
		dir_x -= 1.0
	if Input.is_action_pressed("move_right"):
		dir_x += 1.0
	pos.x += dir_x * MOVE_SPEED * delta
	pos.x = clamp(pos.x, starting_point.x - 3.0, starting_point.x + 3.0)

	# start a jump only when on the ground
	var on_ground: bool = pos.y <= ground_y + 0.01
	if on_ground and Input.is_action_just_pressed("jump"):
		vertical_velocity = JUMP_FORCE
		is_jumping = true
		if jump_anim != "":
			anim_player.play(jump_anim)

	# apply gravity and move vertically (no floor collider, so handle it here)
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
	overlay.visible = true
	if run_anim != "":
		anim_player.stop()
	get_tree().paused = true

func _on_collision_area_entered(area):
	var parent = area.get_parent()
	if parent.is_in_group("coins"):
		audio_player.play()
		coin_count += 1
		coin_label.text = "Coins: " + str(coin_count)
		parent.queue_free()
