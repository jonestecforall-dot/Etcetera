extends CanvasLayer

# ==========================================
# EXPORTS — scene paths
# ==========================================
@export_file("*.tscn") var build_scene_path : String = ""
@export_file("*.tscn") var animation_scene_path : String = ""

# ==========================================
# EXPORTS — level loading (for PLAY)
# ==========================================
@export var player_scene : PackedScene = null
@export var save_folder : String = "user://saved_worlds/"
@export var shared_worlds_folder : String = "res://worlds/"
@export var default_level_name : String = "new1.tscn"
@export var spawn_position_node : Node2D = null

# ==========================================
# STYLE — matches the menu
# ==========================================
@export_group("Style")
@export var button_bg_color : Color = Color(1, 1, 1, 0.9)
@export var button_text_color : Color = Color(0.15, 0.15, 0.15, 1.0)
@export var button_hover_color : Color = Color(0.92, 0.92, 0.92, 1.0)
@export var button_pressed_color : Color = Color(0.8, 0.8, 0.8, 1.0)
@export var button_font_size : int = 20
@export var main_button_text : String = "🛠 DEV"
@export var top_margin : int = 20
@export var right_margin : int = 20
@export var dropdown_width : int = 220
@export var button_height : int = 50

# ==========================================
# STATE
# ==========================================
var _menu_root : Control = null
var _anchor : VBoxContainer = null
var _dropdown : VBoxContainer = null
var _play_dropdown : VBoxContainer = null
var _dropdown_open : bool = false
var _play_dropdown_open : bool = false

# Level loading (mirrors intro_menu)
var _world_root : Node = null
var _loaded_level : Node = null
var _spawned_player : Node = null

# ==========================================
# READY
# ==========================================
func _ready() -> void:
	if not OS.has_feature("web"):
		visible = false
		set_process(false)
		return
	
	layer = 200
	_build_ui()


# ==========================================
# UI CONSTRUCTION
# ==========================================
func _build_ui() -> void:
	_menu_root = Control.new()
	_menu_root.name = "DevMenuRoot"
	_menu_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_menu_root)
	
	_anchor = VBoxContainer.new()
	_anchor.name = "TopRightAnchor"
	_anchor.anchor_left = 1.0
	_anchor.anchor_right = 1.0
	_anchor.anchor_top = 0.0
	_anchor.anchor_bottom = 0.0
	_anchor.offset_left = -dropdown_width - right_margin
	_anchor.offset_right = -right_margin
	_anchor.offset_top = top_margin
	_anchor.offset_bottom = top_margin + button_height
	_anchor.alignment = BoxContainer.ALIGNMENT_END
	_anchor.mouse_filter = Control.MOUSE_FILTER_PASS
	_menu_root.add_child(_anchor)
	
	# Main DEV toggle
	var main_btn := _make_button(main_button_text)
	main_btn.pressed.connect(_on_main_button_pressed)
	_anchor.add_child(main_btn)
	
	# --- Main dropdown ---
	_dropdown = VBoxContainer.new()
	_dropdown.add_theme_constant_override("separation", 6)
	_dropdown.visible = false
	_anchor.add_child(_dropdown)
	
	var build_btn := _make_button("🔨 BUILD")
	build_btn.pressed.connect(_on_build_pressed)
	_dropdown.add_child(build_btn)
	
	var play_btn := _make_button("▶ PLAY")
	play_btn.pressed.connect(_on_play_pressed)
	_dropdown.add_child(play_btn)
	
	# --- Play sub-dropdown (level list) ---
	_play_dropdown = VBoxContainer.new()
	_play_dropdown.add_theme_constant_override("separation", 4)
	_play_dropdown.visible = false
	_play_dropdown.add_theme_constant_override("separation", 4)
	_dropdown.add_child(_play_dropdown)
	
	var anim_btn := _make_button("🎬 ANIMATION")
	anim_btn.pressed.connect(_on_animation_pressed)
	_dropdown.add_child(anim_btn)


