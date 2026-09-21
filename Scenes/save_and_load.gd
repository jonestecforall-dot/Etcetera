extends Node

# ==========================================
# 💾 SAVE / LOAD
# ==========================================
# This node owns:
#   - save dialog UI
#   - save list UI
#   - confirm dialog
#   - scene packing on save
#   - scene unpacking on load
#   - level_runtime.gd generation
#   - 🆕 exporting worlds into res://worlds/ for git sharing
#
# It reads/writes state on the editor (passed in via setup()).

var editor : Control = null

var save_dialog : Window
var save_name_input : LineEdit
var save_new_button : Button
var save_over_button : Button
var export_project_button : Button
var delete_selected_button : Button
var delete_all_saves_button : Button
var save_list_container : VBoxContainer
var load_button : Button

# 🖼️ Background controls in save dialog
var bg_prev_button : Button
var bg_next_button : Button
var bg_label : Label
var bg_size_x_input : LineEdit
var bg_size_y_input : LineEdit
var bg_apply_button : Button

var confirm_dialog : ConfirmationDialog

var current_save_file : String = ""

const LEVEL_RUNTIME_SCRIPT_PATH := "user://saved_worlds/level_runtime.gd"

# 🆕 Where shared worlds live — inside the project, so they get committed.
const SHARED_WORLDS_FOLDER := "res://worlds/"

# 💾 Save target — where "Save New" and "Save Over" will write.
enum SaveTarget { NORMAL, GITHUB_EXPORT }
var _save_target : int = SaveTarget.NORMAL

# 💾 Folders
const NORMAL_SAVE_FOLDER : String = "user://saved_worlds/"
const GITHUB_SAVE_FOLDER : String = "user://github_exports/"

# ==========================================
# SETUP — called by the editor in _ready()
# ==========================================
func setup(editor_ref: Control) -> void:
	editor = editor_ref
	_ensure_save_folder()
	_ensure_shared_folder()
	_create_save_dialog()
	_create_confirm_dialog()
	print("💾 Save/Load ready")

# ==========================================
# FOLDERS
# ==========================================
func _ensure_save_folder() -> void:
	var root = DirAccess.open("user://")
	if root == null:
		push_warning("save_and_load: cannot open user://")
		return
	for folder in [NORMAL_SAVE_FOLDER, GITHUB_SAVE_FOLDER]:
		if not root.dir_exists(folder):
			root.make_dir(folder)
			print("📁 Created save folder: ", folder)

func _ensure_shared_folder() -> void:
	var dir = DirAccess.open("res://")
	if dir == null:
		push_warning("Save/Load: cannot open res://")
		return
	if not dir.dir_exists("worlds"):
		var err := dir.make_dir("worlds")
		if err == OK:
			print("📁 Created shared worlds folder: ", SHARED_WORLDS_FOLDER)
		else:
			push_warning("Save/Load: failed to create res://worlds/ (err " + str(err) + ")")

# 💾 Returns the folder we should write to for the CURRENT save target.
func _get_save_folder() -> String:
	match _save_target:
		SaveTarget.GITHUB_EXPORT:
			return GITHUB_SAVE_FOLDER
		_:
			return NORMAL_SAVE_FOLDER

