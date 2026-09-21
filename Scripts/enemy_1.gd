extends CharacterBody2D

# --- Dropdown Menu for Non-Coders ---
@export_enum("F-DR Droid", "Swordie", "B-LT Droid", "Floater", "Sproingy") var enemy_type : String = "F-DR Droid"

# --- Basic Stats ---
@export var max_health : int = 1
@export var move_speed : float = 50.0
@export var contact_damage : int = 1

# --- Character Art (Parallel Arrays — keep indexes matched!) ---
# Index 0, 1, 2... in all three arrays line up together.
# Example:
#   sprite_frame_resources[0] = F-DR Droid idle SpriteFrames
#   animation_names[0]         = "idle"
#   animation_groups[0]        = "default"
@export var sprite_frame_resources : Array[SpriteFrames] = []
@export var animation_names : Array[String] = []
@export var animation_groups : Array[String] = []

# --- Node Paths (Drag and drop these) ---
@export var sprite_node_path : NodePath
@export var collision_node_path : NodePath
@export var audio_node_path : NodePath
@export var bounce_area_node_path : NodePath # For Sproingy

# --- References ---
var sprite : AnimatedSprite2D
var collision_shape : CollisionShape2D
var audio_player : AudioStreamPlayer2D
var bounce_area : Area2D

# --- Internal State ---
var is_dead : bool = false
var is_attacking : bool = false

# --- Animation lookup: group -> { anim_name -> SpriteFrames } ---
var _animation_library : Dictionary = {}


func _ready() -> void:
	add_to_group("enemies")
	
	if sprite_node_path: sprite = get_node(sprite_node_path)
	if collision_node_path: collision_shape = get_node(collision_node_path)
	if audio_node_path: audio_player = get_node(audio_node_path)
	if bounce_area_node_path: bounce_area = get_node(bounce_area_node_path)
	
	_build_animation_library()
	_initialize_enemy()
	
	if enemy_type == "Sproingy" and bounce_area:
		bounce_area.body_entered.connect(_on_bounce_area_body_entered)


# --- Build a lookup table from the three parallel arrays ---
func _build_animation_library() -> void:
	_animation_library.clear()
	
	var count : int = min(
		sprite_frame_resources.size(),
		min(animation_names.size(), animation_groups.size())
	)
	
	if sprite_frame_resources.size() != animation_names.size() \
	or animation_names.size() != animation_groups.size():
		push_warning("Enemy '%s': sprite_frame_resources / animation_names / animation_groups sizes don't match! Using %d entries." % [name, count])
	
	for i in count:
		var group : String = animation_groups[i]
		var anim_name : String = animation_names[i]
		var frames : SpriteFrames = sprite_frame_resources[i]
		
		if frames == null:
			push_warning("Enemy '%s': sprite_frame_resources[%d] is null." % [name, i])
			continue
		
		if not _animation_library.has(group):
			_animation_library[group] = {}
		
		_animation_library[group][anim_name] = frames


func _initialize_enemy() -> void:
	match enemy_type:
		"F-DR Droid":
			_play_anim("default", "idle")
		"Swordie":
			_play_anim("default", "idle")
		"B-LT Droid":
			_play_anim("default", "idle")
		"Floater":
			move_speed = 0
			_play_anim("default", "idle")
		"Sproingy":
			move_speed = 0
			_play_anim("default", "idle")


# --- Play an animation by group + name ---
func _play_anim(group : String, anim_name : String) -> void:
	if not sprite:
		return
	
	if not _animation_library.has(group):
		push_warning("Enemy '%s': no animation group '%s'." % [name, group])
		return
	
	var group_dict : Dictionary = _animation_library[group]
	if not group_dict.has(anim_name):
		push_warning("Enemy '%s': group '%s' has no animation '%s'." % [name, group, anim_name])
		return
	
	var frames : SpriteFrames = group_dict[anim_name]
	
	# Only swap frames if they actually changed (preserves playback)
	if sprite.sprite_frames != frames:
		sprite.sprite_frames = frames
	
	if sprite.animation != anim_name or not sprite.is_playing():
		sprite.animation = anim_name
		sprite.play()


func _physics_process(delta: float) -> void:
	if is_dead:
		return
	
	match enemy_type:
		"F-DR Droid", "Swordie", "B-LT Droid":
			velocity.x = -move_speed
			_play_anim("default", "walk")
		"Floater":
			velocity.y = sin(Time.get_ticks_msec() * 0.002) * move_speed
			_play_anim("default", "float")
		"Sproingy":
			velocity = Vector2.ZERO
			_play_anim("default", "idle")
	
	move_and_slide()
	
	# Contact damage (CharacterBody2D has no body_entered signal, so check slides)
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var body := col.get_collider()
		if body and body.is_in_group("player") and not is_dead:
			if body.has_method("take_damage"):
				body.take_damage(contact_damage)


# --- Universal Damage / Hit Logic ---
func take_hit(attack_type : String, attacker_position : Vector2 = Vector2.ZERO) -> void:
	if is_dead:
		return
	
	match enemy_type:
		"Swordie":
			if attack_type == "jump":
				print("Swordie helmet blocked the jump!")
				return
			
			var is_attacking_from_behind : bool = attacker_position.x > global_position.x
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
			print("Sproingy cannot be attacked!")
			return
	
	max_health -= 1
	if max_health <= 0:
		_die()


func _die() -> void:
	is_dead = true
	if collision_shape: collision_shape.set_deferred("disabled", true)
	if bounce_area: bounce_area.set_deferred("monitoring", false)
	if is_instance_valid(sprite):
		sprite.visible = false
	queue_free()


# --- Signal for Sproingy Bounce ---
func _on_bounce_area_body_entered(body : Node) -> void:
	if enemy_type == "Sproingy" and body.is_in_group("player"):
		body.velocity.y = -1200.0
		print("Bounce!")
