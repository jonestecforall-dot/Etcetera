extends Control

# --- Config ---
const STATIC_SIZE := Vector2i(320, 180)   # Low res, scaled up = chunky static
const FRAME_COUNT := 8                    # How many unique noise frames to cache
const REFRESH_RATE := 0.05                # ~20fps refresh

# --- Dimming (tweak in Inspector) ---
@export_range(0.0, 1.0, 0.01) var min_brightness: float = 0.15
@export_range(0.0, 1.0, 0.01) var max_brightness: float = 0.65

# --- Internal ---
var _frames: Array[ImageTexture] = []     # Cached textures
var _texture_rect: TextureRect
var _current_frame: int = 0
var _accumulator: float = 0.0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	# --- Cache all noise frames once ---
	_cache_noise_frames()

	# --- Create the TextureRect child that will display the static ---
	_texture_rect = TextureRect.new()
	_texture_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_texture_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_texture_rect.texture = _frames[0]
	add_child(_texture_rect)

func _process(delta: float) -> void:
	if _frames.is_empty():
		return

	_accumulator += delta
	if _accumulator < REFRESH_RATE:
		return
	_accumulator = 0.0

	# Just cycle the cached frames — no math, no allocation
	_current_frame = (_current_frame + 1) % _frames.size()
	_texture_rect.texture = _frames[_current_frame]

# --- Cache generation (runs once) ---
func _cache_noise_frames() -> void:
	var w := STATIC_SIZE.x
	var h := STATIC_SIZE.y

	for f in range(FRAME_COUNT):
		# L8 = 8-bit grayscale, so we get proper black & white static
		var img := Image.create(w, h, false, Image.FORMAT_L8)

		for y in range(h):
			for x in range(w):
				# Dimmed noise — no harsh pure whites or blacks
				var val := randf_range(min_brightness, max_brightness)
				img.set_pixel(x, y, Color(val, val, val))

		_frames.append(ImageTexture.create_from_image(img))
