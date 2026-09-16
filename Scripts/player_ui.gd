extends CanvasLayer

# --- Signals to send to the Player ---
signal ui_move_direction(direction: Vector2)
signal ui_attack_pressed
signal ui_jump_pressed
signal ui_rage_pressed

# --- Screen Size Detection ---
var screen_size : Vector2

# --- Joystick Variables ---
var joystick_base : Control # Changed from Panel to Control for custom drawing
var joystick_handle : Control # Changed from Panel to Control
var is_touching_joystick : bool = false
var joystick_touch_index : int = -1
var joystick_center : Vector2
var joystick_radius : float = 80.0
var joystick_handle_radius : float = 30.0

# --- Colors ---
const COLOR_BASE = Color(1, 1, 1, 0.15)
const COLOR_BASE_BORDER = Color(1, 1, 1, 0.3)
const COLOR_HANDLE = Color(1, 1, 1, 0.6)
const COLOR_ATTACK = Color(0.9, 0.2, 0.2, 0.7)  # Red
const COLOR_JUMP = Color(0.2, 0.8, 0.2, 0.7)    # Green
const COLOR_RAGE = Color(0.9, 0.8, 0.1, 0.7)    # Yellow

func _ready() -> void:
	# Get the actual viewport size (works on mobile and desktop)
	screen_size = get_viewport().get_visible_rect().size
	# Recalculate if screen resizes
	get_viewport().size_changed.connect(_on_viewport_resized)
	
	_build_joystick()
	_build_action_buttons()

func _on_viewport_resized() -> void:
	screen_size = get_viewport().get_visible_rect().size
	# Re-position UI elements on resize
	if joystick_base and is_instance_valid(joystick_base):
		joystick_base.position = Vector2(50, screen_size.y - (joystick_radius * 2) - 50)
	# It's easier to just clear and rebuild buttons on resize, but for simplicity 
	# we will just rely on anchors for the buttons below.

# --- Build the Left Joystick ---
func _build_joystick() -> void:
	# The joystick base (custom drawn circle)
	joystick_base = Control.new()
	joystick_base.custom_minimum_size = Vector2(joystick_radius * 2, joystick_radius * 2)
	joystick_base.position = Vector2(50, screen_size.y - (joystick_radius * 2) - 50)
	joystick_base.mouse_filter = Control.MOUSE_FILTER_STOP
	joystick_base.gui_input.connect(_on_joystick_gui_input)
	joystick_base.draw.connect(_draw_joystick_base)
	add_child(joystick_base)
	
	# The joystick handle (custom drawn circle)
	joystick_handle = Control.new()
	joystick_handle.custom_minimum_size = Vector2(joystick_handle_radius * 2, joystick_handle_radius * 2)
	joystick_handle.position = Vector2(joystick_radius - joystick_handle_radius, joystick_radius - joystick_handle_radius)
	joystick_handle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	joystick_handle.draw.connect(_draw_joystick_handle)
	joystick_base.add_child(joystick_handle)
	
	# Set the center point for calculations
	joystick_center = Vector2(joystick_radius, joystick_radius)

# --- Custom Drawing for the Joystick ---
func _draw_joystick_base() -> void:
	joystick_base.draw_circle(Vector2(joystick_radius, joystick_radius), joystick_radius, COLOR_BASE)
	# Draw a border for better visibility
	joystick_base.draw_arc(Vector2(joystick_radius, joystick_radius), joystick_radius, 0, TAU, 64, COLOR_BASE_BORDER, 2.0)

func _draw_joystick_handle() -> void:
	joystick_handle.draw_circle(Vector2(joystick_handle_radius, joystick_handle_radius), joystick_handle_radius, COLOR_HANDLE)

