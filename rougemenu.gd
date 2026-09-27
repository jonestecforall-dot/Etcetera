extends Control

# --- Signal for the player UI to re-show itself ---
signal ui_resumed

# --- Exports ---
@export var font: FontFile

# Scene exports — assign the scenes each option opens
@export_group("Scene Targets")
@export_file("*.tscn") var build_scene_path : String = ""
@export_file("*.tscn") var settings_scene_path : String = ""
@export_file("*.tscn") var quit_scene_path : String = ""

# Menu label (offset from top of oval)
@export var menu_label_offset: Vector2 = Vector2(0, -80)
@export var menu_label_size: Vector2 = Vector2(450, 60)
@export var menu_font_size: int = 48

# Oval (now anchored to center automatically)
@export var oval_size: Vector2 = Vector2(450, 380)
@export var oval_color: Color = Color(0.2, 0.8, 0.2, 0.9)

# Button text
@export var button_text_size: int = 40
@export var button_spacing: float = 16.0

# Date label
@export var date_text: String = "x-x-3021"
@export var date_position: Vector2 = Vector2(20, -60)
@export var date_font_size: int = 32

# --- Internal ---
var _menu_label: Label
var _date_label: Label
var _oval: Panel
var _options_container: VBoxContainer
var _option_labels: Array[Label] = []
var _current_index: int = 0
var _ready_done : bool = false   # 👈 guards the notification during scene load

const OPTIONS := ["CONTINUE", "BUILD", "SETTINGS", "QUIT"]

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP   # 👈 receive clicks

	_create_oval_and_options()
	_create_menu_label()
	_create_date_label()
	_update_cursor()

	# Only start mirroring visibility to the parent after _ready finishes,
	# so load-time visibility writes don't accidentally hide the gameplay scene.
	_ready_done = true

# Mirror our visibility onto the parent so the gameplay scene hides while
# this menu is open, and re-shows when we close.


func _create_oval_and_options() -> void:
	# --- Green oval ---
	_oval = Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = oval_color
	var radius := int(min(oval_size.x, oval_size.y) * 0.5)
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	_oval.add_theme_stylebox_override("panel", style)

	_oval.size = oval_size
	_oval.set_anchors_preset(Control.PRESET_CENTER)
	_oval.position = -oval_size * 0.5
	_oval.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_oval.grow_vertical = Control.GROW_DIRECTION_BOTH
	_oval.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_oval)

	# --- VBox for options ---
	_options_container = VBoxContainer.new()
	_options_container.add_theme_constant_override("separation", int(button_spacing))
	_options_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_options_container.alignment = BoxContainer.ALIGNMENT_CENTER
	_options_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_oval.add_child(_options_container)

	# --- Option labels (clickable buttons) ---
	for i in range(OPTIONS.size()):
		var lbl := Label.new()
		lbl.text = OPTIONS[i]
		lbl.add_theme_color_override("font_color", Color.WHITE)
		if font:
			lbl.add_theme_font_override("font", font)
		lbl.add_theme_font_size_override("font_size", button_text_size)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.mouse_filter = Control.MOUSE_FILTER_STOP
		lbl.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		lbl.gui_input.connect(_on_option_gui_input.bind(i))
		_options_container.add_child(lbl)
		_option_labels.append(lbl)

func _create_menu_label() -> void:
	_menu_label = Label.new()
	_menu_label.text = "MENU"
	_menu_label.add_theme_color_override("font_color", Color.WHITE)
	if font:
		_menu_label.add_theme_font_override("font", font)
	_menu_label.add_theme_font_size_override("font_size", menu_font_size)
	_menu_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_menu_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	_menu_label.size = menu_label_size
	_menu_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_menu_label.position = Vector2(-menu_label_size.x * 0.5, menu_label_offset.y)
	_menu_label.grow_horizontal = Control.GROW_DIRECTION_BOTH

	_menu_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_menu_label)
	
	var screen_size := get_viewport_rect().size
	var oval_half_y := oval_size.y * 0.5
	_menu_label.position = Vector2(
		screen_size.x * 0.5 - menu_label_size.x * 0.5,
		screen_size.y * 0.5 - oval_half_y + menu_label_offset.y
	)

func _create_date_label() -> void:
	_date_label = Label.new()
	_date_label.text = date_text
	_date_label.add_theme_color_override("font_color", Color.WHITE)
	if font:
		_date_label.add_theme_font_override("font", font)
	_date_label.add_theme_font_size_override("font_size", date_font_size)
	_date_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_date_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM

	_date_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_date_label.position = date_position
	_date_label.size = Vector2(300, 50)

	_date_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_date_label)

func _update_cursor() -> void:
	for i in range(_option_labels.size()):
		var clean_text: String = OPTIONS[i]
		if i == _current_index:
			_option_labels[i].text = "> " + clean_text
		else:
			_option_labels[i].text = "  " + clean_text

# ==========================================
# 🖱️ INPUT (Keyboard + Touch/Mouse)
# ==========================================
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_down"):
		_current_index = (_current_index + 1) % _option_labels.size()
		_update_cursor()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up"):
		_current_index = (_current_index - 1 + _option_labels.size()) % _option_labels.size()
		_update_cursor()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		_activate_option(_current_index)
		get_viewport().set_input_as_handled()

# Per-option click detection (works for both mouse and touch on Android)
func _on_option_gui_input(event: InputEvent, option_index: int) -> void:
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_activate_option(option_index)
	elif event is InputEventScreenTouch:
		if event.pressed:
			_activate_option(option_index)

# ==========================================
# 🎬 OPTION ACTIVATION
# ==========================================
func _activate_option(index: int) -> void:
	if index < 0 or index >= OPTIONS.size():
		return
	
	var option_name : String = OPTIONS[index]
	print("⚙️ Menu option chosen: ", option_name)
	
	match option_name:
		"CONTINUE":
			_on_continue_pressed()
		"BUILD":
			_on_scene_option_pressed(build_scene_path, "BUILD")
		"SETTINGS":
			_on_scene_option_pressed(settings_scene_path, "SETTINGS")
		"QUIT":
			_on_scene_option_pressed(quit_scene_path, "QUIT")
		_:
			print("⚠️ Unknown option: ", option_name)
func _on_continue_pressed() -> void:
	# Hide the wrapper (RougePauseMenu), which contains this menu,
	# the static background, and the REC button all together.
	var wrapper := get_parent()
	if wrapper and is_instance_valid(wrapper):
		wrapper.visible = false
	else:
		visible = false
	# 🌍 Unpause everything so gameplay resumes
	get_tree().paused = false
	ui_resumed.emit()
	print("▶️ Continue — pause menu hidden, tree unpaused")

func _on_scene_option_pressed(scene_path: String, label: String) -> void:
	if scene_path.is_empty():
		print("⚠️ ", label, " scene path is empty! Set it in the Inspector.")
		return
	if not ResourceLoader.exists(scene_path):
		print("⚠️ ", label, " scene not found at: ", scene_path)
		return
	print("🎬 Loading ", label, " scene: ", scene_path)
	get_tree().change_scene_to_file.call_deferred(scene_path)
