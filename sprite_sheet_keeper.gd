extends Control

# =============================================================================
# 🎬 SPRITE SHEET KEEPER — ROOT
# =============================================================================

# =============================================================================
# 📤 EXPORTS
# =============================================================================
@export_group("Inputs")
@export var sprite_sheets : Array[Texture2D] = []
@export var detection_mode : int = 0
# 0 = GRID (default)
# 1 = TRANSPARENCY

@export var transparency_alpha_cutoff : float = 0.5
@export var merge_close_distance : int = 4
@export var waist_min_pixels : int = 2
@export_group("UI")
@export var ui_canvas_layer : CanvasLayer
@export var animation_preview : AnimatedSprite2D

# 0 = GRID (default, current behavior)
# 1 = TRANSPARENCY (extract non-uniform sprites)
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
	
	# ---- 🆕 TRANSPARENCY MODE ----
	# Extract sprites by connected non-transparent regions instead of grid.
	# Handles sheets with irregular spacing, mixed sizes, and touching sprites.
	if detection_mode == 1:
		print("🔍 Using TRANSPARENCY mode on sheet ", sheet_size)
		
		var t_blocks := _detect_by_transparency(image, bg_color)
		
		# Merge blobs that are parts of the same sprite
		if merge_close_distance > 0 and t_blocks.size() > 1:
			t_blocks = _merge_close_rects(t_blocks, merge_close_distance)
		
		# Filter tiny blocks (noise pixels, stray dots, etc.)
		var t_filtered := []
		for cell in t_blocks:
			var r: Rect2i = cell["rect"]
			if r.size.x >= min_cell_size and r.size.y >= min_cell_size:
				t_filtered.append(cell)
		
		# ── Keep only the largest row of cells ──
		# Kills stragglers the merger couldn't reconnect. Ideal for
		# single-row animation sheets like Kaia's 1280x64.
		if t_filtered.size() > 1:
			t_filtered = _keep_dominant_row(t_filtered)
		
		# ── 🆕 Rebuild a clean, centered sheet ──
		# Instead of trying to align rects in the original sheet (which can
		# jitter due to misaligned source art), build a brand-new image where
		# every sprite is centered in its own uniform cell.
		if t_filtered.size() > 1:
			var rebuild := _rebuild_centered_sheet(t_filtered, image, bg_color)
			var new_image : Image = rebuild["image"]
			var new_tex := ImageTexture.create_from_image(new_image)
			sheet_data["texture"] = new_tex
			sheet_data["image"] = new_image
			sheet_data["sheet_size"] = Vector2i(new_image.get_width(), new_image.get_height())
			t_filtered = rebuild["cells"]
		
		sheet_data["cells"] = t_filtered
		sheet_data["rows"] = _group_cells_by_row(t_filtered)
		sheet_data["avg_cell_size"] = _compute_avg_cell_size(t_filtered)
		
		_last_debug_image = sheet_data["image"]
		_last_debug_sheet_index = detected_sheets.size()
		
		if debug_enabled:
			_print_sheet_debug(sheet_data)
		
		return sheet_data
	# ------------------------------
	
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

# =============================================================================
# 📐 NORMALIZE CELL SIZES
# =============================================================================
# Resizes every cell rect to the same dimensions, centered on the sprite's
# original content. Prevents animation jitter from mismatched frame sizes.
# Cells are clamped to the sheet bounds — no out-of-bounds sampling.
# =============================================================================
# 📐 NORMALIZE + CENTER CELLS ON CONTENT
# =============================================================================
# Sizes every cell to the same dimensions AND recenters each sprite so its
# content centroid aligns with the cell's center. Fixes left/right jitter
# caused by frames where the sprite is drawn off-center.
func _normalize_cell_sizes(cells: Array, image: Image, bg: Color) -> Array:
	if cells.is_empty():
		return cells
	
	var bg_is_opaque : bool = bg.a >= 0.5
	
	# ── Pass 1: find max content width and height across all cells ──
	var max_w : int = 0
	var max_h : int = 0
	for cell in cells:
		var r : Rect2i = cell["rect"]
		var content := _find_content_bounds(image, r, bg, bg_is_opaque)
		if content.size.x > max_w: max_w = content.size.x
		if content.size.y > max_h: max_h = content.size.y
	
	# Padding so sprites never touch the cell edge
	max_w += 4
	max_h += 4
	
	var sheet_w : int = image.get_width()
	var sheet_h : int = image.get_height()
	
	# ── Pass 2: build normalized cells with content centered ──
	var normalized : Array = []
	for cell in cells:
		var r : Rect2i = cell["rect"]
		var content := _find_content_bounds(image, r, bg, bg_is_opaque)
		
		# Center of the sprite's actual content
		var cx : int = content.position.x + content.size.x / 2
		var cy : int = content.position.y + content.size.y / 2
		
		# Shift the new cell so its center aligns with the content center
		var new_x : int = cx - max_w / 2
		var new_y : int = cy - max_h / 2
		
		# Clamp so we stay inside the sheet (no sampling outside)
		new_x = clampi(new_x, 0, max(0, sheet_w - max_w))
		new_y = clampi(new_y, 0, max(0, sheet_h - max_h))
		
		normalized.append({
			"rect": Rect2i(new_x, new_y, max_w, max_h),
			"confidence": cell["confidence"],
			"reason": cell["reason"] + "_centered"
		})
	
	print("📐 Normalized + centered ", cells.size(), " cells to ", max_w, "x", max_h)
	return normalized


