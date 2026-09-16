extends CanvasLayer

# ==========================================
# EXPORTS
# ==========================================
@export var swap_to_right_side : bool = false  # Check to put D-Pad on right side
@export var button_size : float = 90.0         # Size of each D-Pad button
@export var button_spacing : float = 6.0       # Space between buttons
@export var dpad_margin : float = 40.0         # Distance from screen edge
@export var hold_repeat_speed : float = 0.05   # Seconds between each move tick
@export var scroll_speed : float = 8.0         # How fast the camera scrolls (higher = faster)

# ==========================================
# SIGNALS
# ==========================================
signal tile_selected(index: int)
signal tool_changed(tool: int)
signal undo_pressed
signal save_pressed
signal delete_all_pressed
signal joystick_dragged(offset: Vector2)
signal joystick_released
signal last_position_updated(position: Vector2)

# ==========================================
# UI ELEMENTS
# ==========================================
var tile_buttons: Array[Button] = []
var selected_tile_index: int = 0
var current_tool: int = 0
var main_container: VBoxContainer
var tile_grid: GridContainer
var last_position_label: Label

# D-Pad Buttons
var dpad_up : Button
var dpad_down : Button
var dpad_left : Button
var dpad_right : Button
var dpad_container : Control

# Hold Timers
var up_timer : Timer
var down_timer : Timer
var left_timer : Timer
var right_timer : Timer

# ==========================================
# INITIALIZATION
# ==========================================
func _ready() -> void:
	_build_ui_elements()
	_build_dpad()

# ==========================================
# BUILD UI
# ==========================================
func _build_ui_elements() -> void:
	var ui_root = Control.new()
	ui_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(ui_root)
	
	main_container = VBoxContainer.new()
	main_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_container.add_theme_constant_override("separation", 10)
	ui_root.add_child(main_container)
	
	var title = Label.new()
	title.text = "MAP EDITOR"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	main_container.add_child(title)
	
	var tool_row = HBoxContainer.new()
	tool_row.add_theme_constant_override("separation", 5)
	main_container.add_child(tool_row)
	
	var place_btn = Button.new()
	place_btn.text = "PLACE"
	place_btn.pressed.connect(func(): _on_tool_button_pressed(0))
	tool_row.add_child(place_btn)
	
	var delete_btn = Button.new()
	delete_btn.text = "DELETE"
	delete_btn.pressed.connect(func(): _on_tool_button_pressed(1))
	tool_row.add_child(delete_btn)
	
	var paint_delete_btn = Button.new()
	paint_delete_btn.text = "PAINT DEL"
	paint_delete_btn.pressed.connect(func(): _on_tool_button_pressed(2))
	tool_row.add_child(paint_delete_btn)
	
	var action_row = HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 10)
	main_container.add_child(action_row)
	
	var undo_btn = Button.new()
	undo_btn.text = "UNDO"
	undo_btn.pressed.connect(func(): undo_pressed.emit())
	action_row.add_child(undo_btn)
	
	var delete_all_btn = Button.new()
	delete_all_btn.text = "DELETE ALL"
	delete_all_btn.modulate = Color(1, 0.3, 0.3, 1)
	delete_all_btn.pressed.connect(func(): delete_all_pressed.emit())
	action_row.add_child(delete_all_btn)
	
	var save_btn = Button.new()
	save_btn.text = "SAVE"
	save_btn.pressed.connect(func(): save_pressed.emit())
	action_row.add_child(save_btn)
	
	var info_container = HBoxContainer.new()
	info_container.add_theme_constant_override("separation", 10)
	main_container.add_child(info_container)
	
	var position_label_prefix = Label.new()
	position_label_prefix.text = "LAST POSITION:"
	position_label_prefix.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	position_label_prefix.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_container.add_child(position_label_prefix)
	
	last_position_label = Label.new()
	last_position_label.text = "NONE"
	last_position_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	last_position_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	last_position_label.add_theme_color_override("font_color", Color(0.3, 1, 0.3, 1))
	info_container.add_child(last_position_label)
	
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_container.add_child(scroll)
	
	tile_grid = GridContainer.new()
	tile_grid.columns = 4
	tile_grid.add_theme_constant_override("h_separation", 5)
	tile_grid.add_theme_constant_override("v_separation", 5)
	scroll.add_child(tile_grid)

# ==========================================
# UPDATE LAST POSITION
# ==========================================
func update_last_position(position: Vector2) -> void:
	if last_position_label:
		last_position_label.text = "X: %d, Y: %d" % [position.x, position.y]
		last_position_updated.emit(position)

func clear_last_position() -> void:
	if last_position_label:
		last_position_label.text = "NONE"
		last_position_label.add_theme_color_override("font_color", Color(0.3, 1, 0.3, 1))