# ==========================================
# SAVE DIALOG CONSTRUCTION
# ==========================================
func _create_save_dialog() -> void:
	save_dialog = Window.new()
	save_dialog.title = "Save/Load World"
	save_dialog.size = Vector2(540, 620)
	save_dialog.visible = false
	save_dialog.exclusive = true
	save_dialog.min_size = Vector2(480, 580)
	save_dialog.close_requested.connect(_on_save_dialog_closed)
	add_child(save_dialog)
	
	var main_vbox = VBoxContainer.new()
	main_vbox.anchor_right = 1.0
	main_vbox.anchor_bottom = 1.0
	main_vbox.offset_right = -10
	main_vbox.offset_bottom = -10
	main_vbox.offset_left = 10
	main_vbox.offset_top = 10
	main_vbox.add_theme_constant_override("separation", 8)
	save_dialog.add_child(main_vbox)
	
	var name_label = Label.new()
	name_label.text = "Level Name:"
	main_vbox.add_child(name_label)
	
	save_name_input = LineEdit.new()
	save_name_input.placeholder_text = "Enter level name..."
	main_vbox.add_child(save_name_input)
	
	main_vbox.add_child(HSeparator.new())
	
	# 🖼️ BACKGROUND ROW
	var bg_title = Label.new()
	bg_title.text = "Background:"
	main_vbox.add_child(bg_title)
	
	var bg_row = HBoxContainer.new()
	bg_row.add_theme_constant_override("separation", 6)
	main_vbox.add_child(bg_row)
	
	bg_prev_button = Button.new()
	bg_prev_button.text = "◀"
	bg_prev_button.custom_minimum_size = Vector2(40, 0)
	bg_prev_button.pressed.connect(_on_bg_prev_pressed)
	bg_row.add_child(bg_prev_button)
	
	bg_label = Label.new()
	bg_label.text = "NONE"
	bg_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bg_row.add_child(bg_label)
	
	bg_next_button = Button.new()
	bg_next_button.text = "▶"
	bg_next_button.custom_minimum_size = Vector2(40, 0)
	bg_next_button.pressed.connect(_on_bg_next_pressed)
	bg_row.add_child(bg_next_button)
	
	# 🖼️ SIZE ROW
	var size_row = HBoxContainer.new()
	size_row.add_theme_constant_override("separation", 6)
	main_vbox.add_child(size_row)
	
	var size_label = Label.new()
	size_label.text = "Size:"
	size_row.add_child(size_label)
	
	bg_size_x_input = LineEdit.new()
	bg_size_x_input.placeholder_text = "W"
	bg_size_x_input.custom_minimum_size = Vector2(70, 0)
	bg_size_x_input.text = str(int(editor.background_size.x))
	size_row.add_child(bg_size_x_input)
	
	var size_x_lbl = Label.new()
	size_x_lbl.text = "×"
	size_row.add_child(size_x_lbl)
	
	bg_size_y_input = LineEdit.new()
	bg_size_y_input.placeholder_text = "H"
	bg_size_y_input.custom_minimum_size = Vector2(70, 0)
	bg_size_y_input.text = str(int(editor.background_size.y))
	size_row.add_child(bg_size_y_input)
	
	bg_apply_button = Button.new()
	bg_apply_button.text = "Apply Size"
	bg_apply_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bg_apply_button.pressed.connect(_on_bg_apply_size_pressed)
	size_row.add_child(bg_apply_button)
	
	main_vbox.add_child(HSeparator.new())
	
	# --- SAVE / LOAD BUTTONS ---
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
	
	# 🆕 EXPORT TO PROJECT BUTTON (below the save/load row)
	export_project_button = Button.new()
	export_project_button.text = "📤 Export to Project (git)"
	export_project_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	export_project_button.tooltip_text = "Copies this world into res://worlds/ so it can be committed and shared with the team."
	export_project_button.pressed.connect(_on_export_to_project_pressed)
	main_vbox.add_child(export_project_button)
	
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
	saves_label.text = "Available Saves:   [P] personal   [S] shared (git)"
	main_vbox.add_child(saves_label)
	
	var scroll_container = ScrollContainer.new()
	scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(scroll_container)
	
	save_list_container = VBoxContainer.new()
	save_list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_container.add_child(save_list_container)
	
	_refresh_save_list()
	_refresh_bg_label()

func _create_confirm_dialog() -> void:
	confirm_dialog = ConfirmationDialog.new()
	confirm_dialog.title = "Are you sure?"
	confirm_dialog.dialog_text = "This will permanently delete ALL saved worlds. Continue?"
	confirm_dialog.ok_button_text = "Delete All"
	confirm_dialog.cancel_button_text = "Cancel"
	confirm_dialog.confirmed.connect(_on_delete_all_saves_confirmed)
	add_child(confirm_dialog)

# ==========================================
# SHOW DIALOG — public
# ==========================================
func show_save_dialog() -> void:
	if save_dialog:
		save_dialog.visible = true
		save_dialog.popup_centered()
		save_name_input.text = ""
		_refresh_save_list()
		_refresh_bg_label()