# ==========================================
# BUTTON FACTORY
# ==========================================
func _make_button(label_text: String) -> Button:
	var btn := Button.new()
	btn.text = label_text
	btn.custom_minimum_size = Vector2(dropdown_width, button_height)
	
	var normal := StyleBoxFlat.new()
	normal.bg_color = button_bg_color
	normal.set_corner_radius_all(8)
	normal.content_margin_left = 12
	normal.content_margin_right = 12
	normal.content_margin_top = 6
	normal.content_margin_bottom = 6
	normal.border_width_left = 2
	normal.border_width_right = 2
	normal.border_width_top = 2
	normal.border_width_bottom = 2
	normal.border_color = Color(0.15, 0.15, 0.15, 1.0)
	
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = button_hover_color
	
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = button_pressed_color
	
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", hover)
	
	btn.add_theme_font_size_override("font_size", button_font_size)
	btn.add_theme_color_override("font_color", button_text_color)
	btn.add_theme_color_override("font_hover_color", button_text_color)
	btn.add_theme_color_override("font_pressed_color", button_text_color)
	btn.add_theme_color_override("font_focus_color", button_text_color)
	
	return btn


# ==========================================
# MAIN MENU HANDLERS
# ==========================================
func _on_main_button_pressed() -> void:
	_dropdown_open = not _dropdown_open
	_dropdown.visible = _dropdown_open
	if not _dropdown_open:
		_play_dropdown.visible = false
		_play_dropdown_open = false


func _on_build_pressed() -> void:
	_close_all_dropdowns()
	_change_scene(build_scene_path, "BUILD")


func _on_play_pressed() -> void:
	# Toggle the play sub-dropdown (list of saves)
	_play_dropdown_open = not _play_dropdown_open
	if _play_dropdown_open:
		_rebuild_play_dropdown()
	_play_dropdown.visible = _play_dropdown_open


func _on_animation_pressed() -> void:
	_close_all_dropdowns()
	_change_scene(animation_scene_path, "ANIMATION")


func _close_all_dropdowns() -> void:
	_dropdown.visible = false
	_play_dropdown.visible = false
	_dropdown_open = false
	_play_dropdown_open = false


# ==========================================
# PLAY SUB-DROPDOWN — list of saves
# ==========================================
func _rebuild_play_dropdown() -> void:
	for child in _play_dropdown.get_children():
		child.queue_free()
	
	var personal_saves := _list_tscn_files(save_folder)
	var shared_saves := _list_tscn_files(shared_worlds_folder)
	
	if personal_saves.is_empty() and shared_saves.is_empty():
		var empty := _make_button("(no saves)")
		empty.disabled = true
		_play_dropdown.add_child(empty)
		return
	
	for f in personal_saves:
		var b := _make_button("[P] " + f.replace(".tscn", ""))
		b.pressed.connect(_on_level_selected.bind(save_folder, f))
		_play_dropdown.add_child(b)
	
	for f in shared_saves:
		var b := _make_button("[S] " + f.replace(".tscn", ""))
		b.pressed.connect(_on_level_selected.bind(shared_worlds_folder, f))
		_play_dropdown.add_child(b)


func _list_tscn_files(folder: String) -> Array[String]:
	var out : Array[String] = []
	if folder.is_empty():
		return out
	# Web can't enumerate res:// — skip it
	if OS.has_feature("web") and folder.begins_with("res://"):
		return out
	var dir = DirAccess.open(folder)
	if dir == null:
		return out
	dir.list_dir_begin()
	var file = dir.get_next()
	while file != "":
		if not dir.current_is_dir() and file.ends_with(".tscn"):
			out.append(file)
		file = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out


# ==========================================
# LEVEL LOADING — same pattern as intro_menu
# ==========================================
func _on_level_selected(folder: String, level_name: String) -> void:
	_close_all_dropdowns()
	_load_level_and_spawn_player(folder, level_name)


