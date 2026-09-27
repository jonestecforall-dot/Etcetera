extends Node2D
class_name Rock

# ==========================================
# 🪨 EXPORTS
# ==========================================
@export_group("Visual")
@export var rock_texture : Texture2D
@export var rock_size : Vector2 = Vector2(64, 64)
@export var keep_pixel_perfect : bool = true
@export var rock_modulate : Color = Color(1, 1, 1, 1)
@export var rock_z_index : int = 0

@export_group("Collision")
@export var collision_enabled : bool = true
@export var collision_layer : int = 1
@export var collision_mask : int = 0
@export var collision_shrink : Vector2 = Vector2(4, 4)  # inset from texture edges

@export_group("Collision Shape")
@export_enum("Rectangle", "Circle", "Capsule") var collision_shape_type : int = 0

# ==========================================
# INTERNAL
# ==========================================
var _sprite : Sprite2D
var _body : StaticBody2D
var _shape : CollisionShape2D

# ==========================================
# READY
# ==========================================
func _ready() -> void:
	_build_sprite()
	if collision_enabled:
		_build_collision()

func _build_sprite() -> void:
	_sprite = Sprite2D.new()
	_sprite.name = "RockSprite"
	_sprite.texture = rock_texture
	_sprite.modulate = rock_modulate
	_sprite.z_index = rock_z_index
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_sprite)
	_apply_sprite_size()

func _apply_sprite_size() -> void:
	if _sprite == null or _sprite.texture == null:
		return
	if not keep_pixel_perfect:
		_sprite.scale = Vector2.ONE
		return
	var tex_size := Vector2(_sprite.texture.get_width(), _sprite.texture.get_height())
	if tex_size.x <= 0 or tex_size.y <= 0:
		return
	_sprite.scale = Vector2(rock_size.x / tex_size.x, rock_size.y / tex_size.y)

func _build_collision() -> void:
	_body = StaticBody2D.new()
	_body.name = "RockBody"
	_body.collision_layer = collision_layer
	_body.collision_mask = collision_mask
	add_child(_body)

	_shape = CollisionShape2D.new()
	_shape.name = "RockShape"
	_shape.shape = _make_shape()
	_body.add_child(_shape)

func _make_shape() -> Shape2D:
	# Use the VISUAL size (rock_size), minus the inset margins
	var s := Vector2(
		max(1.0, rock_size.x - collision_shrink.x * 2.0),
		max(1.0, rock_size.y - collision_shrink.y * 2.0)
	)
	match collision_shape_type:
		0: # Rectangle
			var r := RectangleShape2D.new()
			r.size = s
			return r
		1: # Circle — use the smaller axis as diameter
			var c := CircleShape2D.new()
			c.radius = min(s.x, s.y) * 0.5
			return c
		2: # Capsule
			var cap := CapsuleShape2D.new()
			cap.radius = min(s.x, s.y) * 0.5
			cap.height = max(s.x, s.y)
			return cap
	return RectangleShape2D.new()

# ==========================================
# PUBLIC API
# ==========================================
func set_texture(tex: Texture2D) -> void:
	rock_texture = tex
	if _sprite:
		_sprite.texture = tex
		_apply_sprite_size()

func set_size(new_size: Vector2) -> void:
	rock_size = new_size
	_apply_sprite_size()
	if _shape:
		_shape.shape = _make_shape()

# ==========================================
# EDITOR LIVE PREVIEW
# ==========================================
func _get_configuration_warnings() -> PackedStringArray:
	var warnings : PackedStringArray = []
	if rock_texture == null:
		warnings.append("No rock_texture assigned — sprite will be invisible.")
	if rock_size.x <= 0 or rock_size.y <= 0:
		warnings.append("rock_size must be positive.")
	return warnings
