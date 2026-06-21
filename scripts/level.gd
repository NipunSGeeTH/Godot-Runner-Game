extends Node

@onready var player: CharacterBody3D = $player_body
@onready var spawn_timer: Timer = $spawn_timer
@onready var spawn_env_timer: Timer = $spawn_env_timer
@onready var spawn_obstacle_timer: Timer = $spawn_obstacle_timer

@onready var coin: PackedScene = preload("res://scenes/coin.tscn")
@onready var fence: PackedScene = preload("res://models/cartoon-assets/fence.tscn")

@onready var line_mat: ShaderMaterial = preload("res://models/linemat.tres")

# moves a spawned prop toward the player and frees it once it passes by
@onready var env_move_script = preload("res://scripts/env_script.gd")

# Stylized CC0 nature kit (Quaternius). Each .glb is a row of variants, so at
# load time we split them into individual reusable mesh "templates".
const NATURE_TREES: Array = [
	"res://models/nature/Trees.glb",
	"res://models/nature/PineTrees.glb",
	"res://models/nature/BirchTrees.glb",
	"res://models/nature/MapleTrees.glb",
]
const NATURE_SHRUBS: Array = [
	"res://models/nature/Bushes.glb",
	"res://models/nature/FlowerBushes.glb",
]
const NATURE_ROCKS: Array = [
	"res://models/nature/Rocks.glb",
]

var tree_templates: Array = []
var shrub_templates: Array = []
var rock_templates: Array = []

# avoid showing the same model twice in a row so repetition isn't obvious
var _last_tree: int = -1
var _last_rock: int = -1

# how far the dashed lane lines have scrolled; advanced only while running
const LANE_SCROLL_SPEED: float = 15.0
var line_scroll: float = 0.0

var startz: float = -50.0
var road_spawnx: Array = [-2, 0, 2]

const FENCE_COUNT: int = 30
var fences: Array = []
var fencez: float = 0.0


func _ready():
	randomize()
	_load_nature()

	var z = 5
	for i in FENCE_COUNT:
		var fence_inst = fence.instantiate()
		fence_inst.connect("body_entered", Callable(self, "fence_area_body_entered"))
		fences.append(fence_inst)
		add_child(fence_inst)
		fence_inst.global_transform.origin = Vector3(0, 0, z)
		z -= 1.5
		fencez = z


# Split each nature .glb (a row of 3-5 variants) into single mesh templates we
# can cheaply duplicate at spawn time.
func _load_nature() -> void:
	_collect(NATURE_TREES, tree_templates)
	_collect(NATURE_SHRUBS, shrub_templates)
	_collect(NATURE_ROCKS, rock_templates)


func _collect(paths: Array, into: Array) -> void:
	for p in paths:
		if not ResourceLoader.exists(p):
			continue
		var inst: Node = (load(p) as PackedScene).instantiate()
		# add to the tree so global_transform (which bakes the import's Z-up to
		# Y-up rotation + unit scale) is valid for each variant
		add_child(inst)
		var meshes: Array = []
		_gather_meshes(inst, meshes)
		for m in meshes:
			var tpl := MeshInstance3D.new()
			tpl.mesh = m.mesh
			for si in m.get_surface_override_material_count():
				var om = m.get_surface_override_material(si)
				if om:
					tpl.set_surface_override_material(si, om)
			# bake full orientation/scale; recenter (variants are spread along X)
			var gt: Transform3D = m.global_transform
			gt.origin = Vector3.ZERO
			tpl.transform = gt
			into.append(tpl)
		remove_child(inst)
		inst.free()


func _gather_meshes(n: Node, into: Array) -> void:
	if n is MeshInstance3D:
		into.append(n)
	for c in n.get_children():
		_gather_meshes(c, into)


# Wrap a template in a mover node so it slides toward the player and frees itself.
func _make_mover(template: MeshInstance3D) -> Node3D:
	var mover := Node3D.new()
	mover.set_script(env_move_script)
	mover.add_child(template.duplicate())
	return mover


func fence_area_body_entered():
	var first_fence = fences.front()
	first_fence.global_transform.origin = Vector3(0, 0, fencez)
	fences.pop_front()
	fences.append(first_fence)


