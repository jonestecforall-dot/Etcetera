extends Node

# --- POWER-UP CONFIGURATION ---
@export var shell_name: String = "Anvil Smash"

# --- ANVIL SETTINGS ---
@export_group("Anvil Settings")
@export var slam_gravity_multiplier: float = 3.0     # Extra gravity while falling (makes it feel heavy)
@export var slam_damage: int = 3                     # Damage dealt to enemies on impact
@export var slam_radius: float = 40.0                # Radius of the ground-impact shockwave
@export var break_floors: bool = true                # Can the anvil smash breakable floors?
@export var floor_break_group: String = "breakable_floor"  # Group for breakable tiles
@export var camera_shake_strength: float = 8.0       # Screen shake on impact
@export var impact_effect_scene: PackedScene         # Optional: particle/dust effect on slam

# --- INTERNAL STATE ---
var _is_active: bool = false
var _player_ref: CharacterBody2D = null
var _was_in_air: bool = false
var _has_slammed_this_fall: bool = false

func _ready() -> void:
	_is_active = false
	set_process(false)
	set_physics_process(false)

# --- APPLY: Called when the shell is collected ---
func apply(player: Node) -> void:
	if not player is CharacterBody2D:
		print("⚠️ Anvil power-up requires a CharacterBody2D player!")
		return

	_player_ref = player
	_is_active = true
	set_physics_process(true)

	print("⚒️ Anvil power-up applied!")

# --- REMOVE: Called when the shell is swapped out ---
func remove(player: Node) -> void:
	_is_active = false
	set_physics_process(false)

	print("⚒️ Anvil power-up removed.")

# --- MAIN ANVIL LOGIC ---
func _physics_process(delta: float) -> void:
	if not _is_active or _player_ref == null:
		return

	var on_floor: bool = _player_ref.is_on_floor()

	# --- STEP 1: Detect entering the air ---
	if not on_floor and not _was_in_air:
		_was_in_air = true
		_has_slammed_this_fall = false

	# --- STEP 2: While falling, increase gravity for a heavy feel ---
	if not on_floor and _player_ref.velocity.y > 0:
		_player_ref.velocity.y += _player_ref.gravity * (slam_gravity_multiplier - 1.0) * delta

	# --- STEP 3: Detect the landing impact ---
	if on_floor and _was_in_air and not _has_slammed_this_fall:
		_has_slammed_this_fall = true
		_do_slam_impact()

	# --- STEP 4: Reset air-tracking when back on floor ---
	if on_floor:
		_was_in_air = false

# --- THE SLAM IMPACT (called the moment you land) ---
func _do_slam_impact() -> void:
	print("⚒️ SLAM!")

	# 1. Damage nearby enemies
	_damage_nearby_enemies()

	# 2. Break floors below the player
	if break_floors:
		_break_floors_below()

	# 3. Spawn visual effect
	_spawn_impact_effect()

	# 4. Camera shake
	_shake_camera()

# --- DAMAGE ENEMIES IN A RADIUS AROUND THE PLAYER ---
func _damage_nearby_enemies() -> void:
	var enemies := _player_ref.get_tree().get_nodes_in_group("enemies")
	for enemy in enemies:
		if not enemy is Node2D:
			continue

		var dist: float = _player_ref.global_position.distance_to(enemy.global_position)
		if dist <= slam_radius:
			if enemy.has_method("take_hit"):
				enemy.take_hit("slam", _player_ref.global_position)
			elif enemy.has_method("take_damage"):
				enemy.take_damage(slam_damage)

# --- BREAK BREAKABLE FLOORS DIRECTLY BELOW ---
func _break_floors_below() -> void:
	# Use the player's collision shape info if available, otherwise a small box check
	var check_pos: Vector2 = _player_ref.global_position + Vector2(0, 20)

	var floors := _player_ref.get_tree().get_nodes_in_group(floor_break_group)
	for floor in floors:
		if not floor is Node2D:
			continue

		var dist: float = check_pos.distance_to(floor.global_position)
		if dist <= slam_radius:
			if floor.has_method("break_floor"):
				floor.break_floor()
			elif floor.has_method("destroy"):
				floor.destroy()
			else:
				floor.queue_free()

# --- SPAWN DUST / IMPACT EFFECT ---
func _spawn_impact_effect() -> void:
	if impact_effect_scene == null:
		return

	var effect = impact_effect_scene.instantiate()
	if effect is Node2D:
		_player_ref.get_tree().current_scene.add_child(effect)
		effect.global_position = _player_ref.global_position + Vector2(0, 16)

# --- SHAKE THE CAMERA (if the player has one) ---
func _shake_camera() -> void:
	# Look for a camera on the player or the current scene
	var camera: Camera2D = null

	if _player_ref.has_node("Camera2D"):
		camera = _player_ref.get_node("Camera2D")
	else:
		for child in _player_ref.get_children():
			if child is Camera2D:
				camera = child
				break

	if camera == null:
		return

	# Simple shake: offset the camera briefly using a tween
	var original_offset: Vector2 = camera.offset
	var shake_vector: Vector2 = Vector2(
		randf_range(-camera_shake_strength, camera_shake_strength),
		randf_range(-camera_shake_strength, camera_shake_strength)
	)

	var tween = _player_ref.create_tween()
	tween.tween_property(camera, "offset", shake_vector, 0.05)
	tween.tween_property(camera, "offset", original_offset, 0.15)
