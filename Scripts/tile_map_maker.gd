extends Control

# ==========================================
# THE TILE ATLAS
# ==========================================
@export var tile_textures: Array[Texture2D] = []
@export var tile_names: Array[String] = []
@export var tile_collisions: Array[bool] = []
@export var tile_z_indices: Array[int] = []

# ==========================================
# VIEW SETTINGS
# ==========================================
@export var max_map_width: int = 100
@export var max_map_height: int = 100
@export var joystick_sensitivity: float = 5.0
@export var save_folder: String = "user://saved_worlds/"

# ==========================================
# SPAWN POINT
# ==========================================
@export_group("Spawn Point")
## Drag a Marker2D (or any Node2D) here. Its position is saved into every level
## as a "PlayerSpawn" node, which the MainMenu autoload uses to place the player.
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
enum ToolMode { PLACE, DELETE_SINGLE, DELETE_PAINT }
var current_tool: ToolMode = ToolMode.PLACE
var current_tile_index: int = 0
var is_painting: bool = false
var camera: Camera2D
var tile_container: Node2D
var placed_tiles: Dictionary = {}
var preview_sprite: Sprite2D
var last_placed_position: Vector2 = Vector2.ZERO
var current_save_file: String = ""

var death_plane_y: float = INF
var player_spawn_points: Dictionary = {}

var save_dialog: Window
var save_name_input: LineEdit
var save_new_button: Button
var save_over_button: Button
var delete_selected_button: Button
var delete_all_saves_button: Button
var save_list_container: VBoxContainer
var load_button: Button

# Confirmation popup for delete-all
var confirm_dialog: ConfirmationDialog

func _ready() -> void:
	_ensure_save_folder()
	
	camera = Camera2D.new()
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
	
	if ui_canvas_layer:
		_connect_ui_signals()
	else:
		print("⚠️ No UI CanvasLayer assigned!")

	print("🆕 Ready to create or load a world!")
	_create_save_dialog()
	_create_confirm_dialog()
	_capture_initial_player_spawns()

func _capture_initial_player_spawns() -> void:
	for p in get_tree().get_nodes_in_group(player_group_name):
		if is_instance_valid(p):
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
	var spawn_pos: Vector2 = player_spawn_points.get(player, Vector2.ZERO)
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

func _ensure_save_folder() -> void:
	var dir = DirAccess.open("user://")
	if not dir.dir_exists(save_folder):
		dir.make_dir(save_folder)
		print("📁 Created save folder: ", save_folder)

# ==========================================
# SAVE DIALOG
# ==========================================
func _create_save_dialog() -> void:
	save_dialog = Window.new()
	save_dialog.title = "Save/Load World"
	save_dialog.size = Vector2(500, 420)
	save_dialog.visible = false
	save_dialog.exclusive = true
	save_dialog.min_size = Vector2(450, 380)
	save_dialog.close_requested.connect(_on_save_dialog_closed)
	add_child(save_dialog)
	
	var main_vbox = VBoxContainer.new()
	main_vbox.anchor_right = 1.0
	main_vbox.anchor_bottom = 1.0
	main_vbox.offset_right = -10
	main_vbox.offset_bottom = -10
	main_vbox.offset_left = 10
	main_vbox.offset_top = 10
	save_dialog.add_child(main_vbox)
	
	var name_label = Label.new()
	name_label.text = "Level Name:"
	main_vbox.add_child(name_label)
	
	save_name_input = LineEdit.new()
	save_name_input.placeholder_text = "Enter level name..."
	main_vbox.add_child(save_name_input)
	
	main_vbox.add_child(HSeparator.new())
	
	# --- Row 1: Save/Load buttons ---
	var button_hbox = HBoxContainer.new()
	button_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(button_hbox)
	
	save_new_button = Button.new()
	save_new_button.text = "Save New World"
	save_new_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_new_button.pressed.connect(_on_save_new_pressed)
	button_hbox.add_child(save_new_button)
	
	save_over_button = Button.new()
	save_over_button.text = "Save Over"
	save_over_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_over_button.pressed.connect(_on_save_over_pressed)
	button_hbox.add_child(save_over_button)
	
	load_button = Button.new()
	load_button.text = "Load World"
	load_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	load_button.pressed.connect(_on_load_pressed)
	button_hbox.add_child(load_button)
	
	# --- Row 2: Delete selected / Delete all ---
	var delete_hbox = HBoxContainer.new()
	delete_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(delete_hbox)
	
	delete_selected_button = Button.new()
	delete_selected_button.text = "🗑️ Delete Selected"
	delete_selected_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	delete_selected_button.pressed.connect(_on_delete_selected_pressed)
	delete_hbox.add_child(delete_selected_button)
	
	delete_all_saves_button = Button.new()
	delete_all_saves_button.text = "🗑️ Delete All"
	delete_all_saves_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	delete_all_saves_button.pressed.connect(_on_delete_all_saves_pressed)
	delete_hbox.add_child(delete_all_saves_button)
	
	main_vbox.add_child(HSeparator.new())
	
	var saves_label = Label.new()
	saves_label.text = "Available Saves:"
	main_vbox.add_child(saves_label)
	
	var scroll_container = ScrollContainer.new()
	scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(scroll_container)
	
	save_list_container = VBoxContainer.new()
	save_list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_container.add_child(save_list_container)
	
	_refresh_save_list()

