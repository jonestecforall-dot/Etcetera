extends CanvasLayer

# =============================================================================
# 🎬 SPRITE SLICE 3000 — UI
# =============================================================================

var root : Node = null
var sheets : Array = []
var selected_sheet_index : int = 0
var selected_row_index : int = 0
# Per-sheet detection mode override
# 0 = GRID (default), 1 = TRANSPARENCY
var _sheet_detection_modes : Dictionary = {}
var row_name_inputs : Array = []

# Animation player state
var anim_frames : Array[Texture2D] = []
var anim_frame_index : int = 0
var anim_timer : Timer = null
var anim_playing : bool = false

# Delete confirmation dialog
var confirm_dialog : ConfirmationDialog = null

# Sheet tab paging
var visible_tab_start : int = 0
const MAX_VISIBLE_TABS : int = 6
var prev_tab_btn : Button = null
var next_tab_btn : Button = null

# =============================================================================
# 🎨 COLORS
# =============================================================================
const COL_BG          := Color(0.06, 0.06, 0.09)
const COL_PANEL       := Color(0.10, 0.10, 0.14)
const COL_PANEL_ALT   := Color(0.13, 0.13, 0.18)
const COL_BORDER      := Color(0.25, 0.27, 0.35)
const COL_ACCENT      := Color(0.35, 0.65, 1.0)
const COL_ACCENT_DARK := Color(0.20, 0.40, 0.75)
const COL_TEXT        := Color(0.92, 0.94, 1.0)
const COL_TEXT_DIM    := Color(0.55, 0.58, 0.68)
const COL_GREEN       := Color(0.30, 0.75, 0.40)
const COL_PURPLE      := Color(0.55, 0.35, 0.85)
const COL_RED         := Color(0.75, 0.25, 0.25)

# =============================================================================
# 🎨 UI NODES
# =============================================================================
var root_control : Control
var bg_rect : ColorRect
var top_bar : ColorRect
var bottom_bar : ColorRect

var title_label : Label
var subtitle_label : Label
var sheet_row : HBoxContainer
var sheet_buttons : Array = []
var status_label : Label

var menu_btn : Button

var preview_panel : Panel
var preview_title : Label
var preview_display : TextureRect
var preview_overlay : Control

var anim_panel : Panel
var anim_title : Label
var anim_display : TextureRect

var info_panel : Panel
var info_label : RichTextLabel

var rows_panel : Panel
var rows_title : Label
var rows_container : VBoxContainer
var rows_scroll : ScrollContainer

var button_row : HBoxContainer
var re_detect_btn : Button
var save_btn : Button
var export_btn : Button
var play_all_btn : Button
var delete_btn : Button

# =============================================================================
# 🚀 INIT
# =============================================================================
func _ready() -> void:
	root = get_parent()
	if root == null:
		push_warning("SpriteSlice3000UI: no parent found")
		return
	_build_ui()
	
	# Animation player timer
	anim_timer = Timer.new()
	anim_timer.wait_time = 0.1
	anim_timer.autostart = false
	anim_timer.timeout.connect(_on_anim_tick)
	add_child(anim_timer)
	
	status_label.text = "Ready. Press  Re-Detect  to scan your sprite sheets."

# =============================================================================
# 🎨 BUILD UI
# =============================================================================

