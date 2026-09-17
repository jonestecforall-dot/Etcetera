extends CharacterBody2D

# --- MOVEMENT MODE TOGGLE ---
enum MovementMode { SIDE_SCROLLER, TOP_DOWN }
# --- Wall Slide / Wall Jump State ---
var is_wall_sliding : bool = false
var wall_normal : Vector2 = Vector2.ZERO
var wall_jump_force_x : float = 250.0
var wall_slide_gravity : float = 100.0
@export var movement_mode: MovementMode = MovementMode.SIDE_SCROLLER

# --- TEXTURES ---
@export_group("Textures")
@export var textures: Array[Texture2D] = []
@export var texture_position: Node2D

# --- JUMPING EXPORTS ---
@export_group("Jumping")
@export var jump_force: float = -400.0
@export var gravity: float = 900.0
@export var jump_smoothing: float = 0.8
@export var coyote_time: float = 0.1
@export var jump_buffer: float = 0.1
@export var fall_multiplier: float = 1.5

# --- SHOOTING EXPORTS ---
@export_group("Shooting")
@export var bullet_texture: Texture2D
@export var bullet_speed: float = 600.0
@export var bullet_damage: int = 1
@export var fire_rate: float = 0.25
@export var bullet_scene: PackedScene
@export var bullet_spawn_distance: float = 20.0

# --- Exported Stats ---
@export var max_health : int = 3
@export var invulnerable : bool = false 
@export var stun_duration : float = 2.0
@export var hit_flash_color : Color = Color(1, 0, 0)
@export var hit_flash_duration : float = 0.1

# --- Exported Sounds ---
@export_group("Sounds")
@export var shoot_sound : AudioStream
@export var death_sound : AudioStream
@export var jump_sound : AudioStream

# --- Exported Node Paths ---
@export_group("Nodes")
@export var camera_node_path : NodePath
@export var collision_node_path : NodePath
@export var sprite_node_path : NodePath
@export var audio_node_path : NodePath
@export var ui_node_path : NodePath

# --- Internal State ---
var current_health : int
var is_stunned : bool = false
var is_dead : bool = false
var ui_input_direction : Vector2 = Vector2.ZERO
var is_moving : bool = false
var can_shoot : bool = true
var facing_direction : Vector2 = Vector2.RIGHT
var last_direction : Vector2 = Vector2.RIGHT
var is_jumping : bool = false
var jump_buffer_timer : float = 0.0
var coyote_timer : float = 0.0

# --- Resolved Node References ---
var camera : Camera2D
var collision_shape : CollisionShape2D
var sprite : AnimatedSprite2D
var audio_player : AudioStreamPlayer2D
var mobile_ui : CanvasLayer

# --- Child Node Container ---
var logic_nodes : Array = []

# --- Spawned Texture Sprites ---
var spawned_textures : Array[Sprite2D] = []

# --- Cached raw X of texture_position as placed in editor ---
var texture_position_base_x : float = 0.0

func _ready() -> void:
	current_health = max_health
	_resolve_nodes()
	_spawn_textures()
	
	# Cache the RAW X (no abs), so the editor placement = facing-right position
	if is_instance_valid(texture_position):
		texture_position_base_x = texture_position.position.x
	
	if camera:
		camera.make_current()
	else:
		print("Warning: Player Camera node path not set!")
	
	if audio_player and death_sound:
		audio_player.stream = death_sound
	
	if collision_shape:
		var parent = collision_shape.get_parent()
		if parent is Area2D:
			parent.connect("body_entered", _on_hurtbox_body_entered)

	if ui_node_path:
		mobile_ui = get_node(ui_node_path)
		if mobile_ui:
			mobile_ui.ui_move_direction.connect(_on_ui_move)
			mobile_ui.ui_attack_pressed.connect(_on_ui_attack)
			mobile_ui.ui_jump_pressed.connect(_on_ui_jump)
			mobile_ui.ui_rage_pressed.connect(_on_ui_rage)

	_find_logic_nodes()
	for logic in logic_nodes:
		if logic.has_method("initialize"):
			logic.initialize(self, sprite, audio_player)

func _spawn_textures() -> void:
	if textures.is_empty():
		print("Warning: No textures assigned!")
		return
	if not is_instance_valid(texture_position):
		print("Warning: texture_position (Node2D) not assigned!")
		return

	for tex in textures:
		if tex == null:
			continue
		var spr := Sprite2D.new()
		spr.texture = tex
		spr.z_index = z_index
		spr.z_as_relative = z_as_relative
		texture_position.add_child(spr)
		spr.position = Vector2.ZERO
		spawned_textures.append(spr)

func _update_texture_flip() -> void:
	if not is_instance_valid(texture_position):
		return
	# Facing right  -> keep as placed (-17 = behind)
	# Facing left   -> mirror to +17 (behind on the other side)
	if facing_direction == Vector2.LEFT:
		texture_position.position.x = -texture_position_base_x
	else:
		texture_position.position.x = texture_position_base_x

