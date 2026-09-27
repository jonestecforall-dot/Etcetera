extends Control

# --- The CanvasLayer that will HOLD the UI (assign the child node here) ---
@export var ui_canvas_layer_path : NodePath

# --- Scene to load when the player presses start ---
@export_file("*.tscn") var intro_scene_path : String = "res://intro_menu.tscn"

# --- 🆕 Swoosh wiring (leave blank to auto-find "TitleSwoosh" by name) ---
@export_group("Swoosh")
@export var swoosh_node_path : NodePath

# --- Transition timing ---
@export_group("Transition")
@export var fade_color : Color = Color.BLACK
@export var fade_out_duration : float = 0.4
@export var fade_hold_duration : float = 0.05

# --- Background ---
@export var background_color : Color = Color(0.94, 0.92, 0.86)

# --- Studio Line ---
@export_group("Studio Line")
@export var studio_line_1_text  : String = "THE ROUGE ROOM"
@export var studio_line_1_color : Color  = Color(0.25, 0.25, 0.25)
@export var studio_line_1_font  : FontFile
@export var studio_line_1_font_size : int = 28

# --- Presents ---
@export_group("Presents")
@export var presents_text  : String = "PRESENTS"
@export var presents_color : Color  = Color(0.25, 0.25, 0.25)
@export var presents_font  : FontFile
@export var presents_font_size : int = 24

# --- Logo ---
@export_group("Logo")
@export var logo_text  : String = "ETCETERA"
@export var logo_color : Color  = Color(0.55, 0.75, 0.35)
@export var logo_font  : FontFile
@export var logo_font_size : int = 120

# --- Company ---
@export_group("Company")
@export var company_text  : String = "COMPANY"
@export var company_color : Color  = Color(0.25, 0.25, 0.25)
@export var company_font  : FontFile
@export var company_font_size : int = 28

# --- Press Start ---
@export_group("Press Start")
@export var press_start_text  : String = "PRESS START"
@export var press_start_color : Color  = Color(0.25, 0.25, 0.25)
@export var press_start_font  : FontFile
@export var press_start_font_size : int = 36
@export var press_start_blink_speed : float = 1.0

# --- Fee Line ---
@export_group("Fee Line")
@export var fee_line_text  : String = "(FEE WILL APPLY)"
@export var fee_line_color : Color  = Color(0.4, 0.4, 0.4)
@export var fee_line_font  : FontFile
@export var fee_line_font_size : int = 18

# --- Intro timing ---
@export_group("Intro Timing")
@export var logo_intro_duration : float = 1.0
@export var logo_intro_delay : float = 0.25

# --- References (built at runtime) ---
var ui_canvas_layer : CanvasLayer
var background_rect : ColorRect
var studio_line_1 : Label
var presents_label : Label
var logo_label : Label
var company_label : Label
var press_start_label : Label
var fee_line_label : Label

# --- Persistent fade (survives scene change) ---
var _fade_layer : CanvasLayer
var _fade_rect : ColorRect

# --- State ---
var _blink_timer : float = 0.0
var _input_locked : bool = true
var _transitioning : bool = false


func _ready() -> void:
	# Find the CanvasLayer we're going to dump everything into
	if ui_canvas_layer_path:
		ui_canvas_layer = get_node_or_null(ui_canvas_layer_path)
	if ui_canvas_layer == null:
		push_warning("TitleScreen: no ui_canvas_layer_path assigned — UI won't spawn.")
		return

	_ensure_fade_overlay()
	_build_ui()
	_play_intro()
	_wire_swoosh()


func _process(delta : float) -> void:
	_tick_press_start_blink(delta)


# ==========================================
# SWOOSH WIRING
# ==========================================
func _wire_swoosh() -> void:
	await get_tree().process_frame

	var swoosh : Node = null
	if swoosh_node_path:
		swoosh = get_node_or_null(swoosh_node_path)
	if swoosh == null:
		swoosh = find_child("TitleSwoosh", true, false)

	if swoosh == null:
		push_warning("TitleScreen: no TitleSwoosh node found — swoosh won't be wired")
		return

	if "logo_label" in swoosh:
		swoosh.logo_label = logo_label
	if "company_label" in swoosh:
		swoosh.company_label = company_label

	if swoosh.has_method("rebuild"):
		swoosh.rebuild()

	print("🎨 TitleScreen: swoosh wired with labels")


# ==========================================
# PERSISTENT FADE OVERLAY
# ==========================================
func _ensure_fade_overlay() -> void:
	var root := get_tree().root

	_fade_layer = root.get_node_or_null("SceneFadeLayer") as CanvasLayer
	if _fade_layer == null:
		_fade_layer = CanvasLayer.new()
		_fade_layer.name = "SceneFadeLayer"
		_fade_layer.layer = 128
		root.add_child.call_deferred(_fade_layer)

	_fade_rect = _fade_layer.get_node_or_null("FadeRect") as ColorRect
	if _fade_rect == null:
		_fade_rect = ColorRect.new()
		_fade_rect.name = "FadeRect"
		_fade_rect.color = fade_color
		_fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_fade_rect.modulate.a = 0.0
		_fade_layer.add_child(_fade_rect)
	else:
		_fade_rect.color = fade_color