# ==========================================
# SAVE LIST — shows personal + shared
# ==========================================
func _refresh_save_list() -> void:
	for child in save_list_container.get_children():
		child.queue_free()
	
	var personal_saves : Array = []
	var shared_saves : Array = []
	
	# Personal
	var dir = DirAccess.open(NORMAL_SAVE_FOLDER)
	if dir:
		dir.list_dir_begin()
		var file = dir.get_next()
		while file != "":
			if file.ends_with(".tscn"):
				personal_saves.append(file)
			file = dir.get_next()
		dir.list_dir_end()
	
	# 🆕 Shared
	var shared_dir = DirAccess.open(SHARED_WORLDS_FOLDER)
	if shared_dir:
		shared_dir.list_dir_begin()
		var sfile = shared_dir.get_next()
		while sfile != "":
			if sfile.ends_with(".tscn"):
				shared_saves.append(sfile)
			sfile = shared_dir.get_next()
		shared_dir.list_dir_end()
	
	if personal_saves.is_empty() and shared_saves.is_empty():
		var no_saves = Label.new()
		no_saves.text = "No saved worlds found"
		no_saves.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		no_saves.modulate = Color.GRAY
		save_list_container.add_child(no_saves)
		return
	
	if not personal_saves.is_empty():
		_add_section_header("[P] Personal (this device)")
		for save_file in personal_saves:
			_add_save_row(save_file, NORMAL_SAVE_FOLDER, false)
	
	if not shared_saves.is_empty():
		_add_section_header("[S] Shared (in project)")
		for save_file in shared_saves:
			_add_save_row(save_file, SHARED_WORLDS_FOLDER, true)

func _add_section_header(text: String) -> void:
	var lbl = Label.new()
	lbl.text = text
	lbl.modulate = Color(0.75, 0.8, 1.0)
	lbl.add_theme_font_size_override("font_size", 12)
	save_list_container.add_child(lbl)

func _add_save_row(save_file: String, folder: String, is_shared: bool) -> void:
	var row = HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_list_container.add_child(row)
	
	var save_button = Button.new()
	save_button.text = save_file
	save_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_button.set_meta("filename", save_file)
	save_button.set_meta("folder", folder)
	save_button.set_meta("is_shared", is_shared)
	save_button.pressed.connect(_on_save_selected.bind(save_button))
	row.add_child(save_button)
	
	if not is_shared:
		# Personal: allow inline delete
		var row_delete = Button.new()
		row_delete.text = "🗑️"
		row_delete.custom_minimum_size = Vector2(40, 0)
		row_delete.tooltip_text = "Delete this save"
		row_delete.set_meta("filename", save_file)
		row_delete.set_meta("folder", folder)
		row_delete.pressed.connect(_on_delete_save_button_pressed.bind(row_delete))
		row.add_child(row_delete)
	else:
		# Shared: no inline delete (delete via git / file manager)
		var spacer = Control.new()
		spacer.custom_minimum_size = Vector2(40, 0)
		row.add_child(spacer)

# 💾 Clicking a row now sets BOTH the name field AND the save target.
# This is the key fix — Save Over will write to the same folder the row came from.
func _on_save_selected(button: Button) -> void:
	var filename = button.get_meta("filename")
	var is_shared = button.get_meta("is_shared")
	if filename:
		save_name_input.text = filename
	if is_shared != null:
		_save_target = SaveTarget.GITHUB_EXPORT if is_shared else SaveTarget.NORMAL
		print("💾 Save target set to ", ("GITHUB" if is_shared else "NORMAL"), " (from row click)")

func _on_save_dialog_closed() -> void:
	save_dialog.visible = false

# ==========================================
# 🖼️ BACKGROUND DIALOG HANDLERS
# ==========================================
func _refresh_bg_label() -> void:
	if bg_label == null:
		return
	if editor.background_textures.is_empty():
		bg_label.text = "NONE (no textures in array)"
	else:
		var i := clampi(editor.active_background_index, 0, editor.background_textures.size() - 1)
		bg_label.text = "[" + str(i) + "] " + str(editor.background_textures[i].resource_path.get_file())
	if bg_size_x_input and bg_size_y_input:
		bg_size_x_input.text = str(int(editor.background_size.x))
		bg_size_y_input.text = str(int(editor.background_size.y))

