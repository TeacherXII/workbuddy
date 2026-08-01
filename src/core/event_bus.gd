class_name EventBus
extends Node

# ASHEN STEP — Sprint 0 vertical slice (Phase 5).
# L2 Event Bus. Declares the shared cross-GDD event vocabulary from
# design/gdd/system-breakdown.md §2 so every system emits/connects only
# these declared signals (anti-drift; aligns E01-S1 / consistency-review §1.3).
#
# Parameter shapes mirror the §2 vocabulary:
#   - time_scale_changed(old, new, mode)   mode: TimeMode FLOWING|FOCUS|PAUSED
#   - *payload signals carry Dictionary (StepCommitPayload / SoundPayload)
#   - target params are Node references (player / guard / interactable)

# --- 2.1 Upstream / infrastructure events (L2 / engine) ---
signal time_scale_changed(old: float, new: float, mode: String)
signal light_state_changed(point: Vector3, level: float)

# --- 2.2 Gameplay-layer events (L4 / L3) ---
signal player_step_committed(payload: Dictionary)
signal sound_emitted(payload: Dictionary)
signal vision_stimulus(guard_id: int, target: Node, visibility: float)
signal suspicion_changed(guard_id: int, value: float)
signal exposure_detected(guard_id: int, target: Node)
signal interactable_triggered(id: int, kind: String)
signal decoy_landed(pos: Vector3)


func _ready() -> void:
	# Registered so any node can grab the bus via group query:
	#   get_tree().get_first_node_in_group("event_bus")
	add_to_group("event_bus")
