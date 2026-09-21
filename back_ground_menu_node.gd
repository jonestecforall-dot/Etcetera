extends TextureRect

# =============================================================================
# 🎨 PROCEDURAL BACKDROP (with debug)
# =============================================================================

enum Formation {
	GRID, DIAGONAL, WAVE, RADIAL, SPIRAL, HEX, CHECKER, RANDOM_SCATTER
}

# =============================================================================
# 📐 EXPORTS — LAYOUT
# =============================================================================
@export_group("Layout")
@export var formation: Formation = Formation.GRID
@export var tile_size: Vector2 = Vector2(64, 64)
@export var spacing: Vector2 = Vector2(0, 0)
@export var tile_scale: Vector2 = Vector2.ONE
@export var rotation_per_tile: float = 0.0
@export var global_rotation: float = 0.0
@export var center_origin: bool = true
@export var tile_count_override: int = 0

# =============================================================================
# 🧩 EXPORTS — TEXTURES (optional)
# =============================================================================
@export_group("Textures")
@export var atlas_texture: Texture2D = null
@export var atlas_pool: Array[Texture2D] = []
@export var atlas_region: Rect2 = Rect2(0, 0, 64, 64)
@export_range(0.0, 1.0, 0.01) var pool_pick_chance: float = 0.0
@export var global_tint: Color = Color(1, 1, 1, 1)
@export var use_solid_colors: bool = true

# =============================================================================
# 🎨 EXPORTS — COLORS
# =============================================================================
@export_group("Colors")
@export var color_a: Color = Color(0.35, 0.65, 1.0, 1.0)
@export var color_b: Color = Color(0.55, 0.35, 0.85, 1.0)
@export var color_c: Color = Color(0.20, 0.40, 0.75, 1.0)
@export var background_color: Color = Color(0.06, 0.06, 0.09, 1.0)
@export var alpha_min: float = 0.08
@export var alpha_max: float = 0.55
@export var color_blend_speed: float = 0.0

# =============================================================================
# 🌊 EXPORTS — ANIMATION
# =============================================================================
@export_group("Animation")
@export var animate: bool = true
@export var wave_amplitude: float = 12.0
@export var wave_speed: float = 1.5
@export var breathe_scale: float = 0.0
@export var drift_speed: Vector2 = Vector2.ZERO

# =============================================================================
# 🎲 EXPORTS — RANDOM
# =============================================================================
@export_group("Random")
@export var random_seed: int = 1337
@export_range(0.0, 1.0, 0.01) var size_jitter: float = 0.15
@export_range(0.0, 360.0, 1.0) var rotation_jitter: float = 0.0
@export var scatter_radius: float = 400.0

# =============================================================================
# DEBUG EXPORTS
# =============================================================================
@export_group("Debug")
@export var debug_verbose: bool = true
@export var debug_dump_state: bool = true

# =============================================================================
# STATE
# =============================================================================
var _container: Control
var _tiles: Array[TextureRect] = []
var _tile_data: Array = []
var _time: float = 0.0
var _rng := RandomNumberGenerator.new()
var _generated_pixel: ImageTexture
var _built: bool = false
var _build_count: int = 0

# =============================================================================
# READY
# =============================================================================
func _ready() -> void:
	print("═══════════════════════════════════════════")
	print("🎨 BACKDROP _ready() starting")
	print("   parent           = ", get_parent())
	print("   parent type      = ", get_parent().get_class() if get_parent() else "null")
	print("   initial size     = ", size)
	print("   visible          = ", visible)
	print("   modulate         = ", modulate)
	print("   self_modulate    = ", self_modulate)
	print("   position         = ", position)
	print("   global_position  = ", global_position)
	print("   z_index          = ", z_index)
	print("   formation        = ", Formation.keys()[formation])
	print("   tile_size        = ", tile_size)
	print("   alpha range      = ", alpha_min, " .. ", alpha_max)
	print("   color_a          = ", color_a)
	print("   animate          = ", animate)

	mouse_filter = Control.MOUSE_FILTER_IGNORE
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_SCALE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	texture = _make_bg_texture()
	self_modulate = background_color

	print("   after preset     = ", size)
	print("   after preset pos = ", position)

	await get_tree().process_frame
	await get_tree().process_frame

	print("🎨 Backdrop after 2 frames:")
	print("   size             = ", size)
	print("   position         = ", position)
	print("   global_position  = ", global_position)
	print("   visible          = ", visible)
	print("   is_visible_in_tree = ", is_visible_in_tree())
	print("   modulate         = ", modulate)
	print("   self_modulate    = ", self_modulate)

	if size == Vector2.ZERO:
		var vp := get_viewport_rect().size
		size = vp
		print("   ⚠️ size was 0, using viewport = ", vp)

	_container = Control.new()
	_container.name = "TileContainer"
	_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_container)
	print("   _container created, size = ", _container.size)

	_rng.seed = random_seed
	_build_tiles()
	_apply_global_rotation()
	_built = true

	resized.connect(_on_resized)

	if debug_dump_state:
		await get_tree().process_frame
		_dump_visual_state()

