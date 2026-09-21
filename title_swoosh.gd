extends CanvasLayer

# ==========================================
# 🎨 SWOOSH RIBBON — ANCHORED TO TITLE TEXT
# ==========================================
# Priority order for the texture:
#   1. cached_texture (if assigned in inspector — best for Android builds)
#   2. user://swoosh_cache/swoosh.png (auto-generated on first PC run)
#   3. Math generation (fallback, slow but always works)

@export_group("Debug")
@export var debug_swoosh : bool = true

@export_group("Layer")
@export var layer_order : int = 5

@export_group("Baked Texture (assign for Android builds)")
@export var cached_texture : Texture2D

@export_group("Cache")
@export var cache_folder : String = "user://swoosh_cache/"
@export var cache_filename : String = "swoosh.png"
@export var force_regenerate : bool = false

@export_group("Direct Label Refs (set at runtime)")
@export var logo_label : Control
@export var company_label : Control

@export_group("Title Node Paths (fallback if refs not set)")
@export var logo_label_path : NodePath
@export var company_label_path : NodePath

@export_group("Shape")
@export var ribbon_thickness : float = 30.0
@export var wave_amplitude : float = 26.0
@export var wave_frequency : float = 1.2
@export var end_loop_radius : float = 55.0
@export var tail_dot_radius : float = 45.0
@export var path_oversample : int = 4
@export var start_inset : float = 0.85
@export var end_inset : float = 1.02
@export var vertical_offset : float = 0.0
@export var tail_dot_offset : Vector2 = Vector2(0, -10)

@export_group("Color")
@export var ribbon_color : Color = Color(0.62, 0.80, 0.42, 1.0)
@export var outline_color : Color = Color(0.18, 0.22, 0.14, 1.0)
@export var outline_thickness : int = 3

@export_group("Intro Fade")
@export var fade_in_duration : float = 1.5
@export var fade_in_delay : float = 0.4

var _sprite : Sprite2D
var _image : Image
var _buf : PackedByteArray
var _w : int
var _h : int
var _cached_size : Vector2 = Vector2.ZERO

func _ready() -> void:
	layer = layer_order
	_sprite = Sprite2D.new()
	_sprite.name = "SwooshSprite"
	_sprite.centered = false
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_sprite)

	# Fade the sprite in
	_sprite.modulate.a = 0.0
	create_tween().tween_property(_sprite, "modulate:a", 1.0, fade_in_duration)\
		.set_delay(fade_in_delay)

	# 🆕 Try to load a baked texture first
	if _try_apply_cached_texture():
		# No math needed — just position the sprite when labels exist
		await get_tree().process_frame
		await get_tree().process_frame
		_rebuild_from_cache()
		get_viewport().size_changed.connect(_on_resize_cached)
		if debug_swoosh:
			call_deferred("_debug_dump")
		return

	# Otherwise wait for labels and generate the math texture
	await get_tree().process_frame
	await get_tree().process_frame
	rebuild()
	get_viewport().size_changed.connect(_on_resize)
	if debug_swoosh:
		call_deferred("_debug_dump")

# ==========================================
# CACHE LOGIC
# ==========================================
func _get_cache_full_path() -> String:
	return cache_folder + cache_filename

func _try_apply_cached_texture() -> bool:
	# Priority 1: baked texture assigned in the inspector (Android builds)
	if cached_texture != null and not force_regenerate:
		_sprite.texture = cached_texture
		_cached_size = Vector2(cached_texture.get_width(), cached_texture.get_height())
		if debug_swoosh:
			print("🎨 SWOOSH: using inspector texture (",
				int(_cached_size.x), "x", int(_cached_size.y), ")")
		return true

	# Priority 2: cached PNG on disk
	var path : String = _get_cache_full_path()
	if not force_regenerate and FileAccess.file_exists(path):
		var tex : ImageTexture = _load_texture_from_path(path)
		if tex != null:
			_sprite.texture = tex
			_cached_size = Vector2(tex.get_width(), tex.get_height())
			if debug_swoosh:
				print("🎨 SWOOSH: loaded cached PNG (",
					int(_cached_size.x), "x", int(_cached_size.y), ")")
			return true
		elif debug_swoosh:
			print("🎨 SWOOSH: cached PNG failed to load, regenerating")

	return false