# ==========================================
# CONFIRMATION DIALOG (for Delete All)
# ==========================================
func _create_confirm_dialog() -> void:
	confirm_dialog = ConfirmationDialog.new()
	confirm_dialog.title = "Are you sure?"
	confirm_dialog.dialog_text = "This will permanently delete ALL saved worlds. Continue?"
	confirm_dialog.ok_button_text = "Delete All"
	confirm_dialog.cancel_button_text = "Cancel"
	confirm_dialog.confirmed.connect(_on_delete_all_saves_confirmed)
	add_child(confirm_dialog)

func _refresh_save_list() -> void:
	for child in save_list_container.get_children():
		child.queue_free()
	
	var saves = []
	var dir = DirAccess.open(save_folder)
	if dir:
		dir.list_dir_begin()
		var file = dir.get_next()
		while file != "":
			if file.ends_with(".tscn"):
				saves.append(file)
			file = dir.get_next()
		dir.list_dir_end()
	
	if saves.is_empty():
		var no_saves = Label.new()
		no_saves.text = "No saved worlds found"
		no_saves.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		no_saves.modulate = Color.GRAY
		save_list_container.add_child(no_saves)
	else:
		for save_file in saves:
			# Row = [Save Button] [Delete Button]
			var row = HBoxContainer.new()
			row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			save_list_container.add_child(row)
			
			var save_button = Button.new()
			save_button.text = save_file
			save_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			save_button.set_meta("filename", save_file)
			save_button.pressed.connect(_on_save_selected.bind(save_button))
			row.add_child(save_button)
			
			var row_delete = Button.new()
			row_delete.text = "🗑️"
			row_delete.custom_minimum_size = Vector2(40, 0)
			row_delete.tooltip_text = "Delete this save"
			row_delete.set_meta("filename", save_file)
			row_delete.pressed.connect(_on_delete_save_button_pressed.bind(row_delete))
			row.add_child(row_delete)

func _on_save_selected(button: Button) -> void:
	var filename = button.get_meta("filename")
	if filename:
		save_name_input.text = filename

func _on_save_dialog_closed() -> void:
	save_dialog.visible = false

# ==========================================
# SAVE / LOAD HANDLERS
# ==========================================
func _on_save_new_pressed() -> void:
	var level_name = save_name_input.text.strip_edges()
	if level_name.is_empty():
		level_name = "new_level_" + str(int(Time.get_unix_time_from_system()))
	
	if not level_name.ends_with(".tscn"):
		level_name += ".tscn"
	
	var full_path = save_folder + level_name
	_save_scene(full_path)
	current_save_file = full_path
	save_dialog.visible = false
	_refresh_save_list()
	print("✅ Saved new world: ", full_path)

func _on_save_over_pressed() -> void:
	var level_name = save_name_input.text.strip_edges()
	if level_name.is_empty():
		print("⚠️ No level selected to save over")
		return
	
	if not level_name.ends_with(".tscn"):
		level_name += ".tscn"
	
	var full_path = save_folder + level_name
	_save_scene(full_path)
	current_save_file = full_path
	save_dialog.visible = false
	_refresh_save_list()
	print("✅ Saved over: ", full_path)

