extends CanvasLayer

# ==========================================
# EXPORTS
# ==========================================
@export var swap_to_right_side : bool = false
@export var button_size : float = 90.0
@export var button_spacing : float = 6.0
@export var dpad_margin : float = 40.0
@export var hold_repeat_speed : float = 0.05
@export var scroll_speed : float = 8.0

# --- Smooth movement tuning ---
@export var smooth_accel : float = 900.0
@export var smooth_max_speed : float = 700.0

# --- Zoom tuning ---
@export var zoom_step : float = 0.15
@export var zoom_min : float = 0.25
@export var zoom_max : float = 3.0
@export var zoom_smooth_speed : float = 6.0

# --- Shell pickup scene (self-contained) ---
@export var shell_pickup_scene : PackedScene

# ==========================================
# 👾 ENEMY SCENES (mirror of BuildEditor.enemy_scenes)
# ==========================================
@export var enemy_scenes : Array[PackedScene] = []
@export var enemy_names : Array[String] = []

# ==========================================
# 🌍 WORLD MATERIALS CONFIG
# ==========================================
const WORLD_MATERIALS : Array = [
	{ "id": "water", "label": "🌊 Water", "color": Color(0.3, 0.6, 1.0) },
	# { "id": "lava", "label": "🔥 Lava", "color": Color(1.0, 0.4, 0.1) },
	# { "id": "ice",  "label": "❄️ Ice",  "color": Color(0.7, 0.9, 1.0) },
]

# ==========================================
# SIGNALS
# ==========================================
signal tile_selected(index: int)
signal shell_mode_activated
signal shell_mode_deactivated
signal shell_cycle_requested
signal tool_changed(tool: int)
signal undo_pressed
signal save_pressed
signal delete_all_pressed
signal joystick_dragged(offset: Vector2)
signal joystick_released
signal last_position_updated(position: Vector2)
signal menu_pressed
signal zoom_changed(new_zoom: float)
signal pan_mode_changed(is_panning: bool)
signal world_material_selected(material_id: String)   # 🌍
signal enemy_selected(scene_index: int)               # 👾

# ==========================================
# UI STATE
# ==========================================
var tile_buttons : Array[Button] = []
var selected_tile_index : int = 0
var current_tool : int = 0
var main_container : VBoxContainer
var tile_grid : GridContainer
var last_position_label : Label
var _panel : PanelContainer

# Shell controls
var shell_cycle_btn : Button
var _shell_button_mode : bool = false

# 🌍 World popup
var world_popup : Window
var world_popup_list : VBoxContainer

# 👾 Enemy popup
var enemy_popup : Window
var enemy_popup_list : VBoxContainer
var _selected_enemy_index : int = 0

# D-Pad
var dpad_up : Button
var dpad_down : Button
var dpad_left : Button
var dpad_right : Button
var dpad_container : Control

# Hold timers (legacy)
var up_timer : Timer
var down_timer : Timer
var left_timer : Timer
var right_timer : Timer

# --- Smooth movement state ---
var _dir_up : float = 0.0
var _dir_down : float = 0.0
var _dir_left : float = 0.0
var _dir_right : float = 0.0
var _current_velocity : Vector2 = Vector2.ZERO

# --- Zoom state ---
var _target_zoom : float = 1.0
var _current_zoom : float = 1.0
var _zoom_initialized : bool = false

# --- Pan mode state ---
var _pan_mode : bool = false
var pan_button : Button
var _pan_disabled_buttons : Array[BaseButton] = []
var _pan_grayed_controls : Array[Control] = []