func _build_ui() -> void:
	root_control = Control.new()
	root_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root_control)
	
	bg_rect = ColorRect.new()
	bg_rect.color = COL_BG
	bg_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_control.add_child(bg_rect)
	
	top_bar = ColorRect.new()
	top_bar.color = Color(0.08, 0.08, 0.12, 1.0)
	top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_bar.offset_bottom = 110
	top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_control.add_child(top_bar)
	
	title_label = Label.new()
	title_label.text = "🎬  SpriteSlice3000"
	title_label.position = Vector2(24, 16)
	title_label.add_theme_font_size_override("font_size", 26)
	title_label.add_theme_color_override("font_color", COL_TEXT)
	root_control.add_child(title_label)
	
	subtitle_label = Label.new()
	subtitle_label.text = "Auto-detect sprite cells · Name animations · Export as SpriteFrames"
	subtitle_label.position = Vector2(26, 50)
	subtitle_label.add_theme_font_size_override("font_size", 12)
	subtitle_label.add_theme_color_override("font_color", COL_TEXT_DIM)
	root_control.add_child(subtitle_label)
	
	# =====================================================================
	# MENU BUTTON (top right)
	# =====================================================================
	menu_btn = _make_button("☰  Menu", COL_ACCENT_DARK, false)
	menu_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	menu_btn.offset_left = -170
	menu_btn.offset_right = -24
	menu_btn.offset_top = 16
	menu_btn.offset_bottom = 56
	menu_btn.custom_minimum_size = Vector2(140, 40)
	menu_btn.pressed.connect(_on_menu_pressed)
	root_control.add_child(menu_btn)
	
	# =====================================================================
	# SHEET TABS ROW (prev arrow + up to 6 tabs + next arrow)
	# =====================================================================
	sheet_row = HBoxContainer.new()
	sheet_row.position = Vector2(24, 76)
	sheet_row.add_theme_constant_override("separation", 8)
	root_control.add_child(sheet_row)
	
	prev_tab_btn = _make_tab_button("◄")
	prev_tab_btn.custom_minimum_size = Vector2(34, 30)
	prev_tab_btn.pressed.connect(_on_prev_tab_pressed)
	prev_tab_btn.visible = false
	sheet_row.add_child(prev_tab_btn)
	
	next_tab_btn = _make_tab_button("►")
	next_tab_btn.custom_minimum_size = Vector2(34, 30)
	next_tab_btn.pressed.connect(_on_next_tab_pressed)
	next_tab_btn.visible = false
	sheet_row.add_child(next_tab_btn)
	
	status_label = Label.new()
	status_label.position = Vector2(24, 120)
	status_label.add_theme_font_size_override("font_size", 13)
	status_label.add_theme_color_override("font_color", COL_TEXT_DIM)
	root_control.add_child(status_label)
	
	# =====================================================================
	# LEFT: Preview panel
	# =====================================================================
	preview_panel = Panel.new()
	preview_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	preview_panel.anchor_bottom = 1.0
	preview_panel.offset_left = 24
	preview_panel.offset_top = 150
	preview_panel.offset_right = 400
	preview_panel.offset_bottom = -90
	preview_panel.add_theme_stylebox_override("panel", _style(COL_PANEL, COL_BORDER, 1, 10))
	root_control.add_child(preview_panel)
	
	preview_title = Label.new()
	preview_title.text = "PREVIEW"
	preview_title.position = Vector2(14, 10)
	preview_title.add_theme_font_size_override("font_size", 11)
	preview_title.add_theme_color_override("font_color", COL_TEXT_DIM)
	preview_panel.add_child(preview_title)
	
	preview_display = TextureRect.new()
	preview_display.set_anchors_preset(Control.PRESET_FULL_RECT)
	preview_display.offset_left = 12
	preview_display.offset_top = 32
	preview_display.offset_right = -12
	preview_display.offset_bottom = -12
	preview_display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview_display.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview_display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_panel.add_child(preview_display)
	
	preview_overlay = Control.new()
	preview_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	preview_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_overlay.draw.connect(_draw_overlay)
	preview_display.add_child(preview_overlay)
	
	# =====================================================================
	# CENTER: Info panel
	# =====================================================================
	info_panel = Panel.new()
	info_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	info_panel.offset_left = 420
	info_panel.offset_right = 900
	info_panel.offset_top = 150
	info_panel.offset_bottom = 194
	info_panel.add_theme_stylebox_override("panel", _style(COL_PANEL, COL_BORDER, 1, 10))
	root_control.add_child(info_panel)
	
	info_label = RichTextLabel.new()
	info_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	info_label.offset_left = 14
	info_label.offset_top = 4
	info_label.offset_right = -14
	info_label.offset_bottom = -4
	info_label.bbcode_enabled = true
	info_label.fit_content = true
	info_label.scroll_active = false
	info_label.add_theme_color_override("default_color", COL_TEXT)
	info_label.add_theme_font_size_override("normal_font_size", 12)
	info_label.add_theme_font_size_override("bold_font_size", 13)
	info_panel.add_child(info_label)
	
	# =====================================================================
	# CENTER: Rows / animations list
	# =====================================================================
	rows_panel = Panel.new()
	rows_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	rows_panel.anchor_bottom = 1.0
	rows_panel.offset_left = 420
	rows_panel.offset_right = 900
	rows_panel.offset_top = 210
	rows_panel.offset_bottom = -90
	rows_panel.add_theme_stylebox_override("panel", _style(COL_PANEL, COL_BORDER, 1, 10))
	root_control.add_child(rows_panel)
	
	rows_title = Label.new()
	rows_title.text = "ANIMATIONS"
	rows_title.position = Vector2(14, 10)
	rows_title.add_theme_font_size_override("font_size", 11)
	rows_title.add_theme_color_override("font_color", COL_TEXT_DIM)
	rows_panel.add_child(rows_title)
	
	rows_scroll = ScrollContainer.new()
	rows_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	rows_scroll.offset_left = 12
	rows_scroll.offset_top = 32
	rows_scroll.offset_right = -12
	rows_scroll.offset_bottom = -12
	rows_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rows_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	rows_panel.add_child(rows_scroll)
	
	rows_container = VBoxContainer.new()
	rows_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows_container.add_theme_constant_override("separation", 6)
	rows_scroll.add_child(rows_container)
	
	# =====================================================================
	# RIGHT: Live animation panel
	# =====================================================================
	anim_panel = Panel.new()
	anim_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	anim_panel.anchor_bottom = 1.0
	anim_panel.offset_left = -380
	anim_panel.offset_right = -24
	anim_panel.offset_top = 150
	anim_panel.offset_bottom = -90
	anim_panel.add_theme_stylebox_override("panel", _style(COL_PANEL, COL_ACCENT_DARK, 2, 10))
	root_control.add_child(anim_panel)
	
	anim_title = Label.new()
	anim_title.text = "LIVE ANIMATION"
	anim_title.position = Vector2(14, 10)
	anim_title.add_theme_font_size_override("font_size", 11)
	anim_title.add_theme_color_override("font_color", COL_ACCENT)
	anim_panel.add_child(anim_title)
	
	anim_display = TextureRect.new()
	anim_display.set_anchors_preset(Control.PRESET_FULL_RECT)
	anim_display.offset_left = 12
	anim_display.offset_top = 32
	anim_display.offset_right = -12
	anim_display.offset_bottom = -12
	anim_display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	anim_display.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	anim_display.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	anim_display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	anim_panel.add_child(anim_display)
	
	# =====================================================================
	# BOTTOM: Buttons
	# =====================================================================
	bottom_bar = ColorRect.new()
	bottom_bar.color = Color(0.08, 0.08, 0.12, 1.0)
	bottom_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom_bar.offset_top = -74
	bottom_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_control.add_child(bottom_bar)
	
	button_row = HBoxContainer.new()
	button_row.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	button_row.offset_left = 24
	button_row.offset_right = -24
	button_row.offset_top = -62
	button_row.offset_bottom = -12
	button_row.add_theme_constant_override("separation", 12)
	root_control.add_child(button_row)
	
	re_detect_btn = _make_button("🔍  Re-Detect", COL_ACCENT, true)
	re_detect_btn.pressed.connect(_on_re_detect_pressed)
	button_row.add_child(re_detect_btn)
	
	# ── DETECTION MODE TOGGLE (lives here, next to Re-Detect) ──────
	var toggle_container = HBoxContainer.new()
	toggle_container.name = "DetectionToggleRow"
	toggle_container.add_theme_constant_override("separation", 0)
	
	var grid_btn = _make_tab_button("Grid")
	grid_btn.name = "GridBtn"
	grid_btn.custom_minimum_size = Vector2(90, 40)
	grid_btn.add_theme_font_size_override("font_size", 13)
	grid_btn.pressed.connect(func(): _set_sheet_detection_mode(0))
	toggle_container.add_child(grid_btn)
	
	var transp_btn = _make_tab_button("Transparency")
	transp_btn.name = "TranspBtn"
	transp_btn.custom_minimum_size = Vector2(130, 40)
	transp_btn.add_theme_font_size_override("font_size", 13)
	transp_btn.pressed.connect(func(): _set_sheet_detection_mode(1))
	toggle_container.add_child(transp_btn)
	
	button_row.add_child(toggle_container)
	# ───────────────────────────────────────────────────────────────
	
	save_btn = _make_button("💾  Save Row As .tres", COL_PURPLE, true)
	save_btn.pressed.connect(_on_save_pressed)
	button_row.add_child(save_btn)
	
	export_btn = _make_button("📦  Export All Rows", COL_GREEN, true)
	export_btn.pressed.connect(_on_export_all_pressed)
	button_row.add_child(export_btn)
	
	play_all_btn = _make_button("▶  Play All Rows", COL_ACCENT_DARK, true)
	play_all_btn.pressed.connect(_on_play_all_pressed)
	button_row.add_child(play_all_btn)
	
	delete_btn = _make_button("🗑  Delete Saves", COL_RED, true)
	delete_btn.pressed.connect(_on_delete_pressed)
	button_row.add_child(delete_btn)
	
	# =====================================================================
	# DELETE CONFIRMATION DIALOG
	# =====================================================================
	confirm_dialog = ConfirmationDialog.new()
	confirm_dialog.title = "Delete All Saves?"
	confirm_dialog.dialog_text = "⚠️ This will permanently delete ALL .tres files in:\n\nres://sprite_frames/\n\nThis cannot be undone. Continue?"
	confirm_dialog.ok_button_text = "Yes, Delete All"
	confirm_dialog.cancel_button_text = "Cancel"
	confirm_dialog.confirmed.connect(_on_delete_confirmed)
	add_child(confirm_dialog)

