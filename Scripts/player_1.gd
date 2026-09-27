extends CharacterBody2D

# --- MOVEMENT MODE TOGGLE ---
enum MovementMode { SIDE_SCROLLER, TOP_DOWN }
# --- Wall Slide / Wall Jump State ---
var is_wall_sliding : bool = false
var wall_normal : Vector2 = Vector2.ZERO
var wall_jump_force_x : float = 250.0
var wall_slide_gravity : float = 100.0
# 🌊 Water state
var in_water : bool = false
var drown_timer : float = 0.0
var _water_enter_debounce : float = 0.0     # 🆕 grace period before leaving water
const WATER_EXIT_GRACE : float = 0.15       # 🆕 seconds of "still in water" after last overlap
@export var movement_mode: MovementMode = MovementMode.SIDE_SCROLLER
# --- CAMERA TILE BOUNDS ---
@export_group("Camera Bounds")
@export var enable_tile_camera_bounds : bool = true
@export var tile_scan_radius : int = 8              # how many tiles around the player to scan
@export var camera_edge_padding : float = 0.0       # extra world-units of breathing room
@export var debug_camera_bounds : bool = false
# --- TEXTURES ---
@export_group("Textures")
@export var textures: Array[Texture2D] = []
@export var texture_position: Node2D

@export var shell_base_size : Vector2 = Vector2(32, 32)
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

# --- CLAW ATTACK EXPORTS ---
@export_group("Claw Attack")
@export var claw_damage: int = 1
@export var claw_radius: float = 18.0          # radius of the claw hitbox
@export var claw_reach: float = 32.0           # how far in front the claw sweeps
@export var claw_start_offset: Vector2 = Vector2(0, 16)  # starting point (under player)
@export var claw_swing_time: float = 0.18      # how long the swing takes
@export var claw_cooldown: float = 0.35        # total time before next claw
@export var claw_debug_color: Color = Color(1, 0.5, 0.1, 0.6)

# --- Exported Stats ---
@export var max_health : int = 3
@export var invulnerable : bool = false 
@export var stun_duration : float = 2.0
@export var hit_flash_color : Color = Color(1, 0, 0)
@export var hit_flash_duration : float = 0.1
@export var iframe_duration : float = 0.75     # 🛡️ invulnerability window after a hit

# 🌊 DROWNING
@export_group("Water")
@export var hostile : bool = true
@export var drown_damage_interval : float = 1.0
@export var drown_damage_amount : int = 1
@export var debug_water : bool = true

# --- Exported Sounds ---
@export_group("Sounds")
@export var claw_sound : AudioStream
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
var can_attack : bool = true
var facing_direction : Vector2 = Vector2.RIGHT
var last_direction : Vector2 = Vector2.RIGHT
var is_jumping : bool = false
var jump_buffer_timer : float = 0.0
var coyote_timer : float = 0.0

var is_holding_jump : bool = false
var jump_hold_timer : float = 0.0

# 🛡️ I-frames
var _iframes_remaining : float = 0.0

# 🌊 Water state



# Shell system state
var current_shell_name : String = ""
var current_shell_texture : Texture2D = null
var active_power_ups : Array = []

# Ability flags
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

# 🦶 Stomp fall memory — remembers "was falling" for a short window so
# enemies can detect a stomp even after move_and_slide() zeroes velocity.
var _falling_memory : float = 0.0

# 🐾 Claw state
var _claw_active : bool = false


func _ready() -> void:
	current_health = max_health
	_resolve_nodes()
	_spawn_textures()
	_fit_collision_to_sprite()
	
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
			
			# 🎨 Initialize the HUD with our health values
			if mobile_ui.has_method("set_hud_max_health"):
				mobile_ui.set_hud_max_health(max_health)
			_push_health_to_hud()

	_find_logic_nodes()
	for logic in logic_nodes:
		if logic.has_method("initialize"):
			logic.initialize(self, sprite, audio_player)