# Finds the tight bounding box of non-transparent content within a rect.
# Used to compute the actual visual center of a sprite (ignoring padding
# inside the cell that the flood fill may have included).

# Finds the tight bounding box of non-transparent content within a rect.
# Used to compute the actual visual center of a sprite (ignoring padding
# inside the cell that the flood fill may have included).
func _find_content_bounds(image: Image, r: Rect2i, bg: Color, bg_is_opaque: bool) -> Rect2i:
	var min_x : int = r.position.x + r.size.x
	var max_x : int = r.position.x
	var min_y : int = r.position.y + r.size.y
	var max_y : int = r.position.y
	
	var w := image.get_width()
	var h := image.get_height()
	
	for cy in range(r.position.y, r.position.y + r.size.y):
		if cy < 0 or cy >= h:
			continue
		for cx in range(r.position.x, r.position.x + r.size.x):
			if cx < 0 or cx >= w:
				continue
			var px := image.get_pixel(cx, cy)
			var ok : bool = px.a > transparency_alpha_cutoff
			if ok and bg_is_opaque:
				ok = not _colors_close(px, bg, bg_tolerance)
			if ok:
				if cx < min_x: min_x = cx
				if cx > max_x: max_x = cx
				if cy < min_y: min_y = cy
				if cy > max_y: max_y = cy
	
	if min_x > max_x or min_y > max_y:
		return r
	
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)


# =============================================================================
# ⚓ FIND ANCHOR POINT (weighted by pixel density)
# =============================================================================
# Computes a stable anchor point for a sprite by finding the horizontal row
# with the most pixels, and using the center of that row as the X anchor.
# Robust against asymmetric silhouettes (like a swinging antenna).
func _find_anchor_point(image: Image, r: Rect2i, bg: Color, bg_is_opaque: bool) -> Vector2i:
	var w := image.get_width()
	var h := image.get_height()
	
	var row_counts := PackedInt32Array()
	row_counts.resize(r.size.y)
	var row_min_x := PackedInt32Array()
	var row_max_x := PackedInt32Array()
	row_min_x.resize(r.size.y)
	row_max_x.resize(r.size.y)
	for i in range(r.size.y):
		row_min_x[i] = 1_000_000
		row_max_x[i] = -1_000_000
	
	for cy in range(r.size.y):
		var src_y : int = r.position.y + cy
		if src_y < 0 or src_y >= h:
			continue
		var count := 0
		for cx in range(r.size.x):
			var src_x : int = r.position.x + cx
			if src_x < 0 or src_x >= w:
				continue
			var px := image.get_pixel(src_x, src_y)
			var ok : bool = px.a > transparency_alpha_cutoff
			if ok and bg_is_opaque:
				ok = not _colors_close(px, bg, bg_tolerance)
			if ok:
				count += 1
				if src_x < row_min_x[cy]: row_min_x[cy] = src_x
				if src_x > row_max_x[cy]: row_max_x[cy] = src_x
		row_counts[cy] = count
	
	var best_row : int = 0
	var best_count : int = 0
	for cy in range(r.size.y):
		if row_counts[cy] > best_count:
			best_count = row_counts[cy]
			best_row = cy
	
	var anchor_x : int = (row_min_x[best_row] + row_max_x[best_row]) / 2
	if row_min_x[best_row] > row_max_x[best_row]:
		anchor_x = r.position.x + r.size.x / 2
	
	var dense_top : int = best_row
	var dense_bot : int = best_row
	var threshold : int = best_count / 2
	for cy in range(best_row, -1, -1):
		if row_counts[cy] < threshold:
			break
		dense_top = cy
	for cy in range(best_row, r.size.y):
		if row_counts[cy] < threshold:
			break
		dense_bot = cy
	var anchor_y : int = r.position.y + (dense_top + dense_bot) / 2
	
	return Vector2i(anchor_x, anchor_y)

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


