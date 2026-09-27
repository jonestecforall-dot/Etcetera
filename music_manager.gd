extends Node2D
# =============================================================================
# 🎵 MUSIC MANAGER
# =============================================================================
# Central audio player for the game. Handles:
#   - Named music slots (intro, battle, build, general)
#   - Auto-creating AudioStreamPlayers if they don't exist
#   - Fade in / fade out via Tween
#   - Detection of game state via Groups (player, enemy, intro)
#   - Export arrays for editors / tools to browse tracks
#   - 🆕 Playlist rotation — cycles through every track in a category
#   - 🆕 Debug logging throttled + change-only (safe for web export)
#   - 🆕 Optional CanvasLayer for any manager-owned UI

# =============================================================================
# 📤 EXPORTS
# =============================================================================
@export_group("Music Tracks")
## Played while a visible node is in the "intro" group (menus, title screens).
@export var intro_tracks : Array[AudioStream] = []
## Played while enemies are present in the current scene.
@export var battle_tracks : Array[AudioStream] = []
## Played while the player is in build mode (no enemies present).
@export var build_tracks : Array[AudioStream] = []
## Fallback — anything that doesn't match the other states.
@export var general_tracks : Array[AudioStream] = []

@export_group("Playback")
@export var music_bus : StringName = &"Music"
@export var base_volume_db : float = -8.0
@export var fade_in_time : float = 1.5
@export var fade_out_time : float = 1.0
@export var crossfade_time : float = 0.8
@export var shuffle_within_category : bool = true
@export var auto_detect_state : bool = true
@export var state_poll_interval : float = 0.5

@export_group("Groups")
@export var player_group : StringName = &"player"
@export var enemy_group : StringName = &"enemy"
@export var intro_group : StringName = &"intro"
@export var water_group : StringName = &"water"

# 🆕 Optional CanvasLayer — assign in the inspector if this manager needs
# to own any UI (e.g. now-playing overlay, debug readout). The layer is
# created automatically if left null, so code can still add children to it.
@export_group("UI")
@export var ui_canvas_layer : CanvasLayer = null
@export var ui_canvas_layer_index : int = 90

# =============================================================================
# 🐛 DEBUG
# =============================================================================
@export_group("Debug")
## Print every state transition. Disable before shipping to web.
@export var debug_state_changes : bool = false
## Print the per-poll state check. VERY noisy — keep off unless diagnosing.
@export var debug_state_polls : bool = false

# =============================================================================
# 🎛 STATE
# =============================================================================
enum MusicState { NONE, INTRO, BATTLE, BUILD, GENERAL }
var current_state : MusicState = MusicState.NONE

var _player_a : AudioStreamPlayer
var _player_b : AudioStreamPlayer
var _active : AudioStreamPlayer
var _inactive : AudioStreamPlayer

var _state_poll_accum : float = 0.0
var _current_category : String = ""
var _rng := RandomNumberGenerator.new()
var _playing : bool = false
var _current_stream : AudioStream = null

# 🆕 Playlist rotation state — remembers where we are in each category
var _category_index : Dictionary = {}     # category_name -> current index
var _last_state_log : String = ""          # for change-only logging

# 🆕 Manager-owned UI layer
var _ui_layer : CanvasLayer = null

# =============================================================================
# 🚀 LIFECYCLE
# =============================================================================
func _ready() -> void:
	_rng.randomize()
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_ui_layer()
	_ensure_players()
	
	# If we can figure out the state right away, start playing.
	if auto_detect_state:
		_update_state_now()
	else:
		# Default to intro if any intro tracks exist, otherwise general.
		if intro_tracks.size() > 0:
			play_category("intro")
		elif general_tracks.size() > 0:
			play_category("general")


func _process(delta: float) -> void:
	if not auto_detect_state:
		return
	_state_poll_accum += delta
	if _state_poll_accum >= state_poll_interval:
		_state_poll_accum = 0.0
		_update_state_now()