# =============================================================================
# 📥 HANDLERS
# =============================================================================
func on_sheets_detected(new_sheets: Array) -> void:
	sheets = new_sheets
	selected_sheet_index = 0
	selected_row_index = 0
	visible_tab_start = 0
	_refresh_sheet_tabs()
	_refresh_sheet_view()
	status_label.text = "Detected %d sheet(s)." % sheets.size()

func _on_menu_pressed() -> void:
	get_tree().change_scene_to_file("res://intro_menu.tscn")

func _on_re_detect_pressed() -> void:
	if root and root.has_method("detect_all"):
		root.detect_all()
	else:
		status_label.text = "⚠️ Root missing detect_all()"

func _on_save_pressed() -> void:
	if sheets.is_empty():
		return
	var sheet = sheets[selected_sheet_index]
	if sheet.is_empty():
		return
	var rows = sheet["rows"]
	if selected_row_index < 0 or selected_row_index >= rows.size():
		status_label.text = "⚠️ No row selected"
		return
	var row_name = _get_row_name(selected_row_index)
	if row_name.strip_edges() == "":
		status_label.text = "⚠️ Name the row first"
		return
	var dir = DirAccess.open("res://")
	if dir and not dir.dir_exists("sprite_frames"):
		dir.make_dir("sprite_frames")
	var path = "res://sprite_frames/%s.tres" % row_name.strip_edges()
	if root.has_method("save_row_as_sprite_frames"):
		var err = root.save_row_as_sprite_frames(selected_sheet_index, selected_row_index, path)
		if err == OK:
			status_label.text = "✅ Saved: " + path
		else:
			status_label.text = "❌ Save failed: %s" % err
	else:
		status_label.text = "⚠️ Root missing save_row_as_sprite_frames"