# ==========================================
# 🎨 THEME PALETTE
# ==========================================
const THEME := {
	"bg_panel":       Color(0.09, 0.10, 0.14, 0.92),
	"bg_panel_edge":  Color(0.30, 0.55, 0.90, 0.55),
	"btn_base":       Color(0.16, 0.18, 0.24, 1.0),
	"btn_hover":      Color(0.22, 0.25, 0.33, 1.0),
	"btn_pressed":    Color(0.10, 0.12, 0.17, 1.0),
	"btn_border":     Color(0.35, 0.40, 0.52, 0.9),
	"text":           Color(0.92, 0.95, 1.00, 1.0),
	"text_dim":       Color(0.60, 0.66, 0.78, 1.0),
	"accent_gold":    Color(1.00, 0.82, 0.32, 1.0),
	"accent_green":   Color(0.35, 0.95, 0.55, 1.0),
	"accent_blue":    Color(0.45, 0.75, 1.00, 1.0),
	"accent_pink":    Color(1.00, 0.50, 0.68, 1.0),
	"accent_red":     Color(1.00, 0.38, 0.38, 1.0),
	"accent_cyan":    Color(0.45, 0.88, 1.00, 1.0),
	"accent_orange":  Color(1.00, 0.65, 0.30, 1.0),
	"disabled":       Color(0.45, 0.48, 0.55, 0.45),
}

# ==========================================
# INITIALIZATION
# ==========================================
func _ready() -> void:
	_autofill_enemy_names()
	_build_ui_elements()
	_build_dpad()
	_build_zoom_buttons()
	_build_pan_button()
	_build_world_popup()   # 🌍
	_build_enemy_popup()   # 👾

func _autofill_enemy_names() -> void:
	if enemy_names.size() < enemy_scenes.size():
		for i in range(enemy_names.size(), enemy_scenes.size()):
			var nm := "Enemy " + str(i + 1)
			if enemy_scenes[i] != null:
				nm = enemy_scenes[i].resource_path.get_file().get_basename()
			enemy_names.append(nm)

# ==========================================
# 🎨 STYLEBOX FACTORY
# ==========================================
func _make_flat_style(
	bg: Color,
	border: Color = Color.TRANSPARENT,
	border_w: int = 2,
	radius: int = 10,
	shadow: bool = false
) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	if border_w > 0 and border.a > 0.0:
		s.set_border_width_all(border_w)
		s.border_color = border
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	if shadow:
		s.shadow_color = Color(0, 0, 0, 0.4)
		s.shadow_size = 6
		s.shadow_offset = Vector2(0, 2)
	return s

# Applies a full modern look to any Button, with an accent tint.
func _style_button(btn: Button, accent: Color, font_size: int = 15) -> void:
	var base := THEME.btn_base.lerp(accent, 0.12)
	var hover := base.lerp(accent, 0.22).lightened(0.06)
	var pressed := base.darkened(0.30)
	var border := accent.darkened(0.15)

	btn.add_theme_stylebox_override("normal",
		_make_flat_style(base, border, 2, 10))
	btn.add_theme_stylebox_override("hover",
		_make_flat_style(hover, accent, 2, 10))
	btn.add_theme_stylebox_override("pressed",
		_make_flat_style(pressed, accent.darkened(0.25), 2, 10))
	btn.add_theme_stylebox_override("focus",
		_make_flat_style(Color.TRANSPARENT, accent, 2, 10))

	btn.add_theme_color_override("font_color", THEME.text)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", accent.lightened(0.15))
	btn.add_theme_color_override("font_disabled_color", THEME.disabled)
	btn.add_theme_font_size_override("font_size", font_size)

	btn.custom_minimum_size.y = max(btn.custom_minimum_size.y, 40)

