class_name CheckpointProducer
extends Node

# ASHEN STEP — Phase 6, D1. Checkpoint write-end coordinator (L4).
#
# Story: D1 "自动检查点触发" — close the WRITE half of the checkpoint loop.
#
# Single responsibility: collect the §② seven-field world snapshot and hand it
# to SaveManager.write_slot(CHECKPOINT_SLOT_ID, data). This node is the ONLY
# place that builds that dict, so SaveManager (L2) stays a pure function and
# never reaches back into L3/L4 (architecture.md §2 one-way dependency — exactly
# the discipline restore_checkpoint() already obeys by publishing restored_state
# instead of touching GuardBrain/HUD).
#
# Three trigger sources all converge on produce():
#   1. CheckpointVolume.body_entered  -> the GDD §2 diegetic trigger (final).
#   2. EventBus.interactable_triggered (LIGHT_TOGGLE/DECOY success) — an interim
#      "safe progress" trigger.
#   3. EventBus.guard_fsm_changed(new==RETURN) — "escaped pursuit" trigger.
#
# Frequency is bounded by SaveManager's own 0.5s CHECKPOINT_WRITE_COOLDOWN
# (write_slot throttles; extra calls report success=false and are ignored by the
# world). See _on_guard_fsm_changed for the soft-fail suppression rule, which is
# NOT a frequency concern but a CORRECTNESS one.
#
# Headless-safe: no rendering, no scene-tree requirement beyond group lookups.
# Tests construct it with explicit collaborators and drive produce() directly.

const SaveManagerScript = preload("res://src/core/save_manager.gd")
const EventBus = preload("res://src/core/event_bus.gd")
const GuardSpawner = preload("res://src/game/guard_spawner.gd")
const LightModel = preload("res://src/game/light_model.gd")
const InteractableRegistry = preload("res://src/game/interactables/interactable_registry.gd")


# ── Level-owned collaborators (wired by the level / sprint0_bootstrap) ───────
# Each may be null; produce() simply omits that slice of the snapshot. A real
# level wires all four so the checkpoint captures the full world diff state.
var guard_spawner: GuardSpawner = null
var light_model: LightModel = null
var interactable_registry: InteractableRegistry = null
var player_node: Node3D = null

# The two interim bus triggers (interactable_triggered / guard_fsm_changed). The
# GDD §2 final trigger is CheckpointVolume, which calls produce() directly and is
# unaffected by this flag. Flip to false to make the producer volume-only.
var signal_driven: bool = true


var _bus: EventBus = null
var _sm: Node = null
var _event_seq: int = 0


func _ready() -> void:
	# So CheckpointVolume (which is level-placed and may exist far from this
	# node in the tree) can find the producer without an explicit NodePath.
	add_to_group("checkpoint_producer")
	_resolve_collaborators()
	if _bus != null:
		if not _bus.interactable_triggered.is_connected(_on_interactable_triggered):
			_bus.interactable_triggered.connect(_on_interactable_triggered)
		if not _bus.guard_fsm_changed.is_connected(_on_guard_fsm_changed):
			_bus.guard_fsm_changed.connect(_on_guard_fsm_changed)


func _resolve_collaborators() -> void:
	var tree := get_tree()
	if tree == null:
		return
	if _bus == null:
		_bus = tree.get_first_node_in_group("event_bus") as EventBus
	if _sm == null:
		_sm = tree.get_first_node_in_group("save_manager") as Node


## ★ The single collection + write entry. Called by CheckpointVolume on
## body_entered (the GDD §2 trigger) and by the two bus-signal triggers below.
## `checkpoint_id` identifies the volume/event that caused the write (e.g.
## "cp_atrium_01"); the snapshot itself carries the world diff state.
func produce(checkpoint_id: String) -> void:
	if _sm == null:
		_resolve_collaborators()
	if _sm == null:
		push_error("CheckpointProducer.produce: SaveManager (group 'save_manager') unresolved — checkpoint '%s' not written." % checkpoint_id)
		return
	var data := _collect_snapshot(checkpoint_id)
	_sm.write_slot(SaveManagerScript.CHECKPOINT_SLOT_ID, data)