func _resolve_nodes() -> void:
	if camera_node_path: camera = get_node(camera_node_path)
	if collision_node_path: collision_shape = get_node(collision_node_path)
	if sprite_node_path: sprite = get_node(sprite_node_path)
	if audio_node_path: audio_player = get_node(audio_node_path)

func _find_logic_nodes() -> void:
	for child in get_children():
		if child.has_method("initialize") and child != self:
			logic_nodes.append(child)

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
		"jump":
			if jump_sound:
				audio_player.stream = jump_sound
				audio_player.play()

func _physics_process(delta: float) -> void:
	if is_stunned or is_dead:
		velocity = Vector2.ZERO
		return

	var direction = ui_input_direction
	if direction == Vector2.ZERO: 
		direction.x = Input.get_axis("ui_left", "ui_right")
		direction.y = Input.get_axis("ui_up", "ui_down")

	match movement_mode:
		MovementMode.SIDE_SCROLLER:
			direction.y = 0.0
		MovementMode.TOP_DOWN:
			pass

	if movement_mode == MovementMode.SIDE_SCROLLER:
		is_wall_sliding = false
		
		if not is_on_floor() and is_on_wall() and direction.x != 0:
			var wall_normal = get_wall_normal()
			if sign(direction.x) == -sign(wall_normal.x):
				is_wall_sliding = true
				wall_normal = get_wall_normal()
		
		if is_wall_sliding:
			if velocity.y > 0:
				velocity.y = min(velocity.y, wall_slide_gravity)
			else:
				velocity.y += gravity * delta
		else:
			if velocity.y > 0:
				velocity.y += gravity * fall_multiplier * delta
			else:
				velocity.y += gravity * delta
		
		if is_on_floor():
			coyote_timer = coyote_time
		else:
			coyote_timer -= delta
		
		jump_buffer_timer -= delta

	# --- UPDATE FACING DIRECTION ---
	if direction != Vector2.ZERO:
		last_direction = direction.normalized()
		
	if is_instance_valid(sprite):
		if direction.x < 0:
			sprite.flip_h = true
			facing_direction = Vector2.LEFT
		elif direction.x > 0:
			sprite.flip_h = false
			facing_direction = Vector2.RIGHT

	# Swap the backpack to the trailing side
	_update_texture_flip()

	direction = direction.normalized()

	if movement_mode == MovementMode.SIDE_SCROLLER:
		velocity.x = direction.x * 300.0
	else:
		velocity = direction * 300.0

	if jump_buffer_timer > 0:
		if is_wall_sliding or is_on_wall():
			var wall_dir = get_wall_normal()
			velocity.x = wall_dir.x * wall_jump_force_x
			velocity.y = jump_force * 0.85
			is_jumping = true
			coyote_timer = 0
			jump_buffer_timer = 0
			play_sound("jump")
			
			if is_instance_valid(sprite):
				if wall_dir.x > 0:
					sprite.flip_h = false
					facing_direction = Vector2.RIGHT
				else:
					sprite.flip_h = true
					facing_direction = Vector2.LEFT
					
			if is_instance_valid(sprite) and sprite.has_method("update_visual_state"): 
				sprite.update_visual_state("jumping")
				
		elif coyote_timer > 0:
			_do_jump()

	if is_instance_valid(sprite):
		if sprite.has_method("update_visual_state"):
			if movement_mode == MovementMode.SIDE_SCROLLER and not is_on_floor():
				sprite.update_visual_state("jumping")
			elif direction != Vector2.ZERO:
				is_moving = true
				sprite.update_visual_state("moving")
			else:
				is_moving = false
				sprite.update_visual_state("idle")

	for logic in logic_nodes:
		if logic.has_method("update_logic"):
			logic.update_logic(delta)
			
	move_and_slide()
	
	if is_on_floor() and is_jumping:
		is_jumping = false

func _do_jump() -> void:
	velocity.y = jump_force
	is_jumping = true
	coyote_timer = 0
	jump_buffer_timer = 0
	play_sound("jump")
	if is_instance_valid(sprite) and sprite.has_method("update_visual_state"): 
		sprite.update_visual_state("jumping")

func _on_ui_move(direction: Vector2) -> void:
	ui_input_direction = direction

func _on_ui_attack() -> void:
	print("UI Attack pressed!")
	shoot()
	if is_instance_valid(sprite) and sprite.has_method("update_visual_state"): 
		sprite.update_visual_state("attacking")
	
	await get_tree().create_timer(0.2).timeout
	if is_instance_valid(sprite) and sprite.has_method("update_visual_state"): 
		if is_moving:
			sprite.update_visual_state("moving")
		else:
			sprite.update_visual_state("idle")