func _on_bg_prev_pressed() -> void:
	if editor.background_textures.is_empty():
		return
	editor.active_background_index = (editor.active_background_index - 1 + editor.background_textures.size()) % editor.background_textures.size()
	editor._apply_active_background()
	_refresh_bg_label()

func _on_bg_next_pressed() -> void:
	if editor.background_textures.is_empty():
		return
	editor.active_background_index = (editor.active_background_index + 1) % editor.background_textures.size()
	editor._apply_active_background()
	_refresh_bg_label()

func _on_bg_apply_size_pressed() -> void:
	var w := int(bg_size_x_input.text) if bg_size_x_input else int(editor.background_size.x)
	var h := int(bg_size_y_input.text) if bg_size_y_input else int(editor.background_size.y)
	editor.background_size = Vector2(w, h)
	editor._apply_active_background()
	_refresh_bg_label()
	print("🖼️ Background size set to ", editor.background_size)

# ==========================================
# SAVE / LOAD HANDLERS
# ==========================================
func _on_save_new_pressed() -> void:
	var level_name = save_name_input.text.strip_edges()
	if level_name.is_empty():
		level_name = "new_level_" + str(int(Time.get_unix_time_from_system()))
	
	if not level_name.ends_with(".tscn"):
		level_name += ".tscn"
	
	var full_path = _get_save_folder() + level_name
	save_scene(full_path)
	current_save_file = full_path
	editor.current_save_file = full_path
	save_dialog.visible = false
	_refresh_save_list()
	print("✅ Saved new world to ", full_path)

func _on_save_over_pressed() -> void:
	var level_name = save_name_input.text.strip_edges()
	if level_name.is_empty():
		print("⚠️ No level selected to save over")
		return
	
	if not level_name.ends_with(".tscn"):
		level_name += ".tscn"
	
	var full_path = _get_save_folder() + level_name
	save_scene(full_path)
	current_save_file = full_path
	editor.current_save_file = full_path
	save_dialog.visible = false
	_refresh_save_list()
	print("✅ Saved over ", full_path)

func _on_load_pressed() -> void:
	var level_name = save_name_input.text.strip_edges()
	if level_name.is_empty():
		print("⚠️ No level selected to load")
		return
	
	if not level_name.ends_with(".tscn"):
		level_name += ".tscn"
	
	# Try current target folder first, then the other one as fallback.
	var full_path : String = _get_save_folder() + level_name
	if not FileAccess.file_exists(full_path):
		var other : String = NORMAL_SAVE_FOLDER + level_name if _save_target == SaveTarget.GITHUB_EXPORT else GITHUB_SAVE_FOLDER + level_name
		if FileAccess.file_exists(other):
			full_path = other
		else:
			# Last chance: res://worlds/
			var shared_path : String = SHARED_WORLDS_FOLDER + level_name
			if FileAccess.file_exists(shared_path):
				full_path = shared_path
			else:
				print("❌ Level not found: ", level_name)
				return
	
	load_world(full_path)
	save_dialog.visible = false
	print("🔄 Loaded world: ", full_path)

# ==========================================
# 🆕 EXPORT TO PROJECT — copies a personal/git save into res://worlds/
# ==========================================
func _on_export_to_project_pressed() -> void:
	var level_name = save_name_input.text.strip_edges()
	if level_name.is_empty():
		if current_save_file != "":
			level_name = current_save_file.get_file().replace(".tscn", "")
		else:
			print("⚠️ No level to export (nothing selected and nothing loaded)")
			return
	
	if not level_name.ends_with(".tscn"):
		level_name += ".tscn"
	
	# Source: prefer current target, fall back to other folder
	var source_path : String = _get_save_folder() + level_name
	if not FileAccess.file_exists(source_path):
		var other : String = NORMAL_SAVE_FOLDER + level_name if _save_target == SaveTarget.GITHUB_EXPORT else GITHUB_SAVE_FOLDER + level_name
		if FileAccess.file_exists(other):
			source_path = other
		else:
			print("⚠️ Cannot export: no save named ", level_name)
			return
	
	_ensure_shared_folder()
	var dest_path : String = SHARED_WORLDS_FOLDER + level_name
	
	var src_file = FileAccess.open(source_path, FileAccess.READ)
	if src_file == null:
		print("❌ Failed to open source: ", source_path)
		return
	var bytes = src_file.get_buffer(src_file.get_length())
	src_file.close()
	
	var dst_file = FileAccess.open(dest_path, FileAccess.WRITE)
	if dst_file == null:
		print("❌ Failed to create destination: ", dest_path)
		return
	dst_file.store_buffer(bytes)
	dst_file.close()
	
	print("📤 Exported ", level_name, " to ", dest_path)
	print("   Commit this file to share it with the team.")
	_refresh_save_list()

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
	
	var full_path = _get_save_folder() + level_name
	_delete_level_data(full_path)
	
	if current_save_file == full_path:
		current_save_file = ""
		editor.current_save_file = ""
	
	save_name_input.text = ""
	_refresh_save_list()
	print("🗑️ Deleted: ", full_path)

