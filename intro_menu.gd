extends Control

# ==========================================
# EXPORTS - SCENES
# ==========================================
@export var player_scene: PackedScene
@export var editor_scene_path: String = "res://tile_map_maker.tscn"
@export var sprite_sheet_keeper_scene_path: String = "res://sprite_sheet_keeper.tscn"
@export var settings_scene_path: String = "res://settings.tscn"
@export var default_level_name: String = "new1.tscn"
@export var save_folder: String = "user://saved_worlds/"
@export var shared_worlds_folder: String = "res://worlds/"
@export var spawn_position_node: Node2D

# ==========================================
# EXPORTS - GAME TITLE
# ==========================================
@export var game_title: String = "MY GAME"
@export var game_title_font_size: int = 48
@export var game_title_color: Color = Color(1, 1, 1, 1)

# ==========================================
# EXPORTS - LAYOUT
# ==========================================
@export_group("Layout")
@export var panel_min_size: Vector2 = Vector2(420, 380)
@export var panel_fill_screen: bool = false
@export var panel_screen_margin: int = 40
@export var title_panel_spacing: int = 20

# ==========================================
# EXPORTS - FONTS
# ==========================================
@export_group("Fonts")
@export var font_override: Font = null
@export var title_font: Font = null
@export var subtitle_font: Font = null
@export var label_font: Font = null
@export var button_font: Font = null
@export var game_title_font: Font = null

# ==========================================
# EXPORTS - COLORS
# ==========================================
@export_group("Overlay")
@export var overlay_color: Color = Color(0, 0, 0, 0.75)

@export_group("Panel")
@export var panel_bg_color: Color = Color(0.15, 0.15, 0.18, 0.98)
@export var panel_border_color: Color = Color(0.4, 0.4, 0.5, 1.0)
@export var panel_border_width: int = 2
@export var panel_corner_radius: int = 10

@export_group("Text")
@export var title_color: Color = Color(1, 1, 1, 1)
@export var subtitle_color: Color = Color(0.7, 0.7, 0.8, 1.0)
@export var label_color: Color = Color(1, 1, 1, 1)

@export_group("Buttons")
@export var build_button_color: Color = Color(1, 1, 1, 1)
@export var play_button_color: Color = Color(1, 1, 1, 1)
@export var load_button_color: Color = Color(0.8, 1.0, 0.8, 1)
@export var sprite_button_color: Color = Color(0.9, 0.7, 1.0, 1)
@export var refresh_button_color: Color = Color(1, 1, 1, 1)
@export var settings_button_color: Color = Color(0.8, 0.9, 1.0, 1)
@export var quit_button_color: Color = Color(1.0, 0.7, 0.7, 1)

# ==========================================
# EXPORTS - BACKDROP
# ==========================================
@export_group("Backdrop")
@export var backdrop_enabled: bool = false
@export var backdrop_scene: PackedScene = null
@export var backdrop_node: Node = null                # 👈 Node, not Control
@export var backdrop_script_path: String = "res://procedural_backdrop.gd"
@export var backdrop_use_overlay_dim: bool = true
@export var backdrop_canvas_layer: int = -1

@export_subgroup("Backdrop Colors")
@export var backdrop_background_color: Color = Color(0.06, 0.06, 0.09, 1.0)
@export var backdrop_color_a: Color = Color(0.35, 0.65, 1.0, 1.0)
@export var backdrop_color_b: Color = Color(0.55, 0.35, 0.85, 1.0)
@export var backdrop_color_c: Color = Color(0.20, 0.40, 0.75, 1.0)
@export var backdrop_alpha_min: float = 0.08
@export var backdrop_alpha_max: float = 0.55
@export var backdrop_color_blend_speed: float = 0.0

@export_subgroup("Backdrop Formation")
@export_enum("GRID", "DIAGONAL", "WAVE", "RADIAL", "SPIRAL", "HEX", "CHECKER", "RANDOM_SCATTER")
var backdrop_formation: int = 0
@export var backdrop_tile_size: Vector2 = Vector2(64, 64)
@export var backdrop_spacing: Vector2 = Vector2(0, 0)
@export var backdrop_tile_scale: Vector2 = Vector2.ONE
@export var backdrop_rotation_per_tile: float = 0.0
@export var backdrop_global_rotation: float = 0.0
@export var backdrop_center_origin: bool = true
@export var backdrop_tile_count_override: int = 0