# ==========================================
# 🎨 HUD SYNC
# ==========================================
func _push_health_to_hud() -> void:
	if mobile_ui and mobile_ui.has_method("set_hud_health"):
		mobile_ui.set_hud_health(current_health)


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


# 🆕 Forces the player's CollisionShape2D to match the current sprite size.
func _fit_collision_to_sprite() -> void:
	if collision_shape == null:
		return
	
	var tex_size := Vector2.ZERO
	
	if is_instance_valid(sprite) and sprite.sprite_frames:
		var tex := sprite.sprite_frames.get_frame_texture(sprite.animation, 0)
		if tex:
			tex_size = Vector2(tex.get_width(), tex.get_height()) * sprite.scale
	elif is_instance_valid(texture_position):
		for child in texture_position.get_children():
			if child is Sprite2D and child.texture:
				tex_size = Vector2(
					child.texture.get_width() * child.scale.x,
					child.texture.get_height() * child.scale.y
				)
				break
	
	if tex_size.x <= 0.0 or tex_size.y <= 0.0:
		return
	
	var shape : Shape2D = collision_shape.shape
	if shape is RectangleShape2D:
		(shape as RectangleShape2D).size = tex_size
	elif shape is CapsuleShape2D:
		var cap := shape as CapsuleShape2D
		cap.radius = tex_size.x * 0.5
		cap.height = tex_size.y
	elif shape is CircleShape2D:
		var c := shape as CircleShape2D
		c.radius = min(tex_size.x, tex_size.y) * 0.5
	else:
		var rect := RectangleShape2D.new()
		rect.size = tex_size
		collision_shape.shape = rect


func _find_logic_nodes() -> void:
	for child in get_children():
		if child.has_method("initialize") and child != self:
			logic_nodes.append(child)


func play_sound(sound_type: String) -> void:
	if not audio_player:
		return
	match sound_type:
		"claw":
			if claw_sound:
				audio_player.stream = claw_sound
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
var _cached_surface_y : float = INF
var _last_water_check_pos : Vector2 = Vector2.ZERO
var _cached_water_areas : Array[Area2D] = []
func _update_water_state(delta: float) -> void:
	var moved := global_position.distance_squared_to(_last_water_check_pos) > 16.0
	if not moved and not in_water and _water_enter_debounce <= 0.0:
		return
	_last_water_check_pos = global_position
	
	# Check for actual overlap this frame
	var overlapping_now : bool = false
	for node in get_tree().get_nodes_in_group("water"):
		if node is Area2D and node.overlaps_body(self):
			overlapping_now = true
			break
	
	# 🛑 Debounce: if we're overlapping, keep the "in water" state alive.
	# If we're NOT overlapping, only leave water after the grace period expires.
	if overlapping_now:
		_water_enter_debounce = WATER_EXIT_GRACE
	else:
		_water_enter_debounce = max(0.0, _water_enter_debounce - delta)
	
	var now_in_water : bool = overlapping_now or (_water_enter_debounce > 0.0)
	
	if debug_water and Engine.get_physics_frames() % 60 == 0:
		print("🌊 water check | in_water=", now_in_water, " health=", current_health)
	
	# Only trigger the transition if the state ACTUALLY changed
	var was_in_water := in_water
	in_water = now_in_water
	
	if in_water and not was_in_water:
		if debug_water:
			print("🌊 Entered water")
		_enter_water()
	elif not in_water and was_in_water:
		if debug_water:
			print("🌊 Left water")
		_exit_water()
	
	# 🌊 Surface handling — only when we're actually in water and can't breathe.
	if in_water and not can_breathe_underwater and _cached_surface_y != INF:
		var depth_below_surface := global_position.y - _cached_surface_y
		
		var player_half_h : float = 16.0
		if collision_shape and collision_shape.shape is RectangleShape2D:
			player_half_h = (collision_shape.shape as RectangleShape2D).size.y * 0.5
		
		var surface_tolerance : float = player_half_h + 4.0
		
		if depth_below_surface <= surface_tolerance and depth_below_surface > -surface_tolerance:
			# 🌊 Settling at the surface: don't snap Y, just ease velocity toward rest.
			# Pull gently toward the rest Y, and damp vertical velocity instead of
			# zeroing it. This is what removes the bounce.
			var rest_y : float = _cached_surface_y - player_half_h
			global_position.y = lerp(global_position.y, rest_y, 0.25)
			velocity.y = lerp(velocity.y, 0.0, 0.35)
		elif depth_below_surface > surface_tolerance:
			# 🌊 Submerged: gentle upward push scaled by depth (soft spring).
			# Lower multiplier + lower cap = no launch.
			var push : float = clamp(depth_below_surface * 4.0, 0.0, 180.0)
			velocity.y = lerp(velocity.y, -push, 0.35)
	
	if in_water and hostile and not can_breathe_underwater:
		drown_timer += delta
		if drown_timer >= drown_damage_interval:
			drown_timer = 0.0
			if debug_water:
				print("💀 Drowning!")
			take_damage(drown_damage_amount)
	else:
		drown_timer = 0.0

