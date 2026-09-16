extends CharacterBody2D

# --- Exported Stats (For Non-Coders to Tweak) ---
@export var max_health : int = 30
@export var invulnerable : bool = false 
@export var stun_duration : float = 2.0
@export var hit_flash_color : Color = Color(1, 0, 0)
@export var hit_flash_duration : float = 0.1

# --- Exported Sounds (Drag and drop audio files here) ---
@export_group("Sounds")
@export var shoot_sound : AudioStream
@export var death_sound : AudioStream
@export var dodge_sound : AudioStream

# --- Exported Node Paths (Find these specific standard nodes) ---
@export_group("Nodes")
@export var camera_node_path : NodePath
@export var collision_node_path : NodePath
@export var sprite_node_path : NodePath
@export var audio_node_path : NodePath

# --- Internal State ---
var current_health : int
var is_stunned : bool = false
var is_dead : bool = false

# --- Resolved Node References ---
var camera : Camera2D
var collision_shape : CollisionShape2D
var sprite : AnimatedSprite2D
var audio_player : AudioStreamPlayer2D

# --- Phase Node Container ---
var phase_nodes : Array = []

func _ready() -> void:
	current_health = max_health
	_resolve_nodes()
	
	# TURN ON THE CAMERA
	if camera:
		camera.make_current()
		print("Camera is now active!")
	else:
		print("Warning: Camera node path not set! Add your Camera2D to the export slot.")
	
	# Set up audio player with death sound by default
	if audio_player and death_sound:
		audio_player.stream = death_sound
	
	# Hook up the specific signals these nodes have
	if collision_shape:
		var parent = collision_shape.get_parent()
		if parent is Area2D:
			parent.connect("body_entered", _on_hurtbox_body_entered)
		else:
			pass

	# 1. Automatically find all child scripts that are meant to be phases
	_find_phase_nodes()

	# 2. Call the child's specific initialization logic
	_initialize_boss()
	
	# 3. Tell all phase children to initialize with their required references
	for phase in phase_nodes:
		if phase.has_method("initialize"):
			phase.initialize(self, sprite, audio_player)

# Function to fetch the nodes regardless of their names
func _resolve_nodes() -> void:
	if camera_node_path: camera = get_node(camera_node_path)
	if collision_node_path: collision_shape = get_node(collision_node_path)
	if sprite_node_path: sprite = get_node(sprite_node_path)
	if audio_node_path: audio_player = get_node(audio_node_path)

# --- Find Child Scripts ---
func _find_phase_nodes() -> void:
	for child in get_children():
		if child.has_method("initialize") and child != self:
			phase_nodes.append(child)

# --- Sound Helper Function (For Child Scripts to call) ---
func play_sound(sound_type: String) -> void:
	if not audio_player:
		return
		
	match sound_type:
		"shoot":
			if shoot_sound:
				audio_player.stream = shoot_sound
				audio_player.play()
		"death":
			if death_sound:
				audio_player.stream = death_sound
				audio_player.play()
		"dodge":
			if dodge_sound:
				audio_player.stream = dodge_sound
				audio_player.play()

# --- Override Methods for Child Scripts ---
func _initialize_boss() -> void:
	pass

func _physics_process(delta: float) -> void:
	if is_stunned or is_dead:
		velocity = Vector2.ZERO
		return

	# Call the child's movement logic
	_update_movement(delta)
	
	# Also call movement logic on all phase nodes
	for phase in phase_nodes:
		if phase.has_method("update_movement"):
			phase.update_movement(delta)
			
	move_and_slide()

func _update_movement(delta: float) -> void:
	pass

# --- Shared Combat and State Logic ---
func take_damage(amount: int) -> void:
	if invulnerable or is_stunned or is_dead:
		return
	
	current_health -= amount
	if current_health <= 0:
		_die()
	else:
		_flash_on_hit()

func apply_stun(duration: float = stun_duration) -> void:
	if is_dead: return
	is_stunned = true
	get_tree().create_timer(duration).timeout.connect(_end_stun)

func _end_stun() -> void:
	is_stunned = false

func _die() -> void:
	is_dead = true
	if collision_shape: collision_shape.set_deferred("disabled", true)
	if is_instance_valid(sprite): 
		sprite.visible = false
	
	# Play the death sound
	play_sound("death")
	
	# Add explosion logic here, then queue_free()
	queue_free()

func _flash_on_hit() -> void:
	if is_instance_valid(sprite):
		sprite.modulate = hit_flash_color
		await get_tree().create_timer(hit_flash_duration).timeout
		if is_instance_valid(sprite) and not is_dead:
			sprite.modulate = Color(1, 1, 1)

# --- Signal Handler ---
func _on_hurtbox_body_entered(body: Node) -> void:
	# Check if the body is the player or a player bullet. 
	# For example: if body.is_in_group("player_bullets"):
	#     take_damage(1)
	#     body.queue_free()
	pass
