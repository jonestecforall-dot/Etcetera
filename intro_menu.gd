extends Control

# ==========================================
# EXPORTS
# ==========================================
@export var player_scene: PackedScene
@export var editor_scene_path: String = "res://tile_map_maker.tscn"
@export var sprite_sheet_keeper_scene_path: String = "res://sprite_sheet_keeper.tscn"
@export var default_level_name: String = "new1.tscn"
@export var save_folder: String = "user://saved_worlds/"
@export var spawn_position_node: Node2D

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

# ==========================================
# READY
# ==========================================
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_refresh_level_list()

# ==========================================
# BUILD UI
# ==========================================
func _build_ui() -> void:
	ui_layer = CanvasLayer.new()
	ui_layer.name = "MenuUI"
	ui_layer.layer = 100
	add_child(ui_layer)

	overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.75)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui_layer.add_child(overlay)

	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)

	panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(420, 380)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.18, 0.98)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.4, 0.4, 0.5, 1.0)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)

	var title = Label.new()
	title.text = "MAIN MENU"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	vbox.add_child(title)

	var subtitle = Label.new()
	subtitle.text = "Choose a level and press Play, or build a new one."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8, 1.0))
	vbox.add_child(subtitle)

	var list_label = Label.new()
	list_label.text = "Saved Levels:"
	vbox.add_child(list_label)

	level_dropdown = OptionButton.new()
	level_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(level_dropdown)

	var refresh_row = HBoxContainer.new()
	vbox.add_child(refresh_row)
	var refresh_btn = Button.new()
	refresh_btn.text = "🔄 Refresh List"
	refresh_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	refresh_btn.pressed.connect(_refresh_level_list)
	refresh_row.add_child(refresh_btn)

	# --- Row 1: BUILD + PLAY ---
	var button_row = HBoxContainer.new()
	button_row.add_theme_constant_override("separation", 10)
	vbox.add_child(button_row)

	var build_btn = Button.new()
	build_btn.text = "🔨 BUILD"
	build_btn.custom_minimum_size = Vector2(160, 60)
	build_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	build_btn.pressed.connect(_on_build_pressed)
	button_row.add_child(build_btn)

	var play_btn = Button.new()
	play_btn.text = "▶ PLAY"
	play_btn.custom_minimum_size = Vector2(160, 60)
	play_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	play_btn.pressed.connect(_on_play_pressed)
	button_row.add_child(play_btn)

	# --- Row 2: SPRITE SHEETS ---
	var tool_row = HBoxContainer.new()
	tool_row.add_theme_constant_override("separation", 10)
	vbox.add_child(tool_row)

	var sprite_btn = Button.new()
	sprite_btn.text = "🎨 SPRITE SHEETS"
	sprite_btn.custom_minimum_size = Vector2(0, 60)
	sprite_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sprite_btn.modulate = Color(0.9, 0.7, 1.0, 1)  # purple tint
	sprite_btn.pressed.connect(_on_sprite_sheets_pressed)
	tool_row.add_child(sprite_btn)

# ==========================================
# LEVEL LIST
# ==========================================
func _refresh_level_list() -> void:
	if not level_dropdown:
		return
	level_dropdown.clear()
	
	var dir = DirAccess.open(save_folder)
	if dir == null:
		level_dropdown.add_item("(no saves yet)")
		level_dropdown.disabled = true
		return
	
	level_dropdown.disabled = false
	dir.list_dir_begin()
	var file = dir.get_next()
	while file != "":
		if file.ends_with(".tscn"):
			level_dropdown.add_item(file)
		file = dir.get_next()
	dir.list_dir_end()
	
	if level_dropdown.item_count == 0:
		level_dropdown.add_item("(no saves yet)")
		level_dropdown.disabled = true
	else:
		for i in range(level_dropdown.item_count):
			if level_dropdown.get_item_text(i) == default_level_name:
				level_dropdown.select(i)
				break

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
	var level_name = level_dropdown.get_item_text(level_dropdown.selected)
	_load_level_and_spawn_player(level_name)

func _on_sprite_sheets_pressed() -> void:
	if sprite_sheet_keeper_scene_path.is_empty():
		print("⚠️ sprite_sheet_keeper_scene_path is empty!")
		return
	_hide_menu()
	get_tree().change_scene_to_file(sprite_sheet_keeper_scene_path)

# ==========================================
# LOAD LEVEL + SPAWN PLAYER
# ==========================================
func _load_level_and_spawn_player(level_name: String) -> void:
	_clear_loaded_level_and_player()
	
	var path = save_folder + level_name
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
	print("✅ Loaded level: ", level_name)
	
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

func _show_menu() -> void:
	if ui_layer:
		ui_layer.visible = true
	_refresh_level_list()
