extends CanvasLayer

# --- Signals to send to the Player ---
signal ui_move_direction(direction: Vector2)
signal ui_attack_pressed
signal ui_jump_pressed
signal ui_jump_released     # 🔴 Fires when jump button is released
signal ui_rage_pressed

# --- Exported Menu Scene Path ---
@export_file("*.tscn") var menu_scene_path : String = "res://intro_menu.tscn"

# --- Exported Keyboard Bindings (For PC) ---
@export var key_move_up : Array[Key] = [KEY_W, KEY_UP]
@export var key_move_down : Array[Key] = [KEY_S, KEY_DOWN]
@export var key_move_left : Array[Key] = [KEY_A, KEY_LEFT]
@export var key_move_right : Array[Key] = [KEY_D, KEY_RIGHT]
@export var key_attack : Key = KEY_V
@export var key_jump : Key = KEY_SPACE
@export var key_rage : Key = KEY_R

# --- Pause Menu ---
@export_group("Pause Menu")
@export var pause_panel : Control = null               # 👈 drag the child Control scene here
@export var pause_button_text : String = "❚❚ PAUSE"
@export var pause_button_color : Color = Color(0.3, 0.5, 0.9, 0.85)
@export var start_with_pause_hidden : bool = true

# --- HUD Configuration ---
@export_group("HUD")
@export var hud_texture : Texture2D              # React box texture (top-left icon)
@export var hud_char_name : String = "Herbie"
@export var hud_box_size : Vector2 = Vector2(48, 48)
@export var hud_bar_size : Vector2 = Vector2(180, 24)
@export var hud_margin : Vector2 = Vector2(20, 20)
@export var hud_bar_fill_color : Color = Color(0.9, 0.25, 0.25, 1.0)
@export var hud_bar_bg_color : Color = Color(0.08, 0.08, 0.08, 0.9)
@export var hud_bar_border_color: Color = Color(1, 1, 1, 0.5)
@export var hud_name_font_size : int = 16

# 🎯 Health — set this from the player on _ready()
@export var hud_max_health : int = 3
@export var hud_tween_duration : float = 0.45
@export var hud_tween_trans : Tween.TransitionType = Tween.TRANS_CUBIC
@export var hud_tween_ease : Tween.EaseType = Tween.EASE_OUT

# --- Screen Size Detection ---
var screen_size : Vector2

# --- Joystick Variables ---
var joystick_base : Control
var joystick_handle : Control
var is_touching_joystick : bool = false
var joystick_touch_index : int = -1
var joystick_center : Vector2
var joystick_radius : float = 80.0
var joystick_handle_radius : float = 30.0

# --- HUD Nodes ---
var hud_root : Control
var hud_texture_rect : TextureRect
var hud_progress_bar : ProgressBar
var hud_name_label : Label
var _hud_tween : Tween

# --- Pause Button ---
var _pause_button : Button = null

# --- Colors ---
const COLOR_BASE = Color(1, 1, 1, 0.15)
const COLOR_BASE_BORDER = Color(1, 1, 1, 0.3)
const COLOR_HANDLE = Color(1, 1, 1, 0.6)
const COLOR_ATTACK = Color(0.9, 0.2, 0.2, 0.7)
const COLOR_JUMP = Color(0.2, 0.8, 0.2, 0.7)
const COLOR_RAGE = Color(0.9, 0.8, 0.1, 0.7)
const COLOR_MENU = Color(0.3, 0.5, 0.9, 0.85)
func _ready() -> void:
	_build_hud()

	screen_size = get_viewport().get_visible_rect().size
	get_viewport().size_changed.connect(_on_viewport_resized)

	# 🆕 Pause menu setup — hide the panel initially if requested
	if pause_panel:
		pause_panel.visible = not start_with_pause_hidden
		# 🔗 Find the actual pause menu node (may be nested inside a wrapper)
		var actual_menu := _find_pause_menu_node(pause_panel)
		if actual_menu and actual_menu.has_signal("ui_resumed"):
			actual_menu.ui_resumed.connect(_on_pause_menu_resumed)
			print("🔗 Connected to pause menu's ui_resumed signal (on ", actual_menu.name, ")")
		else:
			print("⚠️ Could not find a node with 'ui_resumed' inside pause_panel.")
	else:
		print("⚠️ UI: no pause_panel assigned in the Inspector.")

	if _is_desktop_platform():
		_build_pause_button()
		return

	_build_joystick()
	_build_action_buttons()
	_build_pause_button()


