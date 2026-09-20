extends Node2D

# --- SHELL CONFIGURATION ---
@export_group("Shell Setup")
@export var shell_textures: Array[Texture2D] = []
@export var shell_names: Array[String] = []
@export var randomize_on_spawn: bool = true

# --- POWER-UP CHILD NODES ---
@export_group("Power-Up Logic Nodes")
@export var power_up_nodes: Array[Node] = []

# --- NODE REFERENCES ---
@export_group("Node References")
@export var sprite_node: Sprite2D
@export var collision_area: Area2D

# --- COLLISION SETTINGS ---
@export_group("Collision")
@export var collision_radius: float = 16.0
@export var player_group: String = "player"

# --- INTERNAL STATE (exported so save/load preserves them) ---
@export var current_shell_index: int = -1
@export var current_shell_texture: Texture2D = null
@export var current_shell_name: String = ""
var is_collected: bool = false

func _ready() -> void:
	# Only auto-pick if nothing forced an index before _ready() ran
	if current_shell_index < 0:
		if randomize_on_spawn and shell_textures.size() > 0:
			current_shell_index = randi() % shell_textures.size()
		elif shell_textures.size() > 0:
			current_shell_index = 0

	# Set the texture and name from the (possibly forced) index
	if current_shell_index >= 0 and current_shell_index < shell_textures.size():
		current_shell_texture = shell_textures[current_shell_index]
		if current_shell_index < shell_names.size():
			current_shell_name = shell_names[current_shell_index]
		else:
			current_shell_name = "Shell_" + str(current_shell_index)

	if sprite_node and current_shell_texture:
		sprite_node.texture = current_shell_texture

	_build_collision()

func _build_collision() -> void:
	var area: Area2D = collision_area
	if area == null:
		area = Area2D.new()
		area.name = "ShellPickupArea"
		add_child(area)

	area.collision_layer = 0
	area.collision_mask = 1
	area.monitoring = true
	area.monitorable = true

	var col_shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = collision_radius
	col_shape.shape = circle
	area.add_child(col_shape)

	area.body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if is_collected:
		return
	if not body.is_in_group(player_group):
		return
	_collect(body)

func _collect(player: Node) -> void:
	is_collected = true
	_apply_texture_to_player(player)
	queue_free()


func _apply_texture_to_player(player: Node) -> void:
	if not player.has_method("equip_shell"):
		print("⚠️ Player has no equip_shell() method — texture not applied")
		return

	# Build the power-up list. If the export is empty (which happens after
	# reparenting on load), fall back to scanning our own children.
	var sources: Array = []
	if power_up_nodes.size() > 0:
		sources = power_up_nodes
	else:
		for child in get_children():
			if child.has_method("apply"):
				sources.append(child)
		print("🔧 Shell rebuilt power_up_nodes from children: ", sources.size())

	# Collect matching power-ups as DUPLICATES so they survive queue_free()
	var matching_power_ups: Array = []
	for power_up in sources:
		if power_up == null or not is_instance_valid(power_up):
			continue
		var pu_name = power_up.get("shell_name")
		print("   [check] node='", power_up.name,
			"' shell_name='", pu_name,
			"' vs current='", current_shell_name,
			"' match=", pu_name == current_shell_name)
		if pu_name != null and pu_name != current_shell_name:
			continue
		matching_power_ups.append(power_up.duplicate())

	player.equip_shell(current_shell_texture, current_shell_name, matching_power_ups)
	print("🐚 Shell equipped on player: ", current_shell_name,
		" (", matching_power_ups.size(), " power-ups) | sources=", sources.size(),
		" | current='", current_shell_name, "'")