func _on_spawn_timer_timeout():
	spawn_timer.wait_time = randf_range(1.2, 2.2)
	# A clean trail of coins down a single lane (classic runner pickup line).
	var lane_idx: int = randi() % 3
	var count: int = 4 + (randi() % 5)  # 4..8 coins in a row
	for i in count:
		var coin_inst: MeshInstance3D = coin.instantiate()
		add_child(coin_inst)
		coin_inst.global_transform.origin = Vector3(
			road_spawnx[lane_idx],
			1.0,
			startz + i * 2.5
		)


func _on_spawn_env_timer_timeout():
	# trees on both shoulders, plus the occasional bush for layered depth
	_spawn_tree(1)
	_spawn_tree(-1)
	if randf() < 0.6:
		_spawn_shrub(1)
	if randf() < 0.6:
		_spawn_shrub(-1)
	spawn_env_timer.wait_time = randf_range(0.45, 0.8)


func _spawn_tree(dir: int) -> void:
	if tree_templates.is_empty():
		return
	# pick a different tree than last time
	var idx: int = randi() % tree_templates.size()
	if tree_templates.size() > 1 and idx == _last_tree:
		idx = (idx + 1) % tree_templates.size()
	_last_tree = idx

	var mover := _make_mover(tree_templates[idx])
	add_child(mover)
	var s: float = randf_range(0.85, 1.5)
	mover.global_transform.origin = Vector3(
		dir * randf_range(7.0, 18.0),
		0.0,
		startz + randf_range(-4.0, 4.0)
	)
	mover.rotation.y = randf() * TAU
	mover.scale = Vector3(s, s, s)


func _spawn_shrub(dir: int) -> void:
	if shrub_templates.is_empty():
		return
	var mover := _make_mover(shrub_templates[randi() % shrub_templates.size()])
	add_child(mover)
	var s: float = randf_range(0.7, 1.3)
	mover.global_transform.origin = Vector3(
		dir * randf_range(4.5, 8.5),
		0.0,
		startz + randf_range(-3.0, 3.0)
	)
	mover.rotation.y = randf() * TAU
	mover.scale = Vector3(s, s, s)


func _on_spawn_obstacle_timer_timeout():
	spawn_obstacle_timer.wait_time = randf_range(1.6, 2.8)
	if rock_templates.is_empty():
		return
	# Block 1 or 2 of the 3 lanes — NEVER all three, so there is always an
	# escape lane (you can also jump a single rock). This keeps the game fair.
	var lanes: Array = [0, 1, 2]
	lanes.shuffle()
	var block_count: int = 1 + (randi() % 2)  # 1 or 2
	for i in block_count:
		_spawn_rock(lanes[i])


func _spawn_rock(lane_idx: int) -> void:
	var idx: int = randi() % rock_templates.size()
	if rock_templates.size() > 1 and idx == _last_rock:
		idx = (idx + 1) % rock_templates.size()
	_last_rock = idx

	var mover := _make_mover(rock_templates[idx])
	mover.add_to_group("rocks")
	add_child(mover)
	mover.global_transform.origin = Vector3(road_spawnx[lane_idx], 0.0, startz)
	mover.rotation.y = randf() * TAU
	var rs: float = randf_range(1.5, 2.0)
	mover.scale = Vector3(rs, rs, rs)


# Deterministic, lane-aligned collision: you only die if a rock is in YOUR
# lane, has reached you in Z, and you haven't jumped above it.
const HIT_Z: float = 0.9
const HIT_X: float = 0.9
const JUMP_CLEAR_Y: float = 0.8


func _process(delta: float) -> void:
	# flow the dashed lane lines toward the player in lock-step with obstacles
	line_scroll += LANE_SCROLL_SPEED * delta
	line_mat.set_shader_parameter("scroll_offset", line_scroll)


func _physics_process(_delta: float) -> void:
	if player == null or player.is_dead or player.game_over:
		return
	var pp: Vector3 = player.global_transform.origin
	for r in get_tree().get_nodes_in_group("rocks"):
		if not is_instance_valid(r):
			continue
		var rp: Vector3 = r.global_transform.origin
		if abs(rp.z - pp.z) < HIT_Z and abs(rp.x - pp.x) < HIT_X and pp.y < JUMP_CLEAR_Y:
			player.is_dead = true
			return
