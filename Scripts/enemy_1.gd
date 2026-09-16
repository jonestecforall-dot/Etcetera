extends CharacterBody2D

# --- Dropdown Menu for Non-Coders ---
@export_enum("F-DR Droid", "Swordie", "B-LT Droid", "Floater", "Sproingy") var enemy_type : String = "F-DR Droid"

# --- Basic Stats ---
@export var max_health : int = 1
@export var move_speed : float = 50.0
@export var contact_damage : int = 1

# --- Node Paths (Drag and drop these) ---
@export var sprite_node_path : NodePath
@export var collision_node_path : NodePath
@export var audio_node_path : NodePath
@export var bounce_area_node_path : NodePath # NEW: For Sproingy

# --- References ---
var sprite : AnimatedSprite2D
var collision_shape : CollisionShape2D
var audio_player : AudioStreamPlayer2D
var bounce_area : Area2D # NEW

# --- Internal State ---
var is_dead : bool = false
var is_attacking : bool = false

func _ready() -> void:
	add_to_group("enemies") # So the player can find us!
	
	if sprite_node_path: sprite = get_node(sprite_node_path)
	if collision_node_path: collision_shape = get_node(collision_node_path)
	if audio_node_path: audio_player = get_node(audio_node_path)
	if bounce_area_node_path: bounce_area = get_node(bounce_area_node_path) 
	
	_initialize_enemy()
	
	# Connect the Sproingy bounce area
	if enemy_type == "Sproingy" and bounce_area:
		bounce_area.body_entered.connect(_on_bounce_area_body_entered)

func _initialize_enemy() -> void:
	# Set up timers or unique logic for specific types here
	match enemy_type:
		"F-DR Droid":
			pass # Basic walker, no special logic needed
		"Swordie":
			pass # Will add a timer to jump/swing sword later
		"Floater":
			move_speed = 0 # Floaters don't walk left
		"Sproingy":
			move_speed = 0 # Springs don't move
			# DO NOT disable the collision! Leave it as is, or the player won't bounce.

func _physics_process(delta: float) -> void:
	if is_dead:
		return
		
	# --- Movement based on Enemy Type ---
	match enemy_type:
		"F-DR Droid", "Swordie", "B-LT Droid":
			# Walk left
			velocity.x = -move_speed
		"Floater":
			# Float up and down slightly
			velocity.y = sin(Time.get_ticks_msec() * 0.002) * move_speed
		"Sproingy":
			# Stay still
			velocity = Vector2.ZERO
			
	move_and_slide()

# --- Universal Damage / Hit Logic ---
# This is called by the Player when they attack
func take_hit(attack_type: String, attacker_position: Vector2 = Vector2.ZERO) -> void:
	if is_dead:
		return

	# Handle specific enemy invulnerabilities
	match enemy_type:
		"Swordie":
			# Swordie helmet blocks jump attacks
			if attack_type == "jump":
				print("Swordie helmet blocked the jump!")
				return
			
			# Swordie can only be hit from behind!
			# Check if the attacker is to the left or right of us.
			# Our enemy walks left, so their face is on the left.
			var is_attacking_from_behind = attacker_position.x > global_position.x
			
			if not is_attacking_from_behind:
				print("Swordie blocked the front attack! Hit it from behind!")
				return
				
		"B-LT Droid":
			if attack_type != "midair_spin":
				print("B-LT Droid is invulnerable to that!")
				return
		"Floater":
			if attack_type != "land_on_head":
				print("Floater ignores that attack!")
				return
		"Sproingy":
			# Springs can't be hurt, they just bounce you
			print("Sproingy cannot be attacked!")
			return

	# If we got here, take damage!
	max_health -= 1
	if max_health <= 0:
		_die()

func _die() -> void:
	is_dead = true
	if collision_shape: collision_shape.set_deferred("disabled", true)
	if bounce_area: bounce_area.set_deferred("monitoring", false) # Turn off the trigger
	if is_instance_valid(sprite): 
		sprite.visible = false
	queue_free()

# --- Signal for Player to Detect (Body collision) ---
func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player") and not is_dead:
		body.take_damage(contact_damage)

# --- Signal for Sproingy Bounce (Area collision) ---
func _on_bounce_area_body_entered(body: Node) -> void:
	if enemy_type == "Sproingy" and body.is_in_group("player"):
		# Send the player 3x higher than a normal jump (based on your docs)
		body.velocity.y = -1200.0 # Adjust this until it feels right
		print("Bounce!")
		
		# Optional: Play a "boing" sound here
		# if audio_player: audio_player.play()
