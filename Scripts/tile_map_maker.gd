extends Control

# ==========================================
# THE TILE ATLAS
# ==========================================
# ==========================================
# 📦 SHIPPED STARTING LEVELS
# ==========================================
@export_group("Shipped Levels")
## Folder (inside the project) that holds shipped .tscn levels.
## Scanned recursively at runtime AND via the [Scan] button below.
@export_dir var shipped_levels_folder : String = "res://levels/"
## Auto-populated from shipped_levels_folder. You can also drag individual
## .tscn files in here to override / add to the scan.
@export var shipped_levels : Array[PackedScene] = []
## Optional display names, parallel to shipped_levels.
@export var shipped_level_names : Array[String] = []
## Press to (re)scan shipped_levels_folder and populate shipped_levels.

@export var tile_textures: Array[Texture2D] = []
@export var tile_names: Array[String] = []
@export var tile_collisions: Array[bool] = []
@export var tile_z_indices: Array[int] = []

# ==========================================
# 🚩 GAME FLAGS (Start / End)
# ==========================================
@export_group("Game Flags")
@export var start_flag_color: Color = Color(0.2, 1.0, 0.3, 0.8)  # green
@export var end_flag_color: Color = Color(1.0, 0.2, 0.2, 0.8)    # red
@export var flag_size: Vector2 = Vector2(48, 48)

# ==========================================
# 🔴 SHELL PICKUP
# ==========================================
@export_group("Shell Pickup")
@export var shell_pickup_scene : PackedScene

# ==========================================
# 🌊 WATER TILES
# ==========================================
@export_group("Water Tiles")
@export var water_tile_texture : Texture2D
@export var water_texture_is_transparent : bool = false
@export var water_alpha : float = 0.45
@export var water_tint : Color = Color(0.2, 0.5, 1.0)
@export var water_z_index: int = 10

# ==========================================
# 👾 ENEMY SCENES  (shows under World button)
# ==========================================
@export_group("Enemies")
@export var enemy_scenes : Array[PackedScene] = []
@export var enemy_names : Array[String] = []

# ==========================================
# 🪑 PROPS  (shows under World button)
# ==========================================
@export_group("Props")
@export var prop_scenes : Array[PackedScene] = []
@export var prop_names : Array[String] = []
# ==========================================
# 🖼️ BACKGROUND
# ==========================================
@export_group("Background")
@export var background_scene : PackedScene
@export var background_textures : Array[Texture2D] = []
@export var active_background_index : int = 0
@export var background_size : Vector2 = Vector2(1920, 1080)
@export var background_stretch_to_viewport : bool = false

# ==========================================
# 💾 SAVE / LOAD
# ==========================================
@export_group("Save / Load")
@export var save_and_load : Node    # 💾 child node with the save/load script

# ==========================================
# VIEW SETTINGS
# ==========================================
@export var max_map_width: int = 100
@export var max_map_height: int = 100
@export var joystick_sensitivity: float = 5.0

# 💾 save_folder now lives on save_and_load, but keep this for backward compat
# until you migrate the inspector value. It's read by save_and_load via editor.
@export var save_folder: String = "user://saved_worlds/"

# ==========================================
# SPAWN POINT
# ==========================================
@export_group("Spawn Point")
@export var spawn_point: Node2D

# ==========================================
# DEATH PLANE SETTINGS
# ==========================================
@export_group("Death Plane")
@export var death_plane_margin: float = 50.0
@export var player_group_name: String = "player"
@export var debug_death_plane: bool = true

# ==========================================
# UI CANVAS LAYER
# ==========================================
@export var ui_canvas_layer: CanvasLayer

# ==========================================
# TOOL STATE
# ==========================================
enum ToolMode { PLACE, DELETE_SINGLE, DELETE_PAINT, WATER }
var current_tool: ToolMode = ToolMode.PLACE
var current_tile_index: int = 0
var is_painting: bool = false
var camera: Camera2D
var tile_container: Node2D
var placed_tiles: Dictionary = {}
var placed_shells: Array = []
var placed_enemies: Array = []
var placed_water: Dictionary = {}
var preview_sprite: Sprite2D
var last_placed_position: Vector2 = Vector2.ZERO
var _last_tap_frame : int = -1
# 🚩 Game flag nodes
var start_flag_node: Node2D = null
var end_flag_node: Node2D = null
# 💾 moved to save_and_load — kept here so old references still resolve.
# Sync it whenever save/load changes it, or read directly via save_and_load.
var current_save_file: String = ""
var placed_props : Array = []
# 🪑 Prop mode state
var _placing_prop : bool = false
var _prop_cycle_index : int = 0
# 🔴 Shell mode state
var _placing_shell : bool = false
var _available_shell_names : Array[String] = []
var _shell_cycle_index : int = 0

var _last_drag_frame : int = -1
# 👾 Enemy mode state
var _placing_enemy : bool = false
var _enemy_cycle_index : int = 0

# 🖼️ Background instance
var _background_node : Node = null

var death_plane_y: float = INF
var player_spawn_points: Dictionary = {}

# 💾 save dialog node vars all moved to save_and_load.

var confirm_dialog: ConfirmationDialog

var _water_code_texture : Texture2D = null
func _ready() -> void:
	camera = Camera2D.new()
	_load_default_shipped_level()
	camera.zoom = Vector2(1, 1)
	add_child(camera)
	camera.make_current()
	
	tile_container = Node2D.new()
	add_child(tile_container)
	
	preview_sprite = Sprite2D.new()
	preview_sprite.visible = false
	preview_sprite.centered = false
	preview_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tile_container.add_child(preview_sprite)
	
	if tile_names.size() < tile_textures.size():
		for i in range(tile_textures.size()):
			tile_names.append("Tile " + str(i + 1))
	if tile_collisions.size() < tile_textures.size():
		for i in range(tile_textures.size()):
			tile_collisions.append(true)
	if tile_z_indices.size() < tile_textures.size():
		for i in range(tile_textures.size()):
			tile_z_indices.append(0)
	
	# Auto-fill enemy names if missing
	if enemy_names.size() < enemy_scenes.size():
		for i in range(enemy_names.size(), enemy_scenes.size()):
			var nm := "Enemy " + str(i + 1)
			if enemy_scenes[i] != null:
				nm = enemy_scenes[i].resource_path.get_file().get_basename()
			enemy_names.append(nm)
	
	# 🪑 Auto-fill prop names if missing
	if prop_names.size() < prop_scenes.size():
		for i in range(prop_names.size(), prop_scenes.size()):
			var nm := "Prop " + str(i + 1)
			if prop_scenes[i] != null:
				nm = prop_scenes[i].resource_path.get_file().get_basename()
			prop_names.append(nm)
	
	_ensure_water_texture()
	_ensure_background_node()
	_update_background_map_size()
	
	if ui_canvas_layer:
		_connect_ui_signals()
	else:
		print("⚠️ No UI CanvasLayer assigned!")
	
	_collect_shell_names_from_scene()
	
	# 💾 Initialize save/load child
	if save_and_load:
		save_and_load.setup(self)
	else:
		print("⚠️ No save_and_load node assigned!")
	
	print("🆕 Ready to create or load a world!")
	_capture_initial_player_spawns()
	
	# 🎨 Draw the build-area border
	queue_redraw()