func _load_texture_from_path(path : String) -> ImageTexture:
	var img : Image = Image.load_from_file(path)
	if img == null:
		return null
	return ImageTexture.create_from_image(img)

func _save_image_to_cache(img : Image) -> void:
	# Make sure the cache folder exists
	if not DirAccess.dir_exists_absolute(cache_folder):
		var err : int = DirAccess.make_dir_recursive_absolute(cache_folder)
		if err != OK:
			push_warning("Swoosh: could not create cache folder: " + cache_folder)
			return

	var path : String = _get_cache_full_path()
	var save_err : int = img.save_png(path)
	if save_err == OK:
		if debug_swoosh:
			print("🎨 SWOOSH: cached PNG saved → ", path)
	else:
		push_warning("Swoosh: failed to save cache PNG (err " + str(save_err) + ")")

# ==========================================
# CACHED PATH — no math, just positioning
# ==========================================
func _rebuild_from_cache() -> void:
	if _sprite.texture == null:
		return

	# If we have labels, anchor to them (so it still moves with layout)
	var logo : Control = logo_label
	var company : Control = company_label
	if logo == null and logo_label_path != NodePath():
		logo = _resolve_label(logo_label_path)
	if company == null and company_label_path != NodePath():
		company = _resolve_label(company_label_path)

	if logo == null or company == null:
		# No labels — just center the cached texture on the viewport
		var vp : Vector2 = get_viewport().get_visible_rect().size
		_sprite.position = Vector2(
			(vp.x - _cached_size.x) * 0.5,
			(vp.y - _cached_size.y) * 0.5
		)
		return

	# Anchor the cached texture the same way the math version does
	var logo_rect : Rect2 = _control_rect_in_canvas(logo)
	var company_rect : Rect2 = _control_rect_in_canvas(company)

	var min_x : float = min(logo_rect.position.x, company_rect.position.x) - 140.0
	var top_y : float = logo_rect.position.y - 40.0

	_sprite.position = Vector2(min_x, top_y)

	if debug_swoosh:
		print("🎨 SWOOSH: cached texture positioned at ", _sprite.position)

func _on_resize_cached() -> void:
	await get_tree().process_frame
	_rebuild_from_cache()

# ==========================================
# PUBLIC — TitleScreen calls this after wiring labels
# ==========================================
func rebuild() -> void:
	# If we're using a cached/baked texture, use the light path
	if _sprite.texture != null and _cached_size != Vector2.ZERO:
		_rebuild_from_cache()
		return

	# Otherwise, do the math
	var logo : Control = logo_label
	var company : Control = company_label

	if logo == null and logo_label_path != NodePath():
		logo = _resolve_label(logo_label_path)
	if company == null and company_label_path != NodePath():
		company = _resolve_label(company_label_path)

	if logo == null or company == null:
		if debug_swoosh:
			print("🎨 SWOOSH: waiting for labels... (logo=", logo, " company=", company, ")")
		return

	_build_and_apply(logo, company)

func _on_resize() -> void:
	await get_tree().process_frame
	rebuild()