func _process(delta: float) -> void:
	if not animate and color_blend_speed <= 0.0 and breathe_scale <= 0.0 and drift_speed == Vector2.ZERO:
		return
	_time += delta
	_tick_tiles(delta)

# =============================================================================
# DEBUG DUMP
# =============================================================================
func _dump_visual_state() -> void:
	print("═══════════════════════════════════════════")
	print("🎨 BACKDROP STATE DUMP (frame 3)")
	print("   self size             = ", size)
	print("   self position         = ", position)
	print("   self global_position  = ", global_position)
	print("   self visible          = ", visible)
	print("   self is_visible_in_tree = ", is_visible_in_tree())
	print("   self modulate         = ", modulate)
	print("   self self_modulate    = ", self_modulate)
	print("   self texture          = ", texture)
	print("   self texture size     = ", texture.get_size() if texture else Vector2.ZERO)
	print("   self z_index          = ", z_index)
	print("   tiles built           = ", _tiles.size())
	if _container:
		print("   _container size       = ", _container.size)
		print("   _container visible    = ", _container.visible)
		print("   _container children   = ", _container.get_child_count())
	if _tiles.size() > 0:
		var t0 := _tiles[0]
		var t_last := _tiles[_tiles.size() - 1]
		print("   ── first tile ──")
		print("      pos        = ", t0.position)
		print("      size       = ", t0.size)
		print("      modulate   = ", t0.modulate)
		print("      visible    = ", t0.visible)
		print("      texture    = ", t0.texture)
		print("      parent     = ", t0.get_parent())
		print("      global_pos = ", t0.global_position)
		print("   ── last tile ──")
		print("      pos        = ", t_last.position)
		print("      size       = ", t_last.size)
		print("      modulate   = ", t_last.modulate)
	# Walk up ancestry to check for hidden CanvasLayers
	var p = get_parent()
	var depth := 0
	while p != null and depth < 10:
		print("   ancestor[", depth, "] = ", p.get_class(), " (", p.name, ")")
		if p is CanvasLayer:
			print("      → CanvasLayer.layer   = ", p.layer)
			print("      → CanvasLayer.visible = ", p.visible)
		elif p is CanvasItem:
			print("      → CanvasItem.visible  = ", p.visible)
		p = p.get_parent()
		depth += 1
	print("═══════════════════════════════════════════")

# =============================================================================
# TILE GENERATION
# =============================================================================
func _build_tiles() -> void:
	_build_count += 1
	print("🎨 _build_tiles() call #", _build_count)
	if _container == null:
		print("   ❌ _container is null, aborting")
		return
	for t in _tiles:
		if is_instance_valid(t):
			t.queue_free()
	_tiles.clear()
	_tile_data.clear()

	_rng.seed = random_seed
	var positions := _generate_positions()
	print("   positions generated = ", positions.size())
	print("   bounds              = ", _grid_bounds())
	print("   cell step           = ", _cell_step())
	if positions.size() > 0:
		print("   first pos           = ", positions[0])
		print("   last pos            = ", positions[positions.size() - 1])
	for i in range(positions.size()):
		var pos: Vector2 = positions[i]
		var tr := _spawn_tile(pos, i)
		if tr != null:
			_tiles.append(tr)
	print("   tiles created       = ", _tiles.size())

func _generate_positions() -> Array:
	match formation:
		Formation.GRID: return _grid_positions(false)
		Formation.DIAGONAL: return _diagonal_positions()
		Formation.WAVE: return _wave_positions()
		Formation.RADIAL: return _radial_positions()
		Formation.SPIRAL: return _spiral_positions()
		Formation.HEX: return _hex_positions()
		Formation.CHECKER: return _grid_positions(true)
		Formation.RANDOM_SCATTER: return _scatter_positions()
	return []

func _grid_bounds() -> Rect2:
	var s := size
	if s == Vector2.ZERO:
		s = get_viewport_rect().size
	return Rect2(Vector2.ZERO, s)

func _cell_step() -> Vector2:
	return tile_size * tile_scale + spacing