# --- Build the Right Action Buttons ---
func _build_action_buttons() -> void:
	var button_size = Vector2(90, 90) # Slightly larger
	var margin = 40.0
	var spacing = 110.0 # Space between buttons

	# Using Anchors for screen-size safety.
	# Anchors are 0-1, where 1 is the bottom/right of the screen.
	# This keeps the buttons in the corner regardless of screen shape.
	
	# ATTACK Button (Big Red)
	var attack_btn = _create_round_button("ATK", COLOR_ATTACK, button_size)
	attack_btn.anchor_left = 1.0
	attack_btn.anchor_top = 1.0
	attack_btn.anchor_right = 1.0
	attack_btn.anchor_bottom = 1.0
	attack_btn.offset_left = -margin - button_size.x
	attack_btn.offset_top = -margin - button_size.y - spacing
	attack_btn.offset_right = -margin
	attack_btn.offset_bottom = -margin - spacing
	attack_btn.pressed.connect(func(): ui_attack_pressed.emit())
	add_child(attack_btn)

	# JUMP Button (Green)
	var jump_btn = _create_round_button("JMP", COLOR_JUMP, button_size)
	jump_btn.anchor_left = 1.0
	jump_btn.anchor_top = 1.0
	jump_btn.anchor_right = 1.0
	jump_btn.anchor_bottom = 1.0
	jump_btn.offset_left = -margin - button_size.x - spacing
	jump_btn.offset_top = -margin - button_size.y - (spacing * 1.5)
	jump_btn.offset_right = -margin - spacing
	jump_btn.offset_bottom = -margin - (spacing * 1.5)
	jump_btn.pressed.connect(func(): ui_jump_pressed.emit())
	add_child(jump_btn)

	# RAGE Button (Yellow)
	var rage_btn = _create_round_button("RGE", COLOR_RAGE, button_size)
	rage_btn.anchor_left = 1.0
	rage_btn.anchor_top = 1.0
	rage_btn.anchor_right = 1.0
	rage_btn.anchor_bottom = 1.0
	rage_btn.offset_left = -margin - button_size.x
	rage_btn.offset_top = -margin - button_size.y
	rage_btn.offset_right = -margin
	rage_btn.offset_bottom = -margin
	rage_btn.pressed.connect(func(): ui_rage_pressed.emit())
	add_child(rage_btn)

# --- Helper to make nice round buttons ---
func _create_round_button(text: String, color: Color, size: Vector2) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.custom_minimum_size = size
	# Set the pivot to center for rotation if needed later
	btn.pivot_offset = size / 2.0
	
	var style = StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(int(size.x / 2.0))
	# Add a border for contrast
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(1, 1, 1, 0.5)
	
	btn.add_theme_stylebox_override("normal", style)
	
	# Add a slightly darker style for when pressed
	var pressed_style = style.duplicate()
	pressed_style.bg_color = color.darkened(0.3)
	btn.add_theme_stylebox_override("pressed", pressed_style)
	
	# Make font bigger
	btn.add_theme_font_size_override("font_size", 20)
	
	return btn

# --- Input Handling (Directly on the Joystick Base) ---
func _on_joystick_gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and not is_touching_joystick:
			is_touching_joystick = true
			joystick_touch_index = event.index
			
			# Update handle position immediately using local coords
			_update_joystick_handle(event.position)
			
		elif not event.pressed and event.index == joystick_touch_index:
			# Release
			is_touching_joystick = false
			joystick_touch_index = -1
			joystick_handle.position = Vector2(joystick_radius - joystick_handle_radius, joystick_radius - joystick_handle_radius)
			ui_move_direction.emit(Vector2.ZERO)

	elif event is InputEventScreenDrag and event.index == joystick_touch_index:
		_update_joystick_handle(event.position)
		
	# Support for desktop mouse testing
	elif event is InputEventMouseButton:
		if event.pressed:
			is_touching_joystick = true
			_update_joystick_handle(event.position)
		else:
			is_touching_joystick = false
			joystick_handle.position = Vector2(joystick_radius - joystick_handle_radius, joystick_radius - joystick_handle_radius)
			ui_move_direction.emit(Vector2.ZERO)
			
	elif event is InputEventMouseMotion and is_touching_joystick:
		_update_joystick_handle(event.position)

# --- Calculate and Clamp the Joystick Handle ---
func _update_joystick_handle(touch_pos: Vector2) -> void:
	# touch_pos is LOCAL to the joystick_base
	var delta = touch_pos - joystick_center
	var clamped_delta = delta.limit_length(joystick_radius)
	
	# Move the visual handle
	joystick_handle.position = Vector2(joystick_radius - joystick_handle_radius, joystick_radius - joystick_handle_radius) + clamped_delta
	
	# Normalize to get the direction (-1 to 1 range)
	var direction = clamped_delta / joystick_radius
	ui_move_direction.emit(direction)
