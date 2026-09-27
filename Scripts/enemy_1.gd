extends CharacterBody2D

# --- Dropdown Menu for Non-Coders ---
@export_enum("F-DR Droid", "Swordie", "B-LT Droid", "Floater", "Sproingy") var enemy_type : String = "F-DR Droid"

# --- Basic Stats ---
@export var max_health : int = 1
@export var move_speed : float = 50.0
@export var contact_damage : int = 1
@export var gravity : float = 900.0

# --- Movement Behavior ---
@export_group("Movement")
@export var turn_at_walls : bool = true
@export var turn_at_ledges : bool = true
@export var ledge_ray_length : float = 24.0

# --- 🛑 MAP MAKER FREEZE ---
@export_group("Map Maker Freeze")
@export var editor_freeze_group : String = "stopenemy"

# --- Character Art (Parallel Arrays — keep indexes matched!) ---
@export_group("Character Art")
@export var sprite_frame_resources : Array[SpriteFrames] = []
@export var animation_names : Array[String] = []
@export var animation_groups : Array[String] = []

# --- Node Paths (Drag and drop these) ---
@export_group("Nodes")
@export var sprite_node_path : NodePath
@export var collision_node_path : NodePath
@export var audio_node_path : NodePath
@export var bounce_area_node_path : NodePath
@export var stomp_zone_node_path : NodePath

# --- Death Feedback ---
@export_group("Death Feedback")
@export var death_sound : AudioStream
@export var death_flash_duration : float = 0.15
@export var death_flash_color : Color = Color(1, 0.4, 0.4)

# --- Stomp ---
@export_group("Stomp")
@export var stomp_bounce_force : float = -500.0

# --- Collision Auto-fit ---
@export_group("Collision")
@export var auto_fit_collision : bool = true
@export var collision_size_multiplier : Vector2 = Vector2(1.0, 1.0)

# --- References ---
var sprite : AnimatedSprite2D
var collision_shape : CollisionShape2D
var audio_player : AudioStreamPlayer2D
var bounce_area : Area2D
var stomp_zone : Area2D

# --- Internal State ---
var is_dead : bool = false
var is_attacking : bool = false
var _frozen_by_editor : bool = false
var _spawn_locked : bool = true
var _player_in_zone : Node = null
var _animation_library : Dictionary = {}

func _ready() -> void:
	add_to_group("enemies")
	
	if sprite_node_path: sprite = get_node(sprite_node_path)
	if collision_node_path: collision_shape = get_node(collision_node_path)
	if audio_node_path: audio_player = get_node(audio_node_path)
	if bounce_area_node_path: bounce_area = get_node(bounce_area_node_path)
	if stomp_zone_node_path: stomp_zone = get_node(stomp_zone_node_path)
	
	_build_animation_library()
	_initialize_enemy()
	
	if auto_fit_collision:
		_fit_collision_to_sprite()
	
	# 🎯 Align the collision shape with the sprite's VISIBLE center.
	if collision_shape and is_instance_valid(sprite):
		var gs := sprite.global_scale.abs()
		collision_shape.position = sprite.offset * gs
		print("🎯 [", name, "] collision_shape moved to ", collision_shape.position,
			" (sprite.offset=", sprite.offset, " × global_scale=", gs, ")")
	
	if stomp_zone:
		stomp_zone.monitoring = false
		stomp_zone.monitorable = false
	
	if auto_fit_collision and stomp_zone:
		_fit_stomp_zone_to_sprite()
	
	if enemy_type == "Sproingy" and bounce_area:
		bounce_area.body_entered.connect(_on_bounce_area_body_entered)
	
	if stomp_zone:
		stomp_zone.body_entered.connect(_on_stomp_zone_body_entered)
		stomp_zone.body_exited.connect(_on_stomp_zone_body_exited)
		print("🦶 [", name, "] StompZone CONNECTED (monitoring OFF until unfrozen).")
	else:
		print("⚠️ [", name, "] NO STOMP ZONE")
	
	# 🛑 NUCLEAR SPAWN FREEZE
	process_mode = Node.PROCESS_MODE_DISABLED
	if collision_shape:
		collision_shape.disabled = true
	if stomp_zone:
		stomp_zone.monitoring = false
		stomp_zone.monitorable = false
	if bounce_area:
		bounce_area.monitoring = false
		bounce_area.monitorable = false
	velocity = Vector2.ZERO
	
	await _finish_spawn_freeze()
	
	# 🔍 FINAL DEBUG — print where the collision bottom and sprite bottom actually land
	await get_tree().physics_frame
	print("═══════════ ENEMY FINAL STATE: ", name, " ═══════════")
	print("  global_position         = ", global_position)
	print("  sprite.centered         = ", sprite.centered)
	print("  sprite.offset           = ", sprite.offset)
	print("  sprite.global_scale     = ", sprite.global_scale)
	print("  sprite.global_position  = ", sprite.global_position)
	
	if sprite.sprite_frames and sprite.sprite_frames.get_frame_count(sprite.animation) > 0:
		var tex := sprite.sprite_frames.get_frame_texture(sprite.animation, 0)
		if tex:
			print("  sprite tex size (px)    = ", tex.get_width(), " x ", tex.get_height())
			var visible_h : float = tex.get_height() * sprite.global_scale.y
			var sprite_top_y : float = sprite.global_position.y - visible_h * 0.5
			var sprite_bottom_y : float = sprite.global_position.y + visible_h * 0.5
			print("  sprite top y (world)    = ", sprite_top_y)
			print("  sprite bottom y (world) = ", sprite_bottom_y)
	
	print("  collision_shape.position        = ", collision_shape.position)
	print("  collision_shape.global_position = ", collision_shape.global_position)
	if collision_shape.shape is RectangleShape2D:
		var r := collision_shape.shape as RectangleShape2D
		print("  collision_shape.size            = ", r.size)
		var col_top_y : float = collision_shape.global_position.y - r.size.y * 0.5
		var col_bottom_y : float = collision_shape.global_position.y + r.size.y * 0.5
		print("  collision top y (world)         = ", col_top_y)
		print("  collision bottom y (world)      = ", col_bottom_y)
	print("═══════════════════════════════════════════════════")