# ==========================================
# 🖼️ BACKGROUND MANAGEMENT
# ==========================================
func _ensure_background_node() -> void:
	if is_instance_valid(_background_node):
		return
	if background_scene == null:
		print("⚠️ No background_scene assigned — editor will have no background")
		return
	
	_background_node = background_scene.instantiate()
	_background_node.name = "BackgroundNode"
	if _background_node is CanvasItem:
		_background_node.z_index = -100
	add_child(_background_node)
	move_child(_background_node, 0)
	
	if "background_textures" in _background_node:
		_background_node.set("background_textures", background_textures)
	if "background_size" in _background_node:
		_background_node.set("background_size", background_size)
	if "fit_mode" in _background_node:
		_background_node.set("fit_mode", 2)
	if "stretch_to_viewport" in _background_node:
		_background_node.set("stretch_to_viewport", background_stretch_to_viewport)
	
	_apply_active_background()
	_update_background_map_size()
	print("🖼️ Background node ready")

func _apply_active_background() -> void:
	if not is_instance_valid(_background_node):
		return
	if "background_textures" in _background_node:
		_background_node.set("background_textures", background_textures)
	if _background_node.has_method("apply_background"):
		_background_node.apply_background(active_background_index)
	if "background_size" in _background_node:
		_background_node.set("background_size", background_size)
		if _background_node.has_method("set_background_size"):
			_background_node.set_background_size(background_size)
	_update_background_map_size()

func _update_background_map_size() -> void:
	if not is_instance_valid(_background_node):
		return
	var tile_size := get_current_texture_size()
	var map_px := Vector2(max_map_width * tile_size.x, max_map_height * tile_size.y)
	if "map_size" in _background_node:
		_background_node.set("map_size", map_px)
	if _background_node.has_method("set_map_size"):
		_background_node.set_map_size(map_px)
	if "fit_mode" in _background_node:
		_background_node.set("fit_mode", 2)

# ==========================================
# 🌊 WATER TEXTURE SETUP
# ==========================================
func _ensure_water_texture() -> void:
	if water_tile_texture != null:
		return
	if _water_code_texture == null:
		_water_code_texture = _make_code_water_texture()
		print("🌊 Generated code water texture (no export assigned)")

func _make_code_water_texture() -> Texture2D:
	var size := 16
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := water_tint
	c.a = water_alpha if not water_texture_is_transparent else 0.5
	img.fill(c)
	return ImageTexture.create_from_image(img)

func _get_water_texture() -> Texture2D:
	if water_tile_texture != null:
		return water_tile_texture
	if _water_code_texture == null:
		_ensure_water_texture()
	return _water_code_texture

# ==========================================
# 🌊 WATER PLACEMENT API
# ==========================================
func set_tool_water() -> void:
	current_tool = ToolMode.WATER
	print("🌊 Tool: WATER")
	if ui_canvas_layer and ui_canvas_layer.has_method("update_tool_info"):
		ui_canvas_layer.update_tool_info(current_tool)
func _place_water_at(world_pos: Vector2) -> void:
	var tex_size = get_current_texture_size()
	var grid_pos = Vector2(
		floor(world_pos.x / tex_size.x) * tex_size.x,
		floor(world_pos.y / tex_size.y) * tex_size.y
	)
	var water_coord = Vector2i(
		int(grid_pos.x / tex_size.x),
		int(grid_pos.y / tex_size.y)
	)
	
	if water_coord.x < 0 or water_coord.x >= max_map_width:
		return
	if water_coord.y < 0 or water_coord.y >= max_map_height:
		return
	
	if placed_water.has(water_coord):
		return
	
	var visual = Sprite2D.new()
	visual.texture = _get_water_texture()
	visual.position = grid_pos
	visual.centered = false
	visual.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	visual.z_index = -1   # 🌊 behind all tiles
	visual.modulate = Color(1, 1, 1, water_alpha if not water_texture_is_transparent else 1.0)
	visual.name = "WaterVisual"
	visual.add_to_group("water", true)
	if visual.texture:
		visual.scale = Vector2(
			tex_size.x / visual.texture.get_width(),
			tex_size.y / visual.texture.get_height()
		)
	tile_container.add_child(visual)
	
	var area := Area2D.new()
	area.name = "WaterArea_" + str(water_coord.x) + "_" + str(water_coord.y)
	area.position = grid_pos + (tex_size / 2.0)
	area.collision_layer = 0
	area.collision_mask = 1
	area.monitoring = true
	area.monitorable = false
	area.add_to_group("water", true)
	
	var shape := RectangleShape2D.new()
	shape.size = tex_size
	var col := CollisionShape2D.new()
	col.shape = shape
	area.add_child(col)
	tile_container.add_child(area)
	
	placed_water[water_coord] = {
		"visual": visual,
		"area": area
	}
	
	last_placed_position = grid_pos
	if ui_canvas_layer and ui_canvas_layer.has_method("update_last_position"):
		ui_canvas_layer.update_last_position(grid_pos)
	
	print("🌊 Placed water at ", water_coord)

func _delete_water_at(world_pos: Vector2) -> bool:
	# 🌊 Always use the WATER tile size for water grid math,
	# regardless of what tool is currently active.
	var tex_size : Vector2
	if water_tile_texture != null:
		tex_size = Vector2(water_tile_texture.get_width(), water_tile_texture.get_height())
	else:
		tex_size = Vector2(32, 32)
	
	var grid_pos = Vector2(
		floor(world_pos.x / tex_size.x) * tex_size.x,
		floor(world_pos.y / tex_size.y) * tex_size.y
	)
	var water_coord = Vector2i(
		int(grid_pos.x / tex_size.x),
		int(grid_pos.y / tex_size.y)
	)
	
	if placed_water.has(water_coord):
		var data = placed_water[water_coord]
		if is_instance_valid(data["visual"]):
			data["visual"].queue_free()
		if is_instance_valid(data["area"]):
			data["area"].queue_free()
		placed_water.erase(water_coord)
		print("🗑️ Deleted water at ", water_coord)
		return true
	return false