# =============================================================================
# 🔄 RE-DETECT SINGLE SHEET WITH A SPECIFIC MODE
# =============================================================================
# Called by the UI when the user toggles Grid/Transparency on a sheet.
# Doesn't touch the other sheets — only re-detects the one requested.
func redetect_sheet_with_mode(sheet_index: int, mode: int) -> bool:
	if sheet_index < 0 or sheet_index >= sprite_sheets.size():
		return false
	var tex : Texture2D = sprite_sheets[sheet_index]
	if tex == null:
		return false
	
	# Remember the old mode, temporarily force the requested one,
	# re-detect this sheet, then restore the old mode.
	var old_mode : int = detection_mode
	detection_mode = mode
	
	var data : Dictionary = detect_sheet(tex)
	
	detection_mode = old_mode
	
	# Only commit if detection actually returned something
	if data.is_empty():
		return false
	
	# Preserve the index slot
	while detected_sheets.size() <= sheet_index:
		detected_sheets.append({})
	detected_sheets[sheet_index] = data
	
	# Redraw the debug overlay in case it's showing this sheet
	_last_debug_image = data.get("image", null)
	_last_debug_sheet_index = sheet_index
	queue_redraw()
	
	return true


# =============================================================================
# 🔍 TRANSPARENCY MODE — EXTRACT NON-UNIFORM SPRITES
# =============================================================================
# Finds every connected region of non-transparent pixels. Uses a 4-connected
# flood fill (BFS) so no recursion depth issues on large sheets.
# Returns an array of {rect, confidence, reason} dictionaries, same shape
# as the grid detector, so downstream code doesn't care which mode produced it.
func _detect_by_transparency(image: Image, bg: Color) -> Array:
	var w := image.get_width()
	var h := image.get_height()
	
	# ---- 1. Build a boolean "content" map ----
	# A pixel is content if it's opaque enough AND not close to the bg color
	# (when the bg is opaque). If bg is transparent, any opaque pixel counts.
	var is_content := PackedByteArray()
	is_content.resize(w * h)
	
	var bg_is_opaque : bool = bg.a >= 0.5
	
	for y in range(h):
		var row_base := y * w
		for x in range(w):
			var px := image.get_pixel(x, y)
			var ok : bool = px.a > transparency_alpha_cutoff
			if ok and bg_is_opaque:
				ok = not _colors_close(px, bg, bg_tolerance)
			is_content[row_base + x] = 1 if ok else 0
	
	# ---- 2. Flood fill to find connected components ----
	var visited := PackedByteArray()
	visited.resize(w * h)
	
	var rects : Array = []
	
	for y in range(h):
		var row_base := y * w
		for x in range(w):
			var seed_idx := row_base + x
			if is_content[seed_idx] == 0 or visited[seed_idx] == 1:
				continue
			
			# BFS from this seed — expand to the full connected blob
			var min_x := x
			var max_x := x
			var min_y := y
			var max_y := y
			
			var stack : Array = [Vector2i(x, y)]
			visited[seed_idx] = 1
			
			while stack.size() > 0:
				var p : Vector2i = stack.pop_back()
				if p.x < min_x: min_x = p.x
				if p.x > max_x: max_x = p.x
				if p.y < min_y: min_y = p.y
				if p.y > max_y: max_y = p.y
				
				var px_idx := p.y * w + p.x
				
				# 4-connected neighbors
				# (up)
				if p.y > 0:
					var ni := px_idx - w
					if is_content[ni] == 1 and visited[ni] == 0:
						visited[ni] = 1
						stack.append(Vector2i(p.x, p.y - 1))
				# (down)
				if p.y < h - 1:
					var ni := px_idx + w
					if is_content[ni] == 1 and visited[ni] == 0:
						visited[ni] = 1
						stack.append(Vector2i(p.x, p.y + 1))
				# (left)
				if p.x > 0:
					var ni := px_idx - 1
					if is_content[ni] == 1 and visited[ni] == 0:
						visited[ni] = 1
						stack.append(Vector2i(p.x - 1, p.y))
				# (right)
				if p.x < w - 1:
					var ni := px_idx + 1
					if is_content[ni] == 1 and visited[ni] == 0:
						visited[ni] = 1
						stack.append(Vector2i(p.x + 1, p.y))
			
			var rw : int = max_x - min_x + 1
			var rh : int = max_y - min_y + 1
			
			# Skip tiny blobs (noise, single stray pixels, etc.)
			if rw < min_cell_size or rh < min_cell_size:
				continue
			
			rects.append({
				"rect": Rect2i(min_x, min_y, rw, rh),
				"confidence": 1.0,
				"reason": "transparency"
			})
	
	print("🔍 Transparency: ", rects.size(), " raw blobs from ", w, "x", h, " sheet")
	return rects