func _finish_spawn_freeze() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	
	_spawn_locked = false
	
	if _is_editor_active():
		_freeze_for_editor()
	else:
		process_mode = Node.PROCESS_MODE_INHERIT
		if collision_shape:
			collision_shape.disabled = false
		if stomp_zone:
			stomp_zone.monitoring = true
			stomp_zone.monitorable = true
		if bounce_area:
			bounce_area.monitoring = true
			bounce_area.monitorable = true
		velocity = Vector2.ZERO
		print("🔓 [", name, "] spawn freeze done — running normally")


func _freeze_for_editor() -> void:
	if _frozen_by_editor:
		return
	_frozen_by_editor = true
	
	velocity = Vector2.ZERO
	
	if collision_shape:
		collision_shape.disabled = true
	if stomp_zone:
		stomp_zone.monitoring = false
		stomp_zone.monitorable = false
	if bounce_area:
		bounce_area.monitoring = false
		bounce_area.monitorable = false
	
	process_mode = Node.PROCESS_MODE_DISABLED
	print("🛑 [", name, "] FROZEN by editor")


func _unfreeze_from_editor() -> void:
	if not _frozen_by_editor:
		return
	_frozen_by_editor = false
	
	process_mode = Node.PROCESS_MODE_INHERIT
	
	if collision_shape:
		collision_shape.disabled = false
	if stomp_zone:
		stomp_zone.monitoring = true
		stomp_zone.monitorable = true
	if bounce_area:
		bounce_area.monitoring = true
		bounce_area.monitorable = true
	
	velocity = Vector2.ZERO
	print("🔓 [", name, "] UNFROZEN by editor")


func _is_editor_active() -> bool:
	for node in get_tree().get_nodes_in_group(editor_freeze_group):
		if node == self:
			continue
		if not is_instance_valid(node):
			continue
		if node is CanvasItem:
			if (node as CanvasItem).visible:
				return true
		else:
			return true
	return false


# 🆕 Resizes the CollisionShape2D to match the sprite's ON-SCREEN size

# 🆕 Resizes + positions the CollisionShape2D to match the sprite's
# ACTUAL VISIBLE PIXELS (ignoring any transparent padding in the PNG).