# ==========================================
# 🔍 HELPER — find the node that owns `ui_resumed`
# The pause menu may be nested inside a wrapper node, so we search
# the wrapper's children for the one that actually has the signal.
# ==========================================
func _find_pause_menu_node(root: Node) -> Node:
	if root == null:
		return null
	if root.has_signal("ui_resumed"):
		return root
	for child in root.get_children():
		var found := _find_pause_menu_node(child)
		if found != null:
			return found
	return null

func _is_desktop_platform() -> bool:
	var os_name = OS.get_name()
	return os_name == "Windows" or os_name == "macOS" or os_name == "Linux" or os_name == "X11"

func _on_viewport_resized() -> void:
	screen_size = get_viewport().get_visible_rect().size
	if joystick_base and is_instance_valid(joystick_base):
		joystick_base.position = Vector2(50, screen_size.y - (joystick_radius * 2) - 50)

# ==========================================
# 🎨 HUD (Top-Left)
# ==========================================
func _build_hud() -> void:
	hud_root = Control.new()
	hud_root.name = "HUD"
	hud_root.position = hud_margin
	hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.size = Vector2(hud_box_size.x + 8 + hud_bar_size.x, hud_box_size.y + 28)
	add_child(hud_root)
	
	# --- Fixed-size wrapper that clamps the texture ---
	# The wrapper is a plain Control with a locked size + clip_contents.
	# The TextureRect inside fills the wrapper and can NEVER grow past it.
	var tex_wrapper := Control.new()
	tex_wrapper.name = "HUDTextureWrapper"
	tex_wrapper.position = Vector2.ZERO
	tex_wrapper.size = hud_box_size
	tex_wrapper.custom_minimum_size = hud_box_size
	tex_wrapper.clip_contents = true
	tex_wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(tex_wrapper)
	
	hud_texture_rect = TextureRect.new()
	hud_texture_rect.name = "HUDTexture"
	hud_texture_rect.texture = hud_texture
	hud_texture_rect.set_anchors_preset(Control.PRESET_FULL_RECT)  # fill the wrapper
	hud_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hud_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	hud_texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tex_wrapper.add_child(hud_texture_rect)
	
	# --- Progress bar next to the texture ---
	hud_progress_bar = ProgressBar.new()
	hud_progress_bar.name = "HUDProgressBar"
	hud_progress_bar.min_value = 0.0
	hud_progress_bar.max_value = float(hud_max_health)
	hud_progress_bar.value = float(hud_max_health)
	hud_progress_bar.show_percentage = false
	hud_progress_bar.position = Vector2(
		hud_box_size.x + 8,
		(hud_box_size.y - hud_bar_size.y) * 0.5
	)
	hud_progress_bar.size = hud_bar_size
	hud_progress_bar.custom_minimum_size = hud_bar_size
	hud_progress_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = hud_bar_bg_color
	bg_style.set_corner_radius_all(4)
	bg_style.set_border_width_all(2)
	bg_style.border_color = hud_bar_border_color
	hud_progress_bar.add_theme_stylebox_override("background", bg_style)
	
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = hud_bar_fill_color
	fill_style.set_corner_radius_all(4)
	hud_progress_bar.add_theme_stylebox_override("fill", fill_style)
	
	hud_root.add_child(hud_progress_bar)
	
	# --- Character name below the bar ---
	hud_name_label = Label.new()
	hud_name_label.name = "HUDName"
	hud_name_label.text = hud_char_name
	hud_name_label.add_theme_font_size_override("font_size", hud_name_font_size)
	hud_name_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	hud_name_label.position = Vector2(0, hud_box_size.y + 2)
	hud_name_label.size = Vector2(hud_box_size.x + 8 + hud_bar_size.x, 24)
	hud_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	hud_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(hud_name_label)

# ==========================================
# ❤️ HUD PUBLIC API
# ==========================================
func set_hud_max_health(new_max: int) -> void:
	hud_max_health = max(1, new_max)
	if hud_progress_bar == null:
		return
	hud_progress_bar.max_value = float(hud_max_health)
	hud_progress_bar.value = float(hud_max_health)