# ==========================================
# BUILD MAIN UI
# ==========================================
func _build_ui_elements() -> void:
	var ui_root := Control.new()
	ui_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ui_root)

	# --- Framed panel behind the top-left controls ---
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_panel.position = Vector2(14, 14)
	_panel.custom_minimum_size = Vector2(360, 0)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var panel_style := _make_flat_style(
		THEME.bg_panel,
		THEME.bg_panel_edge,
		2,
		14,
		true
	)
	panel_style.content_margin_left = 16
	panel_style.content_margin_right = 16
	panel_style.content_margin_top = 14
	panel_style.content_margin_bottom = 14
	_panel.add_theme_stylebox_override("panel", panel_style)
	ui_root.add_child(_panel)

	main_container = VBoxContainer.new()
	main_container.add_theme_constant_override("separation", 10)
	_panel.add_child(main_container)

	# --- TITLE ---
	var title := Label.new()
	title.text = "MAP EDITOR"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", THEME.accent_blue)
	main_container.add_child(title)

	main_container.add_child(_make_divider())

	# --- TOOL ROW ---
	var tool_row := HBoxContainer.new()
	tool_row.add_theme_constant_override("separation", 8)
	main_container.add_child(tool_row)

	var place_btn := _make_styled_button("PLACE", THEME.accent_green)
	place_btn.pressed.connect(func(): _on_tool_button_pressed(0))
	tool_row.add_child(place_btn)

	var delete_btn := _make_styled_button("DELETE", THEME.accent_red)
	delete_btn.pressed.connect(func(): _on_tool_button_pressed(1))
	tool_row.add_child(delete_btn)

	var paint_delete_btn := _make_styled_button("PAINT", THEME.accent_orange)
	paint_delete_btn.pressed.connect(func(): _on_tool_button_pressed(2))
	tool_row.add_child(paint_delete_btn)

	# 🐚 Shell toggle
	var shell_btn := _make_styled_button("🐚 SHELL", THEME.accent_gold)
	shell_btn.pressed.connect(_on_shell_button_pressed)
	tool_row.add_child(shell_btn)

	# 🐚 Shell cycle — hidden until shell mode is on
	shell_cycle_btn = _make_styled_button("◀ ▶", THEME.accent_green, 14)
	shell_cycle_btn.visible = false
	shell_cycle_btn.pressed.connect(_on_shell_cycle_pressed)
	tool_row.add_child(shell_cycle_btn)

	# --- ACTION ROW ---
	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 8)
	main_container.add_child(action_row)

	var undo_btn := _make_styled_button("UNDO", THEME.accent_blue)
	undo_btn.pressed.connect(func(): undo_pressed.emit())
	action_row.add_child(undo_btn)

	var save_btn := _make_styled_button("SAVE", THEME.accent_green)
	save_btn.pressed.connect(func(): save_pressed.emit())
	action_row.add_child(save_btn)

	var delete_all_btn := _make_styled_button("CLEAR ALL", THEME.accent_red)
	delete_all_btn.pressed.connect(func(): delete_all_pressed.emit())
	action_row.add_child(delete_all_btn)

	# --- WORLD / ENEMY ROW ---
	var spawn_row := HBoxContainer.new()
	spawn_row.add_theme_constant_override("separation", 8)
	main_container.add_child(spawn_row)

	var world_btn := _make_styled_button("🌍 WORLD", THEME.accent_cyan)
	world_btn.pressed.connect(_on_world_button_pressed)
	spawn_row.add_child(world_btn)

	var enemy_btn := _make_styled_button("👾 ENEMIES", THEME.accent_pink)
	enemy_btn.pressed.connect(_on_enemy_button_pressed)
	spawn_row.add_child(enemy_btn)

	var menu_btn := _make_styled_button("≡ MENU", THEME.text_dim)
	menu_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://intro_menu.tscn"))
	spawn_row.add_child(menu_btn)

	# Track buttons that support `disabled`
	for btn in [place_btn, delete_btn, paint_delete_btn, shell_btn,
			shell_cycle_btn, undo_btn, save_btn, delete_all_btn,
			world_btn, enemy_btn, menu_btn]:
		_pan_disabled_buttons.append(btn)

	# --- INFO ROW ---
	main_container.add_child(_make_divider())

	var info_container := HBoxContainer.new()
	info_container.add_theme_constant_override("separation", 8)
	main_container.add_child(info_container)

	var position_label_prefix := Label.new()
	position_label_prefix.text = "LAST POSITION"
	position_label_prefix.add_theme_font_size_override("font_size", 12)
	position_label_prefix.add_theme_color_override("font_color", THEME.text_dim)
	position_label_prefix.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	info_container.add_child(position_label_prefix)

	last_position_label = Label.new()
	last_position_label.text = "NONE"
	last_position_label.add_theme_font_size_override("font_size", 13)
	last_position_label.add_theme_color_override("font_color", THEME.accent_green)
	last_position_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	last_position_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_container.add_child(last_position_label)

	# --- TILE GRID ---
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 300)
	main_container.add_child(scroll)

	tile_grid = GridContainer.new()
	tile_grid.columns = 4
	tile_grid.add_theme_constant_override("h_separation", 6)
	tile_grid.add_theme_constant_override("v_separation", 6)
	tile_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(tile_grid)

	_pan_grayed_controls.append(scroll)