func _load_level_and_spawn_player(folder: String, level_name: String) -> void:
	_clear_loaded_level_and_player()
	
	var path = folder.path_join(level_name)
	if not FileAccess.file_exists(path):
		push_warning("DevMenu: level not found: " + path)
		return
	
	var packed = load(path)
	if packed == null:
		push_warning("DevMenu: failed to load: " + path)
		return
	
	var current_scene = get_tree().current_scene
	if current_scene == null:
		push_warning("DevMenu: no current scene")
		return
	
	_world_root = current_scene.get_node_or_null("WorldRoot")
	if _world_root == null:
		_world_root = Node2D.new()
		_world_root.name = "WorldRoot"
		current_scene.add_child(_world_root)
		print("🧱 DevMenu: created WorldRoot under ", current_scene.name)
	else:
		print("🧱 DevMenu: reusing WorldRoot under ", current_scene.name)
	
	_loaded_level = packed.instantiate()
	_world_root.add_child(_loaded_level)
	print("✅ DevMenu loaded level: ", path)
	
	if player_scene == null:
		push_warning("DevMenu: no player_scene assigned")
		_hide_dev_menu_only()
		return
	
	_spawned_player = player_scene.instantiate()
	_world_root.add_child(_spawned_player)
	
	var spawn_pos : Vector2
	if is_instance_valid(spawn_position_node):
		spawn_pos = spawn_position_node.global_position
		print("📍 DevMenu: using exported spawn_position_node at ", spawn_pos)
	else:
		var spawn := _find_spawn_point(_loaded_level)
		if spawn:
			spawn_pos = spawn.global_position
			print("📍 DevMenu: using PlayerSpawn marker at ", spawn_pos)
		else:
			spawn_pos = _loaded_level.global_position
			print("⚠️ DevMenu: no spawn found — using level origin")
	
	_spawned_player.global_position = spawn_pos
	print("🎮 DevMenu: player at ", _spawned_player.global_position)
	
	var new_cam := _find_camera(_spawned_player)
	if new_cam:
		new_cam.make_current()
		new_cam.global_position = _spawned_player.global_position
		print("🎥 DevMenu: camera is current at ", new_cam.global_position)
	
	_hide_dev_menu_only()


# ==========================================
# CLEANUP / HELPERS
# ==========================================
func _clear_loaded_level_and_player() -> void:
	if is_instance_valid(_spawned_player):
		var cam := _find_camera(_spawned_player)
		if cam and cam.is_current():
			cam.clear_current()
		_spawned_player.free()
	_spawned_player = null
	
	if is_instance_valid(_loaded_level):
		_loaded_level.free()
	_loaded_level = null


func _find_camera(node: Node) -> Camera2D:
	if node is Camera2D:
		return node
	for child in node.get_children():
		var found := _find_camera(child)
		if found:
			return found
	return null


func _find_spawn_point(root: Node) -> Node2D:
	if root is Node2D and root.name == "PlayerSpawn":
		return root
	for child in root.get_children():
		var found := _find_spawn_point(child)
		if found:
			return found
	return null


# Hides JUST this dev menu so the level becomes visible.
# The main title/menu UI stays visible (they're a different CanvasLayer).
func _hide_dev_menu_only() -> void:
	if _menu_root:
		_menu_root.visible = false


# Re-show the dev button (e.g. after returning to the title screen).
func _show_dev_menu_only() -> void:
	if _menu_root:
		_menu_root.visible = true


# ==========================================
# SCENE LOADING
# ==========================================
func _change_scene(path: String, label: String) -> void:
	if path.is_empty():
		push_warning("DevMenu: ", label, " scene path is empty — set it in the inspector.")
		return
	if not ResourceLoader.exists(path):
		push_warning("DevMenu: ", label, " scene not found at ", path)
		return
	print("DevMenu → loading ", label, " scene: ", path)
	get_tree().change_scene_to_file(path)