func set_hud_health(current: int) -> void:
	if hud_progress_bar == null:
		return
	
	var target : float = clamp(float(current), 0.0, float(hud_max_health))
	
	if _hud_tween and _hud_tween.is_valid():
		_hud_tween.kill()
	
	_hud_tween = create_tween()
	_hud_tween.set_trans(hud_tween_trans)
	_hud_tween.set_ease(hud_tween_ease)
	_hud_tween.tween_property(hud_progress_bar, "value", target, hud_tween_duration)

func set_hud_name(new_name: String) -> void:
	if hud_name_label == null:
		return
	hud_name_label.text = new_name

func set_hud_texture(tex: Texture2D) -> void:
	if hud_texture_rect == null:
		return
	hud_texture_rect.texture = tex

# ==========================================
# ⌨️ KEYBOARD INPUT (Desktop)
# ==========================================
func _unhandled_input(event: InputEvent) -> void:
	if not _is_desktop_platform():
		return

	if event is InputEventKey:
		if event.pressed and not event.echo:
			if event.keycode == key_attack:
				ui_attack_pressed.emit()
			elif event.keycode == key_jump:
				ui_jump_pressed.emit()
			elif event.keycode == key_rage:
				ui_rage_pressed.emit()
		elif not event.pressed:
			if event.keycode == key_jump:
				ui_jump_released.emit()
		
		_update_keyboard_movement()

func _update_keyboard_movement() -> void:
	var move_vec = Vector2.ZERO
	
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		move_vec.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		move_vec.y += 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		move_vec.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		move_vec.x += 1
		
	if move_vec.length() > 1:
		move_vec = move_vec.normalized()
		
	ui_move_direction.emit(move_vec)

# --- Build the Left Joystick ---
func _build_joystick() -> void:
	joystick_base = Control.new()
	joystick_base.custom_minimum_size = Vector2(joystick_radius * 2, joystick_radius * 2)
	joystick_base.position = Vector2(50, screen_size.y - (joystick_radius * 2) - 50)
	joystick_base.mouse_filter = Control.MOUSE_FILTER_STOP
	joystick_base.gui_input.connect(_on_joystick_gui_input)
	joystick_base.draw.connect(_draw_joystick_base)
	add_child(joystick_base)
	
	joystick_handle = Control.new()
	joystick_handle.custom_minimum_size = Vector2(joystick_handle_radius * 2, joystick_handle_radius * 2)
	joystick_handle.position = Vector2(joystick_radius - joystick_handle_radius, joystick_radius - joystick_handle_radius)
	joystick_handle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	joystick_handle.draw.connect(_draw_joystick_handle)
	joystick_base.add_child(joystick_handle)
	
	joystick_center = Vector2(joystick_radius, joystick_radius)

func _draw_joystick_base() -> void:
	joystick_base.draw_circle(Vector2(joystick_radius, joystick_radius), joystick_radius, COLOR_BASE)
	joystick_base.draw_arc(Vector2(joystick_radius, joystick_radius), joystick_radius, 0, TAU, 64, COLOR_BASE_BORDER, 2.0)

func _draw_joystick_handle() -> void:
	joystick_handle.draw_circle(Vector2(joystick_handle_radius, joystick_handle_radius), joystick_handle_radius, COLOR_HANDLE)

# --- Build the Right Action Buttons ---
func _build_action_buttons() -> void:
	var button_size = Vector2(90, 90)
	var margin = 40.0
	var spacing = 110.0

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

	var jump_btn = _create_round_button("JMP", COLOR_JUMP, button_size, true)
	jump_btn.anchor_left = 1.0
	jump_btn.anchor_top = 1.0
	jump_btn.anchor_right = 1.0
	jump_btn.anchor_bottom = 1.0
	jump_btn.offset_left = -margin - button_size.x - spacing
	jump_btn.offset_top = -margin - button_size.y - (spacing * 1.5)
	jump_btn.offset_right = -margin - spacing
	jump_btn.offset_bottom = -margin - (spacing * 1.5)
	jump_btn.button_down.connect(func(): ui_jump_pressed.emit())
	jump_btn.button_up.connect(func(): ui_jump_released.emit())
	add_child(jump_btn)

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