# ==========================================
# 🔴 SHELL PLACEMENT MODE
# ==========================================
func _on_shell_mode_activated() -> void:
	_placing_shell = true
	_placing_enemy = false
	print("🐚 Main editor: shell mode ON")

func _on_shell_mode_deactivated() -> void:
	_placing_shell = false
	preview_sprite.visible = false
	print("🐚 Main editor: shell mode OFF")

func _on_shell_cycle_requested() -> void:
	if _available_shell_names.is_empty():
		print("⚠️ No shells available to cycle")
		return
	
	_shell_cycle_index = (_shell_cycle_index + 1) % _available_shell_names.size()
	var current_name = _available_shell_names[_shell_cycle_index]
	print("🐚 Current shell: ", current_name)
	
	if ui_canvas_layer and ui_canvas_layer.has_method("set_shell_cycle_label"):
		ui_canvas_layer.set_shell_cycle_label(current_name)

func _collect_shell_names_from_scene() -> void:
	if shell_pickup_scene == null:
		print("⚠️ shell_pickup_scene not assigned — shell mode will be empty")
		return
	var temp_instance = shell_pickup_scene.instantiate()
	if "shell_names" in temp_instance:
		_available_shell_names = temp_instance.shell_names.duplicate()
		print("🐚 Shell names found: ", _available_shell_names)
	temp_instance.queue_free()

func _place_shell_at(world_pos: Vector2) -> void:
	if shell_pickup_scene == null:
		print("⚠️ shell_pickup_scene not assigned!")
		return
	
	var shell = shell_pickup_scene.instantiate()
	
	if not _available_shell_names.is_empty():
		var current_name = _available_shell_names[_shell_cycle_index]
		_try_set_shell_name(shell, current_name)
	
	if shell is Node2D:
		shell.global_position = world_pos
	else:
		var pos_node = shell.get_node_or_null("Position")
		if pos_node and pos_node is Node2D:
			pos_node.global_position = world_pos
		else:
			print("⚠️ Shell has no Position node and root is not Node2D")
			return
	
	tile_container.add_child(shell)
	placed_shells.append(shell)
	
	var shell_name_str = "unknown"
	if not _available_shell_names.is_empty():
		shell_name_str = _available_shell_names[_shell_cycle_index]
	
	print("🐚 Placed shell: ", shell_name_str, " at ", world_pos)
	
	if ui_canvas_layer and ui_canvas_layer.has_method("update_last_position"):
		ui_canvas_layer.update_last_position(world_pos)

func _try_set_shell_name(shell_instance: Node, shell_name: String) -> void:
	var all_names = shell_instance.get("shell_names")
	if all_names == null or all_names.is_empty():
		print("⚠️ Shell instance has no 'shell_names' — cannot pick shell")
		return

	var idx = all_names.find(shell_name)
	if idx < 0:
		print("⚠️ Shell name '", shell_name, "' not found in ", all_names)
		return

	if "current_shell_index" in shell_instance:
		shell_instance.set("current_shell_index", idx)
	else:
		print("⚠️ Shell has no 'current_shell_index' — cannot force texture")

	if "randomize_on_spawn" in shell_instance:
		shell_instance.set("randomize_on_spawn", false)

# ==========================================
# 👾 ENEMY PLACEMENT MODE
# ==========================================
func _on_enemy_mode_activated() -> void:
	_placing_enemy = true
	_placing_shell = false
	print("👾 Main editor: enemy mode ON")

func _on_enemy_mode_deactivated() -> void:
	_placing_enemy = false
	preview_sprite.visible = false
	print("👾 Main editor: enemy mode OFF")

func _on_enemy_cycle_requested() -> void:
	if enemy_scenes.is_empty():
		print("⚠️ No enemy scenes assigned")
		return
	
	_enemy_cycle_index = (_enemy_cycle_index + 1) % enemy_scenes.size()
	var current_name := _get_enemy_name(_enemy_cycle_index)
	print("👾 Current enemy: ", current_name)
	
	if ui_canvas_layer and ui_canvas_layer.has_method("set_enemy_cycle_label"):
		ui_canvas_layer.set_enemy_cycle_label(current_name)

func _get_enemy_name(index: int) -> String:
	if index < 0 or index >= enemy_scenes.size():
		return "none"
	if index < enemy_names.size() and not enemy_names[index].is_empty():
		return enemy_names[index]
	var scene := enemy_scenes[index]
	if scene != null:
		return scene.resource_path.get_file().get_basename()
	return "Enemy " + str(index + 1)
func _place_enemy_at(world_pos: Vector2) -> void:
	if enemy_scenes.is_empty():
		print("⚠️ No enemy scenes assigned!")
		return
	if _enemy_cycle_index < 0 or _enemy_cycle_index >= enemy_scenes.size():
		print("⚠️ Enemy cycle index out of range")
		return
	
	var scene := enemy_scenes[_enemy_cycle_index]
	if scene == null:
		print("⚠️ Enemy scene at index ", _enemy_cycle_index, " is null")
		return
	
	var enemy = scene.instantiate()
	
	if enemy is Node2D:
		enemy.global_position = world_pos
	else:
		var pos_node = enemy.get_node_or_null("Position")
		if pos_node and pos_node is Node2D:
			pos_node.global_position = world_pos
		else:
			print("⚠️ Enemy has no Position node and root is not Node2D")
			enemy.queue_free()
			return
	
	tile_container.add_child(enemy)
	
	# 🛑 NEW: Freeze the enemy so it doesn't move while we're editing
	if enemy.has_method("freeze_for_editor"):
		enemy.freeze_for_editor()
	
	placed_enemies.append(enemy)
	
	print("👾 Placed enemy: ", _get_enemy_name(_enemy_cycle_index), " at ", world_pos)
	
	if ui_canvas_layer and ui_canvas_layer.has_method("update_last_position"):
		ui_canvas_layer.update_last_position(world_pos)