# =============================================================================
# 🔗 MERGE CLOSE RECTS
# =============================================================================
# Reconnects blobs that are parts of the same sprite. For example: a character's
# head and body with a 2-pixel transparent gap between them. Anything within
# max_gap pixels on both axes gets merged into one bounding box.
#
# Runs iteratively until no more merges happen — one pass can create new
# merge opportunities with a third rect that now overlaps.
func _merge_close_rects(rects: Array, max_gap: int) -> Array:
	if rects.size() < 2:
		return rects
	
	var merged_any := true
	while merged_any:
		merged_any = false
		var result : Array = []
		var consumed := []
		consumed.resize(rects.size())
		for i in range(rects.size()):
			consumed[i] = false
		
		for i in range(rects.size()):
			if consumed[i]:
				continue
			
			var a_rect : Rect2i = rects[i]["rect"]
			var a_conf : float = rects[i]["confidence"]
			
			# Try to merge all later rects into `a` if they're close
			for j in range(i + 1, rects.size()):
				if consumed[j]:
					continue
				var b_rect : Rect2i = rects[j]["rect"]
				if _rects_close(a_rect, b_rect, max_gap):
					a_rect = a_rect.merge(b_rect)
					a_conf = min(a_conf, rects[j]["confidence"])
					consumed[j] = true
					merged_any = true
			
			consumed[i] = true
			result.append({
				"rect": a_rect,
				"confidence": a_conf,
				"reason": "merged"
			})
		
		rects = result
	
	print("🔗 After merge: ", rects.size(), " blobs")
	return rects


# =============================================================================
# 🔗 RECT PROXIMITY CHECK
# =============================================================================
# Returns true if `a` and `b` are within `max_gap` pixels of each other
# on BOTH the X and Y axes. Distance is measured edge-to-edge, not
# center-to-center, so overlapping or touching rects are always "close".

func _rects_close(a: Rect2i, b: Rect2i, max_gap: int) -> bool:
	# Horizontal overlap check: how much of the two rects share X range
	var x_overlap : int = min(a.end.x, b.end.x) - max(a.position.x, b.position.x)
	# Vertical overlap check
	var y_overlap : int = min(a.end.y, b.end.y) - max(a.position.y, b.position.y)
	
	# Horizontal gap: positive = space between them, negative = overlapping
	var x_gap : int = max(0, max(a.position.x - b.end.x, b.position.x - a.end.x))
	var y_gap : int = max(0, max(a.position.y - b.end.y, b.position.y - a.end.y))
	
	# Two rects are "close" if EITHER:
	#   1. They're horizontally close AND overlap or nearly overlap on Y
	#   2. They're vertically close AND overlap or nearly overlap on X
	# This means "same row / same column" merging, not diagonal chaos.
	
	# Case 1: side by side (horizontally close, vertically aligned)
	if x_gap <= max_gap and y_overlap >= -max_gap:
		return true
	
	# Case 2: stacked (vertically close, horizontally aligned)
	if y_gap <= max_gap and x_overlap >= -max_gap:
		return true
	
	return false