# ==========================================
# HELPER: Create a stylized button
# ==========================================
func _make_dpad_button(symbol: String, color: Color) -> Button:
	var btn = Button.new()
	btn.text = symbol
	btn.custom_minimum_size = Vector2(button_size, button_size)
	btn.add_theme_font_size_override("font_size", int(button_size * 0.5))
	
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = color
	style_normal.set_corner_radius_all(int(button_size * 0.2))
	style_normal.border_width_left = 3
	style_normal.border_width_right = 3
	style_normal.border_width_top = 3
	style_normal.border_width_bottom = 3
	style_normal.border_color = Color(1, 1, 1, 0.4)
	btn.add_theme_stylebox_override("normal", style_normal)
	
	var style_pressed = style_normal.duplicate()
	style_pressed.bg_color = color.darkened(0.4)
	btn.add_theme_stylebox_override("pressed", style_pressed)
	
	var style_hover = style_normal.duplicate()
	style_hover.bg_color = color.lightened(0.1)
	btn.add_theme_stylebox_override("hover", style_hover)
	
	return btn

# ==========================================
# BUILD D-PAD
# ==========================================
func _build_dpad() -> void:
	var viewport_size = get_viewport().get_visible_rect().size
	var cell = button_size + button_spacing
	var grid_size = (button_size * 3) + (button_spacing * 2)
	
	dpad_container = Control.new()
	dpad_container.size = Vector2(grid_size, grid_size)
	
	if swap_to_right_side:
		dpad_container.position = Vector2(viewport_size.x - grid_size - dpad_margin, viewport_size.y - grid_size - dpad_margin)
	else:
		dpad_container.position = Vector2(dpad_margin, viewport_size.y - grid_size - dpad_margin)
	
	add_child(dpad_container)
	
	var col_up = Color(0.3, 0.8, 0.4, 0.85)    # Green
	var col_down = Color(0.9, 0.4, 0.4, 0.85)  # Red
	var col_left = Color(0.4, 0.6, 0.9, 0.85)  # Blue
	var col_right = Color(0.9, 0.8, 0.3, 0.85) # Yellow
	
	# --- UP BUTTON ---
	dpad_up = _make_dpad_button("▲", col_up)
	dpad_up.position = Vector2(button_size + button_spacing, 0)
	dpad_container.add_child(dpad_up)
	
	# --- DOWN BUTTON ---
	dpad_down = _make_dpad_button("▼", col_down)
	dpad_down.position = Vector2(button_size + button_spacing, cell * 2)
	dpad_container.add_child(dpad_down)
	
	# --- LEFT BUTTON ---
	dpad_left = _make_dpad_button("◀", col_left)
	dpad_left.position = Vector2(0, cell)
	dpad_container.add_child(dpad_left)
	
	# --- RIGHT BUTTON ---
	dpad_right = _make_dpad_button("▶", col_right)
	dpad_right.position = Vector2(cell * 2, cell)
	dpad_container.add_child(dpad_right)
	
	# --- SETUP HOLD TIMERS (Natural directions) ---
	up_timer    = _create_hold_timer(dpad_up,    Vector2(0, -1))
	down_timer  = _create_hold_timer(dpad_down,  Vector2(0, 1))
	left_timer  = _create_hold_timer(dpad_left,  Vector2(-1, 0))
	right_timer = _create_hold_timer(dpad_right, Vector2(1, 0))

# ==========================================
# HELPER: Create a hold-to-repeat timer for a button
# ==========================================
func _create_hold_timer(btn: Button, direction: Vector2) -> Timer:
	var timer = Timer.new()
	timer.wait_time = hold_repeat_speed
	timer.one_shot = false
	timer.autostart = false
	btn.add_child(timer)
	
	# Send direction * scroll_speed so we can control camera speed from UI
	var scaled_dir = direction * scroll_speed
	
	btn.button_down.connect(func():
		joystick_dragged.emit(scaled_dir)
		timer.start()
	)
	
	btn.button_up.connect(func():
		timer.stop()
		joystick_released.emit()
	)
	
	timer.timeout.connect(func():
		joystick_dragged.emit(scaled_dir)
	)
	
	return timer

# ==========================================
# TOOL HANDLING
# ==========================================
func _on_tool_button_pressed(tool: int) -> void:
	current_tool = tool
	tool_changed.emit(tool)
	update_tool_info(tool)

# ==========================================
# TILE HANDLING
# ==========================================
func update_tile_info(tile_names: Array[String], selected_index: int) -> void:
	selected_tile_index = selected_index
	
	for child in tile_grid.get_children():
		child.queue_free()
	
	tile_buttons.clear()
	
	for i in range(tile_names.size()):
		var btn = Button.new()
		btn.text = tile_names[i]
		btn.custom_minimum_size = Vector2(80, 80)
		btn.pressed.connect(_on_tile_button_pressed.bind(i))
		tile_grid.add_child(btn)
		tile_buttons.append(btn)
	
	update_tile_selection()

func _on_tile_button_pressed(index: int) -> void:
	selected_tile_index = index
	tile_selected.emit(index)
	update_tile_selection()

func update_tile_selection() -> void:
	for i in range(tile_buttons.size()):
		if i == selected_tile_index:
			tile_buttons[i].modulate = Color(1, 1, 0.5, 1)
		else:
			tile_buttons[i].modulate = Color(1, 1, 1, 1)

# ==========================================
# TOOL INFO UPDATE
# ==========================================
func update_tool_info(current_tool: int) -> void:
	pass