@export_subgroup("Backdrop Animation")
@export var backdrop_animate: bool = true
@export var backdrop_wave_amplitude: float = 12.0
@export var backdrop_wave_speed: float = 1.5
@export var backdrop_breathe_scale: float = 0.0
@export var backdrop_drift_speed: Vector2 = Vector2.ZERO

@export_subgroup("Backdrop Random")
@export var backdrop_random_seed: int = 1337
@export_range(0.0, 1.0, 0.01) var backdrop_size_jitter: float = 0.15
@export_range(0.0, 360.0, 1.0) var backdrop_rotation_jitter: float = 0.0
@export var backdrop_scatter_radius: float = 400.0

@export_subgroup("Backdrop Textures")
@export var backdrop_atlas_texture: Texture2D = null
@export var backdrop_atlas_pool: Array[Texture2D] = []
@export var backdrop_atlas_region: Rect2 = Rect2(0, 0, 64, 64)
@export_range(0.0, 1.0, 0.01) var backdrop_pool_pick_chance: float = 0.0
@export var backdrop_use_solid_colors: bool = true

# ==========================================
# STATE
# ==========================================
var ui_layer: CanvasLayer
var overlay: ColorRect
var panel: PanelContainer
var level_dropdown: OptionButton

var loaded_level: Node = null
var spawned_player: Node = null
var world_root: Node = null

var _backdrop_instance: Node = null                   # 👈 Node, not Control
var _backdrop_layer: CanvasLayer = null

# ==========================================
# READY
# ==========================================
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_backdrop()
	_build_ui()
	_refresh_level_list()
	get_viewport().size_changed.connect(_on_viewport_resized)

# ==========================================
# BACKDROP SETUP
# ==========================================
func _setup_backdrop() -> void:
	if not backdrop_enabled:
		return
	
	if backdrop_node != null:
		_backdrop_instance = backdrop_node
	elif backdrop_scene != null:
		_backdrop_instance = backdrop_scene.instantiate()
	else:
		_backdrop_instance = _create_backdrop_from_script()
	
	if _backdrop_instance == null:
		push_warning("Menu: backdrop could not be created")
		return
	
	_backdrop_layer = CanvasLayer.new()
	_backdrop_layer.name = "BackdropLayer"
	_backdrop_layer.layer = backdrop_canvas_layer
	add_child(_backdrop_layer)
	
	if _backdrop_instance.get_parent() == null:
		_backdrop_layer.add_child(_backdrop_instance)
	else:
		_backdrop_instance.reparent(_backdrop_layer)
	
	if _backdrop_instance is Control:
		var c := _backdrop_instance as Control
		c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	_push_backdrop_settings()

func _create_backdrop_from_script() -> Node:
	if not ResourceLoader.exists(backdrop_script_path):
		push_warning("Menu: backdrop script not found at " + backdrop_script_path)
		return null
	var script: Script = load(backdrop_script_path)
	if script == null:
		return null
	var tr := TextureRect.new()
	tr.name = "ProceduralBackdrop"
	tr.set_script(script)
	return tr

