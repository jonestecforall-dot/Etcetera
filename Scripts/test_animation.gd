extends AnimatedSprite2D

# --- Exported Stats for Beginners ---
@export_group("Sprite Frames")
# They just drag a .tres SpriteFrames file here. 
# This brings up the normal AnimatedSprite2D inspector view.
@export var sprite_frames_data : SpriteFrames

@export_group("Animation Names")
# These are the names of the animations INSIDE the SpriteFrames resource.
@export var idle_animation : String = "idle"
@export var move_animation : String = "move"
@export var attack_animation : String = "attack"
@export var stun_animation : String = "stun"
@export var death_animation : String = "death"

# --- Internal State ---
var is_stunned : bool = false
var is_dead : bool = false

func _ready() -> void:
	# Apply the SpriteFrames resource
	if sprite_frames_data:
		self.sprite_frames = sprite_frames_data
	
	# Play the idle animation if it exists
	if sprite_frames and sprite_frames.has_animation(idle_animation):
		play(idle_animation)

# --- Helper Functions for BaseBoss & Child Scripts to call ---

func update_visual_state(state: String) -> void:
	# If they haven't set the data in the export, fall back to whatever is on the node
	if sprite_frames_data:
		self.sprite_frames = sprite_frames_data

	match state:
		"idle":
			if sprite_frames and sprite_frames.has_animation(idle_animation):
				play(idle_animation)
		"moving":
			if sprite_frames and sprite_frames.has_animation(move_animation):
				play(move_animation)
		"attacking":
			if sprite_frames and sprite_frames.has_animation(attack_animation):
				play(attack_animation)
		"stunned":
			is_stunned = true
			if sprite_frames and sprite_frames.has_animation(stun_animation):
				play(stun_animation)
		"dead":
			is_dead = true
			if sprite_frames and sprite_frames.has_animation(death_animation):
				play(death_animation)

func set_hurt_flash(color: Color, duration: float) -> void:
	# Called by the BaseBoss when taking damage
	modulate = color
	await get_tree().create_timer(duration).timeout
	if not is_dead:
		modulate = Color(1, 1, 1)
		# Revert to idle or current state if needed
		update_visual_state("idle")