func _on_export_all_pressed() -> void:
	if sheets.is_empty():
		status_label.text = "⚠️ No sheets detected"
		return
	
	var dir = DirAccess.open("res://")
	if dir and not dir.dir_exists("sprite_frames"):
		dir.make_dir("sprite_frames")
	
	var total_saved = 0
	var total_frames = 0
	var saved_names : Array = []
	var skipped : Array = []
	
	for i in range(sheets.size()):
		var sheet = sheets[i]
		if sheet.is_empty():
			continue
		var rows = sheet["rows"]
		if rows.is_empty():
			continue
		
		var named_rows : Array = []
		for r in range(rows.size()):
			var nm = _get_stored_name(i, r).strip_edges()
			if nm != "":
				named_rows.append({"row": r, "name": nm})
		
		if named_rows.is_empty():
			skipped.append("Sheet %d" % i)
			continue
		
		if named_rows.size() == 1:
			var row_name = named_rows[0]["name"]
			var path = "res://sprite_frames/%s.tres" % row_name
			if root.has_method("save_row_as_sprite_frames"):
				if rows.size() == 1:
					if root.save_row_as_sprite_frames(i, 0, path) == OK:
						total_saved += 1
						total_frames += rows[0].size()
						saved_names.append(row_name)
				else:
					if root.has_method("save_merged_rows_as_sprite_frames"):
						if root.save_merged_rows_as_sprite_frames(i, path) == OK:
							var frame_count = 0
							for row in rows:
								frame_count += row.size()
							total_saved += 1
							total_frames += frame_count
							saved_names.append(row_name)
					else:
						status_label.text = "⚠️ Root missing save_merged_rows_as_sprite_frames"
						return
			continue
		
		for entry in named_rows:
			var row_name = entry["name"]
			var r = entry["row"]
			var path = "res://sprite_frames/%s.tres" % row_name
			if root.has_method("save_row_as_sprite_frames"):
				if root.save_row_as_sprite_frames(i, r, path) == OK:
					total_saved += 1
					total_frames += rows[r].size()
					saved_names.append(row_name)
	
	_refresh_sheet_view()
	
	var msg = "✅ Exported %d files (%d frames): %s" % [total_saved, total_frames, ", ".join(saved_names)]
	if skipped.size() > 0:
		msg += "  |  Skipped: %s" % ", ".join(skipped)
	status_label.text = msg