func _enter_water() -> void:
	movement_mode = MovementMode.TOP_DOWN
	is_jumping = false
	is_holding_jump = false
	jump_buffer_timer = 0.0
	coyote_timer = 0.0
	is_wall_sliding = false
	_cached_surface_y = _get_water_surface_y()
	
	# 🌊 Smooth entry: keep horizontal momentum, soften vertical
	# Instead of zeroing velocity, just damp it so we glide in naturally.
	velocity.x *= 0.7                  # keep most of your horizontal speed
	velocity.y = clamp(velocity.y, -150.0, 150.0)  # cap vertical so you don't rocket


func _get_water_surface_y() -> float:
	for node in get_tree().get_nodes_in_group("water"):
		if node is Area2D and node.overlaps_body(self):
			return _water_area_top(node)
	
	for node in _cached_water_areas:
		if is_instance_valid(node) and node.overlaps_body(self):
			return _water_area_top(node)
	
	return INF


func _water_area_top(area: Area2D) -> float:
	for child in area.get_children():
		if child is CollisionShape2D and child.shape is RectangleShape2D:
			var half_h : float = (child.shape as RectangleShape2D).size.y * 0.5
			return area.global_position.y + child.position.y - half_h
	return area.global_position.y


func _exit_water() -> void:
	movement_mode = MovementMode.SIDE_SCROLLER
	velocity = Vector2.ZERO
	ui_input_direction = Vector2.ZERO
	_cached_surface_y = INF


# ==========================================
# 🎮 MAIN PHYSICS
# ==========================================
func _physics_process(delta: float) -> void:
	# 🛡️ Tick down i-frames
	if _iframes_remaining > 0.0:
		_iframes_remaining -= delta
	
	_update_water_state(delta)
	
	if is_stunned or is_dead:
		velocity = Vector2.ZERO
		_falling_memory = 0.0
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
			wall_normal = get_wall_normal()
			if sign(direction.x) == -sign(wall_normal.x):
				is_wall_sliding = true
		
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
	
	if velocity.y > 20.0:
		_falling_memory = 0.25
	else:
		_falling_memory = max(0.0, _falling_memory - delta)
	
	move_and_slide()
	
	_apply_tile_camera_bounds()
	
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
	claw_attack()
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