# 🆕 Sizes the CollisionShape2D in LOCAL space so it matches the sprite's
# world-space visible size after all parent transforms are applied.
func _fit_collision_to_sprite() -> void:
	if collision_shape == null:
		return
	if not is_instance_valid(sprite):
		return
	if not sprite.sprite_frames:
		return
	
	var tex_size := Vector2.ZERO
	
	var anim_name : String = sprite.animation if sprite.animation != "" else "idle"
	var tex : Texture2D = null
	if sprite.sprite_frames.has_animation(anim_name) and sprite.sprite_frames.get_frame_count(anim_name) > 0:
		tex = sprite.sprite_frames.get_frame_texture(anim_name, 0)
	elif sprite.sprite_frames.get_animation_names().size() > 0:
		var anims : Array = sprite.sprite_frames.get_animation_names()
		var first_anim : String = String(anims[0])
		if sprite.sprite_frames.get_frame_count(first_anim) > 0:
			tex = sprite.sprite_frames.get_frame_texture(first_anim, 0)
	
	if tex == null:
		print("⚠️ [", name, "] No texture frame")
		return
	
	# Use RAW texture size — this is the LOCAL size.
	# The parent scale will scale both the sprite AND the collision together.
	tex_size = Vector2(tex.get_width(), tex.get_height())
	
	# But if the sprite ITSELF has a scale != 1 (not the parent), apply it.
	# sprite.scale is the sprite node's local scale, NOT global.
	tex_size *= sprite.scale.abs()
	
	tex_size *= collision_size_multiplier
	
	var rect_shape := RectangleShape2D.new()
	rect_shape.size = tex_size
	collision_shape.shape = rect_shape
	# Match the sprite's local offset so both align
	collision_shape.position = sprite.offset
	
	print("🛑 [", name, "] local collision size = ", tex_size,
		" | sprite.scale=", sprite.scale,
		" | global_scale=", sprite.global_scale)

func _build_animation_library() -> void:
	_animation_library.clear()
	
	var count : int = min(
		sprite_frame_resources.size(),
		min(animation_names.size(), animation_groups.size())
	)
	
	if sprite_frame_resources.size() != animation_names.size() \
	or animation_names.size() != animation_groups.size():
		push_warning("Enemy '%s': arrays don't match! Using %d entries." % [name, count])
	
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


func _play_anim(group : String, anim_name : String) -> void:
	if not sprite:
		return
	if not _animation_library.has(group):
		return
	var group_dict : Dictionary = _animation_library[group]
	if not group_dict.has(anim_name):
		return
	var frames : SpriteFrames = group_dict[anim_name]
	if sprite.sprite_frames != frames:
		sprite.sprite_frames = frames
	if sprite.animation != anim_name or not sprite.is_playing():
		sprite.animation = anim_name
		sprite.play()


func _physics_process(delta: float) -> void:
	if is_dead:
		return
	if _spawn_locked:
		return
	
	var editor_now := _is_editor_active()
	if editor_now and not _frozen_by_editor:
		_freeze_for_editor()
		return
	elif not editor_now and _frozen_by_editor:
		_unfreeze_from_editor()
	
	if _frozen_by_editor:
		return
	
	# --- Normal AI movement ---
	if enemy_type in ["F-DR Droid", "Swordie", "B-LT Droid"]:
		if not is_on_floor():
			velocity.y += gravity * delta
	
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
	
	if enemy_type in ["F-DR Droid", "Swordie", "B-LT Droid"]:
		if turn_at_walls and is_on_wall():
			move_speed = -move_speed
			velocity.x = -move_speed
		elif turn_at_ledges and is_on_floor() and not _has_floor_ahead():
			move_speed = -move_speed
			velocity.x = -move_speed
	
	# 🦶 STOMP CHECK — done every frame with direct player detection.
	_check_for_stomp_contact()
	
	# 🦶 Contact damage — if the player is touching us but NOT stomping
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var body := col.get_collider()
		if body and body.is_in_group("player") and not is_dead:
			if _player_in_zone == body:
				continue
			if body.has_method("take_damage"):
				body.take_damage(contact_damage)


