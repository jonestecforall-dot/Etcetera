extends Control

# =============================================================================
# 🎬 SPRITE SHEET KEEPER — ROOT
# =============================================================================

# =============================================================================
# 📤 EXPORTS
# =============================================================================
@export_group("Inputs")
@export var sprite_sheets : Array[Texture2D] = []

@export_group("UI")
@export var ui_canvas_layer : CanvasLayer
@export var animation_preview : AnimatedSprite2D

@export_group("Detection")
@export var min_cell_size : int = 2
@export var padding : int = 1
@export var auto_detect_bg : bool = true
@export var explicit_bg_color : Color = Color.BLACK
@export var bg_tolerance : float = 0.05

@export_group("Bridge Detection")
@export var bridge_threshold_ratio : float = 0.15
@export var bridge_min_pixels : int = 1
@export var bridge_neighbor_ratio : float = 0.4

@export_group("Span Split")
@export var split_row_spanning_cells : bool = true
@export var split_column_spanning_cells : bool = true
@export var span_tolerance : float = 0.3   # cell is oversize if > median * (1 + tol)

@export_group("Grid Fallback")
@export var force_grid_mode : bool = false
@export var grid_rows : int = 1
@export var grid_cols : int = 1

@export_group("Debug")
@export var debug_enabled : bool = false
@export var debug_density_profiles : bool = false
@export var draw_debug_overlay : bool = true
@export var debug_rect_line_width : float = 1.0

# =============================================================================
# 🧠 DETECTED DATA
# =============================================================================
var detected_sheets : Array = []

var _last_debug_image : Image = null
var _last_debug_sheet_index : int = -1

# =============================================================================
# 🚀 PUBLIC API
# =============================================================================
func detect_all() -> void:
	detected_sheets.clear()
	_last_debug_image = null
	_last_debug_sheet_index = -1
	
	for tex in sprite_sheets:
		if tex == null:
			detected_sheets.append({})
			continue
		var sheet_data = detect_sheet(tex)
		detected_sheets.append(sheet_data)
	
	if debug_enabled:
		_print_summary()
	
	if ui_canvas_layer and ui_canvas_layer.has_method("on_sheets_detected"):
		ui_canvas_layer.on_sheets_detected(detected_sheets)
	
	queue_redraw()


func detect_sheet(texture: Texture2D) -> Dictionary:
	var image := texture.get_image()
	if image == null:
		push_warning("SpriteSheetKeeper: texture has no image: " + texture.resource_path)
		return {}
	
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	
	var sheet_size := Vector2i(image.get_width(), image.get_height())
	var bg_color := _detect_background_color(image) if auto_detect_bg else explicit_bg_color
	
	var sheet_data := {
		"texture": texture,
		"image": image,
		"sheet_size": sheet_size,
		"bg_color": bg_color,
		"cells": [],
		"rows": [],
		"avg_cell_size": Vector2.ZERO
	}
	
	if force_grid_mode:
		sheet_data["cells"] = _detect_grid(image, grid_rows, grid_cols)
		sheet_data["rows"] = _group_cells_by_row(sheet_data["cells"])
		sheet_data["avg_cell_size"] = _compute_avg_cell_size(sheet_data["cells"])
		_last_debug_image = image
		_last_debug_sheet_index = detected_sheets.size()
		return sheet_data
	
	var blocks := _find_non_empty_blocks(image, bg_color)
	
	# Filter tiny blocks
	var filtered := []
	for cell in blocks:
		var rect: Rect2i = cell["rect"]
		if rect.size.x >= min_cell_size and rect.size.y >= min_cell_size:
			filtered.append(cell)
	
	# ---- FINAL PASS 1: split cells that span multiple rows ----
	if split_row_spanning_cells and filtered.size() > 1:
		filtered = _split_row_spanning_cells(filtered)
	
	# ---- FINAL PASS 2: split cells that span multiple columns ----
	if split_column_spanning_cells and filtered.size() > 1:
		filtered = _split_column_spanning_cells(filtered)
	
	sheet_data["cells"] = filtered
	sheet_data["rows"] = _group_cells_by_row(filtered)
	sheet_data["avg_cell_size"] = _compute_avg_cell_size(filtered)
	
	_last_debug_image = image
	_last_debug_sheet_index = detected_sheets.size()
	
	if debug_enabled:
		_print_sheet_debug(sheet_data)
	
	return sheet_data