func _on_load_pressed() -> void:
	var level_name = save_name_input.text.strip_edges()
	if level_name.is_empty():
		print("⚠️ No level selected to load")
		return
	
	if not level_name.ends_with(".tscn"):
		level_name += ".tscn"
	
	var full_path = save_folder + level_name
	_load_world(full_path)
	save_dialog.visible = false
	print("🔄 Loaded world: ", full_path)

# ==========================================
# DELETE HANDLERS
# ==========================================
func _on_delete_selected_pressed() -> void:
	var level_name = save_name_input.text.strip_edges()
	if level_name.is_empty():
		print("⚠️ No level selected to delete")
		return
	
	if not level_name.ends_with(".tscn"):
		level_name += ".tscn"
	
	var full_path = save_folder + level_name
	_delete_level_data(full_path)
	
	if current_save_file == full_path:
		current_save_file = ""
	
	save_name_input.text = ""
	_refresh_save_list()
	print("🗑️ Deleted: ", full_path)

func _on_delete_save_button_pressed(button: Button) -> void:
	var filename = button.get_meta("filename")
	if not filename:
		return
	
	var full_path = save_folder + filename
	_delete_level_data(full_path)
	
	if current_save_file == full_path:
		current_save_file = ""
	
	var current_input = save_name_input.text.strip_edges()
	if current_input == filename or current_input == filename.replace(".tscn", ""):
		save_name_input.text = ""
	
	_refresh_save_list()
	print("🗑️ Deleted: ", full_path)

func _on_delete_all_saves_pressed() -> void:
	if confirm_dialog:
		confirm_dialog.popup_centered()

func _on_delete_all_saves_confirmed() -> void:
	var dir = DirAccess.open(save_folder)
	if dir == null:
		print("❌ Could not open save folder: ", save_folder)
		return
	
	var deleted_count = 0
	dir.list_dir_begin()
	var file = dir.get_next()
	while file != "":
		if file.ends_with(".tscn"):
			var err = dir.remove(file)
			if err == OK:
				deleted_count += 1
			else:
				print("❌ Failed to delete ", file, " (error ", err, ")")
		file = dir.get_next()
	dir.list_dir_end()
	
	current_save_file = ""
	save_name_input.text = ""
	_refresh_save_list()
	print("🗑️ Deleted all saves (", deleted_count, " files).")

# ==========================================
# TEXTURE SIZE HELPERS
# ==========================================
func get_current_texture_size() -> Vector2:
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
func _connect_ui_signals() -> void:
	var ui_controller = ui_canvas_layer
	if ui_controller:
		ui_controller.tile_selected.connect(_on_tile_selected)
		ui_controller.tool_changed.connect(_on_tool_changed)
		ui_controller.undo_pressed.connect(_undo_last_place)
		ui_controller.save_pressed.connect(_show_save_dialog)
		ui_controller.delete_all_pressed.connect(_delete_all_tiles)
		ui_controller.joystick_dragged.connect(_on_joystick_dragged)
		ui_controller.joystick_released.connect(_on_joystick_released)
		
		if ui_controller.has_method("update_tile_info"):
			ui_controller.update_tile_info(tile_names, current_tile_index)
		if ui_controller.has_method("update_tool_info"):
			ui_controller.update_tool_info(current_tool)
		print("✅ BuildUI connected!")
	else:
		print("⚠️ BuildUI not found!")

func _show_save_dialog() -> void:
	if save_dialog:
		save_dialog.visible = true
		save_dialog.popup_centered()
		save_name_input.text = ""
		_refresh_save_list()

func _on_tile_selected(index: int) -> void:
	current_tile_index = index

func _on_tool_changed(tool: ToolMode) -> void:
	current_tool = tool

func _on_joystick_dragged(offset: Vector2) -> void:
	camera.position += offset

func _on_joystick_released() -> void:
	pass

# ==========================================
# INPUT
# ==========================================
func _input(event: InputEvent) -> void:
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

func _is_touching_ui(screen_pos: Vector2) -> bool:
	if screen_pos.y < 200:
		return true
	return false