# ==========================================
# 🐾 CLAW ATTACK
# ==========================================
func claw_attack() -> void:
	if not can_attack or is_dead or is_stunned:
		return
	if _claw_active:
		return
	
	can_attack = false
	_claw_active = true
	
	var dir : Vector2 = facing_direction
	if movement_mode == MovementMode.TOP_DOWN and last_direction != Vector2.ZERO:
		dir = last_direction.normalized()
	
	var claw := Area2D.new()
	claw.name = "Claw"
	claw.collision_layer = 2
	claw.collision_mask = 1 | 4
	claw.monitoring = true
	claw.monitorable = false
	
	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = claw_radius
	col.shape = shape
	claw.add_child(col)
	
	var visual := _create_claw_visual()
	claw.add_child(visual)
	
	var parent := get_parent()
	if parent == null:
		parent = get_tree().current_scene
	parent.add_child(claw)
	
	claw.body_entered.connect(_on_claw_body_entered.bind(claw))
	claw.area_entered.connect(_on_claw_area_entered.bind(claw))
	
	play_sound("claw")
	
	var elapsed : float = 0.0
	
	while elapsed < claw_swing_time and is_instance_valid(claw):
		elapsed += get_process_delta_time()
		var t : float = clamp(elapsed / claw_swing_time, 0.0, 1.0)
		
		var local_offset : Vector2 = claw_start_offset.lerp(
			claw_start_offset + (dir * claw_reach),
			t
		)
		claw.global_position = global_position + local_offset
		
		await get_tree().process_frame
	
	if is_instance_valid(claw):
		claw.queue_free()
	_claw_active = false
	
	await get_tree().create_timer(claw_cooldown).timeout
	can_attack = true


func _create_claw_visual() -> Node2D:
	var root := Node2D.new()
	root.name = "ClawVisual"
	
	var circle := Sprite2D.new()
	var img := Image.create(int(claw_radius * 2), int(claw_radius * 2), false, Image.FORMAT_RGBA8)
	img.fill(claw_debug_color)
	var tex := ImageTexture.create_from_image(img)
	circle.texture = tex
	circle.centered = true
	circle.modulate = Color(1, 1, 1, claw_debug_color.a)
	root.add_child(circle)
	
	return root


func _on_claw_body_entered(body: Node, claw: Area2D) -> void:
	if body == self:
		return
	if body.is_in_group("enemies"):
		if body.has_method("take_hit"):
			body.take_hit("claw", claw.global_position)
	elif body.is_in_group("shells") or body.is_in_group("breakable"):
		if body.has_method("take_hit"):
			body.take_hit("claw", claw.global_position)


func _on_claw_area_entered(area: Area2D, claw: Area2D) -> void:
	if area == self:
		return
	if area.is_in_group("enemies"):
		if area.has_method("take_hit"):
			area.take_hit("claw", claw.global_position)


# ==========================================
# 💥 DAMAGE / DEATH
# ==========================================
func take_damage(amount: int) -> void:
	if invulnerable or is_stunned or is_dead:
		return
	# 🛡️ Block multiple hits in the same window
	if _iframes_remaining > 0.0:
		return
	
	current_health -= amount
	if current_health <= 0:
		current_health = 0
		# 🎨 Push to HUD first so the bar visibly drains to 0
		_push_health_to_hud()
		_die()
	else:
		# 🛡️ Start i-frames
		_iframes_remaining = iframe_duration
		# 🎨 Push the new value to HUD
		_push_health_to_hud()
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
	
	global_position = _find_respawn_position()
	
	is_dead = false
	is_stunned = false
	in_water = false
	drown_timer = 0.0
	_falling_memory = 0.0
	_iframes_remaining = 0.0
	current_health = max_health
	velocity = Vector2.ZERO
	if collision_shape:
		collision_shape.set_deferred("disabled", false)
	if is_instance_valid(sprite) and sprite.has_method("update_visual_state"):
		sprite.update_visual_state("idle")
	sprite.modulate = Color(1, 1, 1, 1)
	
	# 🎨 Refill HUD on respawn
	_push_health_to_hud()
	
	if has_method("on_respawn"):
		on_respawn()

