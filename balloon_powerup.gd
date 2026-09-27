extends Node

# --- POWER-UP CONFIGURATION ---
@export var shell_name: String = "Balloon Float"

# --- BALLOON SETTINGS ---
@export_group("Balloon Settings")
@export var fall_speed_multiplier: float = 0.35     # 1.0 = normal fall, 0.35 = slow float (lower = slower)
@export var max_fall_speed: float = 120.0           # Cap on fall speed while balloon is active
@export var horizontal_control_bonus: float = 1.15  # Slight extra horizontal control while floating
@export var drift_amount: float = 8.0               # Gentle side-to-side sway while floating
@export var drift_speed: float = 2.0                # How fast the sway cycles

# --- INTERNAL STATE ---
var _is_active: bool = false
var _player_ref: CharacterBody2D = null
var _drift_timer: float = 0.0

func _ready() -> void:
	_is_active = false
	set_process(false)
	set_physics_process(false)

# --- APPLY: Called when the shell is collected ---
func apply(player: Node) -> void:
	if not player is CharacterBody2D:
		print("⚠️ Balloon power-up requires a CharacterBody2D player!")
		return

	_player_ref = player
	_is_active = true
	_drift_timer = 0.0
	set_physics_process(true)

	print("🎈 Balloon power-up applied!")

# --- REMOVE: Called when the shell is swapped out ---
func remove(player: Node) -> void:
	_is_active = false
	set_physics_process(false)

	print("🎈 Balloon power-up removed.")

# --- MAIN BALLOON LOGIC ---
func _physics_process(delta: float) -> void:
	if not _is_active or _player_ref == null:
		return

	# Only apply balloon physics when falling (not jumping up)
	if _player_ref.is_on_floor():
		_drift_timer = 0.0
		return

	if _player_ref.velocity.y <= 0:
		# Going up — no balloon effect yet
		return

	# --- STEP 1: Slow down the fall ---
	# Cancel out most of the gravity for this frame by counteracting it,
	# then apply a reduced gravity.
	var gravity_value: float = _player_ref.gravity

	# Subtract normal gravity (added in the player's own _physics_process),
	# then re-apply it at the reduced rate.
	_player_ref.velocity.y -= gravity_value * delta  # undo full gravity
	_player_ref.velocity.y += gravity_value * fall_speed_multiplier * delta  # apply reduced gravity

	# --- STEP 2: Cap the fall speed ---
	if _player_ref.velocity.y > max_fall_speed:
		_player_ref.velocity.y = max_fall_speed

	# --- STEP 3: Gentle horizontal drift for the balloon feel ---
	_drift_timer += delta * drift_speed
	var drift: float = sin(_drift_timer) * drift_amount * delta
	_player_ref.velocity.x += drift

	# --- STEP 4: Bonus horizontal control while floating ---
	# (Optional: makes the player feel more agile while drifting down)
	if horizontal_control_bonus != 1.0:
		_player_ref.velocity.x *= horizontal_control_bonus