func _grid_positions(offset_alt: bool) -> Array:
	var out: Array = []
	var step := _cell_step()
	if step.x <= 0 or step.y <= 0:
		return out
	var bounds := _grid_bounds()
	var cols : int = int(ceil(bounds.size.x / step.x)) + 1
	var rows : int = int(ceil(bounds.size.y / step.y)) + 1
	for y in range(rows):
		for x in range(cols):
			var p := Vector2(x, y) * step
			if offset_alt and y % 2 == 1:
				p.x += step.x * 0.5
			out.append(p)
	return out

func _diagonal_positions() -> Array:
	var out: Array = []
	var step := _cell_step()
	var bounds := _grid_bounds()
	var cols : int = int(ceil(bounds.size.x / step.x)) + 1
	var rows : int = int(ceil(bounds.size.y / step.y)) + 1
	for y in range(rows):
		for x in range(cols):
			var p := Vector2(x, y) * step
			p.x += y * step.x * 0.5
			out.append(p)
	return out

func _wave_positions() -> Array:
	var out: Array = []
	var step := _cell_step()
	var bounds := _grid_bounds()
	var cols : int = int(ceil(bounds.size.x / step.x)) + 1
	var rows : int = int(ceil(bounds.size.y / step.y)) + 1
	for y in range(rows):
		for x in range(cols):
			var p := Vector2(x, y) * step
			var denom : float = float(max(rows - 1, 1))
			var t : float = float(y) / denom
			p.x += sin(t * TAU) * wave_amplitude * 4.0
			p.y += cos(float(x) * 0.4) * wave_amplitude * 0.5
			out.append(p)
	return out

func _radial_positions() -> Array:
	var out: Array = []
	var bounds := _grid_bounds()
	var center := bounds.size * 0.5
	var count : int = tile_count_override if tile_count_override > 0 else 400
	var step := _cell_step()
	var ring_gap : float = max(step.x, step.y)
	var max_radius : float = max(bounds.size.x, bounds.size.y) * 0.75
	var r : float = ring_gap
	while r < max_radius:
		var circumference : float = TAU * r
		var per_ring : int = int(max(1, int(circumference / ring_gap)))
		for i in range(per_ring):
			var ang : float = (float(i) / float(per_ring)) * TAU
			out.append(center + Vector2(cos(ang), sin(ang)) * r)
			if out.size() >= count:
				return out
		r += ring_gap
	return out

func _spiral_positions() -> Array:
	var out: Array = []
	var bounds := _grid_bounds()
	var center := bounds.size * 0.5
	var count : int = tile_count_override if tile_count_override > 0 else 500
	var max_radius : float = max(bounds.size.x, bounds.size.y) * 0.75
	for i in range(count):
		var t : float = float(i) / float(count)
		var r : float = t * max_radius
		var ang : float = t * TAU * 6.0
		out.append(center + Vector2(cos(ang), sin(ang)) * r)
	return out

func _hex_positions() -> Array:
	var out: Array = []
	var step := _cell_step()
	var bounds := _grid_bounds()
	var row_h : float = step.y * 0.866
	var cols : int = int(ceil(bounds.size.x / step.x)) + 2
	var rows : int = int(ceil(bounds.size.y / row_h)) + 2
	for y in range(rows):
		for x in range(cols):
			var p := Vector2(float(x) * step.x, float(y) * row_h)
			if y % 2 == 1:
				p.x += step.x * 0.5
			out.append(p)
	return out

func _scatter_positions() -> Array:
	var out: Array = []
	var bounds := _grid_bounds()
	var count : int = tile_count_override if tile_count_override > 0 else 250
	var center := bounds.size * 0.5
	for i in range(count):
		var ang : float = _rng.randf() * TAU
		var r : float = sqrt(_rng.randf()) * scatter_radius
		out.append(center + Vector2(cos(ang), sin(ang)) * r)
	return out

# =============================================================================
# SPAWN ONE TILE
# =============================================================================
func _spawn_tile(pos: Vector2, idx: int) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = _pick_texture()
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var jitter : float = 1.0 + _rng.randf_range(-size_jitter, size_jitter)
	tr.size = tile_size * tile_scale * jitter
	tr.pivot_offset = tr.size * 0.5

	var p := pos
	if center_origin:
		p -= tr.size * 0.5
	tr.position = p

	var rot_deg : float = rotation_per_tile * float(idx) + _rng.randf_range(-rotation_jitter, rotation_jitter)
	tr.rotation = deg_to_rad(rot_deg)

	tr.modulate = _pick_color(idx)
	_container.add_child(tr)

	if idx == 0 and debug_verbose:
		print("   ▶ first tile created:")
		print("      pos        = ", tr.position)
		print("      size       = ", tr.size)
		print("      modulate   = ", tr.modulate)
		print("      texture    = ", tr.texture)
		print("      rotation   = ", tr.rotation)

	_tile_data.append({
		"origin": tr.position,
		"base_scale": tr.scale,
		"phase": _rng.randf() * TAU,
		"idx": idx
	})
	return tr