# =============================================================================
# ✂️ SPLIT AT WAIST
# =============================================================================
# Splits blobs that are actually TWO sprites touching at a thin seam.
# Example: two characters standing shoulder to shoulder, connected by a
# few pixels of their arms meeting. The bounding box would merge them into
# one blob. This function finds the "waist" — the thin columns where content
# count drops to just a few pixels — and cuts there.
#
# Only splits horizontally (left/right). Vertical waist splitting isn't
# implemented because two sprites rarely touch top-to-bottom in the same
# way — you'd usually want them separate for other reasons anyway.
func _split_at_waist(rects: Array, image: Image, bg: Color) -> Array:
	var result : Array = []
	
	for cell in rects:
		var r : Rect2i = cell["rect"]
		var sub_rects := _find_waist_splits(r, image, bg)
		
		if sub_rects.size() > 1:
			# Blob was split — add each piece with slightly lower confidence
			for s in sub_rects:
				result.append({
					"rect": s,
					"confidence": cell["confidence"] * 0.9,
					"reason": "waist_split"
				})
		else:
			# No split — keep original blob
			result.append(cell)
	
	print("✂️ After waist split: ", result.size(), " blobs")
	return result


# =============================================================================
# ✂️ FIND WAIST SPLITS
# =============================================================================
# Given one bounding box, walks column by column and counts how many content
# pixels are in that column. Columns with very few content pixels (< waist_min_pixels)
# are "seams" where two sprites touch. Splits the box at each contiguous
# run of thin columns.

func _find_waist_splits(r: Rect2i, image: Image, bg: Color) -> Array:
	var w := image.get_width()
	var h := image.get_height()
	var bg_is_opaque : bool = bg.a >= 0.5
	
	var col_counts := PackedInt32Array()
	col_counts.resize(r.size.x)
	for cx in range(r.size.x):
		var count := 0
		for cy in range(r.size.y):
			var px_x := r.position.x + cx
			var px_y := r.position.y + cy
			if px_x < 0 or px_x >= w or px_y < 0 or px_y >= h:
				continue
			var px := image.get_pixel(px_x, px_y)
			var ok : bool = px.a > transparency_alpha_cutoff
			if ok and bg_is_opaque:
				ok = not _colors_close(px, bg, bg_tolerance)
			if ok:
				count += 1
		col_counts[cx] = count
	
	var row_counts := PackedInt32Array()
	row_counts.resize(r.size.y)
	for cy in range(r.size.y):
		var count := 0
		for cx in range(r.size.x):
			var px_x := r.position.x + cx
			var px_y := r.position.y + cy
			if px_x < 0 or px_x >= w or px_y < 0 or px_y >= h:
				continue
			var px := image.get_pixel(px_x, px_y)
			var ok : bool = px.a > transparency_alpha_cutoff
			if ok and bg_is_opaque:
				ok = not _colors_close(px, bg, bg_tolerance)
			if ok:
				count += 1
		row_counts[cy] = count
	
	# ---- DEBUG: dump the counts so we can see what's happening ----
	print("━━━ WAIST SCAN for rect ", r, " ━━━")
	print("  col_counts (first 40): ", _sample_counts(col_counts, 40))
	print("  row_counts (first 40): ", _sample_counts(row_counts, 40))
	
	var col_splits : Array = _find_real_waists(col_counts, r.position.x, "COL")
	var row_splits : Array = _find_real_waists(row_counts, r.position.y, "ROW")
	
	print("  col_splits=", col_splits, " row_splits=", row_splits)
	
	if col_splits.is_empty() and row_splits.is_empty():
		return [r]
	
	var col_pieces : Array = []
	var prev_x : int = r.position.x
	var right_edge : int = r.position.x + r.size.x
	for split_x in col_splits:
		if split_x > prev_x:
			var sw : int = split_x - prev_x
			if sw >= min_cell_size:
				col_pieces.append(Rect2i(prev_x, r.position.y, sw, r.size.y))
		prev_x = split_x + 1
	if prev_x < right_edge:
		var sw : int = right_edge - prev_x
		if sw >= min_cell_size:
			col_pieces.append(Rect2i(prev_x, r.position.y, sw, r.size.y))
	
	if col_pieces.is_empty():
		col_pieces = [r]
	
	var sub_rects : Array = []
	for piece in col_pieces:
		var prev_y : int = piece.position.y
		var bottom_edge : int = piece.position.y + piece.size.y
		for split_y in row_splits:
			if split_y <= piece.position.y or split_y >= bottom_edge:
				continue
			if split_y > prev_y:
				var sh : int = split_y - prev_y
				if sh >= min_cell_size:
					sub_rects.append(Rect2i(piece.position.x, prev_y, piece.size.x, sh))
			prev_y = split_y + 1
		if prev_y < bottom_edge:
			var sh : int = bottom_edge - prev_y
			if sh >= min_cell_size:
				sub_rects.append(Rect2i(piece.position.x, prev_y, piece.size.x, sh))
	
	if sub_rects.is_empty():
		return [r]
	return sub_rects