func _build_and_apply(logo : Control, company : Control) -> void:
	var logo_rect : Rect2 = _control_rect_in_canvas(logo)
	var company_rect : Rect2 = _control_rect_in_canvas(company)

	var min_x : float = min(logo_rect.position.x, company_rect.position.x) - 140.0
	var max_x : float = max(logo_rect.end.x, company_rect.end.x) + 60.0
	var top_y : float = logo_rect.position.y - 40.0
	var bot_y : float = company_rect.end.y + 60.0

	_w = int(max(64.0, max_x - min_x))
	_h = int(max(64.0, bot_y - top_y))

	_buf = PackedByteArray()
	_buf.resize(_w * _h * 4)

	_sprite.position = Vector2(min_x, top_y)

	var logo_local : Rect2 = Rect2(logo_rect.position - _sprite.position, logo_rect.size)
	var company_local : Rect2 = Rect2(company_rect.position - _sprite.position, company_rect.size)

	var fill_rgba : PackedByteArray = _color_to_bytes(ribbon_color)
	var line_rgba : PackedByteArray = _color_to_bytes(outline_color)

	var stroke_half : float = ribbon_thickness * 0.5
	var outline_half : float = stroke_half + float(outline_thickness)

	var start_pt : Vector2 = Vector2(
		logo_local.position.x + logo_local.size.x * (1.0 - start_inset),
		logo_local.end.y + 12.0
	)
	var end_pt : Vector2 = Vector2(
		logo_local.position.x + logo_local.size.x * end_inset,
		logo_local.end.y + 30.0
	) + tail_dot_offset

	var baseline : float = lerp(logo_local.end.y, company_local.position.y, 0.6) + vertical_offset
	var dot_center : Vector2 = Vector2(end_pt.x, end_pt.y)

	# --- Build path ---
	var points : Array[Vector2] = []
	var total_dx : float = end_pt.x - start_pt.x
	var base_steps : int = int(max(4.0, abs(total_dx)))
	var steps : int = base_steps * max(1, path_oversample)

	for i in range(steps):
		var t : float = float(i) / float(steps - 1)
		var x : float = lerp(start_pt.x, end_pt.x, t)
		var blend : float = smoothstep(0.0, 0.35, t)
		var y_base : float = lerp(start_pt.y, baseline, blend)
		var wave_t : float = clamp((t - 0.15) / 0.85, 0.0, 1.0)
		var wave : float = sin(wave_t * PI * wave_frequency) * wave_amplitude
		var tail_pull : float = smoothstep(0.75, 1.0, t)
		var y_final : float = lerp(y_base + wave, dot_center.y, tail_pull)
		points.append(Vector2(x, y_final))

	for p in points:
		_fast_disc(p, outline_half, line_rgba)
	for p in points:
		_fast_disc(p, stroke_half, fill_rgba)

	_fast_disc(dot_center, tail_dot_radius + float(outline_thickness), line_rgba)
	_fast_disc(dot_center, tail_dot_radius, fill_rgba)

	var loop_center : Vector2 = Vector2(
		start_pt.x - end_loop_radius * 0.6,
		start_pt.y + end_loop_radius * 0.4
	)
	var loop_thickness : float = ribbon_thickness * 0.85
	_fast_ring(loop_center, end_loop_radius,
		loop_thickness + float(outline_thickness) * 2.0, line_rgba)
	_fast_ring(loop_center, end_loop_radius, loop_thickness, fill_rgba)

	var connector_steps : int = 20 * max(1, path_oversample)
	var loop_edge : Vector2 = Vector2(loop_center.x + end_loop_radius, loop_center.y)
	for i in range(connector_steps + 1):
		var t : float = float(i) / float(connector_steps)
		var p : Vector2 = loop_edge.lerp(points[0], t)
		_fast_disc(p, outline_half, line_rgba)
	for i in range(connector_steps + 1):
		var t : float = float(i) / float(connector_steps)
		var p : Vector2 = loop_edge.lerp(points[0], t)
		_fast_disc(p, stroke_half, fill_rgba)

	_image = Image.create_from_data(_w, _h, false, Image.FORMAT_RGBA8, _buf)
	_sprite.texture = ImageTexture.create_from_image(_image)

	# 🆕 Save to cache so next run is instant
	_save_image_to_cache(_image)

	if debug_swoosh:
		print("🎨 SWOOSH rebuilt | size=(", _w, ",", _h, ") pos=", _sprite.position)

# ==========================================
# LABEL LOOKUP (fallback path)
# ==========================================
func _resolve_label(path: NodePath) -> Control:
	if path == NodePath():
		return null
	var node : Node = get_node_or_null(path)
	if node is Control:
		return node as Control
	var found : Node = _find_by_name(String(path).get_file())
	if found is Control:
		return found as Control
	return null

func _find_by_name(n: String) -> Node:
	if get_tree() == null:
		return null
	var root : Node = get_tree().current_scene
	if root == null:
		root = get_tree().root
	return _recursive_find(root, n)

func _recursive_find(node: Node, n: String) -> Node:
	if node == null:
		return null
	if node.name == n:
		return node
	for c in node.get_children():
		var r : Node = _recursive_find(c, n)
		if r != null:
			return r
	return null