func _delete_enemy_at(world_pos: Vector2) -> bool:
	for i in range(placed_enemies.size() - 1, -1, -1):
		var enemy = placed_enemies[i]
		if not is_instance_valid(enemy):
			placed_enemies.remove_at(i)
			continue
		
		var enemy_pos := Vector2.ZERO
		if enemy is Node2D:
			enemy_pos = (enemy as Node2D).global_position
		else:
			var pos_node = enemy.get_node_or_null("Position")
			if pos_node is Node2D:
				enemy_pos = (pos_node as Node2D).global_position
			else:
				continue
		
		if enemy_pos.distance_to(world_pos) <= 48.0:
			enemy.queue_free()
			placed_enemies.remove_at(i)
			print("🗑️ Deleted placed enemy")
			return true
	return false

# ==========================================
# SPAWN / DEATH PLANE
# ==========================================
func _capture_initial_player_spawns() -> void:
	# 🚩 If a start flag exists, use it as the spawn point for all players.
	var spawn_override : Vector2 = Vector2.ZERO
	var has_flag_spawn : bool = is_instance_valid(start_flag_node)
	if has_flag_spawn:
		spawn_override = start_flag_node.global_position
		print("🚩 Using Start Flag as spawn point: ", spawn_override)
	
	for p in get_tree().get_nodes_in_group(player_group_name):
		if not is_instance_valid(p):
			continue
		if has_flag_spawn:
			p.global_position = spawn_override
		player_spawn_points[p] = p.global_position

func _process(_delta: float) -> void:
	for p in get_tree().get_nodes_in_group(player_group_name):
		if not is_instance_valid(p):
			continue
		if not player_spawn_points.has(p):
			player_spawn_points[p] = p.global_position
		if p.global_position.y > death_plane_y:
			respawn_player(p)
func respawn_player(player: Node) -> void:
	if not is_instance_valid(player):
		return
	var spawn_pos : Vector2 = player_spawn_points.get(player, Vector2.ZERO)
	
	# 🚩 Fallback: if we somehow lost the spawn, use the start flag
	if spawn_pos == Vector2.ZERO and is_instance_valid(start_flag_node):
		spawn_pos = start_flag_node.global_position
	
	player.global_position = spawn_pos
	if player is CharacterBody2D:
		player.velocity = Vector2.ZERO
	if player.has_method("on_respawn"):
		player.on_respawn()
	if debug_death_plane:
		print("☠️ Player respawned at ", spawn_pos, " (death plane y = ", death_plane_y, ")")

func set_respawn_point(player: Node, pos: Vector2) -> void:
	player_spawn_points[player] = pos

func get_death_plane_y() -> float:
	return death_plane_y

func _recalculate_death_plane() -> void:
	var lowest_y: float = -INF
	var found_collision_tile: bool = false
	
	for coord in placed_tiles.keys():
		var data = placed_tiles[coord]
		if data["collision"] == null:
			continue
		var tex_index: int = data["texture_index"]
		var tex_size := get_texture_size_by_index(tex_index)
		var bottom_y = (coord.y * tex_size.y) + tex_size.y
		if bottom_y > lowest_y:
			lowest_y = bottom_y
			found_collision_tile = true
	
	var new_death_y: float
	if not found_collision_tile:
		new_death_y = INF
	else:
		new_death_y = lowest_y + death_plane_margin
	
	if new_death_y != death_plane_y:
		death_plane_y = new_death_y
		if debug_death_plane:
			print("📉 Death plane recalculated: y = ", death_plane_y)

# ==========================================
# TEXTURE SIZE HELPERS
# ==========================================
func get_current_texture_size() -> Vector2:
	# 🌊 If we're using the water tool, return the water tile size instead
	# of the palette tile size. This makes water placement consistent no
	# matter what tile is currently selected.
	if current_tool == ToolMode.WATER:
		if water_tile_texture != null:
			return Vector2(water_tile_texture.get_width(), water_tile_texture.get_height())
		return Vector2(32, 32)
	
	if tile_textures.is_empty() or current_tile_index >= tile_textures.size():
		return Vector2(32, 32)
	var tex = tile_textures[current_tile_index]
	if tex == null:
		return Vector2(32, 32)
	return Vector2(tex.get_width(), tex.get_height())

func get_texture_size_by_index(index: int) -> Vector2:
	if tile_textures.is_empty() or index >= tile_textures.size():
		return Vector2(32, 32)
	var tex = tile_textures[index]
	if tex == null:
		return Vector2(32, 32)
	return Vector2(tex.get_width(), tex.get_height())

func get_z_index_by_index(index: int) -> int:
	if tile_z_indices.is_empty() or index >= tile_z_indices.size():
		return 0
	return tile_z_indices[index]

# ==========================================
# UI CONNECTIONS
# ==========================================
# ==========================================
# UI CONNECTIONS
# ==========================================
func _connect_ui_signals() -> void:
	var ui_controller = ui_canvas_layer
	if ui_controller:
		ui_controller.tile_selected.connect(_on_tile_selected)
		ui_controller.zoom_changed.connect(_on_zoom_changed)
		ui_controller.tool_changed.connect(_on_tool_changed)
		ui_controller.undo_pressed.connect(_undo_last_place)
		ui_controller.save_pressed.connect(_on_save_pressed)         # 💾 routed to save_and_load
		ui_controller.world_material_selected.connect(_on_world_material_selected)
		ui_controller.delete_all_pressed.connect(_delete_all_tiles)
		ui_controller.joystick_dragged.connect(_on_joystick_dragged)
		ui_controller.joystick_released.connect(_on_joystick_released)
		ui_controller.shell_mode_activated.connect(_on_shell_mode_activated)
		ui_controller.shell_mode_deactivated.connect(_on_shell_mode_deactivated)
		ui_controller.shell_cycle_requested.connect(_on_shell_cycle_requested)
		ui_controller.enemy_selected.connect(_on_enemy_selected)     # 👾 single signal
		# 🪑 Props
		ui_controller.prop_mode_activated.connect(_on_prop_mode_activated)
		ui_controller.prop_mode_deactivated.connect(_on_prop_mode_deactivated)
		ui_controller.prop_cycle_requested.connect(_on_prop_cycle_requested)
		ui_controller.place_start_flag_pressed.connect(_on_place_start_flag_requested)
		ui_controller.place_end_flag_pressed.connect(_on_place_end_flag_requested)
		ui_controller.prop_selected.connect(_on_prop_selected)
		
		if ui_controller.has_method("update_tile_info"):
			ui_controller.update_tile_info(tile_names, current_tile_index)
		if ui_controller.has_method("update_tool_info"):
			ui_controller.update_tool_info(current_tool)
		print("✅ BuildUI connected!")
	else:
		print("⚠️ BuildUI not found!")