func on_respawn() -> void:
	is_dead = false
	is_stunned = false
	in_water = false
	drown_timer = 0.0
	_falling_memory = 0.0
	_iframes_remaining = 0.0
	current_health = max_health
	velocity = Vector2.ZERO
	
	if collision_shape:
		collision_shape.set_deferred("disabled", false)
	
	if is_instance_valid(sprite):
		sprite.modulate = Color(1, 1, 1, 1)
		if sprite.has_method("update_visual_state"):
			sprite.update_visual_state("idle")
	
	# 🎨 Refill HUD
	_push_health_to_hud()
	
	print("🌊 on_respawn — health restored to ", current_health)


func _flash_on_hit() -> void:
	if is_instance_valid(sprite):
		sprite.modulate = hit_flash_color
		await get_tree().create_timer(hit_flash_duration).timeout
		if is_instance_valid(sprite) and not is_dead:
			sprite.modulate = Color(1, 1, 1)


func _on_hurtbox_body_entered(body: Node) -> void:
	pass


# ==========================================
# 🦶 STOMP HELPERS
# ==========================================
func on_stomped_by_enemy() -> void:
	is_jumping = false
	is_holding_jump = false
	jump_buffer_timer = 0.0


func was_falling_last_frame(threshold: float = 5.0) -> bool:
	return _falling_memory > 0.0


# ==========================================
# 🎥 CAMERA TILE BOUNDS
# ==========================================
func _apply_tile_camera_bounds() -> void:
	if not enable_tile_camera_bounds:
		return
	if camera == null:
		return
	
	var level := get_tree().current_scene
	if level == null or not level.has_method("get_camera_bounds_for_position"):
		return
	
	var bounds : Dictionary = level.get_camera_bounds_for_position(
		global_position,
		tile_scan_radius
	)
	
	var vp_size := get_viewport_rect().size * camera.zoom
	var half_w := vp_size.x * 0.5
	var half_h := vp_size.y * 0.5
	
	var cam_pos := global_position
	if camera.has_method("get_screen_center_position"):
		cam_pos = camera.get_screen_center_position()
	
	if bounds["left"] != -INF:
		var min_cam_x : float = bounds["left"] + half_w + camera_edge_padding
		cam_pos.x = max(cam_pos.x, min_cam_x)
	
	if bounds["right"] != INF:
		var max_cam_x : float = bounds["right"] - half_w - camera_edge_padding
		cam_pos.x = min(cam_pos.x, max_cam_x)
	
	if bounds["top"] != -INF:
		var min_cam_y : float = bounds["top"] + half_h + camera_edge_padding
		cam_pos.y = max(cam_pos.y, min_cam_y)
	
	if bounds["bottom"] != INF:
		var max_cam_y : float = bounds["bottom"] - half_h - camera_edge_padding
		cam_pos.y = min(cam_pos.y, max_cam_y)
	
	camera.global_position = cam_pos
	
	if debug_camera_bounds and Engine.get_physics_frames() % 30 == 0:
		print("🎥 cam bounds | pos=", cam_pos, " | ", bounds)


# ==========================================
# 🚩 RESPAWN POSITION LOOKUP
# ==========================================
func _find_respawn_position() -> Vector2:
	var root := get_tree().current_scene
	if root == null:
		return Vector2.ZERO
	
	var flag := _find_node_named(root, "StartFlag")
	if flag is Node2D:
		var pos := (flag as Node2D).global_position
		print("🚩 Respawn: using StartFlag at ", pos)
		return pos
	
	var marker := _find_node_named(root, "PlayerSpawn")
	if marker is Node2D:
		var pos := (marker as Node2D).global_position
		print("📍 Respawn: using PlayerSpawn marker at ", pos)
		return pos
	
	print("⚠️ Respawn: no StartFlag or PlayerSpawn found — using origin")
	return Vector2.ZERO


func _find_node_named(root: Node, target_name: String) -> Node:
	if root.name == target_name:
		return root
	for child in root.get_children():
		var found := _find_node_named(child, target_name)
		if found != null:
			return found
	return null