# ==========================================
# SMALL UI HELPERS
# ==========================================
func _make_styled_button(label: String, accent: Color, font_size: int = 15) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_button(btn, accent, font_size)
	return btn

func _make_divider() -> HSeparator:
	var sep := HSeparator.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1, 1, 1, 0.08)
	style.content_margin_top = 1
	style.content_margin_bottom = 1
	sep.add_theme_stylebox_override("separator", style)
	return sep

# ==========================================
# 🌍 WORLD POPUP
# ==========================================
func _build_world_popup() -> void:
	world_popup = Window.new()
	world_popup.title = "World Materials"
	world_popup.size = Vector2(360, 320)
	world_popup.visible = false
	world_popup.exclusive = true
	world_popup.min_size = Vector2(300, 240)
	world_popup.close_requested.connect(func(): world_popup.visible = false)
	add_child(world_popup)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 12
	vbox.offset_top = 12
	vbox.offset_right = -12
	vbox.offset_bottom = -12
	vbox.add_theme_constant_override("separation", 8)
	world_popup.add_child(vbox)

	var hint := Label.new()
	hint.text = "Choose a world material to place"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", THEME.text_dim)
	vbox.add_child(hint)

	vbox.add_child(_make_divider())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	world_popup_list = VBoxContainer.new()
	world_popup_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	world_popup_list.add_theme_constant_override("separation", 6)
	scroll.add_child(world_popup_list)

	_populate_world_popup()

	var close_btn := _make_styled_button("CLOSE", THEME.accent_blue)
	close_btn.pressed.connect(func(): world_popup.visible = false)
	vbox.add_child(close_btn)

func _populate_world_popup() -> void:
	for child in world_popup_list.get_children():
		child.queue_free()

	for entry in WORLD_MATERIALS:
		var mat_id : String = entry.get("id", "")
		var label  : String = entry.get("label", mat_id.capitalize())
		var col    : Color  = entry.get("color", Color.WHITE)

		var btn := Button.new()
		btn.text = label
		btn.custom_minimum_size = Vector2(0, 52)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_style_button(btn, col, 16)
		btn.pressed.connect(_on_world_material_pressed.bind(mat_id))
		world_popup_list.add_child(btn)

func _on_world_button_pressed() -> void:
	if _pan_mode:
		return
	if world_popup == null:
		_build_world_popup()
	_populate_world_popup()
	world_popup.popup_centered()
	print("🌍 World popup opened")

func _on_world_material_pressed(material_id: String) -> void:
	if world_popup:
		world_popup.visible = false
	world_material_selected.emit(material_id)
	print("🌍 World material chosen: ", material_id)