# --- PAUSE Button (top-right) ---
func _build_pause_button() -> void:
	var button_size = Vector2(100, 50)
	var margin = 40.0
	
	_pause_button = _create_round_button(pause_button_text, pause_button_color, button_size)
	_pause_button.anchor_left = 1.0
	_pause_button.anchor_top = 0.0
	_pause_button.anchor_right = 1.0
	_pause_button.anchor_bottom = 0.0
	_pause_button.offset_left = -margin - button_size.x
	_pause_button.offset_top = margin
	_pause_button.offset_right = -margin
	_pause_button.offset_bottom = margin + button_size.y
	_pause_button.add_theme_font_size_override("font_size", 16)
	_pause_button.pressed.connect(_on_pause_pressed)
	add_child(_pause_button)

# ==========================================
# ⏸️ PAUSE TOGGLE + RESUME HANDLER
# ==========================================
func _on_pause_pressed() -> void:
	if pause_panel == null or not is_instance_valid(pause_panel):
		return
	
	if not pause_panel.visible:
		_show_pause_menu()
		_freeze_world(true)
	else:
		_hide_pause_menu()
		_freeze_world(false)

func _show_pause_menu() -> void:
	# Hide every CanvasItem child EXCEPT the pause panel
	for child in get_children():
		if child == pause_panel:
			continue
		if child is CanvasItem:
			(child as CanvasItem).visible = false
	pause_panel.visible = true
	print("⏸️ Pause menu shown")

func _hide_pause_menu() -> void:
	# Show every CanvasItem child again
	for child in get_children():
		if child is CanvasItem:
			(child as CanvasItem).visible = true
	pause_panel.visible = false
	print("▶️ Pause menu hidden — UI restored")

# 🔗 Called when the pause menu emits `ui_resumed` (Continue clicked)

func _on_pause_menu_resumed() -> void:
	_hide_pause_menu()
	_freeze_world(false)   # 👈 add this

func _create_round_button(text: String, color: Color, size: Vector2, use_hold_mode: bool = false) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.custom_minimum_size = size
	btn.pivot_offset = size / 2.0
	
	var style = StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(int(size.x / 2.0))
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(1, 1, 1, 0.5)
	
	btn.add_theme_stylebox_override("normal", style)
	
	var pressed_style = style.duplicate()
	pressed_style.bg_color = color.darkened(0.3)
	btn.add_theme_stylebox_override("pressed", pressed_style)
	
	btn.add_theme_font_size_override("font_size", 20)
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	
	return btn

# --- Touch Joystick ---
func _on_joystick_gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and not is_touching_joystick:
			is_touching_joystick = true
			joystick_touch_index = event.index
			_update_joystick_handle(event.position)
		elif not event.pressed and event.index == joystick_touch_index:
			is_touching_joystick = false
			joystick_touch_index = -1
			joystick_handle.position = Vector2(joystick_radius - joystick_handle_radius, joystick_radius - joystick_handle_radius)
			ui_move_direction.emit(Vector2.ZERO)
	elif event is InputEventScreenDrag and event.index == joystick_touch_index:
		_update_joystick_handle(event.position)
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

func _update_joystick_handle(touch_pos: Vector2) -> void:
	var delta = touch_pos - joystick_center
	var clamped_delta = delta.limit_length(joystick_radius)
	joystick_handle.position = Vector2(joystick_radius - joystick_handle_radius, joystick_radius - joystick_handle_radius) + clamped_delta
	var direction = clamped_delta / joystick_radius
	ui_move_direction.emit(direction)


# ==========================================
# ⏸️ FREEZE WORLD — pause all physics actors in place
# ==========================================
func _freeze_world(freeze: bool) -> void:
	var mode : int = Node.PROCESS_MODE_DISABLED if freeze else Node.PROCESS_MODE_INHERIT
	
	# Character bodies (player, enemies)
	for node in get_tree().get_nodes_in_group("player"):
		if is_instance_valid(node):
			node.process_mode = mode
			node.set_physics_process(not freeze)
	
	# Enemies (whatever group your enemies use)
	for node in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(node):
			node.process_mode = mode
			node.set_physics_process(not freeze)
	
	# Any node in a "physics_actor" group you tag things with
	for node in get_tree().get_nodes_in_group("physics_actor"):
		if is_instance_valid(node):
			node.process_mode = mode
			node.set_physics_process(not freeze)
	
	print("🧊 World frozen = ", freeze)
