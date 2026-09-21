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

# 🆕 Shell base size — applies uniformly to all spawned shell textures.
# Set this to the pixel-perfect base size of your shell art.
# The sprite is scaled so its texture matches this size on-screen.
@export var shell_base_size : Vector2 = Vector2(32, 32)

# 🆕 Optional: keep shell textures pixel-perfect regardless of camera zoom.
# If true, the shell is scaled to shell_base_size exactly.
# If false, sprite keeps original texture dimensions.
@export var force_shell_base_size : bool = true

# --- JUMPING EXPORTS ---
@export_group("Jumping")
@export var jump_force: float = -400.0
@export var gravity: float = 900.0
@export var jump_smoothing: float = 0.8
@export var coyote_time: float = 0.1
@export var jump_buffer: float = 0.1
@export var fall_multiplier: float = 1.5
@export var jump_cut_multiplier: float = 0.5
@export var max_jump_hold_time: float = 0.3

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

# 🌊 DROWNING
@export_group("Water")
@export var drown_damage_interval : float = 1.0
@export var drown_damage_amount : int = 1
@export var debug_water : bool = true

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

var is_holding_jump : bool = false
var jump_hold_timer : float = 0.0

# 🌊 Water state
var in_water : bool = false
var drown_timer : float = 0.0

# Shell system state
var current_shell_name : String = ""
var current_shell_texture : Texture2D = null
var active_power_ups : Array = []

# Ability flags — set by power-up scripts
var can_breathe_underwater : bool = false
var can_climb_metal : bool = false
var has_heavy_slam : bool = false
var has_slow_fall : bool = false
var has_fire_attack : bool = false

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

	# 🆕 Register in the player group so MusicManager can detect gameplay state.
	if not is_in_group("player"):
		add_to_group("player")
		print("🎮 Player registered in 'player' group")

	if ui_node_path:
		mobile_ui = get_node(ui_node_path)
		if mobile_ui:
			mobile_ui.ui_move_direction.connect(_on_ui_move)
			mobile_ui.ui_attack_pressed.connect(_on_ui_attack)
			mobile_ui.ui_jump_pressed.connect(_on_ui_jump)
			if mobile_ui.has_signal("ui_jump_released"):
				mobile_ui.ui_jump_released.connect(_on_ui_jump_released)
			mobile_ui.ui_rage_pressed.connect(_on_ui_rage)

	_find_logic_nodes()
	for logic in logic_nodes:
		if logic.has_method("initialize"):
			logic.initialize(self, sprite, audio_player)

# ==========================================
# SHELL SYSTEM — public API
# ==========================================
func equip_shell(new_texture: Texture2D, new_name: String, power_ups: Array = []) -> void:
	clear_all_power_ups()

	current_shell_name = new_name
	current_shell_texture = new_texture

	if new_texture and is_instance_valid(texture_position):
		var swapped := false
		for child in texture_position.get_children():
			if child is Sprite2D:
				child.texture = new_texture
				# 🆕 Apply base size scaling whenever the shell texture changes.
				_apply_shell_size(child)
				swapped = true
				break
		if not swapped:
			print("⚠️ No Sprite2D under texture_position to swap the shell onto!")
	elif new_texture == null:
		print("⚠️ equip_shell got a NULL texture for '", new_name, "'")

	for power_up in power_ups:
		if power_up == null:
			continue
		if power_up.has_method("apply"):
			power_up.apply(self)
		add_child(power_up)
		active_power_ups.append(power_up)

	print("🐚 Player equipped shell: ", new_name, " (", power_ups.size(), " power-ups)")

# 🆕 Sizes a shell sprite so its texture occupies shell_base_size on screen.
func _apply_shell_size(spr: Sprite2D) -> void:
	if not force_shell_base_size:
		spr.scale = Vector2.ONE
		return
	if spr.texture == null:
		return
	var tex_size := Vector2(spr.texture.get_width(), spr.texture.get_height())
	if tex_size.x <= 0.0 or tex_size.y <= 0.0:
		return
	spr.scale = Vector2(
		shell_base_size.x / tex_size.x,
		shell_base_size.y / tex_size.y
	)