# 💾 Save button is handled by save_and_load now.
func _on_save_pressed() -> void:
	if save_and_load == null:
		print("⚠️ No save_and_load node assigned!")
		return
	
	# Tell save_and_load which folder / prefix to use
	if save_and_load.has_method("set_save_target"):
		save_and_load.set_save_target(current_save_target)
	
	if save_and_load.has_method("show_save_dialog"):
		save_and_load.show_save_dialog()
	else:
		print("⚠️ save_and_load has no show_save_dialog()")

func _on_tile_selected(index: int) -> void:
	current_tile_index = index

func _on_tool_changed(tool: ToolMode) -> void:
	current_tool = tool
	_placing_enemy = false
	_placing_shell = false
	_placing_prop = false
	print("🔧 Tool changed to: ", tool, " | enemy=", _placing_enemy, " shell=", _placing_shell, " prop=", _placing_prop)


func _on_joystick_dragged(offset: Vector2) -> void:
	camera.position += offset

func _on_joystick_released() -> void:
	pass

# ==========================================
# INPUT

func _input(event: InputEvent) -> void:
	if ui_canvas_layer and ui_canvas_layer._pan_mode:
		return
	
	# --- TOUCH (mobile) ---
	if event is InputEventScreenTouch:
		var touch_event = event as InputEventScreenTouch
		if ui_canvas_layer and _is_touching_ui(touch_event.position):
			return
		
		if touch_event.pressed:
			_handle_tool_tap(touch_event.position)
		else:
			is_painting = false
			preview_sprite.visible = false
	
	elif event is InputEventScreenDrag:
		var drag_event = event as InputEventScreenDrag
		if ui_canvas_layer and _is_touching_ui(drag_event.position):
			return
		
		if is_painting:
			_handle_tool_drag(drag_event.position)
	
	# --- MOUSE (desktop/Windows) ---
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if ui_canvas_layer and _is_touching_ui(mb.position):
				return
			if mb.pressed:
				_handle_tool_tap(mb.position)
			else:
				is_painting = false
				preview_sprite.visible = false
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			# Optional: mouse wheel zoom on desktop
			if ui_canvas_layer and ui_canvas_layer.has_method("_on_zoom_in"):
				ui_canvas_layer._on_zoom_in()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if ui_canvas_layer and ui_canvas_layer.has_method("_on_zoom_out"):
				ui_canvas_layer._on_zoom_out()
	
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		# Only react if the left button is held (mouse drag = paint)
		if mm.button_mask & MOUSE_BUTTON_MASK_LEFT:
			if ui_canvas_layer and _is_touching_ui(mm.position):
				return
			if is_painting:
				_handle_tool_drag(mm.position)
func _handle_tool_drag(screen_pos: Vector2) -> void:
	# 🛑 Prevent double-firing from touch + synthesized mouse drag events
	var frame := Engine.get_physics_frames()
	if frame == _last_drag_frame:
		return
	_last_drag_frame = frame
	
	var world_pos = get_canvas_transform().affine_inverse() * screen_pos
	var grid_pos = _snap_to_grid(world_pos)
	
	if _placing_shell or _placing_enemy or _placing_prop:
		return
	
	match current_tool:
		ToolMode.PLACE:
			_place_tile(grid_pos)
		ToolMode.WATER:
			_place_water_at(world_pos)
		ToolMode.DELETE_PAINT:
			_delete_water_at(world_pos)
			_delete_enemy_at(world_pos)
			_delete_prop_at(world_pos)
			_delete_tile(world_pos)
			_update_preview_sprite(grid_pos)

func _is_touching_ui(screen_pos: Vector2) -> bool:
	if ui_canvas_layer and ui_canvas_layer.has_method("_is_mouse_over_ui"):
		# Pass the screen position to the UI layer's function
		return ui_canvas_layer._is_mouse_over_ui(screen_pos)
	return false
func _handle_tool_tap(screen_pos: Vector2) -> void:
	# 🛑 Prevent double-firing from touch + synthesized mouse events
	var frame := Engine.get_physics_frames()
	if frame == _last_tap_frame:
		return
	_last_tap_frame = frame
	
	var world_pos = get_canvas_transform().affine_inverse() * screen_pos
	var grid_pos = _snap_to_grid(world_pos)
	
	if _placing_shell:
		_place_shell_at(world_pos)
		return
	
	if _placing_enemy:
		_place_enemy_at(world_pos)
		return
	
	if _placing_prop:
		_place_prop_at(world_pos)
		return
	
	# 🚩 Game flag placement (one-shot)
	if _placing_start_flag:
		set_start_flag(world_pos)
		_placing_start_flag = false
		return
	
	if _placing_end_flag:
		set_end_flag(world_pos)
		_placing_end_flag = false
		return
	
	match current_tool:
		ToolMode.PLACE:
			_place_tile(grid_pos)
		ToolMode.DELETE_SINGLE:
			if _delete_water_at(world_pos):
				return
			if _delete_enemy_at(world_pos):
				return
			if _delete_prop_at(world_pos):
				return
			_delete_tile(world_pos)
		ToolMode.DELETE_PAINT:
			is_painting = true
			_delete_water_at(world_pos)
			_delete_enemy_at(world_pos)
			_delete_prop_at(world_pos)
			_delete_tile(world_pos)
			preview_sprite.visible = true
			_update_preview_sprite(grid_pos)
		ToolMode.WATER:
			_place_water_at(world_pos)
func _update_preview_sprite(grid_pos: Vector2) -> void:
	if current_tool == ToolMode.WATER:
		var wtex := _get_water_texture()
		if wtex:
			preview_sprite.texture = wtex
			preview_sprite.position = grid_pos
			var ts := get_current_texture_size()
			preview_sprite.scale = Vector2(
				ts.x / wtex.get_width(),
				ts.y / wtex.get_height()
			)
			preview_sprite.z_index = water_z_index
			preview_sprite.modulate = Color(1, 1, 1, water_alpha if not water_texture_is_transparent else 1.0)
		return
	
	if tile_textures.is_empty() or current_tile_index >= tile_textures.size():
		return
		
	var texture = tile_textures[current_tile_index]
	if texture == null:
		return
	
	preview_sprite.texture = texture
	preview_sprite.position = grid_pos
	preview_sprite.scale = Vector2(1, 1)
	preview_sprite.z_index = get_z_index_by_index(current_tile_index)
	preview_sprite.modulate = Color(1, 1, 1, 1)