func _push_backdrop_settings() -> void:
	if _backdrop_instance == null:
		return
	var b := _backdrop_instance
	_set_if_has(b, "background_color", backdrop_background_color)
	_set_if_has(b, "color_a", backdrop_color_a)
	_set_if_has(b, "color_b", backdrop_color_b)
	_set_if_has(b, "color_c", backdrop_color_c)
	_set_if_has(b, "alpha_min", backdrop_alpha_min)
	_set_if_has(b, "alpha_max", backdrop_alpha_max)
	_set_if_has(b, "color_blend_speed", backdrop_color_blend_speed)
	_set_if_has(b, "formation", backdrop_formation)
	_set_if_has(b, "tile_size", backdrop_tile_size)
	_set_if_has(b, "spacing", backdrop_spacing)
	_set_if_has(b, "tile_scale", backdrop_tile_scale)
	_set_if_has(b, "rotation_per_tile", backdrop_rotation_per_tile)
	_set_if_has(b, "global_rotation", backdrop_global_rotation)
	_set_if_has(b, "center_origin", backdrop_center_origin)
	_set_if_has(b, "tile_count_override", backdrop_tile_count_override)
	_set_if_has(b, "animate", backdrop_animate)
	_set_if_has(b, "wave_amplitude", backdrop_wave_amplitude)
	_set_if_has(b, "wave_speed", backdrop_wave_speed)
	_set_if_has(b, "breathe_scale", backdrop_breathe_scale)
	_set_if_has(b, "drift_speed", backdrop_drift_speed)
	_set_if_has(b, "random_seed", backdrop_random_seed)
	_set_if_has(b, "size_jitter", backdrop_size_jitter)
	_set_if_has(b, "rotation_jitter", backdrop_rotation_jitter)
	_set_if_has(b, "scatter_radius", backdrop_scatter_radius)
	_set_if_has(b, "atlas_texture", backdrop_atlas_texture)
	_set_if_has(b, "atlas_pool", backdrop_atlas_pool)
	_set_if_has(b, "atlas_region", backdrop_atlas_region)
	_set_if_has(b, "pool_pick_chance", backdrop_pool_pick_chance)
	_set_if_has(b, "use_solid_colors", backdrop_use_solid_colors)

func _set_if_has(node: Object, prop: String, value) -> void:
	for p in node.get_property_list():
		if p.name == prop:
			node.set(prop, value)
			return

# ==========================================
# FONT HELPER
# ==========================================
func _apply_font(control: Control, specific_font: Font) -> void:
	var chosen := specific_font
	if chosen == null:
		chosen = font_override
	if chosen != null:
		control.add_theme_font_override("font", chosen)

