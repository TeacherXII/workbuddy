class_name InputManager
extends Node

# ASHEN STEP — Sprint 0 vertical slice (Phase 5).
# L2 minimal input: focus (凝神) hold + gait (步态) toggle.
#
# Input is REAL-TIME (InputEvent), unaffected by Engine.time_scale (ADR-003):
# focus hold / release and gait toggle are read live so slow-mo never delays
# the player's read-and-plan loop. The actual action bindings (ui_focus,
# toggle_gait) are registered in Part 2 (main scene / input setup); this
# contract also exposes a remap hook aligned with accessibility-matrix 行14.

var gait := "SNEAK"   # SNEAK | WALK  (RUN reserved for Tier2)

const FOCUS_ACTION := "ui_focus"          # remappable via InputMap
const GAIT_ACTION := "toggle_gait"        # remappable via InputMap


func is_focus_held() -> bool:
	# Default focus = ui_focus action OR mouse right button (per spec).
	return Input.is_action_pressed(FOCUS_ACTION) \
		or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)


func toggle_gait() -> void:
	if gait == "SNEAK":
		gait = "WALK"
	else:
		gait = "SNEAK"


# --- Remapping hook (accessibility-matrix 行14): read/write via InputMap ---
func is_action_remappable(action: String) -> bool:
	return InputMap.has_action(action)


func remap_action(action: String, event: InputEvent) -> void:
	if not InputMap.has_action(action):
		return
	InputMap.action_erase_events(action)
	InputMap.action_add_event(action, event)