func _handle_tool_tap(screen_pos: Vector2) -> void:
	var world_pos = get_canvas_transform().affine_inverse() * screen_pos
	var grid_pos = _snap_to_grid(world_pos)
	
	match current_tool:
		ToolMode.PLACE:
			_place_tile(grid_pos)
		ToolMode.DELETE_SINGLE:
			_delete_tile(grid_pos)
		ToolMode.DELETE_PAINT:
			is_painting = true
			_delete_tile(grid_pos)
			preview_sprite.visible = true
			_update_preview_sprite(grid_pos)

func _handle_tool_drag(screen_pos: Vector2) -> void:
	var world_pos = get_canvas_transform().affine_inverse() * screen_pos
	var grid_pos = _snap_to_grid(world_pos)
	
	match current_tool:
		ToolMode.PLACE:
			_place_tile(grid_pos)
		ToolMode.DELETE_PAINT:
			_delete_tile(grid_pos)
			_update_preview_sprite(grid_pos)

func _update_preview_sprite(grid_pos: Vector2) -> void:
	if tile_textures.is_empty() or current_tile_index >= tile_textures.size():
		return
		
	var texture = tile_textures[current_tile_index]
	if texture == null:
		return
	
	preview_sprite.texture = texture
	preview_sprite.position = grid_pos
	preview_sprite.scale = Vector2(1, 1) 
	preview_sprite.z_index = get_z_index_by_index(current_tile_index)

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
	var tex_size = get_current_texture_size()
	var grid_pos = _snap_to_grid(world_pos)
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

func _delete_all_tiles() -> void:
	for coord in placed_tiles.keys():
		var data = placed_tiles[coord]
		if is_instance_valid(data["visual"]):
			data["visual"].queue_free()
		if is_instance_valid(data["collision"]):
			data["collision"].queue_free()
	
	placed_tiles.clear()
	last_placed_position = Vector2.ZERO
	if ui_canvas_layer and ui_canvas_layer.has_method("clear_last_position"):
		ui_canvas_layer.clear_last_position()
	
	_recalculate_death_plane()
	print("🗑️ All tiles deleted!")

func _snap_to_grid(world_pos: Vector2) -> Vector2:
	var tex_size = get_current_texture_size()
	return Vector2(
		floor(world_pos.x / tex_size.x) * tex_size.x,
		floor(world_pos.y / tex_size.y) * tex_size.y
	)

func _undo_last_place() -> void:
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
# LEVEL RUNTIME SCRIPT
# ==========================================
const LEVEL_RUNTIME_SCRIPT_PATH := "user://saved_worlds/level_runtime.gd"

func _write_level_runtime_script() -> void:
	var code := """extends Node2D

# Auto-generated runtime script for a saved level.
# Handles the death plane and player respawning.

@export var death_plane_margin: float = 50.0
@export var player_group_name: String = "player"
@export var debug_death_plane: bool = true

var death_plane_y: float = INF
var player_spawn_points: Dictionary = {}
var _initial_spawns_captured: bool = false

func _ready() -> void:
	call_deferred("_deferred_setup")

func _deferred_setup() -> void:
	_recalculate_death_plane()
	_capture_player_spawns()
	_initial_spawns_captured = true
	if debug_death_plane:
		print("✅ Level ready | death plane y = ", death_plane_y, " | players: ", get_tree().get_nodes_in_group(player_group_name).size())

func _capture_player_spawns() -> void:
	for p in get_tree().get_nodes_in_group(player_group_name):
		if is_instance_valid(p) and not player_spawn_points.has(p):
			player_spawn_points[p] = p.global_position

func _process(_delta: float) -> void:
	if not _initial_spawns_captured:
		return
	
	for p in get_tree().get_nodes_in_group(player_group_name):
		if not is_instance_valid(p):
			continue
		if not player_spawn_points.has(p):
			player_spawn_points[p] = p.global_position
		if p.global_position.y > death_plane_y:
			respawn_player(p)

func _recalculate_death_plane() -> void:
	var lowest_y: float = -INF
	var found_collision: bool = false
	
	for child in get_children():
		var bottom_y: float = -INF
		if child is StaticBody2D:
			var half_h: float = 0.0
			for sub in child.get_children():
				if sub is CollisionShape2D and sub.shape is RectangleShape2D:
					half_h = sub.shape.size.y * 0.5
					break
			bottom_y = child.global_position.y + half_h
		elif child is Sprite2D and child.texture:
			continue
		else:
			continue
		
		if bottom_y > lowest_y:
			lowest_y = bottom_y
			found_collision = true
	
	if found_collision:
		death_plane_y = lowest_y + death_plane_margin
	else:
		death_plane_y = INF

func respawn_player(player: Node) -> void:
	if not is_instance_valid(player):
		return
	var spawn_pos: Vector2 = player_spawn_points.get(player, Vector2.ZERO)
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
"""
	
	var file = FileAccess.open(LEVEL_RUNTIME_SCRIPT_PATH, FileAccess.WRITE)
	if file:
		file.store_string(code)
		file.close()
		ResourceLoader.load(LEVEL_RUNTIME_SCRIPT_PATH, "GDScript", ResourceLoader.CACHE_MODE_REPLACE)