func play_preview(sheet_index: int, row_index: int, anim_name: String = "") -> void:
	if animation_preview == null:
		push_warning("SpriteSheetKeeper: no animation_preview assigned")
		return
	if sheet_index < 0 or sheet_index >= detected_sheets.size():
		return
	var sheet = detected_sheets[sheet_index]
	if sheet.is_empty():
		return
	var rows = sheet["rows"]
	if row_index < 0 or row_index >= rows.size():
		return
	var sf := _build_sprite_frames_for_row(sheet, rows[row_index], anim_name, sheet_index, row_index)
	if sf == null:
		return
	animation_preview.sprite_frames = sf
	var anims = sf.get_animation_names()
	if anims.size() > 0:
		animation_preview.play(anims[0])


func save_row_as_sprite_frames(sheet_index: int, row_index: int, path: String) -> int:
	if sheet_index < 0 or sheet_index >= detected_sheets.size():
		return FAILED
	var sheet = detected_sheets[sheet_index]
	if sheet.is_empty():
		return FAILED
	var rows = sheet["rows"]
	if row_index < 0 or row_index >= rows.size():
		return FAILED
	var anim_name = "anim_%d_%d" % [sheet_index, row_index]
	var sf := _build_sprite_frames_for_row(sheet, rows[row_index], anim_name, sheet_index, row_index)
	if sf == null:
		return FAILED
	return ResourceSaver.save(sf, path)


# =============================================================================
# 🖼 BACKGROUND DETECTION
# =============================================================================
func _detect_background_color(image: Image) -> Color:
	var w := image.get_width()
	var h := image.get_height()
	var corners := [
		image.get_pixel(0, 0),
		image.get_pixel(w - 1, 0),
		image.get_pixel(0, h - 1),
		image.get_pixel(w - 1, h - 1),
	]
	for c in corners:
		if c.a < 0.5:
			return Color(0, 0, 0, 0)
	var best : Color = corners[0]
	var best_score : int = -1
	for c in corners:
		var score : int = 0
		for d in corners:
			if c.is_equal_approx(d):
				score += 1
			elif _colors_close(c, d, bg_tolerance):
				score += 1
		if score > best_score:
			best_score = score
			best = c
	return best


func _is_empty_pixel(pixel: Color, bg: Color, tol: float) -> bool:
	if pixel.a < 0.5:
		return true
	return _colors_close(pixel, bg, tol)


func _colors_close(a: Color, b: Color, tol: float) -> bool:
	return (
		abs(a.r - b.r) <= tol and
		abs(a.g - b.g) <= tol and
		abs(a.b - b.b) <= tol and
		abs(a.a - b.a) <= tol
	)


# =============================================================================
# 🔍 DETECTION
# =============================================================================

