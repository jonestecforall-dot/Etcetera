extends Node

# --- POWER-UP CONFIGURATION ---
# This name MUST match one of the entries in the parent shell's `shell_names` array.
# When the parent shell is collected, it checks each child's `shell_name`
# and only calls apply() on the one that matches the current shell.
@export var shell_name: String = "Bubble Deep"

# --- OPTIONAL: PASSIVE LOOP ---
# If your power-up needs to do something every frame while active,
# set this to true and write logic in _process().
@export var is_passive: bool = false

# --- INTERNAL STATE ---
var _is_active: bool = false
var _player_ref: Node = null

func _ready() -> void:
	# Power-ups start inactive until the shell that carries them is collected.
	_is_active = false
	set_process(is_passive)

# --- APPLY: Called by the parent shell when it's collected by the player ---
# This is where the power-up takes effect on the player.
func apply(player: Node) -> void:
	_player_ref = player
	_is_active = true
	
	match shell_name:
		"Bubble Deep":
			player.can_breathe_underwater = true
		# ... others
	
	print("🦀 Power-up applied: ", shell_name, " | player.can_breathe_underwater=", player.can_breathe_underwater)

# --- REMOVE: Optional. Call this to remove the power-up (e.g., when the player swaps shells) ---
func remove(player: Node) -> void:
	_is_active = false

	# ============================
	#   🧹 CLEANUP LOGIC GOES HERE
	# ============================
	# Reset the same flags you set in apply()
	if shell_name == "Bubble":
		if "can_breathe_underwater" in player:
			player.can_breathe_underwater = false
	elif shell_name == "Magnet":
		if "can_climb_metal" in player:
			player.can_climb_metal = false
	elif shell_name == "Anvil":
		if "has_heavy_slam" in player:
			player.has_heavy_slam = false
	elif shell_name == "Balloon":
		if "has_slow_fall" in player:
			player.has_slow_fall = false
	elif shell_name == "Candle":
		if "has_fire_attack" in player:
			player.has_fire_attack = false

	print("🦀 Power-up removed: ", shell_name)

# --- PASSIVE LOOP: Runs every frame while active (if is_passive = true) ---
func _process(delta: float) -> void:
	if not _is_active or _player_ref == null:
		return

	# ============================
	#   ⏱ PASSIVE LOGIC GOES HERE
	# ============================
	# Example: Balloon's slow fall — reduce gravity while in air
	if shell_name == "Balloon":
		if _player_ref is CharacterBody2D:
			if not _player_ref.is_on_floor() and _player_ref.velocity.y > 0:
				_player_ref.velocity.y *= 0.9  # Gradual slow-down