# ==========================================
# PLACE / DELETE TILES
# ==========================================
func _place_tile(world_pos: Vector2) -> void:
	var grid_pos = _snap_to_grid(world_pos)
	
	var tex_size = get_current_texture_size()
	var tile_coord = Vector2i(
		int(grid_pos.x / tex_size.x),
		int(grid_pos.y / tex_size.y)
	)
	
	if tile_coord.x < 0 or tile_coord.x >= max_map_width:
		return
	if tile_coord.y < 0 or tile_coord.y >= max_map_height:
		return
	
	if tile_textures.is_empty() or current_tile_index >= tile_textures.size():
		print("❌ No texture selected or texture index out of range!")
		return
	
	if placed_tiles.has(tile_coord):
		var existing_tile = placed_tiles[tile_coord]
		if is_instance_valid(existing_tile["visual"]):
			existing_tile["visual"].queue_free()
		if is_instance_valid(existing_tile["collision"]):
			existing_tile["collision"].queue_free()
		placed_tiles.erase(tile_coord)
	
	var visual = Sprite2D.new()
	visual.texture = tile_textures[current_tile_index]
	visual.position = grid_pos
	visual.centered = false
	visual.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	visual.z_index = get_z_index_by_index(current_tile_index)
	tile_container.add_child(visual)
	
	var has_collision = tile_collisions[current_tile_index] if current_tile_index < tile_collisions.size() else true
	var collision_node = null
	if has_collision:
		var body = StaticBody2D.new()
		body.position = grid_pos
		body.z_index = get_z_index_by_index(current_tile_index)
		tile_container.add_child(body)
		
		var shape = RectangleShape2D.new()
		shape.size = tex_size
		
		var col = CollisionShape2D.new()
		col.shape = shape
		body.add_child(col)
		collision_node = body
	
	placed_tiles[tile_coord] = {
		"texture_index": current_tile_index,
		"visual": visual,
		"collision": collision_node
	}
	
	last_placed_position = grid_pos
	if ui_canvas_layer and ui_canvas_layer.has_method("update_last_position"):
		ui_canvas_layer.update_last_position(grid_pos)
	
	_recalculate_death_plane()
func _delete_tile(world_pos: Vector2) -> void:
	# 🚩 Start flag check
	if is_instance_valid(start_flag_node):
		if start_flag_node.global_position.distance_to(world_pos) <= 48.0:
			start_flag_node.queue_free()
			start_flag_node = null
			print("🗑️ Deleted START flag")
			return
	
	# 🏁 End flag check
	if is_instance_valid(end_flag_node):
		if end_flag_node.global_position.distance_to(world_pos) <= 48.0:
			end_flag_node.queue_free()
			end_flag_node = null
			print("🗑️ Deleted END flag")
			return
	
	# Shell check
	for i in range(placed_shells.size() - 1, -1, -1):
		var shell = placed_shells[i]
		if not is_instance_valid(shell):
			placed_shells.remove_at(i)
			continue
		
		var shell_pos := Vector2.ZERO
		if shell is Node2D:
			shell_pos = (shell as Node2D).global_position
		else:
			var pos_node = shell.get_node_or_null("Position")
			if pos_node is Node2D:
				shell_pos = (pos_node as Node2D).global_position
			else:
				continue
		
		if shell_pos.distance_to(world_pos) <= 48.0:
			shell.queue_free()
			placed_shells.remove_at(i)
			print("🗑️ Deleted placed shell")
			return
	
	# Enemy check
	if _delete_enemy_at(world_pos):
		return
	
	# 🪑 Prop check
	if _delete_prop_at(world_pos):
		return
	
	var tex_size = get_current_texture_size()
	var grid_pos = Vector2(
		floor(world_pos.x / tex_size.x) * tex_size.x,
		floor(world_pos.y / tex_size.y) * tex_size.y
	)
	var tile_coord = Vector2i(
		int(grid_pos.x / tex_size.x),
		int(grid_pos.y / tex_size.y)
	)
	
	if placed_tiles.has(tile_coord):
		var data = placed_tiles[tile_coord]
		
		if is_instance_valid(data["visual"]):
			data["visual"].queue_free()
		if is_instance_valid(data["collision"]):
			data["collision"].queue_free()
			
		placed_tiles.erase(tile_coord)
		_recalculate_death_plane()
		print("🗑️ Deleted tile at ", tile_coord)

# 💾 Called by save_and_load before it loads a fresh level
func _delete_all_tiles() -> void:
	for coord in placed_tiles.keys():
		var data = placed_tiles[coord]
		if is_instance_valid(data["visual"]):
			data["visual"].queue_free()
		if is_instance_valid(data["collision"]):
			data["collision"].queue_free()
	placed_tiles.clear()
	
	for shell in placed_shells:
		if is_instance_valid(shell):
			shell.queue_free()
	placed_shells.clear()
	
	for enemy in placed_enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	placed_enemies.clear()
	
	# 🪑 Props
	for prop in placed_props:
		if is_instance_valid(prop):
			prop.queue_free()
	placed_props.clear()
	
	for coord in placed_water.keys():
		var wdata = placed_water[coord]
		if is_instance_valid(wdata["visual"]):
			wdata["visual"].queue_free()
		if is_instance_valid(wdata["area"]):
			wdata["area"].queue_free()
	placed_water.clear()
	
	# 🚩 Game Flags
	if is_instance_valid(start_flag_node):
		start_flag_node.queue_free()
		start_flag_node = null
	if is_instance_valid(end_flag_node):
		end_flag_node.queue_free()
		end_flag_node = null
	
	last_placed_position = Vector2.ZERO
	if ui_canvas_layer and ui_canvas_layer.has_method("clear_last_position"):
		ui_canvas_layer.clear_last_position()
	
	_recalculate_death_plane()
	print("🗑️ All tiles, shells, enemies, props, water, and flags deleted!")

func _snap_to_grid(world_pos: Vector2) -> Vector2:
	var tex_size = get_current_texture_size()
	return Vector2(
		floor(world_pos.x / tex_size.x) * tex_size.x,
		floor(world_pos.y / tex_size.y) * tex_size.y
	)