func _find_non_empty_blocks(image: Image, bg: Color) -> Array:
	var w := image.get_width()
	var h := image.get_height()
	
	# ---- Compute content count per Y row ----
	var row_counts := PackedInt32Array()
	row_counts.resize(h)
	for y in range(h):
		var count := 0
		for x in range(w):
			if not _is_empty_pixel(image.get_pixel(x, y), bg, bg_tolerance):
				count += 1
		row_counts[y] = count
	
	# ---- Find max content count for reference ----
	var max_count : int = 0
	for c in row_counts:
		if c > max_count:
			max_count = c
	
	# A row is "sparse" if its content is less than 15% of the max
	var sparse_threshold : int = max(1, int(float(max_count) * 0.15))
	
	# ---- Content runs = contiguous Y rows with content above sparse threshold ----
	var content_runs : Array = []
	var in_content := false
	var run_start : int = 0
	for y in range(h):
		var is_content := row_counts[y] > sparse_threshold
		if is_content and not in_content:
			in_content = true
			run_start = y
		elif not is_content and in_content:
			in_content = false
			content_runs.append(Vector2i(run_start, y - 1))
	if in_content:
		content_runs.append(Vector2i(run_start, h - 1))
	
	# ---- Debug ----
	print("📊 Sheet ", w, "x", h, " | max_count=", max_count, " | sparse_threshold=", sparse_threshold, " | content_runs=", content_runs.size())
	print("   content_runs: ", content_runs)
	
	if content_runs.size() == 0:
		return []
	
	# ---- Merge content runs separated by small gaps ----
	var gap_sizes : Array = []
	for i in range(1, content_runs.size()):
		var gap_between : int = content_runs[i].x - content_runs[i - 1].y - 1
		gap_sizes.append(gap_between)
	gap_sizes.sort()
	
	var merge_threshold : int = 1
	if gap_sizes.size() >= 4:
		var top_half_start : int = gap_sizes.size() / 2
		var top_sum : int = 0
		var top_count : int = 0
		for i in range(top_half_start, gap_sizes.size()):
			top_sum += gap_sizes[i]
			top_count += 1
		var top_avg : int = int(float(top_sum) / float(top_count))
		merge_threshold = max(1, int(float(top_avg) * 0.5))
	elif gap_sizes.size() > 0:
		var mid : int = gap_sizes[gap_sizes.size() / 2]
		merge_threshold = max(1, int(float(mid) * 0.5))
	
	var merged_runs : Array = []
	for run in content_runs:
		if merged_runs.is_empty():
			merged_runs.append(run)
		else:
			var last : Vector2i = merged_runs[merged_runs.size() - 1]
			var gap_between : int = run.x - last.y - 1
			if gap_between < merge_threshold:
				merged_runs[merged_runs.size() - 1] = Vector2i(last.x, run.y)
			else:
				merged_runs.append(run)
	
	var row_runs := merged_runs
	var total_rows : int = row_runs.size()
	
	if total_rows == 0:
		return []
	
	# ---- Compute frame height ----
	var frame_height : int = int(round(float(h) / float(total_rows)))
	if frame_height < 1:
		frame_height = 1
	
	var expected_y_ranges : Array = []
	for i in range(total_rows):
		var y0 : int = i * frame_height
		var y1 : int = min(y0 + frame_height - 1, h - 1)
		expected_y_ranges.append(Vector2i(y0, y1))
	
	print("   → after merge: ", total_rows, " rows, frame_height=", frame_height)
	
	# ---- Column scan on first row band ----
	var y0_first : int = expected_y_ranges[0].x
	var y1_first : int = expected_y_ranges[0].y
	
	var col_has := PackedByteArray()
	col_has.resize(w)
	for x in range(w):
		var found := false
		for y in range(y0_first, y1_first + 1):
			if not _is_empty_pixel(image.get_pixel(x, y), bg, bg_tolerance):
				found = true
				break
		col_has[x] = 1 if found else 0
	
	var col_runs_raw := _find_runs(col_has)
	
	# ---- Adaptive column merge (threshold minimum = 1) ----
	var col_gap_sizes : Array = []
	for i in range(1, col_runs_raw.size()):
		var gap_between : int = col_runs_raw[i].x - col_runs_raw[i - 1].y - 1
		col_gap_sizes.append(gap_between)
	col_gap_sizes.sort()
	
	var col_merge_threshold : int = 1
	if col_gap_sizes.size() >= 4:
		var top_half_start : int = col_gap_sizes.size() / 2
		var top_sum : int = 0
		var top_count : int = 0
		for i in range(top_half_start, col_gap_sizes.size()):
			top_sum += col_gap_sizes[i]
			top_count += 1
		var top_avg : int = int(float(top_sum) / float(top_count))
		col_merge_threshold = max(1, int(float(top_avg) * 0.6))
	elif col_gap_sizes.size() > 0:
		var mid : int = col_gap_sizes[col_gap_sizes.size() / 2]
		col_merge_threshold = max(1, int(float(mid) * 0.6))
	
	var col_runs : Array = []
	for run in col_runs_raw:
		if col_runs.is_empty():
			col_runs.append(run)
		else:
			var last : Vector2i = col_runs[col_runs.size() - 1]
			var gap_between : int = run.x - last.y - 1
			if gap_between < col_merge_threshold:
				col_runs[col_runs.size() - 1] = Vector2i(last.x, run.y)
			else:
				col_runs.append(run)
	
	print("📊 Columns | col_runs_raw=", col_runs_raw.size(), " | col_gaps=", col_gap_sizes, " | col_merge_threshold=", col_merge_threshold)
	print("   → after merge: ", col_runs.size(), " column runs")
	
	var blocks := []
	
	if col_runs.size() >= 2:
		var min_stride : int = 999999
		for i in range(1, col_runs.size()):
			var stride : int = col_runs[i].x - col_runs[i - 1].x
			if stride > 0 and stride < min_stride:
				min_stride = stride
		
		if min_stride == 999999 or min_stride < min_cell_size:
			min_stride = col_runs[0].y - col_runs[0].x + 1
		
		var first_sprite_start : int = col_runs[0].x
		var usable_w : int = w - first_sprite_start
		var total_cols : int = max(1, int(round(float(usable_w) / float(min_stride))))
		
		var sprite_width : int = int(round(float(usable_w) / float(total_cols)))
		if sprite_width < 1:
			sprite_width = min_stride
		
		print("   → min_stride=", min_stride, " total_cols=", total_cols, " sprite_width=", sprite_width)
		
		for band in expected_y_ranges:
			var by0 : int = band.x
			var by1 : int = band.y
			for c in range(total_cols):
				var bx0 : int = first_sprite_start + c * sprite_width
				var bx1 : int = min(bx0 + sprite_width - 1, w - 1)
				if bx0 >= w:
					break
				var rect := Rect2i(bx0, by0, bx1 - bx0 + 1, by1 - by0 + 1)
				blocks.append({
					"rect": rect,
					"confidence": 1.0,
					"reason": "template"
				})
	else:
		for band in expected_y_ranges:
			for col_run in col_runs:
				var rect := Rect2i(col_run.x, band.x, col_run.y - col_run.x + 1, band.y - band.x + 1)
				blocks.append({
					"rect": rect,
					"confidence": 0.8,
					"reason": "fallback"
				})
	
	return blocks
