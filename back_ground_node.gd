extends Node2D

# ==========================================
# BACKGROUND TEXTURES
# ==========================================
@export_group("Background")
@export var background_textures : Array[Texture2D] = []
@export var active_background_index : int = 0
@export var auto_apply_on_ready : bool = true

# ==========================================
# SIZE / FIT MODE
# ==========================================
enum FitMode {
	FIXED_SIZE,
	STRETCH_VIEWPORT,
	FIT_MAP,
}

@export_group("Size")
@export var fit_mode : FitMode = FitMode.FIXED_SIZE
@export var background_size : Vector2 = Vector2(1920, 1080)
@export var keep_aspect_ratio : bool = true
@export var map_size : Vector2 = Vector2(3200, 3200)

# ==========================================
# APPEARANCE
# ==========================================
@export_group("Appearance")
@export var modulate_color : Color = Color(1, 1, 1, 1)
@export var texture_filter_mode : CanvasItem.TextureFilter = CanvasItem.TEXTURE_FILTER_LINEAR

# ==========================================
# INTERNAL
# ==========================================
var _sprite : Sprite2D
var _last_applied_size : Vector2 = Vector2.ZERO

func _ready() -> void:
	_ensure_sprite()
	_apply_size()
	if auto_apply_on_ready:
		apply_background(active_background_index)

func _process(_delta: float) -> void:
	if fit_mode == FitMode.STRETCH_VIEWPORT or fit_mode == FitMode.FIT_MAP:
		_apply_size()

# ==========================================
# PUBLIC API
# ==========================================
func apply_background(index: int) -> void:
	if background_textures.is_empty():
		push_warning("⚠️ BackgroundNode has no textures assigned")
		return
	if index < 0 or index >= background_textures.size():
		push_warning("⚠️ Background index out of range: " + str(index))
		return
	active_background_index = index
	_ensure_sprite()
	_sprite.texture = background_textures[index]
	_apply_size()
	print("🖼️ Background applied: index ", index)

func set_background_texture(tex: Texture2D) -> void:
	_ensure_sprite()
	_sprite.texture = tex
	active_background_index = background_textures.find(tex)
	_apply_size()

func set_background_size(new_size: Vector2) -> void:
	background_size = new_size
	_apply_size()

func set_map_size(new_map_size: Vector2) -> void:
	map_size = new_map_size
	_apply_size()

func set_fit_mode(new_mode: FitMode) -> void:
	fit_mode = new_mode
	_apply_size()

func set_background_tint(color: Color) -> void:
	modulate_color = color
	if _sprite:
		_sprite.modulate = modulate_color

# ==========================================
# INTERNAL
# ==========================================
func _ensure_sprite() -> void:
	if is_instance_valid(_sprite):
		return
	_sprite = Sprite2D.new()
	_sprite.name = "BackgroundSprite"
	_sprite.centered = false    # origin at top-left of sprite
	_sprite.texture_filter = texture_filter_mode
	_sprite.modulate = modulate_color
	_sprite.z_index = -100
	add_child(_sprite)

func _apply_size() -> void:
	if not is_instance_valid(_sprite):
		return
	
	var target_size : Vector2 = background_size
	var target_pos : Vector2 = Vector2.ZERO
	
	match fit_mode:
		FitMode.FIXED_SIZE:
			target_size = background_size
			target_pos = Vector2.ZERO
		
		FitMode.STRETCH_VIEWPORT:
			var vp : Vector2 = get_viewport_rect().size
			target_size = vp
			target_pos = Vector2.ZERO
			if keep_aspect_ratio and _sprite.texture:
				var tex_size := Vector2(_sprite.texture.get_width(), _sprite.texture.get_height())
				if tex_size.x > 0 and tex_size.y > 0:
					var s : float = maxf(vp.x / tex_size.x, vp.y / tex_size.y)
					var draw_size := tex_size * s
					target_size = draw_size
					target_pos = (vp - draw_size) * 0.5
		
		FitMode.FIT_MAP:
			target_size = map_size
			target_pos = Vector2.ZERO
			if keep_aspect_ratio and _sprite.texture:
				var tex_size := Vector2(_sprite.texture.get_width(), _sprite.texture.get_height())
				if tex_size.x > 0 and tex_size.y > 0:
					var s : float = minf(map_size.x / tex_size.x, map_size.y / tex_size.y)
					var draw_size := tex_size * s
					target_size = draw_size
					target_pos = (map_size - draw_size) * 0.5
	
	_sprite.position = target_pos
	# Scale the sprite to fit target_size (since Sprite2D has no `size` property)
	if _sprite.texture:
		var tex_size := Vector2(_sprite.texture.get_width(), _sprite.texture.get_height())
		if tex_size.x > 0 and tex_size.y > 0:
			_sprite.scale = Vector2(target_size.x / tex_size.x, target_size.y / tex_size.y)
	_last_applied_size = target_size