func _on_play_all_pressed() -> void:
	if anim_playing:
		stop_animation()
		status_label.text = "⏹  Stopped"
		return
	if sheets.is_empty():
		return
	var sheet = sheets[selected_sheet_index]
	if sheet.is_empty():
		return
	var rows = sheet["rows"]
	if rows.is_empty():
		return
	
	var atlas : Texture2D = sheet["texture"]
	anim_frames.clear()
	
	for row in rows:
		for cell in row:
			var r : Rect2i = cell["rect"]
			var at := AtlasTexture.new()
			at.atlas = atlas
			at.region = Rect2(r.position, r.size)
			anim_frames.append(at)
	
	if anim_frames.is_empty():
		return
	
	anim_frame_index = 0
	anim_display.texture = anim_frames[0]
	anim_timer.wait_time = 0.12
	anim_timer.start()
	anim_playing = true
	status_label.text = "▶  Playing ALL rows merged: %d frames total" % anim_frames.size()

func _on_delete_pressed() -> void:
	if confirm_dialog:
		confirm_dialog.popup_centered()

func _on_delete_confirmed() -> void:
	var dir = DirAccess.open("res://sprite_frames")
	if dir == null:
		status_label.text = "⚠️ No sprite_frames folder found — nothing to delete"
		return
	
	var deleted = 0
	var failed = 0
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir():
			if file_name.ends_with(".tres"):
				var err = dir.remove(file_name)
				if err == OK:
					deleted += 1
				else:
					failed += 1
		file_name = dir.get_next()
	dir.list_dir_end()
	
	if failed > 0:
		status_label.text = "🗑  Deleted %d files (%d failed)" % [deleted, failed]
	else:
		status_label.text = "🗑  Deleted %d .tres files from sprite_frames/" % deleted

# =============================================================================
# 🖼 SHEET TABS
# =============================================================================
func _refresh_sheet_tabs() -> void:
	for c in sheet_buttons:
		if is_instance_valid(c):
			c.queue_free()
	sheet_buttons.clear()
	
	if sheets.size() <= MAX_VISIBLE_TABS:
		visible_tab_start = 0
	else:
		visible_tab_start = clampi(visible_tab_start, 0, sheets.size() - MAX_VISIBLE_TABS)
	
	var end_idx : int = min(visible_tab_start + MAX_VISIBLE_TABS, sheets.size())
	
	for i in range(visible_tab_start, end_idx):
		var b = _make_tab_button("Sheet %d" % i)
		var idx = i
		b.pressed.connect(func(): _select_sheet(idx))
		sheet_row.add_child(b)
		sheet_row.move_child(b, sheet_row.get_child_count() - 2)
		sheet_buttons.append(b)
	
	prev_tab_btn.visible = sheets.size() > MAX_VISIBLE_TABS
	next_tab_btn.visible = sheets.size() > MAX_VISIBLE_TABS
	prev_tab_btn.disabled = (visible_tab_start == 0)
	next_tab_btn.disabled = (visible_tab_start >= sheets.size() - MAX_VISIBLE_TABS)
	
	_refresh_sheet_tab_state()

func _on_prev_tab_pressed() -> void:
	if visible_tab_start > 0:
		visible_tab_start -= 1
		_refresh_sheet_tabs()