func register_power_up(power_up: Node) -> void:
	if power_up == null:
		return
	if not active_power_ups.has(power_up):
		active_power_ups.append(power_up)

func remove_power_up(power_up: Node) -> void:
	if power_up == null:
		return
	if active_power_ups.has(power_up):
		if power_up.has_method("remove"):
			power_up.remove(self)
		active_power_ups.erase(power_up)

func clear_all_power_ups() -> void:
	for power_up in active_power_ups:
		if is_instance_valid(power_up):
			if power_up.has_method("remove"):
				power_up.remove(self)
			power_up.queue_free()
	active_power_ups.clear()

	can_breathe_underwater = false
	can_climb_metal = false
	has_heavy_slam = false
	has_slow_fall = false
	has_fire_attack = false

# ==========================================
# END SHELL SYSTEM
# ==========================================

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
		# 🆕 Apply the shell base size on initial spawn too.
		_apply_shell_size(spr)
		spawned_textures.append(spr)

func _update_texture_flip() -> void:
	if not is_instance_valid(texture_position):
		return
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

func _input(event: InputEvent) -> void:
	if event.is_action_released("ui_accept"):
		_release_jump()

# ==========================================
# 🌊 WATER DETECTION
# ==========================================
func _update_water_state(delta: float) -> void:
	var was_in_water := in_water
	in_water = false
	
	var found_count := 0
	for node in get_tree().get_nodes_in_group("water"):
		found_count += 1
		if node is Area2D and node.overlaps_body(self):
			in_water = true
			break
	
	if found_count == 0:
		var root := get_tree().current_scene
		if root:
			for node in _find_water_areas(root):
				found_count += 1
				if node is Area2D and node.overlaps_body(self):
					in_water = true
					break
	
	if debug_water and Engine.get_physics_frames() % 60 == 0:
		print("🌊 water check | found=", found_count, " in_water=", in_water, " health=", current_health)
	
	if in_water and not was_in_water and debug_water:
		print("🌊 Entered water | can_breathe=", can_breathe_underwater)
	elif not in_water and was_in_water and debug_water:
		print("🌊 Left water")
	
	if in_water and not can_breathe_underwater:
		drown_timer += delta
		if drown_timer >= drown_damage_interval:
			drown_timer = 0.0
			if debug_water:
				print("💀 Drowning!")
			take_damage(drown_damage_amount)
	else:
		drown_timer = 0.0

var _cached_water_areas : Array[Area2D] = []

func _find_water_areas(root: Node) -> Array:
	if _cached_water_areas.size() > 0:
		var valid := true
		for w in _cached_water_areas:
			if not is_instance_valid(w) or not w.is_inside_tree():
				valid = false
				break
		if valid:
			return _cached_water_areas
		_cached_water_areas.clear()
	
	_scan_for_water(root)
	return _cached_water_areas

func _scan_for_water(node: Node) -> void:
	if node is Area2D and node.name.begins_with("WaterArea_"):
		_cached_water_areas.append(node)
	for child in node.get_children():
		_scan_for_water(child)

