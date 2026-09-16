extends TileMap

@export var collision_layer: int = 1  # Default layer for the player to hit

func _ready() -> void:
	# 1. GET THE TILESET RESOURCE
	var ts: TileSet = tile_set # This is the property directly on the TileMap node
	if ts == null:
		push_error("No TileSet assigned!")
		return
	
	# 2. SET UP THE PHYSICS LAYER
	while ts.get_physics_layers_count() > 0:
		ts.remove_physics_layer(0)
	
	ts.add_physics_layer()
	ts.set_physics_layer_collision_layer(0, collision_layer)
	
	# 3. LOOP THROUGH THE SOURCES
	for source_id in ts.get_source_ids():
		# Get the actual TileSetAtlasSource
		var source = ts.get_source(source_id) 
		
		if source == null:
			continue
		
		# 4. LOOP THROUGH EVERY TILE
		for x in range(0, 64): # Adjust this to match your image width
			for y in range(0, 64): # Adjust this to match your image height
				var atlas_coords = Vector2i(x, y)
				
				# Skip if this tile doesn't exist
				if not source.has_tile(atlas_coords):
					continue
				
				# 5. FORCE COLLISION
				var tile = source.get_tile_data(atlas_coords, 0)
				
				# Create a 16x16 square
				var collision_polygon = PackedVector2Array([
					Vector2(0, 0),
					Vector2(16, 0),
					Vector2(16, 16),
					Vector2(0, 16)
				])
				
				tile.add_collision_polygon(0)
				tile.set_collision_polygon_points(0, 0, collision_polygon)
				
				print("Tile at ", atlas_coords, " has collision!")

func _process(delta: float) -> void:
	pass