func _on_ui_jump() -> void:
	print("UI Jump pressed!")
	jump_buffer_timer = jump_buffer

func _on_ui_rage() -> void:
	print("UI Rage pressed!")

func shoot() -> void:
	if not can_shoot or is_dead or is_stunned:
		return
	
	can_shoot = false
	var shoot_direction = _get_shoot_direction()
	
	var bullet: Node2D
	if bullet_scene:
		bullet = bullet_scene.instantiate()
	else:
		bullet = _create_default_bullet()
	
	if bullet:
		var spawn_position = global_position + (shoot_direction * bullet_spawn_distance)
		bullet.global_position = spawn_position
		
		if bullet.has_method("setup"):
			bullet.setup(shoot_direction, bullet_damage, self)
		else:
			if bullet.has_method("set_direction"): bullet.set_direction(shoot_direction)
			if bullet.has_method("set_speed"): bullet.set_speed(bullet_speed)
			if bullet.has_method("set_damage"): bullet.set_damage(bullet_damage)
			if bullet.has_method("set_shooter"): bullet.set_shooter(self)
		
		get_tree().current_scene.add_child(bullet)
		bullet.global_position = spawn_position
	
	play_sound("shoot")
	await get_tree().create_timer(fire_rate).timeout
	can_shoot = true

func _get_shoot_direction() -> Vector2:
	match movement_mode:
		MovementMode.SIDE_SCROLLER:
			return facing_direction
		MovementMode.TOP_DOWN:
			if last_direction != Vector2.ZERO:
				return last_direction.normalized()
			else:
				return facing_direction
	return Vector2.RIGHT

func _create_default_bullet() -> Area2D:
	var bullet = Area2D.new()
	bullet.name = "Bullet"
	bullet.collision_layer = 2
	bullet.collision_mask = 1 | 4
	
	var collision = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	shape.radius = 4.0
	collision.shape = shape
	bullet.add_child(collision)
	
	var bullet_sprite = Sprite2D.new()
	if bullet_texture:
		bullet_sprite.texture = bullet_texture
		var texture_size = Vector2(bullet_texture.get_width(), bullet_texture.get_height())
		if texture_size.x > 0 and texture_size.y > 0:
			bullet_sprite.scale = Vector2(16.0 / texture_size.x, 16.0 / texture_size.y)
	else:
		var gradient = Gradient.new()
		gradient.set_color(0, Color.YELLOW)
		gradient.set_color(1, Color.ORANGE)
		
		var placeholder = GradientTexture2D.new()
		placeholder.width = 8
		placeholder.height = 8
		placeholder.gradient = gradient
		bullet_sprite.texture = placeholder
	
	bullet.add_child(bullet_sprite)
	
	var bullet_script = GDScript.new()
	bullet_script.source_code = """
extends Area2D

var direction: Vector2 = Vector2.RIGHT
var speed: float = 600.0
var damage: int = 1
var shooter: Node = null

func _ready():
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	get_tree().create_timer(3.0).timeout.connect(queue_free)

func setup(dir: Vector2, dmg: int, shooter_node: Node = null):
	direction = dir.normalized()
	damage = dmg
	shooter = shooter_node

func _physics_process(delta):
	position += direction * speed * delta

func _on_body_entered(body):
	if body == shooter:
		return
	if body.is_in_group("enemies"):
		body.take_hit("bullet", global_position)
		queue_free()
	elif body is StaticBody2D:
		queue_free()

func _on_area_entered(area):
	if area == shooter:
		return
	if area.is_in_group("enemies"):
		area.take_hit("bullet", global_position)
		queue_free()
"""
	bullet_script.reload()
	bullet.set_script(bullet_script)
	
	var shoot_dir = _get_shoot_direction()
	bullet.set("direction", shoot_dir.normalized())
	bullet.set("speed", bullet_speed)
	bullet.set("damage", bullet_damage)
	bullet.set("shooter", self)
	
	return bullet

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
	if is_instance_valid(sprite) and sprite.has_method("update_visual_state"): 
		sprite.update_visual_state("stunned")

func _end_stun() -> void:
	is_stunned = false
	if is_instance_valid(sprite) and sprite.has_method("update_visual_state"): 
		sprite.update_visual_state("idle")

func _die() -> void:
	is_dead = true
	if collision_shape: collision_shape.set_deferred("disabled", true)
	if is_instance_valid(sprite) and sprite.has_method("update_visual_state"): 
		sprite.update_visual_state("dead")
	play_sound("death")
	queue_free()

func _flash_on_hit() -> void:
	if is_instance_valid(sprite):
		sprite.modulate = hit_flash_color
		await get_tree().create_timer(hit_flash_duration).timeout
		if is_instance_valid(sprite) and not is_dead:
			sprite.modulate = Color(1, 1, 1)

func _on_hurtbox_body_entered(body: Node) -> void:
	pass
