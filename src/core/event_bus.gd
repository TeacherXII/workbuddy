class_name EventBus
extends Node

# ASHEN STEP — Sprint 1, E01-S9. Event vocabulary reconciliation against
# design/gdd/system-breakdown.md §2. After this change the bus exposes the full
# 13-signal / shared-type vocabulary from §2. See docs/sprint1-batchA-impl.md
# §E01-S9 for the drift list and the two INTENTIONALLY-DEFERRED gaps
# (decoy_landed / interactable_triggered param shapes -> Batch D, E06-S4 / E09-S4).

# --- Shared vocabulary enums (system-breakdown §2.3) ---
# LightState: a light is LIT or EXTINGUISHED (cover-shadow §4).
enum LightState { LIT, EXTINGUISHED }
# SusTier: suspicion band carried by suspicion_changed (E08-S2, thresholds 25/60/10).
# Contract (sprint1-stories §4 E01-S9) specifies CALM|SUSPICIOUS|ALERT|SEARCH.
# §2.3 已改为 CALM，已与 system-breakdown §2.3 对齐（CALM|SUSPICIOUS|ALERT|SEARCH）。
enum SusTier { CALM, SUSPICIOUS, ALERT, SEARCH }

# --- 2.1 Upstream / infrastructure events (L2 / engine) ---
signal time_scale_changed(old: float, new: float, mode: String)
signal guard_transform_dirty(guard_id: int)
signal light_state_changed(light_id: int, state: LightState)
signal cover_state_changed(cell: Vector3i)

# --- 2.2 Gameplay-layer events (L4 / L3) ---
signal player_step_committed(payload: Dictionary)
# NOTE: Sprint 0 shape retained (§2 wants DecoyPayload{pos,surface,radius});
# realigned by E06-S4 in Batch D. Kept as-is to avoid touching Sprint 0 emitters.
signal decoy_landed(pos: Vector3)
signal sound_emitted(payload: Dictionary)
signal vision_stimulus(guard_id: int, target: Node, visibility: float)
signal vision_looming(guard_id: int)
signal suspicion_changed(guard_id: int, value: float, tier: SusTier)
signal guard_fsm_changed(guard_id: int, old: String, new: String)
signal exposure_detected(guard_id: int, target: Node)
# NOTE: Sprint 0 shape retained (§2 wants obj_id,type,payload); realigned by
# E09-S4 in Batch D. Kept as-is to avoid touching Sprint 0 emitters.
signal interactable_triggered(id: int, kind: String)


func _ready() -> void:
	# Registered so any node can grab the bus via group query:
	#   get_tree().get_first_node_in_group("event_bus")
	add_to_group("event_bus")