# =============================================================================
# 🖼️ UI LAYER
# =============================================================================
# Ensures a CanvasLayer exists and is stored on _ui_layer. If the export
# was assigned in the inspector, we use that; otherwise we create one at
# the configured index so manager UI can be added anywhere in the code.
func _ensure_ui_layer() -> void:
	if ui_canvas_layer != null:
		_ui_layer = ui_canvas_layer
		return
	var existing := get_node_or_null("MusicUI")
	if existing is CanvasLayer:
		_ui_layer = existing as CanvasLayer
		ui_canvas_layer = _ui_layer
		return
	_ui_layer = CanvasLayer.new()
	_ui_layer.name = "MusicUI"
	_ui_layer.layer = ui_canvas_layer_index
	add_child(_ui_layer)
	ui_canvas_layer = _ui_layer


# Public accessor — anything that needs to add UI to the manager's layer
# can call this instead of reaching for a hard node path.
func get_ui_layer() -> CanvasLayer:
	if _ui_layer == null:
		_ensure_ui_layer()
	return _ui_layer


# =============================================================================
# 🎧 PLAYER SETUP
# =============================================================================
func _ensure_players() -> void:
	_player_a = _find_or_create_player("MusicPlayerA")
	_player_b = _find_or_create_player("MusicPlayerB")
	_active = _player_a
	_inactive = _player_b
	
	for p in [_player_a, _player_b]:
		p.volume_db = base_volume_db
		p.bus = music_bus
		p.process_mode = Node.PROCESS_MODE_ALWAYS
		# 🆕 Auto-advance to the next track in the category when one ends.
		p.finished.connect(_on_player_finished.bind(p))


func _find_or_create_player(name: String) -> AudioStreamPlayer:
	var existing := get_node_or_null(name)
	if existing is AudioStreamPlayer:
		return existing as AudioStreamPlayer
	var p := AudioStreamPlayer.new()
	p.name = name
	add_child(p)
	return p


func _on_player_finished(player: AudioStreamPlayer) -> void:
	# Only auto-advance if the finished player is the active one.
	if player != _active:
		return
	if not _playing:
		return
	if _current_category == "":
		return
	next_track()


# =============================================================================
# 🎵 PUBLIC API
# =============================================================================
# Play a category by name: "intro", "battle", "build", "general".
func play_category(category: String) -> void:
	if category == _current_category and _playing:
		return
	var tracks := _tracks_for_category(category)
	if tracks.is_empty():
		push_warning("MusicManager: no tracks for category '" + category + "'")
		return
	var track : AudioStream = _pick_track(category, tracks)
	_play_stream(track, category)


# Play a specific AudioStream directly. Bypasses category logic.
func play_stream(stream: AudioStream) -> void:
	if stream == null:
		return
	_play_stream(stream, "")


# Stop whatever is playing, with a fade.
func stop_music(fade : bool = true) -> void:
	if not _playing:
		return
	_playing = false
	_current_stream = null
	if fade:
		_fade_out_and_stop(_active)
	else:
		_active.stop()


# Skip to the next track in the current category.
func next_track() -> void:
	if _current_category == "":
		return
	var tracks := _tracks_for_category(_current_category)
	if tracks.size() <= 1:
		return
	var current_idx : int = int(_category_index.get(_current_category, -1))
	var next_idx : int = (current_idx + 1) % tracks.size()
	_category_index[_current_category] = next_idx
	_play_stream(tracks[next_idx], _current_category)


# Returns the music tracks for a given category as an Array.
func get_tracks_for_category(category: String) -> Array:
	return _tracks_for_category(category)


# Returns a dictionary of all categories and their tracks. Useful for export.
func export_all_tracks() -> Dictionary:
	return {
		"intro": intro_tracks.duplicate(),
		"battle": battle_tracks.duplicate(),
		"build": build_tracks.duplicate(),
		"general": general_tracks.duplicate(),
	}


func is_playing() -> bool:
	return _playing


func get_current_stream() -> AudioStream:
	return _current_stream


func get_current_category() -> String:
	return _current_category


# =============================================================================
# 🔄 STATE DETECTION (via Groups)
# =============================================================================
func _detect_state() -> String:
	var tree := get_tree()
	if tree == null:
		return "general"
	
	var has_player := _has_live_group_members(player_group)
	var has_enemy := _has_live_group_members(enemy_group)
	var has_visible_intro := _has_visible_group_members(intro_group)
	
	if debug_state_polls:
		print("🎵 [poll] player=", has_player, " enemy=", has_enemy, " intro=", has_visible_intro)
	
	# Player exists → we're in-game. Never play intro music.
	if has_player:
		if has_enemy:
			return "battle"
		return "build"
	
	# No player → we might be on a menu.
	if has_visible_intro:
		return "intro"
	
	return "general"