# Helper: dump a sample of a PackedInt32Array for debugging
func _sample_counts(arr: PackedInt32Array, n: int) -> Array:
	var out : Array = []
	var limit : int = min(n, arr.size())
	for i in range(limit):
		out.append(arr[i])
	return out


func _find_real_waists(counts: PackedInt32Array, offset: int, tag: String) -> Array:
	if counts.size() < 5:
		return []
	
	var nonzero : Array = []
	for c in counts:
		if c > 0:
			nonzero.append(c)
	if nonzero.size() == 0:
		return []
	nonzero.sort()
	var reference : int = nonzero[nonzero.size() / 2]
	var thick_threshold : int = int(reference * 0.6)
	
	print("  [", tag, "] reference=", reference, " thick=", thick_threshold, " waist_max=", waist_min_pixels)
	
	var candidates : Array = []
	for i in range(counts.size()):
		if counts[i] > waist_min_pixels:
			continue
		
		var has_left : bool = false
		var has_right : bool = false
		for k in range(1, 3):
			if i - k >= 0 and counts[i - k] >= thick_threshold:
				has_left = true
				break
		for k in range(1, 3):
			if i + k < counts.size() and counts[i + k] >= thick_threshold:
				has_right = true
				break
		
		if has_left and has_right:
			candidates.append(i)
			print("  [", tag, "] candidate at local idx=", i, " (global=", offset + i, ") count=", counts[i])
	
	var splits : Array = []
	var i := 0
	while i < candidates.size():
		var start : int = candidates[i]
		var end : int = start
		while i + 1 < candidates.size() and candidates[i + 1] == candidates[i] + 1:
			i += 1
			end = candidates[i]
		var run_width : int = end - start + 1
		
		if run_width <= 2:
			var mid : int = (start + end) / 2
			splits.append(offset + mid)
			print("  [", tag, "] ACCEPTED split at ", offset + mid, " (run width ", run_width, ")")
		else:
			print("  [", tag, "] REJECTED run at ", offset + start, " (width ", run_width, " too wide)")
		
		i += 1
	
	return splits

# =============================================================================
# 🎯 KEEP DOMINANT ROW
# =============================================================================
# For single-row animation sheets, keeps only the largest detected row and
# discards stragglers that got mis-grouped into other rows. Useful when a
# merge step can't reconnect every stray piece to its parent sprite.
#
# Safety: only fires if the dominant row is at least 3x the size of the
# second-biggest row. That prevents this from accidentally dropping a real
# second row of animations (like on a 1280x128 double-row sheet).
func _keep_dominant_row(cells: Array) -> Array:
	if cells.size() < 2:
		return cells
	
	# Group cells into rows using the existing row-grouping logic
	var rows := _group_cells_by_row(cells)
	if rows.size() <= 1:
		return cells
	
	# Find the biggest row
	var biggest : Array = rows[0]
	var biggest_idx : int = 0
	for i in range(rows.size()):
		var row = rows[i]
		if row.size() > biggest.size():
			biggest = row
			biggest_idx = i
	
	# Find the second-biggest row size
	var second_size : int = 0
	for i in range(rows.size()):
		if i == biggest_idx:
			continue
		var row = rows[i]
		if row.size() > second_size:
			second_size = row.size()
	
	# Only keep dominant row if it's clearly bigger (3x safety margin)
	if biggest.size() >= second_size * 3:
		print("🎯 Kept dominant row (", biggest.size(), " cells), discarded ",
			cells.size() - biggest.size(), " stragglers from ", rows.size() - 1, " other row(s)")
		return biggest
	
	return cells