func _on_next_tab_pressed() -> void:
	if visible_tab_start < sheets.size() - MAX_VISIBLE_TABS:
		visible_tab_start += 1
		_refresh_sheet_tabs()

func _refresh_sheet_tab_state() -> void:
	for i in range(sheet_buttons.size()):
		var btn = sheet_buttons[i]
		var real_index : int = visible_tab_start + i
		if real_index == selected_sheet_index:
			btn.add_theme_stylebox_override("normal", _style(COL_ACCENT_DARK, COL_ACCENT, 2, 6))
			btn.add_theme_color_override("font_color", Color.WHITE)
		else:
			btn.add_theme_stylebox_override("normal", _style(COL_PANEL_ALT, COL_BORDER, 1, 6))
			btn.add_theme_color_override("font_color", COL_TEXT_DIM)

func _select_sheet(idx: int) -> void:
	selected_sheet_index = idx
	selected_row_index = 0
	if idx < visible_tab_start:
		visible_tab_start = idx
	elif idx >= visible_tab_start + MAX_VISIBLE_TABS:
		visible_tab_start = idx - MAX_VISIBLE_TABS + 1
	_refresh_sheet_tabs()
	_refresh_sheet_view()

# =============================================================================
# 🧠 SHEET VIEW
# =============================================================================
func _refresh_sheet_view() -> void:
	if sheets.is_empty():
		return
	var sheet = sheets[selected_sheet_index]
	if sheet.is_empty():
		preview_display.texture = null
		info_label.text = "Empty sheet"
		_clear_rows()
		return
	
	preview_display.texture = sheet["texture"]
	preview_overlay.queue_redraw()
	
	var size: Vector2i = sheet["sheet_size"]
	var cells: Array = sheet["cells"]
	var rows: Array = sheet["rows"]
	var avg: Vector2 = sheet["avg_cell_size"]
	
	info_label.text = (
		"[b]Sheet %d[/b]  [color=#8a8d99]·[/color]  %d × %d px  [color=#8a8d99]·[/color]  %d cells  [color=#8a8d99]·[/color]  %d rows  [color=#8a8d99]·[/color]  avg %.0f × %.0f" % [
			selected_sheet_index, size.x, size.y, cells.size(), rows.size(), avg.x, avg.y
		]
	)
	
	# ── Update detection toggle button colors based on this sheet's mode ──
	_update_detection_toggle_buttons()
	
	_clear_rows()
	row_name_inputs.clear()
	for i in range(rows.size()):
		var row = rows[i]
		var hbox = HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 8)
		hbox.custom_minimum_size = Vector2(0, 34)
		hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		var lbl = Label.new()
		lbl.text = "Row %d" % i
		lbl.custom_minimum_size = Vector2(52, 0)
		lbl.add_theme_color_override("font_color", COL_TEXT_DIM)
		lbl.add_theme_font_size_override("font_size", 12)
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		hbox.add_child(lbl)
		
		var count_lbl = Label.new()
		count_lbl.text = "%d" % row.size()
		count_lbl.custom_minimum_size = Vector2(22, 0)
		count_lbl.add_theme_color_override("font_color", COL_ACCENT)
		count_lbl.add_theme_font_size_override("font_size", 12)
		count_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		hbox.add_child(count_lbl)
		
		var input = LineEdit.new()
		input.placeholder_text = "name..."
		input.text = _get_stored_name(selected_sheet_index, i)
		input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		input.custom_minimum_size = Vector2(0, 30)
		input.add_theme_font_size_override("font_size", 12)
		input.add_theme_stylebox_override("normal", _style(COL_PANEL_ALT, COL_BORDER, 1, 4))
		input.add_theme_stylebox_override("focus", _style(COL_PANEL_ALT, COL_ACCENT, 1, 4))
		var sheet_idx = selected_sheet_index
		var row_idx = i
		input.text_changed.connect(func(txt): _store_row_name(sheet_idx, row_idx, txt))
		input.focus_entered.connect(func():
			selected_row_index = row_idx
			_refresh_overlay_highlight()
		)
		hbox.add_child(input)
		row_name_inputs.append(input)
		
		var play_btn = _make_button("▶", COL_ACCENT_DARK, false)
		play_btn.custom_minimum_size = Vector2(34, 30)
		play_btn.add_theme_font_size_override("font_size", 12)
		var sheet_idx_play = selected_sheet_index
		var row_idx_play = i
		play_btn.pressed.connect(func(): _play_row_preview(sheet_idx_play, row_idx_play))
		hbox.add_child(play_btn)
		
		rows_container.add_child(hbox)