# ==========================================
# BUILD UI
# ==========================================
func _build_ui() -> void:
	ui_layer = CanvasLayer.new()
	ui_layer.name = "MenuUI"
	ui_layer.layer = 100
	add_child(ui_layer)

	overlay = ColorRect.new()
	if backdrop_enabled and not backdrop_use_overlay_dim:
		overlay.color = Color(0, 0, 0, 0)
	else:
		overlay.color = overlay_color
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui_layer.add_child(overlay)

	var center = CenterContainer.new()
	center.name = "Center"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)

	var main_vbox = VBoxContainer.new()
	main_vbox.name = "MainVBox"
	main_vbox.add_theme_constant_override("separation", title_panel_spacing)
	main_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(main_vbox)

	var game_title_label = Label.new()
	game_title_label.text = game_title
	game_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	game_title_label.add_theme_font_size_override("font_size", game_title_font_size)
	game_title_label.add_theme_color_override("font_color", game_title_color)
	_apply_font(game_title_label, game_title_font)
	main_vbox.add_child(game_title_label)

	panel = PanelContainer.new()
	panel.name = "Panel"
	panel.custom_minimum_size = panel_min_size
	if panel_fill_screen:
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var style = StyleBoxFlat.new()
	style.bg_color = panel_bg_color
	style.border_width_left = panel_border_width
	style.border_width_right = panel_border_width
	style.border_width_top = panel_border_width
	style.border_width_bottom = panel_border_width
	style.border_color = panel_border_color
	style.set_corner_radius_all(panel_corner_radius)
	style.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel", style)
	main_vbox.add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(vbox)

	var title = Label.new()
	title.text = "MAIN MENU"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", title_color)
	_apply_font(title, title_font)
	vbox.add_child(title)

	var subtitle = Label.new()
	subtitle.text = "Choose a level and press Play, or build a new one.   [P] personal   [S] shared (git)"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.add_theme_color_override("font_color", subtitle_color)
	_apply_font(subtitle, subtitle_font)
	vbox.add_child(subtitle)

	var list_label = Label.new()
	list_label.text = "Saved Levels:"
	list_label.add_theme_color_override("font_color", label_color)
	_apply_font(list_label, label_font)
	vbox.add_child(list_label)

	var level_row = HBoxContainer.new()
	level_row.add_theme_constant_override("separation", 8)
	vbox.add_child(level_row)

	level_dropdown = OptionButton.new()
	level_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if button_font != null:
		level_dropdown.add_theme_font_override("font", button_font)
	elif font_override != null:
		level_dropdown.add_theme_font_override("font", font_override)
	level_row.add_child(level_dropdown)

	var load_btn = Button.new()
	load_btn.text = "📂 LOAD"
	load_btn.custom_minimum_size = Vector2(120, 0)
	load_btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
	load_btn.modulate = load_button_color
	_apply_font(load_btn, button_font)
	load_btn.pressed.connect(_on_load_pressed)
	level_row.add_child(load_btn)

	var refresh_row = HBoxContainer.new()
	vbox.add_child(refresh_row)
	var refresh_btn = Button.new()
	refresh_btn.text = "🔄 Refresh List"
	refresh_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	refresh_btn.modulate = refresh_button_color
	_apply_font(refresh_btn, button_font)
	refresh_btn.pressed.connect(_refresh_level_list)
	refresh_row.add_child(refresh_btn)

	var button_row = HBoxContainer.new()
	button_row.add_theme_constant_override("separation", 10)
	vbox.add_child(button_row)

	var build_btn = Button.new()
	build_btn.text = "🔨 BUILD"
	build_btn.custom_minimum_size = Vector2(160, 60)
	build_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	build_btn.modulate = build_button_color
	_apply_font(build_btn, button_font)
	build_btn.pressed.connect(_on_build_pressed)
	button_row.add_child(build_btn)

	var play_btn = Button.new()
	play_btn.text = "▶ PLAY"
	play_btn.custom_minimum_size = Vector2(160, 60)
	play_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	play_btn.modulate = play_button_color
	_apply_font(play_btn, button_font)
	play_btn.pressed.connect(_on_play_pressed)
	button_row.add_child(play_btn)

	var tool_row = HBoxContainer.new()
	tool_row.add_theme_constant_override("separation", 10)
	vbox.add_child(tool_row)

	var sprite_btn = Button.new()
	sprite_btn.text = "🎨 SPRITE SHEETS"
	sprite_btn.custom_minimum_size = Vector2(0, 60)
	sprite_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sprite_btn.modulate = sprite_button_color
	_apply_font(sprite_btn, button_font)
	sprite_btn.pressed.connect(_on_sprite_sheets_pressed)
	tool_row.add_child(sprite_btn)

	var bottom_row = HBoxContainer.new()
	bottom_row.add_theme_constant_override("separation", 10)
	vbox.add_child(bottom_row)

	var settings_btn = Button.new()
	settings_btn.text = "⚙ SETTINGS"
	settings_btn.custom_minimum_size = Vector2(0, 60)
	settings_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings_btn.modulate = settings_button_color
	_apply_font(settings_btn, button_font)
	settings_btn.pressed.connect(_on_settings_pressed)
	bottom_row.add_child(settings_btn)

	var quit_btn = Button.new()
	quit_btn.text = "🚪 QUIT"
	quit_btn.custom_minimum_size = Vector2(0, 60)
	quit_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quit_btn.modulate = quit_button_color
	_apply_font(quit_btn, button_font)
	quit_btn.pressed.connect(_on_quit_pressed)
	bottom_row.add_child(quit_btn)

	_update_panel_size()

# ==========================================
# RESPONSIVE SIZE
# ==========================================
func _on_viewport_resized() -> void:
	_update_panel_size()

func _update_panel_size() -> void:
	if panel == null:
		return
	if panel_fill_screen:
		var vp_size = get_viewport().get_visible_rect().size
		var new_size = vp_size - Vector2(panel_screen_margin * 2, panel_screen_margin * 2)
		new_size.x = max(new_size.x, panel_min_size.x)
		new_size.y = max(new_size.y, panel_min_size.y)
		panel.custom_minimum_size = new_size
	else:
		panel.custom_minimum_size = panel_min_size