func _undo_last_place() -> void:
	if not placed_water.is_empty():
		var last_water_coord = placed_water.keys().back()
		var wdata = placed_water[last_water_coord]
		if is_instance_valid(wdata["visual"]):
			wdata["visual"].queue_free()
		if is_instance_valid(wdata["area"]):
			wdata["area"].queue_free()
		placed_water.erase(last_water_coord)
		print("↩️ Undid last water placement")
		return
	
	if not placed_enemies.is_empty():
		var last_enemy = placed_enemies.pop_back()
		if is_instance_valid(last_enemy):
			last_enemy.queue_free()
			print("↩️ Undid last enemy placement")
			return
	
	# 🪑 Props
	if not placed_props.is_empty():
		var last_prop = placed_props.pop_back()
		if is_instance_valid(last_prop):
			last_prop.queue_free()
			print("↩️ Undid last prop placement")
			return
	
	if not placed_shells.is_empty():
		var last_shell = placed_shells.pop_back()
		if is_instance_valid(last_shell):
			last_shell.queue_free()
			print("↩️ Undid last shell placement")
			return
	
	if placed_tiles.is_empty():
		return
	
	var last_coord = placed_tiles.keys().back()
	var data = placed_tiles[last_coord]
	if is_instance_valid(data["visual"]):
		data["visual"].queue_free()
	if is_instance_valid(data["collision"]):
		data["collision"].queue_free()
	placed_tiles.erase(last_coord)
	
	if not placed_tiles.is_empty():
		var new_last_coord = placed_tiles.keys().back()
		var new_last_data = placed_tiles[new_last_coord]
		var new_last_pos = new_last_data["visual"].position
		last_placed_position = new_last_pos
		if ui_canvas_layer and ui_canvas_layer.has_method("update_last_position"):
			ui_canvas_layer.update_last_position(new_last_pos)
	else:
		last_placed_position = Vector2.ZERO
		if ui_canvas_layer and ui_canvas_layer.has_method("clear_last_position"):
			ui_canvas_layer.clear_last_position()
	
	_recalculate_death_plane()

# ==========================================
# UTILITIES
# ==========================================
func _set_owner_recursive(node: Node, owner: Node) -> void:
	node.owner = owner
	for child in node.get_children():
		_set_owner_recursive(child, owner)

func _on_zoom_changed(new_zoom: float) -> void:
	if camera:
		camera.zoom = Vector2(new_zoom, new_zoom)

func _on_world_material_selected(material_id: String) -> void:
	match material_id:
		"water":
			set_tool_water()
		"props":
			_on_prop_mode_activated()
		_:
			print("⚠️ Unknown world material: ", material_id)

# ==========================================
# 👾 ENEMY SELECTION (from UI popup)
# ==========================================
func _on_enemy_selected(scene_index: int) -> void:
	if scene_index < 0 or scene_index >= enemy_scenes.size():
		print("⚠️ Enemy index out of range: ", scene_index)
		return
	
	_enemy_cycle_index = scene_index
	_placing_enemy = true
	_placing_shell = false
	
	var enemy_name := _get_enemy_name(scene_index)
	print("👾 Enemy placement ON — selected: ", enemy_name)


# ==========================================
# SAVE MODE
# ==========================================
enum SaveTarget { NORMAL, GITHUB_EXPORT }
var current_save_target : SaveTarget = SaveTarget.NORMAL

func set_save_target(target: SaveTarget) -> void:
	current_save_target = target
	print("💾 Save target set to: ", target)


func _on_prop_mode_activated() -> void:
	_placing_prop = true
	_placing_enemy = false
	_placing_shell = false
	print("🪑 Main editor: prop mode ON")

func _on_prop_mode_deactivated() -> void:
	_placing_prop = false
	preview_sprite.visible = false
	print("🪑 Main editor: prop mode OFF")

func _on_prop_cycle_requested() -> void:
	if prop_scenes.is_empty():
		print("⚠️ No prop scenes assigned")
		return
	_prop_cycle_index = (_prop_cycle_index + 1) % prop_scenes.size()
	var current_name := _get_prop_name(_prop_cycle_index)
	print("🪑 Current prop: ", current_name)
	if ui_canvas_layer and ui_canvas_layer.has_method("set_prop_cycle_label"):
		ui_canvas_layer.set_prop_cycle_label(current_name)

func _get_prop_name(index: int) -> String:
	if index < 0 or index >= prop_scenes.size():
		return "none"
	if index < prop_names.size() and not prop_names[index].is_empty():
		return prop_names[index]
	var scene := prop_scenes[index]
	if scene != null:
		return scene.resource_path.get_file().get_basename()
	return "Prop " + str(index + 1)
func _place_prop_at(world_pos: Vector2) -> void:
	if prop_scenes.is_empty():
		print("⚠️ No prop scenes assigned!")
		return
	if _prop_cycle_index < 0 or _prop_cycle_index >= prop_scenes.size():
		print("⚠️ Prop cycle index out of range")
		return
	var scene := prop_scenes[_prop_cycle_index]
	if scene == null:
		print("⚠️ Prop scene at index ", _prop_cycle_index, " is null")
		return

	var prop = scene.instantiate()

	# 🪑 Snap to the tile grid so props sit flush with placed tiles
	var snapped_pos := _snap_to_grid(world_pos)

	# 💾 Tag with which scene index this came from, so save/load can find it again
	prop.set_meta("prop_scene_index", _prop_cycle_index)

	if prop is Node2D:
		prop.global_position = snapped_pos
	else:
		var pos_node = prop.get_node_or_null("Position")
		if pos_node and pos_node is Node2D:
			pos_node.global_position = snapped_pos
		else:
			print("⚠️ Prop has no Position node and root is not Node2D")
			prop.queue_free()
			return

	tile_container.add_child(prop)
	placed_props.append(prop)

	print("🪑 Placed prop: ", _get_prop_name(_prop_cycle_index), " at ", snapped_pos)

	if ui_canvas_layer and ui_canvas_layer.has_method("update_last_position"):
		ui_canvas_layer.update_last_position(snapped_pos)

func _delete_prop_at(world_pos: Vector2) -> bool:
	for i in range(placed_props.size() - 1, -1, -1):
		var prop = placed_props[i]
		if not is_instance_valid(prop):
			placed_props.remove_at(i)
			continue
		var prop_pos := Vector2.ZERO
		if prop is Node2D:
			prop_pos = (prop as Node2D).global_position
		else:
			var pos_node = prop.get_node_or_null("Position")
			if pos_node is Node2D:
				prop_pos = (pos_node as Node2D).global_position
			else:
				continue
		if prop_pos.distance_to(world_pos) <= 48.0:
			prop.queue_free()
			placed_props.remove_at(i)
			print("🗑️ Deleted placed prop")
			return true
	return false