# ==========================================
# BUILD UI
# ==========================================
func _build_ui() -> void:
	# Background (first, so it's behind everything)
	background_rect = ColorRect.new()
	background_rect.name = "Background"
	background_rect.color = background_color
	background_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	background_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_canvas_layer.add_child(background_rect)

	studio_line_1 = _make_label(
		"StudioLine", studio_line_1_text, studio_line_1_color,
		studio_line_1_font, studio_line_1_font_size,
		Vector2(0.5, 0.10), Vector2(0.5, 0.5)
	)

	presents_label = _make_label(
		"Presents", presents_text, presents_color,
		presents_font, presents_font_size,
		Vector2(0.5, 0.20), Vector2(0.5, 0.5)
	)

	logo_label = _make_label(
		"Logo", logo_text, logo_color,
		logo_font, logo_font_size,
		Vector2(0.5, 0.42), Vector2(0.5, 0.5)
	)

	company_label = _make_label(
		"Company", company_text, company_color,
		company_font, company_font_size,
		Vector2(0.5, 0.72), Vector2(0.5, 0.5)
	)

	press_start_label = _make_label(
		"PressStart", press_start_text, press_start_color,
		press_start_font, press_start_font_size,
		Vector2(0.5, 0.85), Vector2(0.5, 0.5)
	)

	fee_line_label = _make_label(
		"FeeLine", fee_line_text, fee_line_color,
		fee_line_font, fee_line_font_size,
		Vector2(0.5, 0.92), Vector2(0.5, 0.5)
	)

	# Start hidden for the intro
	for lbl in [studio_line_1, presents_label, logo_label, company_label, press_start_label, fee_line_label]:
		var c : Color = lbl.modulate
		c.a = 0.0
		lbl.modulate = c


# --- Label factory ---
func _make_label(
	node_name : String,
	text : String,
	tint : Color,
	font : FontFile,
	font_size : int,
	anchor : Vector2,
	pivot : Vector2
) -> Label:
	var lbl := Label.new()
	lbl.name = node_name
	lbl.text = text
	lbl.modulate = tint
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	# 🆕 Apply the font if assigned, otherwise falls back to theme default
	if font != null:
		lbl.add_theme_font_override("font", font)
	lbl.add_theme_font_size_override("font_size", font_size)

	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.anchor_left = anchor.x
	lbl.anchor_right = anchor.x
	lbl.anchor_top = anchor.y
	lbl.anchor_bottom = anchor.y
	lbl.grow_horizontal = Control.GROW_DIRECTION_BOTH
	lbl.grow_vertical = Control.GROW_DIRECTION_BOTH
	lbl.pivot_offset = pivot

	ui_canvas_layer.add_child(lbl)
	return lbl


# --- Intro animation ---
func _play_intro() -> void:
	if logo_label == null:
		_input_locked = false
		return

	var start_scale : Vector2 = logo_label.scale
	logo_label.scale = start_scale * 0.85

	var tween := create_tween()
	tween.set_parallel(true)

	tween.tween_property(logo_label, "modulate:a", 1.0, logo_intro_duration)\
		.set_delay(logo_intro_delay)
	tween.tween_property(logo_label, "scale", start_scale, logo_intro_duration)\
		.set_delay(logo_intro_delay)\
		.set_trans(Tween.TRANS_BACK)\
		.set_ease(Tween.EASE_OUT)

	var others : Array[Label] = [studio_line_1, presents_label, company_label]
	for lbl in others:
		if lbl == null: continue
		tween.tween_property(lbl, "modulate:a", 1.0, logo_intro_duration)\
			.set_delay(logo_intro_delay + 0.15)

	var tail : Array[Label] = [press_start_label, fee_line_label]
	for lbl in tail:
		if lbl == null: continue
		tween.tween_property(lbl, "modulate:a", 1.0, logo_intro_duration)\
			.set_delay(logo_intro_delay + 0.6)

	await get_tree().create_timer(logo_intro_delay + logo_intro_duration + 0.6).timeout
	_input_locked = false


# --- Blink ---
func _tick_press_start_blink(delta : float) -> void:
	if press_start_label == null:
		return
	if press_start_blink_speed <= 0.0:
		return

	_blink_timer += delta * press_start_blink_speed
	var a : float = (sin(_blink_timer * TAU) * 0.5 + 0.5)
	var c : Color = press_start_label.modulate
	c.a = lerp(0.35, 1.0, a)
	press_start_label.modulate = c


# --- Input ---
func _unhandled_input(event : InputEvent) -> void:
	if _input_locked or _transitioning:
		return

	var pressed := false
	if event.is_action_pressed("ui_accept"):
		pressed = true
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			pressed = true
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			pressed = true

	if pressed:
		_start_game()
		get_viewport().set_input_as_handled()


# --- Start game with persistent fade ---
func _start_game() -> void:
	if _transitioning:
		return
	_transitioning = true
	_input_locked = true

	print("Starting game... (fee will apply)")

	if intro_scene_path == "" or not ResourceLoader.exists(intro_scene_path):
		push_warning("TitleScreen: intro_scene_path is not set or doesn't exist — not changing scene.")
		_transitioning = false
		_input_locked = false
		return

	if _fade_rect:
		_fade_rect.visible = true

		var t_out := create_tween()
		t_out.tween_property(_fade_rect, "modulate:a", 1.0, fade_out_duration)\
			.set_trans(Tween.TRANS_SINE)\
			.set_ease(Tween.EASE_IN)
		await t_out.finished

		if fade_hold_duration > 0.0:
			await get_tree().create_timer(fade_hold_duration).timeout

	get_tree().change_scene_to_file(intro_scene_path)