func _has_live_group_members(group: StringName) -> bool:
	var tree := get_tree()
	if tree == null:
		return false
	for n in tree.get_nodes_in_group(group):
		if is_instance_valid(n) and n.is_inside_tree():
			return true
	return false


func _has_visible_group_members(group: StringName) -> bool:
	var tree := get_tree()
	if tree == null:
		return false
	for n in tree.get_nodes_in_group(group):
		if not is_instance_valid(n) or not n.is_inside_tree():
			continue
		if n is CanvasItem and not (n as CanvasItem).is_visible_in_tree():
			continue
		if n is Node3D and not (n as Node3D).is_visible_in_tree():
			continue
		return true
	return false


func _update_state_now() -> void:
	var next_category := _detect_state()
	if next_category == _current_category:
		_last_state_log = next_category
		return
	
	var next_tracks := _tracks_for_category(next_category)
	
	if debug_state_changes:
		print("🔄 MusicManager: ", _current_category, " → ", next_category,
			" (tracks: ", next_tracks.size(), ")")
	
	if next_tracks.is_empty():
		if _playing:
			if debug_state_changes:
				print("   ↳ No tracks for '", next_category, "', stopping current music")
			stop_music(true)
		_current_category = next_category
		return
	
	play_category(next_category)


# =============================================================================
# ▶️ PLAYBACK CORE
# =============================================================================
func _play_stream(stream: AudioStream, category: String) -> void:
	if stream == null:
		return
	
	var was_playing := _playing and _active and _active.playing
	
	# Swap active/inactive
	var old_active := _active
	_active = _inactive
	_inactive = old_active
	
	_active.stream = stream
	_active.volume_db = -80.0  # start silent so we can fade in
	_active.play()
	
	_current_stream = stream
	_current_category = category
	_playing = true
	
	# Fade in the new player.
	var fade_in := create_tween()
	fade_in.tween_property(_active, "volume_db", base_volume_db, fade_in_time)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	
	# Fade out the previous player if it was playing.
	if was_playing and old_active and old_active.playing:
		var fade_out := create_tween()
		fade_out.tween_property(old_active, "volume_db", -80.0, crossfade_time)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		fade_out.tween_callback(old_active.stop)
	else:
		if old_active:
			old_active.stop()
	
	if debug_state_changes:
		print("🎵 Music: playing '", category, "' — ", _describe_stream(stream))


func _fade_out_and_stop(player: AudioStreamPlayer) -> void:
	if player == null or not player.playing:
		return
	var t := create_tween()
	t.tween_property(player, "volume_db", -80.0, fade_out_time)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	t.tween_callback(player.stop)


# =============================================================================
# 🎲 TRACK SELECTION
# =============================================================================
func _tracks_for_category(category: String) -> Array:
	match category:
		"intro":    return intro_tracks
		"battle":   return battle_tracks
		"build":    return build_tracks
		"general":  return general_tracks
	return []


# 🆕 Picks the next track in a category. If shuffle is on, picks a random
# index different from the current one (so we never repeat the same track
# back-to-back). Otherwise advances sequentially.
func _pick_track(category: String, tracks: Array) -> AudioStream:
	if tracks.is_empty():
		return null
	if tracks.size() == 1:
		_category_index[category] = 0
		return tracks[0]
	
	var last_idx : int = int(_category_index.get(category, -1))
	var next_idx : int = 0
	
	if shuffle_within_category:
		# Random, but never the same as last time
		next_idx = _rng.randi_range(0, tracks.size() - 1)
		if next_idx == last_idx:
			next_idx = (next_idx + 1) % tracks.size()
	else:
		next_idx = (last_idx + 1) % tracks.size()
	
	_category_index[category] = next_idx
	return tracks[next_idx]


# =============================================================================
# 🧠 HELPERS
# =============================================================================
func _describe_stream(stream: AudioStream) -> String:
	if stream == null:
		return "<null>"
	if stream.resource_path != "":
		return stream.resource_path.get_file()
	return stream.get_class()