func _on_prop_selected(scene_index: int) -> void:
	if scene_index < 0 or scene_index >= prop_scenes.size():
		print("⚠️ Prop index out of range: ", scene_index)
		return
	_prop_cycle_index = scene_index
	_placing_prop = true
	_placing_enemy = false
	_placing_shell = false
	print("🪑 Prop placement ON — selected: ", _get_prop_name(scene_index))


# ==========================================
# 🎨 BUILD AREA BORDER
# ==========================================
func _draw() -> void:
	var tex_size := get_current_texture_size()
	if tex_size.x <= 0 or tex_size.y <= 0:
		return
	
	var total_w : float = max_map_width * tex_size.x
	var total_h : float = max_map_height * tex_size.y
	
	# Draw a border around the whole buildable area, in world space.
	# Because this Control's _draw() runs in its own local space, we need
	# to draw relative to its transform. Since the Control is the whole
	# editor scene root, its origin is (0, 0), matching the map.
	draw_rect(Rect2(Vector2.ZERO, Vector2(total_w, total_h)), Color(0.5, 0.75, 1.0, 0.25), false, 3.0)
	queue_redraw()


# ==========================================
# 🎥 CAMERA BOUNDS QUERY
# Called by the player to find the nearest solid tile edges around them.
# ==========================================
func get_camera_bounds_for_position(world_pos: Vector2, scan_tiles: int = 8) -> Dictionary:
	var result := {
		"left":   -INF,   # nearest solid tile's LEFT edge (you cannot see past this on the left)
		"right":  INF,    # nearest solid tile's RIGHT edge
		"top":    -INF,   # nearest solid tile's TOP edge
		"bottom": INF     # nearest solid tile's BOTTOM edge
	}
	
	if placed_tiles.is_empty():
		return result
	
	var ts := get_current_texture_size()
	if ts.x <= 0 or ts.y <= 0:
		return result
	
	# Convert player's position into tile coords
	var px := int(floor(world_pos.x / ts.x))
	var py := int(floor(world_pos.y / ts.y))
	
	var left_edge    := -INF
	var right_edge   := INF
	var top_edge     := -INF
	var bottom_edge  := INF
	
	# Scan a square around the player for solid tiles
	for ty in range(py - scan_tiles, py + scan_tiles + 1):
		for tx in range(px - scan_tiles, px + scan_tiles + 1):
			var coord := Vector2i(tx, ty)
			if not placed_tiles.has(coord):
				continue
			var data = placed_tiles[coord]
			if data["collision"] == null:
				continue  # decorative tile, ignore
			
			# Tile's world rect
			var tile_left   := tx * ts.x
			var tile_right  := tile_left + ts.x
			var tile_top    := ty * ts.y
			var tile_bottom := tile_top + ts.y
			
			# Left: nearest tile whose RIGHT edge is to our LEFT
			if tile_right <= world_pos.x:
				if tile_right > left_edge:
					left_edge = tile_right
			
			# Right: nearest tile whose LEFT edge is to our RIGHT
			if tile_left >= world_pos.x:
				if tile_left < right_edge:
					right_edge = tile_left
			
			# Top: nearest tile whose BOTTOM edge is ABOVE us
			if tile_bottom <= world_pos.y:
				if tile_bottom > top_edge:
					top_edge = tile_bottom
			
			# Bottom: nearest tile whose TOP edge is BELOW us
			if tile_top >= world_pos.y:
				if tile_top < bottom_edge:
					bottom_edge = tile_top
	
	result["left"]   = left_edge
	result["right"]  = right_edge
	result["top"]    = top_edge
	result["bottom"] = bottom_edge
	return result


# ==========================================
# 🚩 GAME FLAGS API
# ==========================================
func _create_flag_node(flag_color: Color, flag_name: String) -> Node2D:
	var flag := Node2D.new()
	flag.name = flag_name
	
	var visual := ColorRect.new()
	visual.color = flag_color
	visual.size = flag_size
	visual.position = -flag_size * 0.5  # center it on the flag's origin
	visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flag.add_child(visual)
	
	# invisible Area2D so the player can detect "reached end"
	var area := Area2D.new()
	area.name = "Trigger"
	area.collision_layer = 0
	area.collision_mask = 1
	area.monitoring = true
	area.monitorable = false
	area.add_to_group("game_flag", true)
	
	var shape := RectangleShape2D.new()
	shape.size = flag_size
	var col := CollisionShape2D.new()
	col.shape = shape
	area.add_child(col)
	flag.add_child(area)
	
	tile_container.add_child(flag)
	return flag
func set_start_flag(world_pos: Vector2) -> void:
	if is_instance_valid(start_flag_node):
		start_flag_node.queue_free()
	start_flag_node = _create_flag_node(start_flag_color, "StartFlag")
	start_flag_node.global_position = world_pos
	print("🚩 Start flag placed at ", world_pos)
	
	# Re-capture spawns so any existing players snap to the new flag
	_capture_initial_player_spawns()

func set_end_flag(world_pos: Vector2) -> void:
	if is_instance_valid(end_flag_node):
		end_flag_node.queue_free()
	end_flag_node = _create_flag_node(end_flag_color, "EndFlag")
	end_flag_node.global_position = world_pos
	print("🚩 End flag placed at ", world_pos)

func get_start_flag_position() -> Vector2:
	if is_instance_valid(start_flag_node):
		return start_flag_node.global_position
	return Vector2.ZERO

func get_end_flag_position() -> Vector2:
	if is_instance_valid(end_flag_node):
		return end_flag_node.global_position
	return Vector2.ZERO


# ==========================================
# 🚩 FLAG PLACEMENT MODE
# ==========================================
var _placing_start_flag: bool = false
var _placing_end_flag: bool = false

func _on_place_start_flag_requested() -> void:
	_placing_start_flag = true
	_placing_end_flag = false
	_placing_shell = false
	_placing_enemy = false
	_placing_prop = false
	print("🚩 Ready to place START flag — click a tile")

func _on_place_end_flag_requested() -> void:
	_placing_end_flag = true
	_placing_start_flag = false
	_placing_shell = false
	_placing_enemy = false
	_placing_prop = false
	print("🏁 Ready to place END flag — click a tile")


func _load_default_shipped_level() -> void:
	if shipped_levels.is_empty():
		return
	load_shipped_level(0)

func load_shipped_level(index: int) -> void:
	if index < 0 or index >= shipped_levels.size():
		return
	var scene := shipped_levels[index]
	if scene == null:
		return
	_delete_all_tiles()
	var instance = scene.instantiate()
	for child in instance.get_children():
		instance.remove_child(child)
		tile_container.add_child(child)
	instance.queue_free()
	_recalculate_death_plane()
