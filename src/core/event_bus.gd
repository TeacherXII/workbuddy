class_name EventBus
extends Node

# ASHEN STEP — Sprint 1, E01-S9. Event vocabulary reconciliation against
# design/gdd/system-breakdown.md §2. After this change the bus exposes the full
# 13-signal / shared-type vocabulary from §2. See docs/sprint1-batchA-impl.md
# §E01-S9 for the drift list.
# decoy_landed was closed in Batch D (E06-S4, D11-A) — see below.
# interactable_triggered was closed in Batch C (D8) — see below.
#
# [Sprint 2, Batch A — SAV-S2 / FLAG-I RESOLVED] E01-S9 was re-opened for ONE
# round to land the three SaveManager persistence events registered by D16 in
# §2.1 (save_completed / load_completed / checkpoint_restored). The vocabulary is
# now 16 signals and the bus returns to its frozen state. `guard_spawned` (§2.2)
# stays UNDECLARED until Sprint 3 — it rides on the slipped E08 variant work.

# --- Shared vocabulary enums (system-breakdown §2.3) ---
# LightState: a light is LIT or EXTINGUISHED (cover-shadow §4).
enum LightState { LIT, EXTINGUISHED }
# SusTier: suspicion band carried by suspicion_changed (E08-S2, thresholds 25/60/10).
# Contract (sprint1-stories §4 E01-S9) specifies CALM|SUSPICIOUS|ALERT|SEARCH.
# §2.3 已改为 CALM，已与 system-breakdown §2.3 对齐（CALM|SUSPICIOUS|ALERT|SEARCH）。
enum SusTier { CALM, SUSPICIOUS, ALERT, SEARCH }
# GuardState [D6, Batch C]: the AI behaviour FSM value domain, hoisted to L2 so
# it is the SINGLE authority for guard_fsm_changed. L3 (GuardBrain) references
# EventBus.GuardState.* and MUST NOT declare a second copy — duplicate enums
# drift. Ordinals are the wire values and match the locked mapping
# PATROL=CALM=0 / INVESTIGATE=SUSPICIOUS=1 / ALERT=2 (batchc-impl-spec §2.2).
# NOTE: GuardState (5 members, behaviour) != SusTier (4 members, HUD band).
enum GuardState { CALM = 0, SUSPICIOUS = 1, ALERT = 2, SEARCH = 3, RETURN = 4 }
# InteractableType [D8, Batch C]: members locked by interactables §3.
enum InteractableType { DECOY, LIGHT_TOGGLE, TRAP, SMOKE }

# --- 2.1 Upstream / infrastructure events (L2 / engine) ---
signal time_scale_changed(old: float, new: float, mode: String)
signal guard_transform_dirty(guard_id: int)
signal light_state_changed(light_id: int, state: LightState)
signal cover_state_changed(cell: Vector3i)
# [E01-S9 re-opened & closed in Sprint 2 Batch A / SAV-S2, FLAG-I RESOLVED]
# The three SaveManager (L2) persistence events. Registered in
# system-breakdown.md §2.1 by D16; DECLARED here so the vocabulary is
# zero-drift across ① event_bus.gd ② §2.1 ③ the @ci:event-vocab-zero-drift lint.
# Parameter names + types are byte-identical to §2.1 — do not "improve" them.
# ⚠ These are LIFECYCLE/persistence events, NOT stealth stimuli: ④/⑤/⑥ must not
#   consume save_completed / load_completed. `checkpoint_restored` is the ONLY
#   one a gameplay layer (⑥) subscribes to (world reset after a soft fail).
# ⚠ NO DEFAULT PARAMETERS — same N-8 rule as decoy_landed above.
# Sole production emitter: SaveManager (src/core/save_manager.gd).
signal save_completed(slot_id: int, success: bool)
signal load_completed(slot_id: int, success: bool)
signal checkpoint_restored(checkpoint_id: String)

# --- 2.2 Gameplay-layer events (L4 / L3) ---
# NOTE: `guard_spawned` is registered in §2.2 but is a Sprint 3 item (it rides on
# E08 guard variants / GuardVariant, which slipped). It is deliberately NOT
# declared here — sprint2-stories.md §2 SAV-S2: "本 Sprint 不声明，不得顺手加入".
signal player_step_committed(payload: Dictionary)
## E06-S4 (Batch D). DecoyPayload per system-breakdown §2 L51.
## `surface` is a String key into StepCommit.SURFACE_FACTOR /
## FootfallVFX.FOOTFALL_SUBTITLE ("STONE"/"GRASS"/"METAL"/"MOSS"/"WOOD").
## The doc-level type name `Surface` has NO GDScript counterpart — String is the
## codebase-wide convention (step_commit.gd:57, footfall_vfx.gd:32).  [M-1]
## `radius` is METRES; nominal value SoundPropagator.DECOY_RADIUS (8.0).
## [D11-A] `surface` drives foley/subtitle variant ONLY — it does NOT modulate radius.
## ⚠ NO DEFAULT PARAMETERS: GDScript does not apply signal default values on emit();
##   a short emit() raises "Error calling from signal" at runtime, which GUT's
##   variadic signal watcher will NOT surface as a test failure. See N-8.
##   Contract shape is locked by test_event_bus.gd::test_decoy_landed_signature_contract.
signal decoy_landed(pos: Vector3, surface: String, radius: float)
signal sound_emitted(payload: Dictionary)
signal vision_stimulus(guard_id: int, target: Node, visibility: float)
signal vision_looming(guard_id: int)
signal suspicion_changed(guard_id: int, value: float, tier: SusTier)
# [D6, Batch C] Realigned from (old: String, new: String) to the int enum, so
# the wire format matches system-breakdown §2.2 exactly (drift eliminated).
# Sole production emitter: GuardBrain._set_fsm (src/game/patrol_ai.gd).
signal guard_fsm_changed(guard_id: int, old: GuardState, new: GuardState)
signal exposure_detected(guard_id: int, target: Node)
# [D8, Batch C] Sprint 0 shape (id:int, kind:String) CLOSED here — E09-S4 was
# pulled forward from Batch D, so the signature is realigned to §2.2 now rather
# than drifting twice. payload minimal shape: {"charges": int}.
signal interactable_triggered(obj_id: int, type: InteractableType, payload: Dictionary)


func _ready() -> void:
	# Registered so any node can grab the bus via group query:
	#   get_tree().get_first_node_in_group("event_bus")
	add_to_group("event_bus")