# =============================================================================
# ✂️ FINAL PASS: SPLIT ROW-SPANNING CELLS
# =============================================================================
func _split_row_spanning_cells(cells: Array) -> Array:
	if cells.size() < 2:
		return cells
	
	var heights : Array = []
	for c in cells:
		heights.append(c["rect"].size.y)
	heights.sort()
	var median_h : int = heights[heights.size() / 2]
	if median_h < 1:
		median_h = 1
	
	var threshold : float = float(median_h) * (1.0 + span_tolerance)
	
	var splits_to_make : Array = []
	for i in range(cells.size()):
		var r : Rect2i = cells[i]["rect"]
		if float(r.size.y) > threshold:
			var n : int = int(round(float(r.size.y) / float(median_h)))
			if n < 2:
				n = 2
			splits_to_make.append({"index": i, "parts": n})
	
	if splits_to_make.is_empty():
		return cells
	
	var result : Array = []
	var split_map : Dictionary = {}
	for s in splits_to_make:
		split_map[s["index"]] = s["parts"]
	
	for i in range(cells.size()):
		if not split_map.has(i):
			result.append(cells[i])
			continue
		
		var r : Rect2i = cells[i]["rect"]
		var parts : int = split_map[i]
		var part_h : int = int(round(float(r.size.y) / float(parts)))
		
		for p in range(parts):
			var py : int = r.position.y + p * part_h
			var ph : int = part_h
			if py + ph > r.position.y + r.size.y:
				ph = r.position.y + r.size.y - py
			if ph < min_cell_size:
				continue
			result.append({
				"rect": Rect2i(r.position.x, py, r.size.x, ph),
				"confidence": cells[i]["confidence"],
				"reason": "row_split"
			})
	
	return result