# ==========================================
# LEVEL LIST — personal + shared
# ==========================================
func _refresh_level_list() -> void:
	if not level_dropdown:
		return
	level_dropdown.clear()
	
	var personal_saves : Array[String] = _list_tscn_files(save_folder)
	var shared_saves : Array[String] = _list_tscn_files(shared_worlds_folder)
	
	if personal_saves.is_empty() and shared_saves.is_empty():
		level_dropdown.add_item("(no saves yet)")
		level_dropdown.disabled = true
		return
	
	level_dropdown.disabled = false
	
	for f in personal_saves:
		var idx := level_dropdown.item_count
		level_dropdown.add_item("[P] " + f)
		level_dropdown.set_item_metadata(idx, {"folder": save_folder, "filename": f})
	
	for f in shared_saves:
		var idx := level_dropdown.item_count
		level_dropdown.add_item("[S] " + f)
		level_dropdown.set_item_metadata(idx, {"folder": shared_worlds_folder, "filename": f})
	
	for i in range(level_dropdown.item_count):
		var meta = level_dropdown.get_item_metadata(i)
		if meta is Dictionary and meta.get("filename", "") == default_level_name:
			level_dropdown.select(i)
			break

func _list_tscn_files(folder: String) -> Array[String]:
	var out : Array[String] = []
	if folder.is_empty():
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
# BUTTONS
# ==========================================
func _on_build_pressed() -> void:
	_hide_menu()
	get_tree().change_scene_to_file(editor_scene_path)

func _on_play_pressed() -> void:
	if level_dropdown.disabled:
		print("⚠️ No level selected — nothing to play.")
		return
	var entry = _get_selected_level()
	if entry.is_empty():
		return
	_load_level_and_spawn_player(entry["folder"], entry["filename"])

func _on_load_pressed() -> void:
	if level_dropdown.disabled:
		print("⚠️ No level selected — nothing to load.")
		return
	var entry = _get_selected_level()
	if entry.is_empty():
		return
	_load_level_only(entry["folder"], entry["filename"])

func _get_selected_level() -> Dictionary:
	if level_dropdown.selected < 0:
		return {}
	var meta = level_dropdown.get_item_metadata(level_dropdown.selected)
	if meta is Dictionary:
		return meta
	return {}

func _on_sprite_sheets_pressed() -> void:
	if sprite_sheet_keeper_scene_path.is_empty():
		print("⚠️ sprite_sheet_keeper_scene_path is empty!")
		return
	_hide_menu()
	get_tree().change_scene_to_file(sprite_sheet_keeper_scene_path)

func _on_settings_pressed() -> void:
	if settings_scene_path.is_empty():
		print("⚠️ settings_scene_path is empty!")
		return
	_hide_menu()
	get_tree().change_scene_to_file(settings_scene_path)

func _on_quit_pressed() -> void:
	print("🚪 Quitting game...")
	get_tree().quit()

# ==========================================
# LOAD LEVEL ONLY (no player spawn)
# ==========================================
func _load_level_only(folder: String, level_name: String) -> void:
	if is_instance_valid(loaded_level):
		loaded_level.free()
	loaded_level = null
	
	var path = folder.path_join(level_name)
	if not FileAccess.file_exists(path):
		print("❌ Level not found: ", path)
		return
	
	var packed = load(path)
	if packed == null:
		print("❌ Failed to load: ", path)
		return
	
	var current_scene = get_tree().current_scene
	if current_scene == null:
		print("❌ No current scene.")
		return
	
	world_root = current_scene.get_node_or_null("WorldRoot")
	if world_root == null:
		world_root = Node2D.new()
		world_root.name = "WorldRoot"
		current_scene.add_child(world_root)
		print("🧱 Created WorldRoot under ", current_scene.name)
	else:
		print("🧱 Reusing WorldRoot under ", current_scene.name)
	
	loaded_level = packed.instantiate()
	world_root.add_child(loaded_level)
	print("📂 Loaded level (no player spawn): ", path)
	
	_hide_menu()