# ==========================================
# 👾 ENEMY POPUP
# ==========================================
func _build_enemy_popup() -> void:
	enemy_popup = Window.new()
	enemy_popup.title = "Enemy Scenes"
	enemy_popup.size = Vector2(380, 460)
	enemy_popup.visible = false
	enemy_popup.exclusive = true
	enemy_popup.min_size = Vector2(300, 280)
	enemy_popup.close_requested.connect(func(): enemy_popup.visible = false)
	add_child(enemy_popup)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 12
	vbox.offset_top = 12
	vbox.offset_right = -12
	vbox.offset_bottom = -12
	vbox.add_theme_constant_override("separation", 8)
	enemy_popup.add_child(vbox)

	var hint := Label.new()
	hint.text = "Pick an enemy to place"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", THEME.text_dim)
	vbox.add_child(hint)

	vbox.add_child(_make_divider())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	enemy_popup_list = VBoxContainer.new()
	enemy_popup_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	enemy_popup_list.add_theme_constant_override("separation", 6)
	scroll.add_child(enemy_popup_list)

	var close_btn := _make_styled_button("CLOSE", THEME.accent_blue)
	close_btn.pressed.connect(func(): enemy_popup.visible = false)
	vbox.add_child(close_btn)

func _populate_enemy_popup() -> void:
	for child in enemy_popup_list.get_children():
		child.queue_free()

	if enemy_scenes.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "⚠  No enemy scenes assigned"
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.add_theme_color_override("font_color", THEME.accent_red)
		enemy_popup_list.add_child(empty_lbl)
		return

	for i in range(enemy_scenes.size()):
		var scene := enemy_scenes[i]
		var label := ""
		if i < enemy_names.size() and not enemy_names[i].is_empty():
			label = enemy_names[i]
		elif scene != null:
			label = scene.resource_path.get_file().get_basename()
		else:
			label = "Enemy " + str(i + 1)

		var prefix := "▶  " if i == _selected_enemy_index else "     "

		var btn := Button.new()
		btn.text = prefix + label
		btn.custom_minimum_size = Vector2(0, 52)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if scene == null:
			_style_button(btn, THEME.text_dim, 15)
			btn.disabled = true
		else:
			_style_button(btn, THEME.accent_pink, 15)
		btn.pressed.connect(_on_enemy_scene_pressed.bind(i))
		enemy_popup_list.add_child(btn)

func _on_enemy_button_pressed() -> void:
	if _pan_mode:
		return
	if enemy_popup == null:
		_build_enemy_popup()
	_populate_enemy_popup()
	enemy_popup.popup_centered()
	print("👾 Enemy popup opened")

func _on_enemy_scene_pressed(scene_index: int) -> void:
	_selected_enemy_index = scene_index
	if enemy_popup:
		enemy_popup.visible = false
	enemy_selected.emit(scene_index)
	print("👾 Enemy chosen: index ", scene_index)

# ==========================================
# 🐚 SHELL BUTTON HANDLERS
# ==========================================
func _on_shell_button_pressed() -> void:
	if _pan_mode:
		return

	_shell_button_mode = not _shell_button_mode

	if shell_cycle_btn:
		shell_cycle_btn.visible = _shell_button_mode

	if _shell_button_mode:
		shell_mode_activated.emit()
		print("🐚 Shell placement mode ON")
	else:
		shell_mode_deactivated.emit()
		print("🐚 Shell placement mode OFF")

func _on_shell_cycle_pressed() -> void:
	if _pan_mode:
		return
	shell_cycle_requested.emit()
	print("🐚 Shell cycle requested")

func set_shell_cycle_label(shell_name: String) -> void:
	if shell_cycle_btn:
		shell_cycle_btn.text = "◀ " + shell_name + " ▶"

func instantiate_shell_pickup() -> Node:
	if shell_pickup_scene == null:
		push_warning("⚠️ shell_pickup_scene is not assigned!")
		return null
	return shell_pickup_scene.instantiate()

# ==========================================
# LAST POSITION
# ==========================================
func update_last_position(position: Vector2) -> void:
	if last_position_label:
		last_position_label.text = "X: %d, Y: %d" % [position.x, position.y]
		last_position_updated.emit(position)