# =============================================================================
# ✂️ FINAL PASS: SPLIT COLUMN-SPANNING CELLS
# =============================================================================
func _split_column_spanning_cells(cells: Array) -> Array:
	if cells.size() < 2:
		return cells
	
	var widths : Array = []
	for c in cells:
		widths.append(c["rect"].size.x)
	widths.sort()
	var median_w : int = widths[widths.size() / 2]
	if median_w < 1:
		median_w = 1
	
	var threshold : float = float(median_w) * (1.0 + span_tolerance)
	
	var splits_to_make : Array = []
	for i in range(cells.size()):
		var r : Rect2i = cells[i]["rect"]
		if float(r.size.x) > threshold:
			var n : int = int(round(float(r.size.x) / float(median_w)))
			if n < 2:
				n = 2
			splits_to_make.append({"index": i, "parts": n})
	
	if splits_to_make.is_empty():
		return cells
	
	var result : Array = []
	var split_map : Dictionary = {}
	for s in splits_to_make:
		split_map[s["index"]] = s["parts"]
	
	for i in range(cells.size()):
		if not split_map.has(i):
			result.append(cells[i])
			continue
		
		var r : Rect2i = cells[i]["rect"]
		var parts : int = split_map[i]
		var part_w : int = int(round(float(r.size.x) / float(parts)))
		
		for p in range(parts):
			var px : int = r.position.x + p * part_w
			var pw : int = part_w
			if px + pw > r.position.x + r.size.x:
				pw = r.position.x + r.size.x - px
			if pw < min_cell_size:
				continue
			result.append({
				"rect": Rect2i(px, r.position.y, pw, r.size.y),
				"confidence": cells[i]["confidence"],
				"reason": "col_split"
			})
	
	return result


func _find_runs(flags: PackedByteArray) -> Array:
	var runs := []
	var start := -1
	for i in range(flags.size()):
		if flags[i] == 1 and start == -1:
			start = i
		elif flags[i] == 0 and start != -1:
			runs.append(Vector2i(start, i - 1))
			start = -1
	if start != -1:
		runs.append(Vector2i(start, flags.size() - 1))
	return runs


# =============================================================================
# 🔲 GRID MODE
# =============================================================================
func _detect_grid(image: Image, rows: int, cols: int) -> Array:
	if rows <= 0 or cols <= 0:
		return []
	var w := image.get_width()
	var h := image.get_height()
	var cw := w / cols
	var ch := h / rows
	var cells := []
	for r in range(rows):
		for c in range(cols):
			cells.append({
				"rect": Rect2i(c * cw, r * ch, cw, ch),
				"confidence": 1.0,
				"reason": "grid"
			})
	return cells


# =============================================================================
# 📊 HELPERS
# =============================================================================
func _group_cells_by_row(cells: Array) -> Array:
	if cells.is_empty():
		return []
	var sorted : Array = cells.duplicate()
	sorted.sort_custom(func(a, b):
		if a["rect"].position.y == b["rect"].position.y:
			return a["rect"].position.x < b["rect"].position.x
		return a["rect"].position.y < b["rect"].position.y
	)
	var avg_h : float = 0.0
	for c in sorted:
		avg_h += float(c["rect"].size.y)
	avg_h /= float(sorted.size())
	var tolerance : float = max(8.0, avg_h * 0.5)
	var rows : Array = []
	var current_row : Array = []
	var current_y : float = -999999.0
	for cell in sorted:
		var y : float = float(cell["rect"].position.y)
		if current_row.size() > 0 and abs(y - current_y) > tolerance:
			rows.append(current_row)
			current_row = []
		current_row.append(cell)
		current_y = y
	if current_row.size() > 0:
		rows.append(current_row)
	return rows


func _compute_avg_cell_size(cells: Array) -> Vector2:
	if cells.is_empty():
		return Vector2.ZERO
	var total := Vector2.ZERO
	for cell in cells:
		var r: Rect2i = cell["rect"]
		total.x += r.size.x
		total.y += r.size.y
	return total / float(cells.size())


