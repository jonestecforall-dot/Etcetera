extends TextureRect

@export var map_width_tiles: int = 30
@export var map_height_tiles: int = 10
@export var tile_size: int = 16

# DRAG THESE IN!
@export var floor_edge_texture: Texture2D
@export var floor_sand_texture: Texture2D
@export var wall_texture: Texture2D
@export var platform_texture: Texture2D

var textures: Array[Texture2D] = []

func _ready() -> void:
	size = Vector2(map_width_tiles * tile_size, map_height_tiles * tile_size)
	
	# Index 0 = Edge, Index 1 = Sand, Index 2 = Wall, Index 3 = Platform
	textures = [floor_edge_texture, floor_sand_texture, wall_texture, platform_texture]
	
	# Seed the random number generator so every level is the same when you run it
	seed(12345)
	
	_build_world()

func _build_world() -> void:
	# 1. BUILD THE BASE FLOOR (With Hills & Valleys)
	# Instead of a flat line, we create a "height map" so the ground goes up and down.
	var floor_height = {}
	
	for x in range(map_width_tiles):
		var y_height = map_height_tiles - 1
		
		# Create some hills and valleys
		if x > 5 and x < 10:
			y_height -= 2 # Hill going up
		elif x > 14 and x < 16:
			y_height += 1 # Valley going down (Falls in a hole)
		elif x > 20 and x < 24:
			y_height -= 3 # Big mountain up
			
		floor_height[x] = y_height
	
	# 2. BUILD THE FLOOR USING THE HEIGHT MAP
	for x in range(map_width_tiles):
		var top_y = floor_height[x]
		
		# Edge on top
		_create_block(x, top_y, 0)
		# Sand below
		_create_block(x, top_y + 1, 1)
		_create_block(x, top_y + 2, 1)
		_create_block(x, top_y + 3, 1)

	# 3. WALLS (Left and Right)
	for y in range(map_height_tiles - 1):
		_create_block(0, y, 2)  # Left wall
		_create_block(map_width_tiles - 1, y, 2)  # Right wall

	# 4. FLOATING PLATFORMS (A proper platforming route)
	# Low floating steps to get over the first hill
	_create_block(5, 5, 3)
	_create_block(7, 4, 3)
	
	# High jump over the valley
	_create_block(14, 5, 3)
	_create_block(15, 3, 3)
	
	# Route up the big mountain
	_create_block(20, 4, 3)
	_create_block(22, 2, 3)
	
	# A final, high platform for the boss
	_create_block(26, 4, 3)
	_create_block(28, 3, 3)

func _create_block(grid_x: int, grid_y: int, texture_index: int) -> void:
	var pos = Vector2(grid_x * tile_size, grid_y * tile_size)
	
	# PURE VISUAL
	var visual = TextureRect.new()
	visual.texture = textures[texture_index]
	visual.position = pos
	visual.size = Vector2(tile_size, tile_size)
	add_child(visual)
	
	# PURE PHYSICS
	var body = StaticBody2D.new()
	body.position = pos + Vector2(tile_size / 2.0, tile_size / 2.0)
	add_child(body)
	
	var shape = RectangleShape2D.new()
	shape.size = Vector2(tile_size, tile_size)
	
	var collision = CollisionShape2D.new()
	collision.shape = shape
	body.add_child(collision)
