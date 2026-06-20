extends Node

# for coins
@onready var player: CharacterBody3D = $player_body
@onready var spawn_timer: Timer = $spawn_timer
@onready var spawn_env_timer: Timer = $spawn_env_timer
@onready var spawn_obstacle_timer: Timer = $spawn_obstacle_timer

@onready var coin: PackedScene = preload("res://scenes/coin.tscn")

@onready var tree1: PackedScene = preload("res://models/cartoon-assets/tree1.tscn")
@onready var tree2: PackedScene = preload("res://models/cartoon-assets/tree2.tscn")

@onready var fence: PackedScene = preload("res://models/cartoon-assets/fence.tscn")
@onready var rock:  PackedScene = preload("res://models/cartoon-assets/rock.tscn")

@onready var tree_mat: ShaderMaterial = preload("res://models/treemat.tres")
@onready var rock_mat: Material = preload("res://models/rockmat.tres")

# a spread of natural greens so the trees aren't all identical
var tree_greens: Array = [
	Vector4(0.05, 0.24, 0.09, 1),   # medium green
	Vector4(0.03, 0.15, 0.05, 1),   # deep forest
	Vector4(0.09, 0.28, 0.07, 1),   # sunny yellow-green
	Vector4(0.04, 0.2, 0.12, 1),    # cool blue-green
	Vector4(0.12, 0.26, 0.06, 1),   # olive
]

var startz: float = -50.0
var road_spawnx: Array = [-2, 0, 2]
var tree_startx: Array = [10, -10]

@onready var env_assets: Array = [tree1, tree2]

const FENCE_COUNT: int = 30
# example of using object pooling for fences
var fences: Array = []
var fencez: float = 0.0


func _ready():
	var x = 0
	var y = 0
	var z = 5
	for i in FENCE_COUNT:
		var fence_inst = fence.instantiate()
		fence_inst.connect("body_entered", Callable(self, "fence_area_body_entered"))
		fences.append(fence_inst)
		add_child(fence_inst)
		fence_inst.global_transform.origin = Vector3(
			x, y, z
		)
		z -= 1.5
		fencez = z


func fence_area_body_entered():
	var first_fence = fences.front()
	first_fence.global_transform.origin = Vector3(
		0, 0, fencez
	)
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
	randomize()
	# spawn trees on both sides for a fuller, denser environment
	_spawn_tree(1)
	_spawn_tree(-1)
	# occasionally a second, closer-in tree for layered depth
	if randf() < 0.5:
		_spawn_tree(1)
	if randf() < 0.5:
		_spawn_tree(-1)
	spawn_env_timer.wait_time = randf_range(0.45, 0.8)


func _spawn_tree(dir: int) -> void:
	var asset = env_assets[randi() % env_assets.size()].instantiate()
	add_child(asset)
	var mat := tree_mat.duplicate() as ShaderMaterial
	mat.set_shader_parameter("color", tree_greens[randi() % tree_greens.size()])
	_tint(asset, mat)
	var x: float = dir * randf_range(7.0, 16.0)
	asset.global_transform.origin = Vector3(
		x,
		0,
		startz + randf_range(-3.0, 3.0)
	)
	asset.rotation_degrees.y = randf_range(0, 360)
	var s: float = randf_range(0.8, 1.6)
	asset.scale = Vector3(s, s, s)


# recolour every mesh under a spawned asset by overriding its surface material
func _tint(node: Node, mat: Material) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			for i in mi.mesh.get_surface_count():
				mi.set_surface_override_material(i, mat)
	for c in node.get_children():
		_tint(c, mat)


func _on_spawn_obstacle_timer_timeout():
	spawn_obstacle_timer.wait_time = randf_range(1.6, 2.8)
	# Block 1 or 2 of the 3 lanes — NEVER all three, so there is always an
	# escape lane (you can also jump a single rock). This keeps the game fair.
	var lanes: Array = [0, 1, 2]
	lanes.shuffle()
	var block_count: int = 1 + (randi() % 2)  # 1 or 2
	for i in block_count:
		var lane_idx: int = lanes[i]
		var rock_inst = rock.instantiate()
		add_child(rock_inst)
		rock_inst.add_to_group("rocks")
		_tint(rock_inst, rock_mat)
		rock_inst.global_transform.origin = Vector3(
			road_spawnx[lane_idx],
			0.0,
			startz
		)
		rock_inst.rotation_degrees.y = randf_range(0, 360)
		var rs: float = randf_range(1.3, 1.6)
		rock_inst.scale = Vector3(rs, rs, rs)


func on_player_entered_rock():
	player.is_dead = true


# Deterministic, lane-aligned collision: you only die if a rock is in YOUR
# lane, has reached you in Z, and you haven't jumped above it.
const HIT_Z: float = 0.9      # how close in depth counts as a hit
const HIT_X: float = 0.9      # must be essentially the same lane (lanes are 2 apart)
const JUMP_CLEAR_Y: float = 0.8   # player origin.y above this = cleared the rock

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