# =============================================================================
# 🧱 SPRITE FRAMES BUILDER
# =============================================================================
func _build_sprite_frames_for_row(sheet: Dictionary, row_cells: Array, anim_name: String = "", sheet_index: int = 0, row_index: int = 0) -> SpriteFrames:
	if row_cells.is_empty():
		return null
	var atlas_tex : Texture2D = sheet["texture"]
	var sf := SpriteFrames.new()
	if sf.has_animation("default"):
		sf.remove_animation("default")
	var final_name = anim_name
	if final_name.strip_edges() == "":
		final_name = "anim_%d_%d" % [sheet_index, row_index]
	sf.add_animation(final_name)
	sf.set_animation_loop(final_name, true)
	sf.set_animation_speed(final_name, 10.0)
	for cell in row_cells:
		var r: Rect2i = cell["rect"]
		var at := AtlasTexture.new()
		at.atlas = atlas_tex
		at.region = Rect2(r.position, r.size)
		sf.add_frame(final_name, at)
	return sf


# =============================================================================
# 🐞 DEBUG
# =============================================================================
func _print_summary() -> void:
	print("═══════════════════════════════════════════")
	print("🎬 SpriteSheetKeeper — Summary")
	print("  Sheets: ", detected_sheets.size())
	for i in range(detected_sheets.size()):
		var s = detected_sheets[i]
		if s.is_empty():
			continue
		print("  [", i, "] size=", s["sheet_size"], " cells=", s["cells"].size(), " rows=", s["rows"].size())
	print("═══════════════════════════════════════════")


func _print_sheet_debug(sheet: Dictionary) -> void:
	print("──── Sheet ", sheet["sheet_size"], " ────")
	print("  bg=", sheet["bg_color"], " cells=", sheet["cells"].size(), " rows=", sheet["rows"].size())
	for i in range(sheet["rows"].size()):
		var row = sheet["rows"][i]
		print("  Row ", i, ": ", row.size(), " cells")


# =============================================================================
# 🎨 DEBUG OVERLAY
# =============================================================================
func _draw() -> void:
	if not debug_enabled or not draw_debug_overlay:
		return
	if _last_debug_image == null or _last_debug_sheet_index < 0:
		return
	if _last_debug_sheet_index >= detected_sheets.size():
		return
	var sheet = detected_sheets[_last_debug_sheet_index]
	if sheet.is_empty():
		return
	for cell in sheet["cells"]:
		var r: Rect2i = cell["rect"]
		var conf: float = cell["confidence"]
		var color := Color(0, 1, 0, 0.9)
		if conf < 0.8:
			color = Color(1, 1, 0, 0.9)
		if conf < 0.5:
			color = Color(1, 0.3, 0.3, 0.9)
		var rect := Rect2(Vector2(r.position), Vector2(r.size))
		draw_rect(rect, color, false, debug_rect_line_width)


func save_merged_rows_as_sprite_frames(sheet_index: int, path: String) -> int:
	if sheet_index < 0 or sheet_index >= detected_sheets.size():
		return FAILED
	var sheet = detected_sheets[sheet_index]
	if sheet.is_empty():
		return FAILED
	var rows = sheet["rows"]
	if rows.is_empty():
		return FAILED
	
	var atlas_tex : Texture2D = sheet["texture"]
	
	var sf := SpriteFrames.new()
	if sf.has_animation("default"):
		sf.remove_animation("default")
	
	var anim_name = path.get_file().get_basename()
	sf.add_animation(anim_name)
	sf.set_animation_loop(anim_name, true)
	sf.set_animation_speed(anim_name, 10.0)
	
	# Merge every cell from every row into one animation
	for row in rows:
		for cell in row:
			var r : Rect2i = cell["rect"]
			var at := AtlasTexture.new()
			at.atlas = atlas_tex
			at.region = Rect2(r.position, r.size)
			sf.add_frame(anim_name, at)
	
	return ResourceSaver.save(sf, path)
