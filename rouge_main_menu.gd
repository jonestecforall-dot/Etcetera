extends Control

@export var static_background: Control
@export var rec_panel: Control

# 👇 Reference to the pause menu (kept for potential future use)
@export var pause_menu: Control

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	if static_background:
		static_background.set_anchors_preset(Control.PRESET_FULL_RECT)
		print("Static background node is ready: ", static_background.name)
	else:
		print("Warning: No static background node assigned in the inspector!")

	if rec_panel:
		print("REC panel node is ready: ", rec_panel.name)
	else:
		print("Warning: No REC panel node assigned in the inspector!")

	# No signal connections here anymore — the pause menu handles its own
	# visibility, and hiding the pause menu wrapper doesn't affect Main.
	# Main stays visible during gameplay; the pause menu just draws on top.