func clear_last_position() -> void:
	if last_position_label:
		last_position_label.text = "NONE"
		last_position_label.add_theme_color_override("font_color", THEME.accent_green)

# ==========================================
# D-PAD BUTTON STYLE
# ==========================================
func _make_dpad_button(symbol: String, color: Color) -> Button:
	var btn := Button.new()
	btn.text = symbol
	btn.custom_minimum_size = Vector2(button_size, button_size)
	btn.add_theme_font_size_override("font_size", int(button_size * 0.5))

	var style_normal := StyleBoxFlat.new()
	style_normal.bg_color = color
	style_normal.set_corner_radius_all(int(button_size * 0.22))
	style_normal.set_border_width_all(3)
	style_normal.border_color = Color(1, 1, 1, 0.35)
	style_normal.shadow_color = Color(0, 0, 0, 0.35)
	style_normal.shadow_size = 6
	style_normal.shadow_offset = Vector2(0, 3)
	btn.add_theme_stylebox_override("normal", style_normal)

	var style_pressed := style_normal.duplicate()
	style_pressed.bg_color = color.darkened(0.4)
	style_pressed.shadow_size = 2
	btn.add_theme_stylebox_override("pressed", style_pressed)

	var style_hover := style_normal.duplicate()
	style_hover.bg_color = color.lightened(0.12)
	btn.add_theme_stylebox_override("hover", style_hover)

	btn.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	btn.add_theme_color_override("font_pressed_color", Color.WHITE)

	return btn

func _make_zoom_button(symbol: String, color: Color, size: Vector2) -> Button:
	var btn := Button.new()
	btn.text = symbol
	btn.custom_minimum_size = size
	btn.add_theme_font_size_override("font_size", 28)

	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(int(size.x * 0.3))
	style.set_border_width_all(2)
	style.border_color = Color(1, 1, 1, 0.5)
	style.shadow_color = Color(0, 0, 0, 0.35)
	style.shadow_size = 5
	style.shadow_offset = Vector2(0, 2)
	btn.add_theme_stylebox_override("normal", style)

	var pressed_style := style.duplicate()
	pressed_style.bg_color = color.darkened(0.3)
	pressed_style.shadow_size = 1
	btn.add_theme_stylebox_override("pressed", pressed_style)

	var hover_style := style.duplicate()
	hover_style.bg_color = color.lightened(0.12)
	btn.add_theme_stylebox_override("hover", hover_style)

	btn.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))

	return btn

# ==========================================
# BUILD D-PAD
# ==========================================
func _build_dpad() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var cell := button_size + button_spacing
	var grid_size := (button_size * 3) + (button_spacing * 2)

	dpad_container = Control.new()
	dpad_container.size = Vector2(grid_size, grid_size)

	if swap_to_right_side:
		dpad_container.position = Vector2(
			viewport_size.x - grid_size - dpad_margin,
			viewport_size.y - grid_size - dpad_margin
		)
	else:
		dpad_container.position = Vector2(
			dpad_margin,
			viewport_size.y - grid_size - dpad_margin
		)

	add_child(dpad_container)

	var col_up    := Color(0.30, 0.78, 0.45, 0.90)
	var col_down  := Color(0.88, 0.38, 0.42, 0.90)
	var col_left  := Color(0.38, 0.60, 0.90, 0.90)
	var col_right := Color(0.92, 0.78, 0.32, 0.90)

	dpad_up = _make_dpad_button("▲", col_up)
	dpad_up.position = Vector2(button_size + button_spacing, 0)
	dpad_container.add_child(dpad_up)

	dpad_down = _make_dpad_button("▼", col_down)
	dpad_down.position = Vector2(button_size + button_spacing, cell * 2)
	dpad_container.add_child(dpad_down)

	dpad_left = _make_dpad_button("◀", col_left)
	dpad_left.position = Vector2(0, cell)
	dpad_container.add_child(dpad_left)

	dpad_right = _make_dpad_button("▶", col_right)
	dpad_right.position = Vector2(cell * 2, cell)
	dpad_container.add_child(dpad_right)

	_connect_smooth_direction(dpad_up,    "up")
	_connect_smooth_direction(dpad_down,  "down")
	_connect_smooth_direction(dpad_left,  "left")
	_connect_smooth_direction(dpad_right, "right")