# ==========================================
# SAVE SCENE
# ==========================================
func _save_scene(path: String, delete_data: bool = false) -> void:
	print("Saving Level Scene to: ", path)
	
	_write_level_runtime_script()
	
	if delete_data:
		_delete_level_data(path)
	
	var root = Node2D.new()
	root.name = "GeneratedLevel"
	add_child(root)
	
	var runtime_script = load(LEVEL_RUNTIME_SCRIPT_PATH)
	if runtime_script:
		root.set_script(runtime_script)
		root.set("death_plane_margin", death_plane_margin)
		root.set("player_group_name", player_group_name)
		root.set("debug_death_plane", debug_death_plane)
	
	# --- Save the spawn point as "PlayerSpawn" inside the level ---
	if is_instance_valid(spawn_point):
		var spawn_marker := Marker2D.new()
		spawn_marker.name = "PlayerSpawn"
		spawn_marker.position = spawn_point.global_position
		root.add_child(spawn_marker)
		print("📍 Saved PlayerSpawn at: ", spawn_marker.position)
	else:
		print("⚠️ No spawn_point assigned — level will have no PlayerSpawn marker.")
	
	for coord in placed_tiles.keys():
		var data = placed_tiles[coord]
		
		var tex_index = data["texture_index"]
		var tex_size = get_texture_size_by_index(tex_index)
		var grid_pos = Vector2(coord.x * tex_size.x, coord.y * tex_size.y)
		
		if tex_index >= tile_textures.size():
			continue
		
		var texture = tile_textures[tex_index]
		var has_collision = tex_index < tile_collisions.size() and tile_collisions[tex_index]
		
		if has_collision:
			var body = StaticBody2D.new()
			body.name = "CollisionBody_" + str(coord.x) + "_" + str(coord.y)
			body.position = grid_pos + (tex_size / 2.0)
			body.z_index = get_z_index_by_index(tex_index)
			
			var visual = Sprite2D.new()
			visual.name = "Tile_" + str(coord.x) + "_" + str(coord.y)
			visual.texture = texture
			visual.centered = false
			visual.position = -tex_size / 2.0
			visual.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			visual.z_index = 0
			body.add_child(visual)
			
			var shape = RectangleShape2D.new()
			shape.size = tex_size
			
			var col = CollisionShape2D.new()
			col.name = "CollisionShape2D"
			col.position = Vector2.ZERO
			col.shape = shape
			body.add_child(col)
			
			root.add_child(body)
		else:
			var visual = Sprite2D.new()
			visual.name = "Tile_" + str(coord.x) + "_" + str(coord.y)
			visual.texture = texture
			visual.centered = false
			visual.position = grid_pos
			visual.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			visual.z_index = get_z_index_by_index(tex_index)
			root.add_child(visual)
	
	_set_owner_recursive(root, root)
	
	var packed_scene = PackedScene.new()
	var error = packed_scene.pack(root)
	
	if error == OK:
		var save_error = ResourceSaver.save(packed_scene, path)
		if save_error == OK:
			print("✅ Level Saved to: ", path)
			print("📊 Total tiles saved: ", placed_tiles.size())
			if delete_data:
				print("🗑️ Old data was deleted before saving.")
		else:
			print("❌ Failed to save file with error code: ", save_error)
	else:
		print("❌ Failed to pack scene with error code: ", error)
	
	root.queue_free()