# ==========================================
# LOAD LEVEL + SPAWN PLAYER
# ==========================================
func _load_level_and_spawn_player(folder: String, level_name: String) -> void:
	_clear_loaded_level_and_player()
	
	var path = folder.path_join(level_name)
	if not FileAccess.file_exists(path):
		print("❌ Level not found: ", path)
		return
	
	var packed = load(path)
	if packed == null:
		print("❌ Failed to load: ", path)
		return
	
	var current_scene = get_tree().current_scene
	if current_scene == null:
		print("❌ No current scene.")
		return
	
	world_root = current_scene.get_node_or_null("WorldRoot")
	if world_root == null:
		world_root = Node2D.new()
		world_root.name = "WorldRoot"
		current_scene.add_child(world_root)
		print("🧱 Created WorldRoot under ", current_scene.name)
	else:
		print("🧱 Reusing WorldRoot under ", current_scene.name)
	
	loaded_level = packed.instantiate()
	world_root.add_child(loaded_level)
	print("✅ Loaded level: ", path)
	
	if player_scene == null:
		print("⚠️ No player_scene assigned!")
		return
	
	spawned_player = player_scene.instantiate()
	world_root.add_child(spawned_player)
	
	var spawn_pos: Vector2
	if is_instance_valid(spawn_position_node):
		spawn_pos = spawn_position_node.global_position
		print("📍 Using exported spawn_position_node at: ", spawn_pos)
	else:
		var spawn = _find_spawn_point(loaded_level)
		if spawn:
			spawn_pos = spawn.global_position
			print("📍 Using PlayerSpawn marker at: ", spawn_pos)
		else:
			spawn_pos = loaded_level.global_position
			print("⚠️ No spawn found — using level origin")
	
	spawned_player.global_position = spawn_pos
	print("🎮 Player at: ", spawned_player.global_position)
	
	var new_cam := _find_camera(spawned_player)
	if new_cam:
		new_cam.make_current()
		new_cam.global_position = spawned_player.global_position
		print("🎥 Player camera is current at ", new_cam.global_position)
	else:
		print("⚠️ Player has no Camera2D!")
	
	_hide_menu()

# ==========================================
# CLEANUP
# ==========================================
func _clear_loaded_level_and_player() -> void:
	if is_instance_valid(spawned_player):
		var cam := _find_camera(spawned_player)
		if cam and cam.is_current():
			cam.clear_current()
		spawned_player.free()
	spawned_player = null
	
	if is_instance_valid(loaded_level):
		loaded_level.free()
	loaded_level = null

# ==========================================
# HELPERS
# ==========================================
func _find_camera(node: Node) -> Camera2D:
	if node is Camera2D:
		return node
	for child in node.get_children():
		var found = _find_camera(child)
		if found:
			return found
	return null

func _find_spawn_point(root: Node) -> Node2D:
	if root is Node2D and root.name == "PlayerSpawn":
		return root
	for child in root.get_children():
		var found = _find_spawn_point(child)
		if found:
			return found
	return null

# ==========================================
# SHOW / HIDE
# ==========================================
func _hide_menu() -> void:
	if ui_layer:
		ui_layer.visible = false
	if _backdrop_layer:
		_backdrop_layer.visible = false
	if _backdrop_instance and is_instance_valid(_backdrop_instance):
		if _backdrop_instance is CanvasItem:
			(_backdrop_instance as CanvasItem).visible = false
	if overlay and is_instance_valid(overlay):
		overlay.visible = false
	if panel and is_instance_valid(panel):
		panel.visible = false
	
	# Hide EVERY direct-child CanvasItem except WorldRoot.
	# This catches the editor-placed BackGroundMenuNode and anything else
	# added to IntroMenu.tscn directly.
	for child in get_children():
		if child == world_root:
			continue
		if child is CanvasItem:
			(child as CanvasItem).visible = false
	
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	print("🫥 Menu hidden")


func _show_menu() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	if ui_layer:
		ui_layer.visible = true
	if _backdrop_layer:
		_backdrop_layer.visible = true
	if _backdrop_instance and is_instance_valid(_backdrop_instance):
		if _backdrop_instance is CanvasItem:
			(_backdrop_instance as CanvasItem).visible = true
	if overlay and is_instance_valid(overlay):
		overlay.visible = true
	if panel and is_instance_valid(panel):
		panel.visible = true
	
	for child in get_children():
		if child == world_root:
			continue
		if child is CanvasItem:
			(child as CanvasItem).visible = true
	
	_refresh_level_list()
	_update_panel_size()
	print("👁️ Menu shown")