func _on_delete_save_button_pressed(button: Button) -> void:
	var filename = button.get_meta("filename")
	var folder = button.get_meta("folder")
	if not filename or not folder:
		return
	
	var full_path = folder + filename
	_delete_level_data(full_path)
	
	if current_save_file == full_path:
		current_save_file = ""
		editor.current_save_file = ""
	
	var current_input = save_name_input.text.strip_edges()
	if current_input == filename or current_input == filename.replace(".tscn", ""):
		save_name_input.text = ""
	
	_refresh_save_list()
	print("🗑️ Deleted: ", full_path)

func _on_delete_all_saves_pressed() -> void:
	if save_dialog and save_dialog.visible:
		save_dialog.hide()
	
	if confirm_dialog:
		confirm_dialog.popup_centered()

func _on_delete_all_saves_confirmed() -> void:
	var total_deleted = 0
	for folder in [NORMAL_SAVE_FOLDER, GITHUB_SAVE_FOLDER]:
		var dir = DirAccess.open(folder)
		if dir == null:
			continue
		dir.list_dir_begin()
		var file = dir.get_next()
		while file != "":
			if file.ends_with(".tscn"):
				var err = dir.remove(file)
				if err == OK:
					total_deleted += 1
				else:
					print("❌ Failed to delete ", file, " (error ", err, ")")
			file = dir.get_next()
		dir.list_dir_end()
	
	current_save_file = ""
	editor.current_save_file = ""
	save_name_input.text = ""
	_refresh_save_list()
	print("🗑️ Deleted all saves (", total_deleted, " files).")