# ==========================================
# SMOOTH DIRECTION HOOKUP
# ==========================================
func _connect_smooth_direction(btn: Button, dir_name: String) -> void:
	btn.button_down.connect(func(): _set_dir(dir_name, true))
	btn.button_up.connect(func(): _set_dir(dir_name, false))
	btn.mouse_exited.connect(func():
		if not btn.button_pressed:
			_set_dir(dir_name, false)
	)

func _set_dir(dir_name: String, value: bool) -> void:
	var v := 1.0 if value else 0.0
	match dir_name:
		"up":    _dir_up = v
		"down":  _dir_down = v
		"left":  _dir_left = v
		"right": _dir_right = v

# ==========================================
# SMOOTH MOVEMENT + ZOOM (runs every frame)
# ==========================================
func _process(delta: float) -> void:
	var input_vec := Vector2(
		_dir_right - _dir_left,
		_dir_down  - _dir_up
	)

	if input_vec.length() > 1.0:
		input_vec = input_vec.normalized()

	var target_velocity := input_vec * smooth_max_speed
	_current_velocity = _current_velocity.move_toward(target_velocity, smooth_accel * delta)

	if _current_velocity.length_squared() > 0.01:
		joystick_dragged.emit(_current_velocity * delta)

	if _zoom_initialized:
		_current_zoom = lerp(_current_zoom, _target_zoom, clamp(zoom_smooth_speed * delta, 0.0, 1.0))
		zoom_changed.emit(_current_zoom)

# ==========================================
# BUILD ZOOM BUTTONS
# ==========================================
func _build_zoom_buttons() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var zbtn_size := 60.0
	var margin := 40.0
	var gap := 10.0

	var zoom_in_btn := _make_zoom_button("+", Color(0.35, 0.70, 1.0, 0.90), Vector2(zbtn_size, zbtn_size))
	zoom_in_btn.position = Vector2(
		viewport_size.x - zbtn_size - margin,
		dpad_margin + 100.0
	)
	zoom_in_btn.pressed.connect(_on_zoom_in)
	add_child(zoom_in_btn)

	var zoom_out_btn := _make_zoom_button("−", Color(0.35, 0.70, 1.0, 0.90), Vector2(zbtn_size, zbtn_size))
	zoom_out_btn.position = Vector2(
		viewport_size.x - zbtn_size - margin,
		dpad_margin + 100.0 + zbtn_size + gap
	)
	zoom_out_btn.pressed.connect(_on_zoom_out)
	add_child(zoom_out_btn)

	_pan_disabled_buttons.append(zoom_in_btn)
	_pan_disabled_buttons.append(zoom_out_btn)

func _on_zoom_in() -> void:
	if _pan_mode:
		return
	if not _zoom_initialized:
		_init_zoom_from_camera()
	_target_zoom = clamp(_target_zoom + zoom_step, zoom_min, zoom_max)

func _on_zoom_out() -> void:
	if _pan_mode:
		return
	if not _zoom_initialized:
		_init_zoom_from_camera()
	_target_zoom = clamp(_target_zoom - zoom_step, zoom_min, zoom_max)

func _init_zoom_from_camera() -> void:
	var cam := get_viewport().get_camera_2d()
	if cam:
		_current_zoom = cam.zoom.x
		_target_zoom = cam.zoom.x
	_zoom_initialized = true