# =============================================================================
# Snapshot collection — the §② seven-field dict for make_slot()
# =============================================================================
## Only the 7 GDD §2 fields are emitted. a11y_prefs is intentionally omitted:
# per-spec it is "省略" (prefs go through save_prefs(), not the checkpoint slot),
# and make_slot silently drops any extra key anyway — so omitting it is correct,
# not a loss. guard_states MUST enumerate every live guard (see spec §②: the
# restore path only resets guards present in this map).
func _collect_snapshot(checkpoint_id: String) -> Dictionary:
	var data: Dictionary = {}
	data["checkpoint_id"] = checkpoint_id
	data["player_pose"] = _collect_player_pose()
	data["suspicion"] = _collect_suspicion()
	data["guard_states"] = _collect_guard_states()
	data["interactable_charges"] = _collect_charges()
	data["light_states"] = _collect_light_states()
	return data


func _collect_player_pose() -> Dictionary:
	if player_node == null or not is_instance_valid(player_node):
		return {"pos": Vector3.ZERO, "facing": 0.0, "gait": 0}
	return {
		"pos": player_node.global_position,
		"facing": float(player_node.rotation.y),
		"gait": 0,
	}


func _collect_guard_states() -> Dictionary:
	var out: Dictionary = {}
	if guard_spawner == null:
		return out
	for brain in guard_spawner.live_guards():
		if is_instance_valid(brain):
			out[int(brain.guard_id)] = int(brain.get_state())
	return out


## Suspicion is optional on write (restore forces it to 0 regardless). We still
## capture it so a future diagnostic can diff pre/post; harmless extra field.
func _collect_suspicion() -> Dictionary:
	var out: Dictionary = {}
	if guard_spawner == null:
		return out
	for brain in guard_spawner.live_guards():
		if is_instance_valid(brain):
			out[int(brain.guard_id)] = float(brain.suspicion)
	return out


func _collect_charges() -> Dictionary:
	if interactable_registry == null:
		return {}
	return interactable_registry.snapshot_charges()


func _collect_light_states() -> Dictionary:
	var out: Dictionary = {}
	if light_model == null:
		return out
	for id_variant in light_model.light_ids():
		var lid := int(id_variant)
		out[lid] = (light_model.get_light_state(lid) == EventBus.LightState.LIT)
	return out


# =============================================================================
# Interim bus triggers
# =============================================================================
func _on_interactable_triggered(_obj_id: int, type: int, _payload: Dictionary) -> void:
	if not signal_driven:
		return
	# The entity only emits interactable_triggered on a SUCCESSFUL trigger — a
	# blocked/charged-out interactable emits nothing (interactable_entity.gd). So
	# any LIGHT_TOGGLE/DECOY event here is a real "safe progress" moment; no
	# extra success filter is needed. (TRAP/SMOKE are excluded: a trap springing
	# is not "the player advanced safely", and SMOKE is defensive.)
	if type == EventBus.InteractableType.LIGHT_TOGGLE or type == EventBus.InteractableType.DECOY:
		_event_seq += 1
		produce("cp_progress_%d" % _event_seq)


func _on_guard_fsm_changed(_guard_id: int, old: int, new: int) -> void:
	if not signal_driven:
		return
	# ★ CORRECTNESS GATE (not just throttling). Only a guard VOLUNTARILY returning
	# to patrol — SUSPICIOUS->RETURN or SEARCH->RETURN — is a "safe again" moment
	# worth a checkpoint. The soft-fail reset AND the checkpoint-restore reset BOTH
	# force RETURN but from ALERT/CALM, and writing a checkpoint at either point
	# is wrong:
	#   • soft-fail reset (ALERT->RETURN): would snapshot the CAPTURE position and
	#     overwrite the rolling checkpoint, so the next restore rolls the player
	#     back to where they were caught instead of to the last volume.
	#   • restore reset (CALM->RETURN): is the applier unwinding guards; writing a
	#     duplicate checkpoint mid-restore is wasted IO and a feedback smell.
	# In _step_fsm a guard never goes ALERT->RETURN directly (ALERT only leaves via
	# SEARCH), so `old == ALERT` cleanly selects "this RETURN came from a reset",
	# not from genuine pursuit loss.
	if new == EventBus.GuardState.RETURN and old != EventBus.GuardState.ALERT:
		_event_seq += 1
		produce("cp_progress_%d" % _event_seq)