# ==========================================
# DELETE LEVEL DATA
# ==========================================
func _delete_level_data(path: String) -> void:
	if path.is_empty():
		print("⚠️ Delete skipped: empty path.")
		return
	
	if not FileAccess.file_exists(path):
		print("⚠️ Delete skipped: no file at ", path)
		return
	
	var dir = DirAccess.open(save_folder)
	if dir == null:
		print("❌ Could not open save folder for delete: ", save_folder)
		return
	
	var filename = path.get_file()
	var err = dir.remove(filename)
	if err == OK:
		print("🗑️ Deleted level data: ", path)
	else:
		print("❌ Failed to delete file, error code: ", err)

# ==========================================
# LOAD WORLD
# ==========================================
func _load_world(path: String) -> void:
	_delete_all_tiles()
	
	if not FileAccess.file_exists(path):
		print("❌ No save file found at: ", path)
		return
		
	print("🔄 Loading existing level from: ", path)
	var packed_scene = load(path)
	if packed_scene == null:
		print("❌ Failed to load PackedScene at path: ", path)
		return
		
	var loaded_level = packed_scene.instantiate()
	if loaded_level == null:
		return
		
	add_child(loaded_level)
	await get_tree().process_frame
	
	var max_pos = Vector2.ZERO
	var has_tiles = false
	
	var children_to_process = loaded_level.get_children().duplicate()
	
	for child in children_to_process:
		if child is StaticBody2D:
			var body = child
			var sprite = null
			var collision_shape = null
			
			for sub_child in body.get_children():
				if sub_child is Sprite2D:
					sprite = sub_child
				elif sub_child is CollisionShape2D:
					collision_shape = sub_child
					
			if sprite and sprite.texture:
				var found_index = tile_textures.find(sprite.texture)
				if found_index == -1:
					found_index = 0
					
				var tex_size = get_texture_size_by_index(found_index)
				
				var grid_pos = body.position - (tex_size / 2.0)
				var coord = Vector2i(
					int(round(grid_pos.x / tex_size.x)),
					int(round(grid_pos.y / tex_size.y))
				)
				
				loaded_level.remove_child(body)
				tile_container.add_child(body)
				
				body.position = grid_pos + (tex_size / 2.0)
				body.z_index = get_z_index_by_index(found_index)
				
				sprite.position = -tex_size / 2.0
				sprite.z_index = 0
				
				if collision_shape:
					collision_shape.position = Vector2.ZERO
				
				placed_tiles[coord] = {
					"texture_index": found_index,
					"visual": sprite,
					"collision": body
				}
				
				if grid_pos.x > max_pos.x or grid_pos.y > max_pos.y:
					max_pos = grid_pos
				has_tiles = true
				
		elif child is Sprite2D:
			var sprite = child
			
			if sprite.texture:
				var found_index = tile_textures.find(sprite.texture)
				if found_index == -1:
					found_index = 0
					
				var tex_size = get_texture_size_by_index(found_index)
				var grid_pos = sprite.position
				var coord = Vector2i(
					int(round(grid_pos.x / tex_size.x)),
					int(round(grid_pos.y / tex_size.y))
				)
				
				loaded_level.remove_child(sprite)
				tile_container.add_child(sprite)
				
				sprite.position = grid_pos
				sprite.z_index = get_z_index_by_index(found_index)
				
				placed_tiles[coord] = {
					"texture_index": found_index,
					"visual": sprite,
					"collision": null
				}
				
				if grid_pos.x > max_pos.x or grid_pos.y > max_pos.y:
					max_pos = grid_pos
				has_tiles = true
	
	loaded_level.queue_free()
	
	if has_tiles:
		last_placed_position = max_pos
		if ui_canvas_layer and ui_canvas_layer.has_method("update_last_position"):
			ui_canvas_layer.update_last_position(max_pos)
	else:
		last_placed_position = Vector2.ZERO
		if ui_canvas_layer and ui_canvas_layer.has_method("clear_last_position"):
			ui_canvas_layer.clear_last_position()
	
	current_save_file = path
	_recalculate_death_plane()
	print("✅ World loaded! Total tiles: ", placed_tiles.size())

# ==========================================
# UTILITIES
# ==========================================
func _set_owner_recursive(node: Node, owner: Node) -> void:
	node.owner = owner
	for child in node.get_children():
		_set_owner_recursive(child, owner)