# ==========================================
# LEVEL RUNTIME SCRIPT
# ==========================================
func _write_level_runtime_script() -> void:
	var code := """extends Node2D

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
func save_scene(path: String, delete_data: bool = false) -> void:
	print("Saving Level Scene to: ", path)
	
	_write_level_runtime_script()
	
	if delete_data:
		_delete_level_data(path)
	
	var root = Node2D.new()
	root.name = "GeneratedLevel"
	editor.add_child(root)
	
	var runtime_script = load(LEVEL_RUNTIME_SCRIPT_PATH)
	if runtime_script:
		root.set_script(runtime_script)
		root.set("death_plane_margin", editor.death_plane_margin)
		root.set("player_group_name", editor.player_group_name)
		root.set("debug_death_plane", editor.debug_death_plane)
	
	if is_instance_valid(editor.spawn_point):
		var spawn_marker := Marker2D.new()
		spawn_marker.name = "PlayerSpawn"
		spawn_marker.position = editor.spawn_point.global_position
		root.add_child(spawn_marker)
		print("📍 Saved PlayerSpawn at: ", spawn_marker.position)
	else:
		print("⚠️ No spawn_point assigned — level will have no PlayerSpawn marker.")
	
	# 🖼️ BackgroundNode
	if editor.background_scene != null:
		var bg_copy = editor.background_scene.instantiate()
		bg_copy.name = "BackgroundNode"
		if "background_textures" in bg_copy:
			bg_copy.set("background_textures", editor.background_textures)
		if "active_background_index" in bg_copy:
			bg_copy.set("active_background_index", editor.active_background_index)
		if "background_size" in bg_copy:
			bg_copy.set("background_size", editor.background_size)
		if "stretch_to_viewport" in bg_copy:
			bg_copy.set("stretch_to_viewport", editor.background_stretch_to_viewport)
		root.add_child(bg_copy)
		print("🖼️ Saved BackgroundNode | idx=", editor.active_background_index, " size=", editor.background_size)
	else:
		print("⚠️ No background_scene assigned — level will have no background")
	
	# 🔴 Shells
	for shell in editor.placed_shells:
		if not is_instance_valid(shell):
			continue
		var shell_copy = _duplicate_shell_for_save(shell)
		if shell_copy:
			shell_copy.add_to_group("shell", true)
			root.add_child(shell_copy)
	print("🐚 Saved shells: ", editor.placed_shells.size())
	
	# 👾 Enemies
	for enemy in editor.placed_enemies:
		if not is_instance_valid(enemy):
			continue
		var enemy_copy = _duplicate_enemy_for_save(enemy)
		if enemy_copy:
			enemy_copy.add_to_group("enemy", true)
			root.add_child(enemy_copy)
	print("👾 Saved enemies: ", editor.placed_enemies.size())
	
	# 🌊 Water
	for coord in editor.placed_water.keys():
		var wdata = editor.placed_water[coord]
		var tex_size = editor.get_current_texture_size()
		var grid_pos = Vector2(coord.x * tex_size.x, coord.y * tex_size.y)
		
		var area := Area2D.new()
		area.name = "WaterArea_" + str(coord.x) + "_" + str(coord.y)
		area.position = grid_pos + (tex_size / 2.0)
		area.collision_layer = 0
		area.collision_mask = 1
		area.monitoring = true
		area.monitorable = false
		area.add_to_group("water", true)
		
		var shape := RectangleShape2D.new()
		shape.size = tex_size
		var col := CollisionShape2D.new()
		col.name = "CollisionShape2D"
		col.shape = shape
		area.add_child(col)
		
		var visual := Sprite2D.new()
		visual.name = "WaterVisual"
		visual.texture = editor._get_water_texture()
		visual.centered = true
		visual.position = Vector2.ZERO
		visual.z_index = editor.water_z_index
		visual.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		visual.modulate = Color(1, 1, 1, editor.water_alpha if not editor.water_texture_is_transparent else 1.0)
		if visual.texture:
			visual.scale = Vector2(
				tex_size.x / visual.texture.get_width(),
				tex_size.y / visual.texture.get_height()
			)
		area.add_child(visual)
		
		root.add_child(area)
	
	# 🧱 Tiles
	for coord in editor.placed_tiles.keys():
		var data = editor.placed_tiles[coord]
		
		var tex_index = data["texture_index"]
		var tex_size = editor.get_texture_size_by_index(tex_index)
		var grid_pos = Vector2(coord.x * tex_size.x, coord.y * tex_size.y)
		
		if tex_index >= editor.tile_textures.size():
			continue
		
		var texture = editor.tile_textures[tex_index]
		var has_collision = tex_index < editor.tile_collisions.size() and editor.tile_collisions[tex_index]
		
		if has_collision:
			var body = StaticBody2D.new()
			body.name = "CollisionBody_" + str(coord.x) + "_" + str(coord.y)
			body.position = grid_pos + (tex_size / 2.0)
			body.z_index = editor.get_z_index_by_index(tex_index)
			
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
			visual.z_index = editor.get_z_index_by_index(tex_index)
			root.add_child(visual)
	
	editor._set_owner_recursive(root, root)
	
	var packed_scene = PackedScene.new()
	var error = packed_scene.pack(root)
	
	if error == OK:
		var save_error = ResourceSaver.save(packed_scene, path)
		if save_error == OK:
			print("✅ Level Saved to: ", path)
			print("📊 Saved → tiles: ", editor.placed_tiles.size(),
				  " | shells: ", editor.placed_shells.size(),
				  " | enemies: ", editor.placed_enemies.size(),
				  " | water: ", editor.placed_water.size())
		else:
			print("❌ Failed to save file with error code: ", save_error)
	else:
		print("❌ Failed to pack scene with error code: ", error)
	
	root.queue_free()

# ==========================================
# 🔴 DUPLICATE SHELL FOR SAVE
# ==========================================
func _duplicate_shell_for_save(shell: Node) -> Node:
	if not is_instance_valid(shell) or editor.shell_pickup_scene == null:
		return null
	
	var copy = editor.shell_pickup_scene.instantiate()
	
	var idx = shell.get("current_shell_index")
	if idx != null and idx >= 0:
		copy.set("current_shell_index", idx)
	
	copy.set("randomize_on_spawn", false)
	
	var src_sprite = shell.get("sprite_node")
	var dst_sprite = copy.get("sprite_node")
	if src_sprite and dst_sprite and src_sprite.texture:
		dst_sprite.texture = src_sprite.texture
	
	if shell is Node2D and copy is Node2D:
		copy.position = shell.position
	else:
		var src_pos = shell.get_node_or_null("Position")
		var dst_pos = copy.get_node_or_null("Position")
		if src_pos is Node2D and dst_pos is Node2D:
			dst_pos.position = src_pos.position
	
	return copy

# ==========================================
# 👾 DUPLICATE ENEMY FOR SAVE
# ==========================================
func _duplicate_enemy_for_save(enemy: Node) -> Node:
	if not is_instance_valid(enemy):
		return null
	
	var scene_index : int = -1
	if enemy.has_meta("enemy_scene_index"):
		scene_index = int(enemy.get_meta("enemy_scene_index"))
	
	var source_scene : PackedScene = null
	
	if scene_index >= 0 and scene_index < editor.enemy_scenes.size():
		source_scene = editor.enemy_scenes[scene_index]
	else:
		var scene_path : String = enemy.scene_file_path
		if scene_path != "":
			source_scene = load(scene_path)
	
	if source_scene == null:
		push_warning("👾 Cannot save enemy: no source scene for " + enemy.name)
		return null
	
	var copy = source_scene.instantiate()
	
	if enemy is Node2D and copy is Node2D:
		copy.position = enemy.position
		copy.rotation = enemy.rotation
		copy.scale = enemy.scale
	else:
		var src_pos = enemy.get_node_or_null("Position")
		var dst_pos = copy.get_node_or_null("Position")
		if src_pos is Node2D and dst_pos is Node2D:
			dst_pos.position = src_pos.position
	
	copy.name = enemy.name
	copy.set_meta("enemy_scene_index", scene_index)
	
	return copy

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
	
	var folder := path.get_base_dir() + "/"
	var dir = DirAccess.open(folder)
	if dir == null:
		print("❌ Could not open folder for delete: ", folder)
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
func load_world(path: String) -> void:
	editor._delete_all_tiles()
	
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
	
	editor.add_child(loaded_level)
	await get_tree().process_frame
	
	var max_pos = Vector2.ZERO
	var has_tiles = false
	
	var children_to_process = loaded_level.get_children().duplicate()
	
	for child in children_to_process:
		# 🖼️ BackgroundNode
		if child.name == "BackgroundNode":
			loaded_level.remove_child(child)
			if is_instance_valid(editor._background_node):
				editor._background_node.queue_free()
			editor.add_child(child)
			editor.move_child(child, 0)
			editor._background_node = child
			if "active_background_index" in child:
				editor.active_background_index = child.get("active_background_index")
			if "background_size" in child:
				editor.background_size = child.get("background_size")
			if "background_textures" in child:
				var loaded_textures = child.get("background_textures")
				if loaded_textures is Array and loaded_textures.size() > 0:
					editor.background_textures = loaded_textures
			print("🖼️ Loaded BackgroundNode | idx=", editor.active_background_index, " size=", editor.background_size)
			continue
		
		# 🌊 Water
		if child.name.begins_with("WaterArea_") or child.is_in_group("water"):
			loaded_level.remove_child(child)
			editor.tile_container.add_child(child)
			if not child.is_in_group("water"):
				child.add_to_group("water")
			
			var wcoord := Vector2i.ZERO
			var parts : PackedStringArray = child.name.split("_")
			if parts.size() >= 3:
				wcoord = Vector2i(int(parts[1]), int(parts[2]))
			else:
				var ts : Vector2 = editor.water_tile_size
				wcoord = Vector2i(
					int(round((child.position.x - ts.x * 0.5) / ts.x)),
					int(round((child.position.y - ts.y * 0.5) / ts.y))
				)
			
			editor.placed_water[wcoord] = {
				"visual": child.get_node_or_null("WaterVisual"),
				"area": child
			}
			continue
		
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
				var found_index = editor.tile_textures.find(sprite.texture)
				if found_index == -1:
					found_index = 0
				
				var tex_size = editor.get_texture_size_by_index(found_index)
				
				var grid_pos = body.position - (tex_size / 2.0)
				var coord = Vector2i(
					int(round(grid_pos.x / tex_size.x)),
					int(round(grid_pos.y / tex_size.y))
				)
				
				loaded_level.remove_child(body)
				editor.tile_container.add_child(body)
				
				body.position = grid_pos + (tex_size / 2.0)
				body.z_index = editor.get_z_index_by_index(found_index)
				
				sprite.position = -tex_size / 2.0
				sprite.z_index = 0
				
				if collision_shape:
					collision_shape.position = Vector2.ZERO
				
				editor.placed_tiles[coord] = {
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
				var found_index = editor.tile_textures.find(sprite.texture)
				if found_index == -1:
					found_index = 0
				
				var tex_size = editor.get_texture_size_by_index(found_index)
				var grid_pos = sprite.position
				var coord = Vector2i(
					int(round(grid_pos.x / tex_size.x)),
					int(round(grid_pos.y / tex_size.y))
				)
				
				loaded_level.remove_child(sprite)
				editor.tile_container.add_child(sprite)
				
				sprite.position = grid_pos
				sprite.z_index = editor.get_z_index_by_index(found_index)
				
				editor.placed_tiles[coord] = {
					"texture_index": found_index,
					"visual": sprite,
					"collision": null
				}
				
				if grid_pos.x > max_pos.x or grid_pos.y > max_pos.y:
					max_pos = grid_pos
				has_tiles = true
		else:
			# Match by groups first (tagged at save time), fall back to meta/script.
			var is_enemy : bool = child.is_in_group("enemy") or child.has_meta("enemy_scene_index")
			var is_shell : bool = child.is_in_group("shell")
			
			if not is_enemy and not is_shell:
				# Legacy fallback for saves made before groups existed
				if child is Node and child.get_script() != null:
					is_shell = true
			
			if is_enemy:
				loaded_level.remove_child(child)
				editor.tile_container.add_child(child)
				editor.placed_enemies.append(child)
			elif is_shell:
				loaded_level.remove_child(child)
				editor.tile_container.add_child(child)
				editor.placed_shells.append(child)
			else:
				push_warning("⚠️ load_world: unknown child node skipped: " + child.name)
	
	loaded_level.queue_free()
	
	if has_tiles:
		editor.last_placed_position = max_pos
		if editor.ui_canvas_layer and editor.ui_canvas_layer.has_method("update_last_position"):
			editor.ui_canvas_layer.update_last_position(max_pos)
	else:
		editor.last_placed_position = Vector2.ZERO
		if editor.ui_canvas_layer and editor.ui_canvas_layer.has_method("clear_last_position"):
			editor.ui_canvas_layer.clear_last_position()
	
	current_save_file = path
	editor.current_save_file = path
	editor._recalculate_death_plane()
	print("✅ World loaded! Total tiles: ", editor.placed_tiles.size(),
		  " | shells: ", editor.placed_shells.size(),
		  " | enemies: ", editor.placed_enemies.size(),
		  " | water: ", editor.placed_water.size())

# ==========================================
# 💾 SAVE TARGET — public API
# ==========================================
# Called from the UI to switch between personal (user://) and git-export modes.
# NOTE: this does NOT touch editor.save_folder anymore — that was the bug.
# Instead, saves route through _get_save_folder() based on _save_target.
func set_save_target(target: int) -> void:
	_save_target = target
	_ensure_save_folder()
	var label := "GITHUB_EXPORT" if target == SaveTarget.GITHUB_EXPORT else "NORMAL"
	print("💾 Save target → ", label, " (writes go to ", _get_save_folder(), ")")

func get_save_target() -> int:
	return _save_target