func _control_rect_in_canvas(ctrl: Control) -> Rect2:
	return Rect2(ctrl.global_position, ctrl.size)

# ==========================================
# DEBUG
# ==========================================
func _debug_dump() -> void:
	print("═══════════════════════════════════════════")
	print("🎨 SWOOSH DEBUG")
	print("   layer          = ", layer)
	print("   sprite pos     = ", _sprite.position)
	print("   tex size       = (", _w, ",", _h, ")")
	print("   has texture    = ", _sprite.texture != null)
	print("   cached_texture = ", cached_texture)
	print("   cache path     = ", _get_cache_full_path())
	print("   cache exists   = ", FileAccess.file_exists(_get_cache_full_path()))
	if logo_label:
		print("   logo rect      = ", _control_rect_in_canvas(logo_label))
	if company_label:
		print("   company rect   = ", _control_rect_in_canvas(company_label))
	print("═══════════════════════════════════════════")

# ==========================================
# FAST PIXEL WRITES
# ==========================================
func _color_to_bytes(c: Color) -> PackedByteArray:
	var b : PackedByteArray = PackedByteArray()
	b.resize(4)
	b[0] = int(clamp(c.r * 255.0, 0.0, 255.0))
	b[1] = int(clamp(c.g * 255.0, 0.0, 255.0))
	b[2] = int(clamp(c.b * 255.0, 0.0, 255.0))
	b[3] = int(clamp(c.a * 255.0, 0.0, 255.0))
	return b

func _fast_disc(center: Vector2, radius: float, rgba: PackedByteArray) -> void:
	if radius <= 0.0:
		return
	var r : int = int(ceil(radius))
	var cx : int = int(center.x)
	var cy : int = int(center.y)
	var x0 : int = max(0, cx - r)
	var x1 : int = min(_w - 1, cx + r)
	var y0 : int = max(0, cy - r)
	var y1 : int = min(_h - 1, cy + r)
	var r2 : float = radius * radius
	var cfx : float = center.x
	var cfy : float = center.y
	var c0 : int = rgba[0]
	var c1 : int = rgba[1]
	var c2 : int = rgba[2]
	var c3 : int = rgba[3]
	for y in range(y0, y1 + 1):
		var row_base : int = y * _w * 4
		var dy : float = float(y) - cfy
		var dy2 : float = dy * dy
		for x in range(x0, x1 + 1):
			var dx : float = float(x) - cfx
			if dx * dx + dy2 <= r2:
				var idx : int = row_base + x * 4
				_buf[idx]     = c0
				_buf[idx + 1] = c1
				_buf[idx + 2] = c2
				_buf[idx + 3] = c3

func _fast_ring(center: Vector2, ring_radius: float, thickness: float, rgba: PackedByteArray) -> void:
	var outer : float = ring_radius + thickness * 0.5
	var inner : float = ring_radius - thickness * 0.5
	if inner < 0.0:
		inner = 0.0
	var r : int = int(ceil(outer))
	var cx : int = int(center.x)
	var cy : int = int(center.y)
	var x0 : int = max(0, cx - r)
	var x1 : int = min(_w - 1, cx + r)
	var y0 : int = max(0, cy - r)
	var y1 : int = min(_h - 1, cy + r)
	var outer2 : float = outer * outer
	var inner2 : float = inner * inner
	var cfx : float = center.x
	var cfy : float = center.y
	var c0 : int = rgba[0]
	var c1 : int = rgba[1]
	var c2 : int = rgba[2]
	var c3 : int = rgba[3]
	for y in range(y0, y1 + 1):
		var row_base : int = y * _w * 4
		var dy : float = float(y) - cfy
		var dy2 : float = dy * dy
		for x in range(x0, x1 + 1):
			var dx : float = float(x) - cfx
			var d2 : float = dx * dx + dy2
			if d2 <= outer2 and d2 >= inner2:
				var idx : int = row_base + x * 4
				_buf[idx]     = c0
				_buf[idx + 1] = c1
				_buf[idx + 2] = c2
				_buf[idx + 3] = c3