# 🦶 Checks every frame if a player is directly above us and falling.
func _check_for_stomp_contact() -> void:
	if is_dead:
		return
	
	var my_top_y : float = global_position.y
	# Use the collision shape's actual half-height in world space
	if collision_shape and collision_shape.shape is RectangleShape2D:
		var r := collision_shape.shape as RectangleShape2D
		my_top_y = global_position.y - (r.size.y * 0.5 * scale.y)
	elif sprite and sprite.sprite_frames:
		var tex := sprite.sprite_frames.get_frame_texture(sprite.animation, 0)
		if tex:
			my_top_y = global_position.y - (tex.get_height() * sprite.global_scale.y * 0.5)
	
	for p in get_tree().get_nodes_in_group("player"):
		if not p is CharacterBody2D:
			continue
		var cb := p as CharacterBody2D
		
		# Horizontal check: player must be within the enemy's width
		var dx : float = abs(cb.global_position.x - global_position.x)
		var half_width : float = 20.0  # ~half of 31.7
		if collision_shape and collision_shape.shape is RectangleShape2D:
			half_width = (collision_shape.shape as RectangleShape2D).size.x * 0.5 * scale.x
		if dx > half_width + 8.0:
			continue
		
		# Vertical check: player must be ABOVE the enemy's top edge
		var dy : float = my_top_y - cb.global_position.y
		# Player center must be above enemy top (by at least half player height)
		if dy < 0:
			continue
		# Player must be close (within ~40px of the top)
		if dy > 40.0:
			continue
		
		# Player must be falling (or recently falling)
		var falling_now : bool = cb.velocity.y > 5.0
		var was_falling : bool = false
		if cb.has_method("was_falling_last_frame"):
			was_falling = cb.was_falling_last_frame(5.0)
		
		if not falling_now and not was_falling:
			continue
		
		# ✅ STOMP!
		print("🦶 STOMP CONTACT (physics_process check) on player: ", cb.name)
		cb.velocity.y = stomp_bounce_force
		if cb.has_method("on_stomped_by_enemy"):
			cb.on_stomped_by_enemy()
		take_hit("stomp", cb.global_position)
		return

func _has_floor_ahead() -> bool:
	var space := get_world_2d().direct_space_state
	var look_dir : float = sign(-move_speed)
	var from := global_position + Vector2(look_dir * 8.0, 8.0)
	var to := from + Vector2(0, ledge_ray_length)
	var query := PhysicsRayQueryParameters2D.create(from, to)
	query.exclude = [self]
	return not space.intersect_ray(query).is_empty()


func take_hit(attack_type : String, attacker_position : Vector2 = Vector2.ZERO) -> void:
	if is_dead:
		return
	var attack := attack_type
	if attack == "jump":
		attack = "stomp"
	
	match enemy_type:
		"F-DR Droid":
			pass
		"Swordie":
			if attack == "stomp":
				print("Swordie helmet blocked the stomp!")
				return
			var is_attacking_from_behind : bool = attacker_position.x > global_position.x
			if not is_attacking_from_behind:
				print("Swordie blocked the front attack! Hit it from behind!")
				return
		"B-LT Droid":
			if attack != "midair_spin":
				print("B-LT Droid is invulnerable to that!")
				return
		"Floater":
			if attack != "land_on_head":
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
	if stomp_zone: stomp_zone.set_deferred("monitoring", false)
	
	if audio_player and death_sound:
		audio_player.stream = death_sound
		audio_player.play()
	
	if is_instance_valid(sprite):
		sprite.modulate = death_flash_color
		var t := create_tween()
		t.tween_property(sprite, "modulate:a", 0.0, death_flash_duration)
		await t.finished
	
	queue_free()


func _on_bounce_area_body_entered(body : Node) -> void:
	if enemy_type == "Sproingy" and body.is_in_group("player"):
		body.velocity.y = -1200.0
		print("Bounce!")


func _on_stomp_zone_body_entered(body: Node) -> void:
	if is_dead:
		return
	if not body.is_in_group("player"):
		return
	_player_in_zone = body
	_try_stomp(body)


func _on_stomp_zone_body_exited(body: Node) -> void:
	if body == _player_in_zone:
		_player_in_zone = null


func _try_stomp(body: Node) -> void:
	if is_dead:
		return
	if body == null or not is_instance_valid(body):
		return
	if not body is CharacterBody2D:
		return
	
	var cb := body as CharacterBody2D
	var falling_now : bool = cb.velocity.y > 5.0
	var was_falling : bool = false
	if cb.has_method("was_falling_last_frame"):
		was_falling = cb.was_falling_last_frame(5.0)
	if not falling_now and not was_falling:
		return
	
	cb.velocity.y = stomp_bounce_force
	if body.has_method("on_stomped_by_enemy"):
		body.on_stomped_by_enemy()
	take_hit("stomp", body.global_position)
	_player_in_zone = null


func is_stomp_position(pos: Vector2) -> bool:
	var half_w : float = 16.0
	var half_h : float = 16.0
	if is_instance_valid(collision_shape) and collision_shape.shape is RectangleShape2D:
		var r := collision_shape.shape as RectangleShape2D
		half_w = r.size.x * 0.5
		half_h = r.size.y * 0.5
	elif sprite and sprite.sprite_frames:
		var tex := sprite.sprite_frames.get_frame_texture(sprite.animation, 0)
		if tex:
			half_w = tex.get_width() * 0.5 * abs(sprite.scale.x)
			half_h = tex.get_height() * 0.5 * abs(sprite.scale.y)
	
	var top_edge := global_position.y - half_h
	var bottom_of_window := global_position.y + half_h
	if pos.y < top_edge - 32.0 or pos.y > bottom_of_window:
		return false
	var horizontal_margin : float = 16.0
	if abs(pos.x - global_position.x) > half_w + horizontal_margin:
		return false
	return true


