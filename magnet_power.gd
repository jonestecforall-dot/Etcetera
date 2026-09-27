extends Node

# --- POWER-UP CONFIGURATION ---
@export var shell_name: String = "Magnet Pull"

# --- MAGNET SETTINGS ---
@export_group("Magnet Settings")
@export var attract_radius: float = 120.0          # How close the player needs to be to snap onto metal
@export var attract_force: float = 800.0           # How hard the magnet pulls the player toward the metal
@export var stick_distance: float = 12.0           # When this close, player "sticks" to the wall
@export var stick_gravity: float = 0.0             # Gravity while stuck (0 = fully frozen)
@export var climb_speed: float = 80.0              # Up/down speed while climbing metal
@export var metal_group: String = "metal"          # Group name for metal objects in your levels

# --- INTERNAL STATE ---
var _is_active: bool = false
var _player_ref: CharacterBody2D = null
var _is_stuck_to_metal: bool = false
var _current_metal_normal: Vector2 = Vector2.ZERO
var _metal_collider: Node2D = null

func _ready() -> void:
	_is_active = false
	set_process(false)
	set_physics_process(false)

# --- APPLY: Called when the shell is collected ---
func apply(player: Node) -> void:
	if not player is CharacterBody2D:
		print("⚠️ Magnet power-up requires a CharacterBody2D player!")
		return

	_player_ref = player
	_is_active = true
	set_physics_process(true)

	print("🧲 Magnet power-up applied!")

# --- REMOVE: Called when the shell is swapped out ---
func remove(player: Node) -> void:
	_is_active = false
	_is_stuck_to_metal = false
	_current_metal_normal = Vector2.ZERO
	_metal_collider = null
	set_physics_process(false)

	if player and "is_magnet_stuck" in player:
		player.is_magnet_stuck = false

	print("🧲 Magnet power-up removed.")

# --- MAIN MAGNET LOGIC ---
func _physics_process(delta: float) -> void:
	if not _is_active or _player_ref == null:
		return

	# --- STEP 1: Look for nearby metal objects ---
	var closest_metal: Node2D = null
	var closest_dist: float = attract_radius

	for metal in _player_ref.get_tree().get_nodes_in_group(metal_group):
		if not metal is Node2D:
			continue

		var dist: float = _player_ref.global_position.distance_to(metal.global_position)
		if dist < closest_dist:
			closest_dist = dist
			closest_metal = metal

	# --- STEP 2: If we found metal and aren't already stuck, attract to it ---
	if closest_metal and not _is_stuck_to_metal:
		var direction: Vector2 = (closest_metal.global_position - _player_ref.global_position).normalized()
		_player_ref.velocity += direction * attract_force * delta

		# Face the metal
		if "facing_direction" in _player_ref:
			_player_ref.facing_direction = direction

		# Close enough? Snap onto it
		if closest_dist <= stick_distance + 20.0:
			_snap_to_metal(closest_metal)

	# --- STEP 3: If currently stuck to metal, allow climbing up/down ---
	if _is_stuck_to_metal and _metal_collider:
		_handle_climbing(delta)

# --- SNAP ONTO THE METAL OBJECT ---
func _snap_to_metal(metal: Node2D) -> void:
	_is_stuck_to_metal = true
	_metal_collider = metal

	# Determine which side the player is on
	var dir_to_metal: Vector2 = (metal.global_position - _player_ref.global_position).normalized()
	_current_metal_normal = -dir_to_metal  # Normal points away from the metal

	# Freeze physics while stuck
	_player_ref.velocity = Vector2.ZERO

	# Let the player script know
	if "is_magnet_stuck" in _player_ref:
		_player_ref.is_magnet_stuck = true

	print("🧲 Stuck to metal!")

# --- CLIMB UP AND DOWN WHILE STUCK ---
func _handle_climbing(delta: float) -> void:
	# --- Stick to the surface (prevent falling away) ---
	_player_ref.velocity = Vector2.ZERO

	# --- Player input for climbing ---
	var input_dir: Vector2 = Vector2.ZERO
	if "ui_input_direction" in _player_ref:
		input_dir = _player_ref.ui_input_direction
	elif Input.is_action_pressed("ui_up"):
		input_dir.y = -1.0
	elif Input.is_action_pressed("ui_down"):
		input_dir.y = 1.0

	# --- Climb perpendicular to the metal's normal ---
	# The normal points away from the metal, so the tangent is perpendicular to it
	var tangent: Vector2 = Vector2(-_current_metal_normal.y, _current_metal_normal.x)

	# Let the player climb using the input direction
	if input_dir.length() > 0.1:
		var climb_move: Vector2 = tangent * input_dir.dot(tangent) * climb_speed * delta
		_player_ref.global_position += climb_move

	# --- Jump off the metal ---
	var jump_buffer := 0.0
	if "jump_buffer_timer" in _player_ref:
		jump_buffer = _player_ref.jump_buffer_timer
	elif Input.is_action_just_pressed("ui_accept"):
		jump_buffer = 1.0

	if jump_buffer > 0.0:
		_detach_from_metal()

# --- DETACH FROM METAL (called when jumping) ---
func _detach_from_metal() -> void:
	if not _is_stuck_to_metal:
		return

	_is_stuck_to_metal = false
	_metal_collider = null

	# Push the player away from the metal
	var jump_dir: Vector2 = _current_metal_normal
	if "jump_force" in _player_ref:
		_player_ref.velocity.y = _player_ref.jump_force
	_player_ref.velocity += jump_dir * 200.0  # Small outward push

	# Let the player script know
	if "is_magnet_stuck" in _player_ref:
		_player_ref.is_magnet_stuck = false

	print("🧲 Detached from metal!")
