extends Control

# --- Exports ---
@export var font: FontFile
@export var panel_position: Vector2 = Vector2(20, 20)
@export var panel_size: Vector2 = Vector2(120, 40)
@export var font_size: int = 24
@export var blink_interval: float = 0.5

# --- Internal ---
var _rec_dot: ColorRect
var _blink_timer: float = 0.0
var _dot_visible: bool = true

func _ready() -> void:
	# Position and size the control itself
	position = panel_position
	size = panel_size

	# --- Black panel background ---
	var panel := ColorRect.new()
	panel.color = Color.BLACK
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)

	# --- "REC" label ---
	var label := Label.new()
	label.text = "REC"
	label.add_theme_color_override("font_color", Color.WHITE)
	if font:
		label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.position = Vector2(8, 0)
	label.size = Vector2(panel_size.x - 36, panel_size.y)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)

	# --- Red blinking dot on the right end ---
	_rec_dot = ColorRect.new()
	_rec_dot.color = Color.RED
	var dot_size := 12.0
	_rec_dot.size = Vector2(dot_size, dot_size)
	_rec_dot.position = Vector2(
		panel_size.x - dot_size - 10,
		(panel_size.y - dot_size) * 0.5
	)
	_rec_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rec_dot)

func _process(delta: float) -> void:
	if not _rec_dot:
		return

	_blink_timer += delta
	if _blink_timer >= blink_interval:
		_blink_timer = 0.0
		_dot_visible = not _dot_visible
		_rec_dot.visible = _dot_visible