func _physics_process(delta: float) -> void:
	_update_water_state(delta)
	
	if is_stunned or is_dead:
		velocity = Vector2.ZERO
		return

	if is_holding_jump:
		jump_hold_timer += delta
		if jump_hold_timer >= max_jump_hold_time:
			is_holding_jump = false
	else:
		if velocity.y < 0:
			velocity.y *= (1.0 - (1.0 - jump_cut_multiplier) * delta * 10.0)

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
		
		var current_gravity = gravity
		if has_heavy_slam and not is_on_floor() and velocity.y > 0:
			current_gravity = gravity * 3.0
		
		if is_wall_sliding:
			if velocity.y > 0:
				velocity.y = min(velocity.y, wall_slide_gravity)
			else:
				velocity.y += current_gravity * delta
		else:
			if has_slow_fall and not is_on_floor() and velocity.y > 0:
				velocity.y += current_gravity * 0.35 * delta
				if velocity.y > 120.0:
					velocity.y = 120.0
			else:
				if velocity.y > 0:
					velocity.y += current_gravity * fall_multiplier * delta
				else:
					velocity.y += current_gravity * delta
		
		if is_on_floor():
			coyote_timer = coyote_time
			if has_heavy_slam and velocity.y > 200.0:
				_trigger_anvil_slam()
		else:
			coyote_timer -= delta
		
		jump_buffer_timer -= delta

	if direction != Vector2.ZERO:
		last_direction = direction.normalized()
		
	if is_instance_valid(sprite):
		if direction.x < 0:
			sprite.flip_h = true
			facing_direction = Vector2.LEFT
		elif direction.x > 0:
			sprite.flip_h = false
			facing_direction = Vector2.RIGHT

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
		is_holding_jump = false

func _trigger_anvil_slam() -> void:
	print("⚒️ Anvil slam!")
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy is Node2D:
			if global_position.distance_to(enemy.global_position) < 40.0:
				if enemy.has_method("take_hit"):
					enemy.take_hit("slam", global_position)
	for floor_tile in get_tree().get_nodes_in_group("breakable_floor"):
		if floor_tile is Node2D:
			if global_position.distance_to(floor_tile.global_position) < 40.0:
				if floor_tile.has_method("break_floor"):
					floor_tile.break_floor()
				else:
					floor_tile.queue_free()

func _do_jump() -> void:
	velocity.y = jump_force
	is_jumping = true
	coyote_timer = 0
	jump_buffer_timer = 0
	is_holding_jump = true
	jump_hold_timer = 0.0
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
	is_holding_jump = true
	jump_hold_timer = 0.0

func _on_ui_jump_released() -> void:
	_release_jump()

func _release_jump() -> void:
	is_holding_jump = false
	if velocity.y < 0:
		velocity.y *= jump_cut_multiplier

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
	if collision_shape:
		collision_shape.set_deferred("disabled", true)
	if is_instance_valid(sprite) and sprite.has_method("update_visual_state"): 
		sprite.update_visual_state("dead")
	play_sound("death")
	print("☠️ Player died — respawning...")
	
	await get_tree().create_timer(0.5).timeout
	
	if not is_instance_valid(self):
		return
	
	var level := get_tree().current_scene
	if level and level.has_method("respawn_player"):
		level.respawn_player(self)
	else:
		global_position = Vector2.ZERO
	
	is_dead = false
	is_stunned = false
	in_water = false
	drown_timer = 0.0
	current_health = max_health
	velocity = Vector2.ZERO
	if collision_shape:
		collision_shape.set_deferred("disabled", false)
	if is_instance_valid(sprite) and sprite.has_method("update_visual_state"):
		sprite.update_visual_state("idle")
	sprite.modulate = Color(1, 1, 1, 1)
	
	if has_method("on_respawn"):
		on_respawn()

func on_respawn() -> void:
	is_dead = false
	is_stunned = false
	in_water = false
	drown_timer = 0.0
	current_health = max_health
	velocity = Vector2.ZERO
	
	if collision_shape:
		collision_shape.set_deferred("disabled", false)
	
	if is_instance_valid(sprite):
		sprite.modulate = Color(1, 1, 1, 1)
		if sprite.has_method("update_visual_state"):
			sprite.update_visual_state("idle")
	
	print("🌊 on_respawn — health restored to ", current_health)

func _flash_on_hit() -> void:
	if is_instance_valid(sprite):
		sprite.modulate = hit_flash_color
		await get_tree().create_timer(hit_flash_duration).timeout
		if is_instance_valid(sprite) and not is_dead:
			sprite.modulate = Color(1, 1, 1)

func _on_hurtbox_body_entered(body: Node) -> void:
	pass