# =============================================================================
# 🔨 REBUILD CENTERED SHEET
# =============================================================================
# Takes the detected sprite rects, extracts each sprite's actual pixels, and
# writes them into a brand-new image where every sprite is centered in a
# uniform cell. Fixes jitter caused by misaligned source art.
#
# Returns a dictionary: { "image": Image, "cells": Array, "cell_size": Vector2i }
# =============================================================================
# 🔨 REBUILD CENTERED SHEET
# =============================================================================
# Takes detected sprite rects, extracts each sprite's pixels, and writes them
# into a brand-new image where every sprite is anchored at the SAME relative
# position within its cell. The anchor is the sprite's body center (the row
# with the most pixels), which is stable across asymmetric frames.
func _rebuild_centered_sheet(cells: Array, source: Image, bg: Color) -> Dictionary:
	if cells.is_empty():
		return {"image": source, "cells": cells, "cell_size": Vector2i.ZERO}
	
	var bg_is_opaque : bool = bg.a >= 0.5
	var w := source.get_width()
	var h := source.get_height()
	
	# ── Pass 1: find max extent from anchor in each direction ──
	var max_extent_left : int = 0
	var max_extent_right : int = 0
	var max_extent_up : int = 0
	var max_extent_down : int = 0
	
	for cell in cells:
		var r : Rect2i = cell["rect"]
		var content := _find_content_bounds(source, r, bg, bg_is_opaque)
		var anchor := _find_anchor_point(source, r, bg, bg_is_opaque)
		var left : int = anchor.x - content.position.x
		var right : int = (content.position.x + content.size.x) - anchor.x
		var up : int = anchor.y - content.position.y
		var down : int = (content.position.y + content.size.y) - anchor.y
		if left > max_extent_left: max_extent_left = left
		if right > max_extent_right: max_extent_right = right
		if up > max_extent_up: max_extent_up = up
		if down > max_extent_down: max_extent_down = down
	
	max_extent_left += 2
	max_extent_right += 2
	max_extent_up += 2
	max_extent_down += 2
	
	var cell_w : int = max_extent_left + max_extent_right
	var cell_h : int = max_extent_up + max_extent_down
	var anchor_local_x : int = max_extent_left
	var anchor_local_y : int = max_extent_up
	
	# ── Pass 2: build new image ──
	var count := cells.size()
	var new_img := Image.create(cell_w * count, cell_h, false, Image.FORMAT_RGBA8)
	new_img.fill(Color(0, 0, 0, 0))
	
	var new_cells : Array = []
	
	for i in range(count):
		var r : Rect2i = cells[i]["rect"]
		var content := _find_content_bounds(source, r, bg, bg_is_opaque)
		var anchor := _find_anchor_point(source, r, bg, bg_is_opaque)
		
		var dst_x_base : int = i * cell_w
		var dst_y_base : int = 0
		
		var dst_anchor_x : int = dst_x_base + anchor_local_x
		var dst_anchor_y : int = dst_y_base + anchor_local_y
		
		var offset_x : int = dst_anchor_x - anchor.x
		var offset_y : int = dst_anchor_y - anchor.y
		
		for cy in range(content.size.y):
			var src_y : int = content.position.y + cy
			if src_y < 0 or src_y >= h:
				continue
			var dst_y : int = src_y + offset_y
			if dst_y < 0 or dst_y >= cell_h:
				continue
			for cx in range(content.size.x):
				var src_x : int = content.position.x + cx
				if src_x < 0 or src_x >= w:
					continue
				var dst_x : int = src_x + offset_x
				if dst_x < 0 or dst_x >= cell_w * count:
					continue
				var px := source.get_pixel(src_x, src_y)
				if px.a > 0:
					new_img.set_pixel(dst_x, dst_y, px)
		
		new_cells.append({
			"rect": Rect2i(dst_x_base, dst_y_base, cell_w, cell_h),
			"confidence": cells[i]["confidence"],
			"reason": "rebuilt_anchored"
		})
	
	print("🔨 Rebuilt sheet (anchored): ", count, " cells of ", cell_w, "x", cell_h,
		" → new image ", new_img.get_width(), "x", new_img.get_height())
	
	return {
		"image": new_img,
		"cells": new_cells,
		"cell_size": Vector2i(cell_w, cell_h)
	}
