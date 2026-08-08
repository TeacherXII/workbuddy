class_name CheckpointApplier
extends Node

# ASHEN STEP — Phase 6, D1. Checkpoint restore consumer (L4, C).
#
# Closes the RECOVERY half of the checkpoint loop (spec §③). restore_checkpoint()
# (L2) publishes the normalised world snapshot on SaveManager.restored_state and
# broadcasts EventBus.checkpoint_restored; this node is the ⑥ consumer that
# actually applies it to the live world. Without it the snapshot is computed and
# broadcast but never consumed — the loop stays half-open (the D1伴生缺口).
#
# Applies, in order:
#   • player pose      <- restored_state.player_pose
#   • guards            <- GuardBrain.apply_checkpoint_reset() on every live guard
#                         (reuses the soft-fail zeroing, but emits NO
#                         exposure_detected — a restore is a rollback, not a catch)
#   • lights            <- LightModel.set_light_state(id, LIT/EXTINGUISHED)
#   • interactable charges <- InteractableRegistry.restore_charges(...)
#
# This is a HARD dependency of the core loop (unlike SaveSlotsScreen, which the
# slice deliberately does not mount), so sprint0_bootstrap.gd wires it in _ready.

const SaveManagerScript = preload("res://src/core/save_manager.gd")
const EventBus = preload("res://src/core/event_bus.gd")
const GuardSpawner = preload("res://src/game/guard_spawner.gd")
const LightModel = preload("res://src/game/light_model.gd")
const InteractableRegistry = preload("res://src/game/interactables/interactable_registry.gd")


# ── Level-owned collaborators (wired by the level / sprint0_bootstrap) ───────
var guard_spawner: GuardSpawner = null
var light_model: LightModel = null
var interactable_registry: InteractableRegistry = null
var player_node: Node3D = null


var _bus: EventBus = null
var _sm: Node = null


func _ready() -> void:
	_resolve_collaborators()
	if _bus != null and not _bus.checkpoint_restored.is_connected(_on_checkpoint_restored):
		_bus.checkpoint_restored.connect(_on_checkpoint_restored)


func _resolve_collaborators() -> void:
	var tree := get_tree()
	if tree == null:
		return
	if _bus == null:
		_bus = tree.get_first_node_in_group("event_bus") as EventBus
	if _sm == null:
		_sm = tree.get_first_node_in_group("save_manager") as Node


## EventBus.checkpoint_restored handler. `checkpoint_id` is accepted for the
## signature but the authoritative snapshot is SaveManager.restored_state (it is
## already assigned synchronously before the deferred broadcast, so consumers
## always see it — see save_manager.gd restore_checkpoint()).
func _on_checkpoint_restored(_checkpoint_id: String) -> void:
	if _sm == null:
		_resolve_collaborators()
	if _sm == null:
		push_error("CheckpointApplier: SaveManager (group 'save_manager') unresolved — cannot apply restore.")
		return
	var st: Dictionary = _sm.restored_state
	if st.is_empty():
		return
	_apply_player(st)
	_apply_guards(st)
	_apply_lights(st)
	_apply_charges(st)


func _apply_player(st: Dictionary) -> void:
	if player_node == null or not is_instance_valid(player_node):
		return
	var pose: Dictionary = st.get("player_pose", {})
	var pos: Variant = pose.get("pos", null)
	if pos is Vector3:
		player_node.global_position = pos
	var facing: float = float(pose.get("facing", 0.0))
	player_node.rotation.y = facing


## Iterate EVERY live guard and unwind it to patrol. We do not filter by the
## snapshot's guard key set: even a guard the snapshot recorded as already RETURN
## must be forced back (a guard that slipped into ALERT after the snapshot was
## taken still needs the reset). apply_checkpoint_reset emits nothing, so no
## false exposure_detected re-triggers the very soft fail this restore cancels.
func _apply_guards(st: Dictionary) -> void:
	if guard_spawner == null:
		return
	for brain in guard_spawner.live_guards():
		if is_instance_valid(brain) and brain.has_method("apply_checkpoint_reset"):
			brain.apply_checkpoint_reset()


func _apply_lights(st: Dictionary) -> void:
	if light_model == null:
		return
	var lights: Dictionary = st.get("light_states", {})
	for id_variant in lights.keys():
		var lid := int(id_variant)
		var lit: bool = bool(lights[id_variant])
		light_model.set_light_state(lid, EventBus.LightState.LIT if lit else EventBus.LightState.EXTINGUISHED)


func _apply_charges(st: Dictionary) -> void:
	if interactable_registry == null:
		return
	interactable_registry.restore_charges(st.get("interactable_charges", {}))