# =============================================================================
# 🔍 UPDATE DETECTION TOGGLE BUTTON COLORS
# =============================================================================
func _update_detection_toggle_buttons() -> void:
	var toggle_row = root_control.get_node_or_null("DetectionToggleRow")
	if toggle_row == null:
		return
	var current_mode : int = _sheet_detection_modes.get(selected_sheet_index, 0)
	var grid_btn = toggle_row.get_node_or_null("GridBtn")
	var transp_btn = toggle_row.get_node_or_null("TranspBtn")
	
	if grid_btn:
		if current_mode == 0:
			grid_btn.add_theme_stylebox_override("normal", _style(COL_ACCENT_DARK, COL_ACCENT, 2, 6))
			grid_btn.add_theme_color_override("font_color", Color.WHITE)
		else:
			grid_btn.add_theme_stylebox_override("normal", _style(COL_PANEL_ALT, COL_BORDER, 1, 6))
			grid_btn.add_theme_color_override("font_color", COL_TEXT_DIM)
	
	if transp_btn:
		if current_mode == 1:
			transp_btn.add_theme_stylebox_override("normal", _style(COL_ACCENT_DARK, COL_ACCENT, 2, 6))
			transp_btn.add_theme_color_override("font_color", Color.WHITE)
		else:
			transp_btn.add_theme_stylebox_override("normal", _style(COL_PANEL_ALT, COL_BORDER, 1, 6))
			transp_btn.add_theme_color_override("font_color", COL_TEXT_DIM)


func _clear_rows() -> void:
	for c in rows_container.get_children():
		c.queue_free()

# =============================================================================
# 🔍 DETECTION MODE TOGGLE
# =============================================================================
func _set_sheet_detection_mode(mode: int) -> void:
	_sheet_detection_modes[selected_sheet_index] = mode
	
	if root == null:
		status_label.text = "⚠️ Root missing"
		return
	if not root.has_method("redetect_sheet_with_mode"):
		status_label.text = "⚠️ Root missing redetect_sheet_with_mode()"
		return
	
	var ok = root.redetect_sheet_with_mode(selected_sheet_index, mode)
	if ok:
		# Pull the updated sheet data back from root
		if "detected_sheets" in root:
			sheets = root.detected_sheets
		_refresh_sheet_view()
		var mode_label : String = "Grid" if mode == 0 else "Transparency"
		status_label.text = "🔍 Sheet %d re-detected with mode: %s" % [selected_sheet_index, mode_label]
	else:
		status_label.text = "❌ Re-detect failed for sheet %d" % selected_sheet_index

# =============================================================================
# 🎬 PLAY ANIMATION
# =============================================================================
func _play_row_preview(sheet_idx: int, row_idx: int) -> void:
	if sheets.is_empty():
		return
	if sheet_idx < 0 or sheet_idx >= sheets.size():
		return
	var sheet = sheets[sheet_idx]
	if sheet.is_empty():
		return
	var rows = sheet["rows"]
	if row_idx < 0 or row_idx >= rows.size():
		return
	
	var atlas : Texture2D = sheet["texture"]
	var cells : Array = rows[row_idx]
	anim_frames.clear()
	for cell in cells:
		var r : Rect2i = cell["rect"]
		var at := AtlasTexture.new()
		at.atlas = atlas
		at.region = Rect2(r.position, r.size)
		anim_frames.append(at)
	
	if anim_frames.is_empty():
		return
	
	anim_frame_index = 0
	anim_display.texture = anim_frames[0]
	anim_timer.wait_time = 0.12
	anim_timer.start()
	anim_playing = true
	
	var name_str = _get_stored_name(sheet_idx, row_idx)
	if name_str.strip_edges() == "":
		name_str = "Row %d" % row_idx
	status_label.text = "▶  Playing: %s  (%d frames)" % [name_str, anim_frames.size()]