func _pick_texture() -> Texture2D:
	if pool_pick_chance > 0.0 and atlas_pool.size() > 0 and _rng.randf() < pool_pick_chance:
		var pick : Texture2D = atlas_pool[_rng.randi() % atlas_pool.size()]
		if pick != null:
			return _make_atlas_or_plain(pick)
	if atlas_texture != null:
		return _make_atlas_or_plain(atlas_texture)
	return _get_generated_pixel()

func _make_atlas_or_plain(src: Texture2D) -> Texture2D:
	if atlas_region.size.x <= 0 or atlas_region.size.y <= 0:
		return src
	if atlas_region.position == Vector2.ZERO and atlas_region.size == src.get_size():
		return src
	var at := AtlasTexture.new()
	at.atlas = src
	at.region = atlas_region
	return at

func _pick_color(idx: int) -> Color:
	if not use_solid_colors:
		var c := global_tint
		c.a *= _rng.randf_range(alpha_min, alpha_max)
		return c
	var t : float = float(idx % 3) / 2.0
	var base: Color
	if t < 0.5:
		base = color_a.lerp(color_b, t * 2.0)
	else:
		base = color_b.lerp(color_c, (t - 0.5) * 2.0)
	if color_blend_speed > 0.0:
		var shift : float = fmod(_time * color_blend_speed, 1.0)
		base.h = fmod(base.h + shift, 1.0)
	base.a = _rng.randf_range(alpha_min, alpha_max)
	return base * global_tint

# =============================================================================
# ANIMATION TICK
# =============================================================================
func _tick_tiles(delta: float) -> void:
	var step := _cell_step()
	if drift_speed != Vector2.ZERO and _container:
		_container.position += drift_speed * delta
		if step.x > 0 and _container.position.x > step.x:
			_container.position.x -= step.x
		elif step.x > 0 and _container.position.x < -step.x:
			_container.position.x += step.x
		if step.y > 0 and _container.position.y > step.y:
			_container.position.y -= step.y
		elif step.y > 0 and _container.position.y < -step.y:
			_container.position.y += step.y

	for i in range(_tiles.size()):
		var tr := _tiles[i]
		if not is_instance_valid(tr):
			continue
		var d : Dictionary = _tile_data[i]

		if animate and wave_amplitude > 0.0:
			var ph : float = d["phase"]
			var ox : float = d["origin"].x
			var oy : float = d["origin"].y
			var dx : float = sin(_time * wave_speed + oy * 0.01 + ph) * wave_amplitude
			var dy : float = cos(_time * wave_speed + ox * 0.01 + ph) * wave_amplitude
			tr.position = d["origin"] + Vector2(dx, dy)

		if breathe_scale > 0.0:
			var s : float = 1.0 + sin(_time * wave_speed + d["phase"]) * breathe_scale
			tr.scale = d["base_scale"] * s

		if color_blend_speed > 0.0:
			var base := tr.modulate
			base.h = fmod(base.h + _time * color_blend_speed * 0.001, 1.0)
			tr.modulate = base

# =============================================================================
# HELPERS
# =============================================================================
func _apply_global_rotation() -> void:
	if _container and global_rotation != 0.0:
		_container.pivot_offset = size * 0.5
		_container.rotation = deg_to_rad(global_rotation)

func _on_resized() -> void:
	if not _built:
		return
	print("🎨 _on_resized() fired. new size = ", size, " _build_count=", _build_count)
	match formation:
		Formation.GRID, Formation.DIAGONAL, Formation.WAVE, Formation.HEX, Formation.CHECKER:
			_build_tiles()

func _get_generated_pixel() -> Texture2D:
	if _generated_pixel != null:
		return _generated_pixel
	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	_generated_pixel = ImageTexture.create_from_image(img)
	return _generated_pixel

func _make_bg_texture() -> Texture2D:
	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	return ImageTexture.create_from_image(img)

# =============================================================================
# PUBLIC API
# =============================================================================
func regenerate() -> void:
	_build_tiles()
	_apply_global_rotation()

func set_formation(f: Formation) -> void:
	formation = f
	regenerate()
