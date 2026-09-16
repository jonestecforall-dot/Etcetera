extends Node # Change to Node, not BaseBoss!

# --- Scrapheap Specific Stats ---
@export var bullet_scene : PackedScene 
@export var water_jet_scene : PackedScene 
@export var fire_point_path : NodePath # Path to the Marker2D in the mouth

@export var bullet_interval : float = 0.15 
@export var rounds_before_water_jet : int = 3 
@export var attack_cooldown : float = 3.0 
@export var move_speed : float = 150.0

# --- Internal State ---
var current_round : int = 0
var can_attack : bool = true
var is_charging : bool = false
var fire_point : Node2D

# --- References to the Main Boss (Set by the Main Boss) ---
var boss : CharacterBody2D
var boss_sprite : AnimatedSprite2D
var boss_audio : AudioStreamPlayer2D

# --- Called by the Main Boss ---
func initialize(boss_parent: CharacterBody2D, sprite_node: AnimatedSprite2D, audio_node: AudioStreamPlayer2D) -> void:
	boss = boss_parent
	boss_sprite = sprite_node
	boss_audio = audio_node
	
	if fire_point_path:
		fire_point = boss.get_node(fire_point_path)
		
	print("Scrapheap Phase 1 Initialized")
	
	# Set up timer (purely internal to this child node)
	var attack_timer = Timer.new()
	attack_timer.wait_time = attack_cooldown
	attack_timer.autostart = true
	attack_timer.timeout.connect(_on_attack_timer_timeout)
	add_child(attack_timer)

# --- Called by the Main Boss every frame ---
func update_movement(delta: float) -> void:
	if is_charging or not boss:
		return
		
	# Basic Up and Down movement (No tracking)
	boss.velocity.y = sin(Time.get_ticks_msec() * 0.002) * move_speed
	
	# Play the moving animation if it exists
	if boss_sprite and boss_sprite.has_method("update_visual_state"):
		boss_sprite.update_visual_state("moving")
# --- Phase 1 Logic: Attack Patterns ---
func _on_attack_timer_timeout() -> void:
	if not boss or boss.is_dead or boss.is_stunned or not can_attack:
		return
		
	can_attack = false
	current_round += 1
	
	if current_round >= rounds_before_water_jet:
		current_round = 0 
		_start_water_jet_phase()
	else:
		_start_normal_bullet_phase()
	
	boss.get_tree().create_timer(attack_cooldown).timeout.connect(_reset_attack)

func _reset_attack() -> void:
	can_attack = true

# --- Normal Bullet Phase ---
func _start_normal_bullet_phase() -> void:
	if boss_sprite: boss_sprite.update_visual_state("attacking")
	if boss_audio and boss.shoot_sound:
		boss_audio.stream = boss.shoot_sound
		boss_audio.play()
	
	for i in range(3):
		_spawn_bullet()
		await get_tree().create_timer(bullet_interval).timeout
		
	if boss_sprite: boss_sprite.update_visual_state("moving")

func _spawn_bullet() -> void:
	if bullet_scene and fire_point:
		var bullet = bullet_scene.instantiate()
		boss.get_parent().add_child(bullet) 
		bullet.global_position = fire_point.global_position

# --- Water Jet Phase ---
func _start_water_jet_phase() -> void:
	is_charging = true 
	print("Boss is now charging Water Jet!")
	
	if boss_sprite: boss_sprite.update_visual_state("attacking")
	if boss_audio and boss.shoot_sound:
		boss_audio.stream = boss.shoot_sound
		boss_audio.play()
	
	if water_jet_scene and fire_point:
		var jet = water_jet_scene.instantiate()
		boss.get_parent().add_child(jet)
		jet.global_position = fire_point.global_position
		
	await get_tree().create_timer(1.0).timeout
	is_charging = false
	if boss_sprite: boss_sprite.update_visual_state("moving")