func on_stomped(player: Node) -> void:
	if is_dead:
		return
	if player is CharacterBody2D:
		(player as CharacterBody2D).velocity.y = stomp_bounce_force
	take_hit("stomp", player.global_position)


# 🆕 Resizes the StompZone to cover the TOP slice of the sprite,
# using the sprite's ON-SCREEN size.
# 🆕 Sizes the StompZone to cover the TOP slice of the sprite's LOCAL rect.
# Same rule as collision: use raw texture size in LOCAL space, let the
# parent's scale handle world-space sizing.
# 🦶 StompZone covers the TOP HALF of the visible sprite.
# With the parent (1,1) and sprite scaled 0.1, everything is in world units.
func _fit_stomp_zone_to_sprite() -> void:
	if stomp_zone == null:
		return
	if not is_instance_valid(sprite):
		return
	if not sprite.sprite_frames:
		return
	
	var tex : Texture2D = null
	var anim_name : String = sprite.animation if sprite.animation != "" else "idle"
	if sprite.sprite_frames.has_animation(anim_name) and sprite.sprite_frames.get_frame_count(anim_name) > 0:
		tex = sprite.sprite_frames.get_frame_texture(anim_name, 0)
	elif sprite.sprite_frames.get_animation_names().size() > 0:
		var anims : Array = sprite.sprite_frames.get_animation_names()
		var first_anim : String = String(anims[0])
		if sprite.sprite_frames.get_frame_count(first_anim) > 0:
			tex = sprite.sprite_frames.get_frame_texture(first_anim, 0)
	
	if tex == null:
		return
	
	# World-space size of the visible sprite
	var visible_size : Vector2 = Vector2(tex.get_width(), tex.get_height()) * sprite.global_scale.abs()
	
	# Find or create the zone shape node
	var zone_shape_node : CollisionShape2D = null
	for child in stomp_zone.get_children():
		if child is CollisionShape2D:
			zone_shape_node = child
			break
	if zone_shape_node == null:
		zone_shape_node = CollisionShape2D.new()
		zone_shape_node.name = "StompZoneShape"
		stomp_zone.add_child(zone_shape_node)
	
	# Zone covers the TOP HALF of the sprite
	var zone_width : float = visible_size.x
	var zone_height : float = visible_size.y * 0.5
	# Position: center of the top half = (top edge + zone_height/2)
	# Top edge of sprite is at -visible_size.y/2
	var zone_y_center : float = -(visible_size.y * 0.5) + (zone_height * 0.5)
	
	var shape := RectangleShape2D.new()
	shape.size = Vector2(zone_width, zone_height)
	zone_shape_node.shape = shape
	zone_shape_node.position = Vector2(0, zone_y_center)
	
	print("🦶 [", name, "] StompZone size=", shape.size, " at pos=", zone_shape_node.position,
		" | visible_size=", visible_size,
		" | sprite.global_scale=", sprite.global_scale)


# 🛑 Called by the map maker when this enemy is placed.
func freeze_for_editor() -> void:
	if _spawn_locked:
		_frozen_by_editor = true
		return
	
	velocity = Vector2.ZERO
	if collision_shape:
		collision_shape.disabled = true
	if stomp_zone:
		stomp_zone.monitoring = false
		stomp_zone.monitorable = false
	if bounce_area:
		bounce_area.monitoring = false
		bounce_area.monitorable = false
	process_mode = Node.PROCESS_MODE_DISABLED
	_frozen_by_editor = true
	print("🛑 [", name, "] frozen by map maker")


# 🔓 Called by the map maker when play begins (or when the editor unloads).
func unfreeze_from_editor() -> void:
	if _spawn_locked:
		return
	process_mode = Node.PROCESS_MODE_INHERIT
	if collision_shape:
		collision_shape.disabled = false
	if stomp_zone:
		stomp_zone.monitoring = true
		stomp_zone.monitorable = true
	if bounce_area:
		bounce_area.monitoring = true
		bounce_area.monitorable = true
	velocity = Vector2.ZERO
	_frozen_by_editor = false
	print("🔓 [", name, "] unfrozen by map maker")