func _on_anim_tick() -> void:
	if anim_frames.is_empty():
		return
	anim_frame_index = (anim_frame_index + 1) % anim_frames.size()
	anim_display.texture = anim_frames[anim_frame_index]

func stop_animation() -> void:
	anim_timer.stop()
	anim_playing = false
	anim_display.texture = null

# =============================================================================
# 🏷 ROW NAMES
# =============================================================================
var _row_names : Dictionary = {}

func _store_row_name(sheet_idx: int, row_idx: int, name: String) -> void:
	_row_names["%d:%d" % [sheet_idx, row_idx]] = name

func _get_stored_name(sheet_idx: int, row_idx: int) -> String:
	var key = "%d:%d" % [sheet_idx, row_idx]
	return _row_names.get(key, "")

func _get_row_name(row_idx: int) -> String:
	return _get_stored_name(selected_sheet_index, row_idx)

# =============================================================================
# 🎨 DEBUG OVERLAY
# =============================================================================
func _draw_overlay() -> void:
	if sheets.is_empty():
		return
	var sheet = sheets[selected_sheet_index]
	if sheet.is_empty():
		return
	if preview_display.texture == null:
		return
	var disp_size = preview_display.size
	var tex_size: Vector2i = sheet["sheet_size"]
	var ts = Vector2(tex_size)
	if ts.x <= 0 or ts.y <= 0:
		return
	var scale = min(disp_size.x / ts.x, disp_size.y / ts.y)
	var displayed = ts * scale
	var offset = (disp_size - displayed) * 0.5
	for cell in sheet["cells"]:
		var r: Rect2i = cell["rect"]
		var conf: float = cell["confidence"]
		var color := Color(0.30, 0.90, 0.45, 0.85)
		if conf < 0.8:
			color = Color(1.0, 0.85, 0.30, 0.85)
		if conf < 0.5:
			color = Color(1.0, 0.35, 0.35, 0.85)
		var rect := Rect2(
			offset + Vector2(r.position) * scale,
			Vector2(r.size) * scale
		)
		preview_overlay.draw_rect(rect, color, false, 1.5)
	var rows = sheet["rows"]
	if selected_row_index >= 0 and selected_row_index < rows.size():
		var row = rows[selected_row_index]
		if row.size() > 0:
			var first: Rect2i = row[0]["rect"]
			var last: Rect2i = row[row.size() - 1]["rect"]
			var min_x = first.position.x
			var max_x = last.position.x + last.size.x
			var min_y = first.position.y
			var max_y = last.position.y + last.size.y
			var rect := Rect2(
				offset + Vector2(min_x, min_y) * scale,
				Vector2(max_x - min_x, max_y - min_y) * scale
			)
			preview_overlay.draw_rect(rect, Color(0.35, 0.65, 1.0, 1.0), false, 2.5)

func _refresh_overlay_highlight() -> void:
	preview_overlay.queue_redraw()

# =============================================================================
# 🎨 HELPERS
# =============================================================================
func _style(bg: Color, border: Color, border_w: int, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(radius)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s

func _make_button(text: String, color: Color, wide: bool = false) -> Button:
	var btn := Button.new()
	btn.text = text
	# ✅ FIXED: GDScript ternary (was `180 if wide else 80`)
	var min_width : int = 180 if wide else 80
	btn.custom_minimum_size = Vector2(min_width, 40)
	btn.add_theme_font_size_override("font_size", 13)
	btn.add_theme_color_override("font_color", Color.WHITE)
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(6)
	style.set_border_width_all(1)
	style.border_color = color.lightened(0.2)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	btn.add_theme_stylebox_override("normal", style)
	var hover := style.duplicate()
	hover.bg_color = color.lightened(0.15)
	btn.add_theme_stylebox_override("hover", hover)
	var pressed := style.duplicate()
	pressed.bg_color = color.darkened(0.25)
	btn.add_theme_stylebox_override("pressed", pressed)
	return btn

func _make_tab_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(90, 30)
	btn.add_theme_font_size_override("font_size", 12)
	btn.add_theme_color_override("font_color", COL_TEXT_DIM)
	btn.add_theme_stylebox_override("normal", _style(COL_PANEL_ALT, COL_BORDER, 1, 6))
	btn.add_theme_stylebox_override("hover", _style(COL_PANEL_ALT.lightened(0.1), COL_ACCENT_DARK, 1, 6))
	return btn