# ==========================================
# PAN BUTTON
# ==========================================
func _build_pan_button() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var pan_size := Vector2(110, 60)
	var margin := 40.0

	pan_button = Button.new()
	pan_button.text = "✋  PAN"
	pan_button.custom_minimum_size = pan_size
	pan_button.toggle_mode = true
	pan_button.position = Vector2(
		viewport_size.x - pan_size.x - margin,
		dpad_margin + 100.0 + 60.0 + 10.0 + 60.0 + 20.0
	)

	var style_normal := StyleBoxFlat.new()
	style_normal.bg_color = Color(0.75, 0.55, 0.18, 0.92)
	style_normal.set_corner_radius_all(14)
	style_normal.set_border_width_all(2)
	style_normal.border_color = Color(1, 1, 1, 0.35)
	style_normal.shadow_color = Color(0, 0, 0, 0.35)
	style_normal.shadow_size = 5
	style_normal.shadow_offset = Vector2(0, 2)
	style_normal.content_margin_left = 14
	style_normal.content_margin_right = 14
	pan_button.add_theme_stylebox_override("normal", style_normal)

	var style_pressed := style_normal.duplicate()
	style_pressed.bg_color = Color(0.20, 0.80, 0.35, 0.98)
	style_pressed.shadow_size = 1
	pan_button.add_theme_stylebox_override("pressed", style_pressed)

	var style_hover := style_normal.duplicate()
	style_hover.bg_color = style_normal.bg_color.lightened(0.12)
	pan_button.add_theme_stylebox_override("hover", style_hover)

	pan_button.add_theme_font_size_override("font_size", 17)
	pan_button.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	pan_button.add_theme_color_override("font_pressed_color", Color.WHITE)
	pan_button.toggled.connect(_on_pan_toggled)
	add_child(pan_button)

func _on_pan_toggled(pressed: bool) -> void:
	_pan_mode = pressed

	for btn in _pan_disabled_buttons:
		if is_instance_valid(btn):
			btn.disabled = pressed
			btn.modulate = THEME.disabled if pressed else Color.WHITE

	for ctrl in _pan_grayed_controls:
		if is_instance_valid(ctrl):
			ctrl.modulate = THEME.disabled if pressed else Color.WHITE
			ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE if pressed else Control.MOUSE_FILTER_STOP

	if pressed:
		_dir_up = 0.0
		_dir_down = 0.0
		_dir_left = 0.0
		_dir_right = 0.0

	pan_button.text = "✋  PAN ON" if pressed else "✋  PAN"
	pan_mode_changed.emit(pressed)
	print("✋ Pan mode: ", pressed)

# ==========================================
# TILE HELPERS
# ==========================================
func _on_tool_button_pressed(tool: int) -> void:
	if _pan_mode:
		return
	current_tool = tool
	tool_changed.emit(tool)
	update_tool_info(tool)

func update_tile_info(tile_names: Array[String], selected_index: int) -> void:
	selected_tile_index = selected_index

	for child in tile_grid.get_children():
		child.queue_free()

	tile_buttons.clear()

	for i in range(tile_names.size()):
		var btn := Button.new()
		btn.text = tile_names[i]
		btn.custom_minimum_size = Vector2(80, 80)
		_style_button(btn, THEME.accent_blue, 14)
		btn.pressed.connect(_on_tile_button_pressed.bind(i))
		tile_grid.add_child(btn)
		tile_buttons.append(btn)

	update_tile_selection()

func _on_tile_button_pressed(index: int) -> void:
	if _pan_mode:
		return
	selected_tile_index = index
	tile_selected.emit(index)
	update_tile_selection()

func update_tile_selection() -> void:
	for i in range(tile_buttons.size()):
		if i == selected_tile_index:
			tile_buttons[i].modulate = Color(1, 1, 0.5, 1)
		else:
			tile_buttons[i].modulate = Color(1, 1, 1, 1)

func update_tool_info(_current_tool: int) -> void:
	pass
