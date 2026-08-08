# tests/unit/test_checkpoint_applier.gd
# GUT tests for the D1 checkpoint restore consumer (src/game/checkpoint_applier.gd).
#
# Coverage:
#   • On EventBus.checkpoint_restored, the applier reads SaveManager.restored_state
#     and rolls the LIVE world back: player pose, every live guard
#     (apply_checkpoint_reset -> RETURN / suspicion 0, NO exposure_detected),
#     lights (LIT/EXTINGUISHED), interactable charges.
#   • Guards already past the snapshot (e.g. slipped into ALERT after the
#     snapshot was taken) are still unwound — iterate LIVE guards, not the
#     snapshot key set.
#
# Test isolation: re-point SaveManager at a per-file test dir, purged each round.
#
# Run: godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit

extends GutTest

const SaveManagerScript = preload("res://src/core/save_manager.gd")
const EventBus = preload("res://src/core/event_bus.gd")
const GuardSpawner = preload("res://src/game/guard_spawner.gd")
const GuardVariantParams = preload("res://src/game/guard_variant_params.gd")
const LightModel = preload("res://src/game/light_model.gd")
const InteractableRegistry = preload("res://src/game/interactables/interactable_registry.gd")
const CheckpointApplier = preload("res://src/game/checkpoint_applier.gd")
const GuardBrain = preload("res://src/game/patrol_ai.gd")

const TEST_SAVE_DIR := "user://__test_saves_cpa/"
const TEST_PREFS_PATH := "user://__test_prefs_cpa.json"
const TEST_LEGACY_CFG := "user://__test_a11y_cpa.cfg"
const SIGNAL_TIMEOUT := 1.0


var _bus: EventBus
var _sm: Node
var _spawner: GuardSpawner
var _light: LightModel
var _registry: InteractableRegistry
var _player: Marker3D
var _applier: CheckpointApplier


func before_all() -> void:
	DirAccess.make_dir_recursive_absolute(TEST_SAVE_DIR)


func after_all() -> void:
	_purge_test_files()
	DirAccess.remove_absolute(TEST_SAVE_DIR)


func before_each() -> void:
	_purge_test_files()
	_bus = autofree(EventBus.new())
	add_child_autofree(_bus)
	_sm = get_tree().get_first_node_in_group("save_manager")
	if _sm == null:
		_sm = add_child_autofree(SaveManagerScript.new())
	_sm.set_event_bus(_bus)
	_sm.configure_paths(TEST_SAVE_DIR, TEST_PREFS_PATH, TEST_LEGACY_CFG)
	_spawner = GuardSpawner.new()
	_light = LightModel.new()
	_registry = InteractableRegistry.new(_bus)
	_player = autofree(Marker3D.new())
	_player.name = "Player"
	add_child_autofree(_player)
	_applier = CheckpointApplier.new()
	_applier.guard_spawner = _spawner
	_applier.light_model = _light
	_applier.interactable_registry = _registry
	_applier.player_node = _player
	add_child_autofree(_applier)


func after_each() -> void:
	_purge_test_files()
	_bus = null
	_sm = null
	_spawner = null
	_light = null
	_registry = null
	_player = null
	_applier = null


func _spawn_guard(id: int) -> GuardBrain:
	var b: GuardBrain = _spawner.spawn(GuardVariantParams.Variant.STANDARD, id)
	b.set_event_bus(_bus)
	return b


func _purge_test_files() -> void:
	var d := DirAccess.open(TEST_SAVE_DIR)
	if d != null:
		d.list_dir_begin()
		var n := d.get_next()
		while n != "":
			if not d.current_is_dir():
				d.remove(n)
			n = d.get_next()
		d.list_dir_end()
	for p in [TEST_PREFS_PATH, TEST_LEGACY_CFG]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


# Seed a restored_state directly (bypassing a real soft fail) and fire the
# signal, exactly as SaveManager + the bus would at runtime.
func _apply_restored(state: Dictionary) -> void:
	_sm.restored_state = state
	_bus.checkpoint_restored.emit(str(state.get("checkpoint_id", "")))


func test_applier_rolls_back_player_guards_lights_charges() -> void:
	var g1 := _spawn_guard(1)
	var g2 := _spawn_guard(2)

	# Mutate the world away from the snapshot we are about to restore to.
	_player.global_position = Vector3(50.0, 0.0, 50.0)
	_player.rotation.y = 1.7
	g1.fsm = EventBus.GuardState.ALERT
	g1.suspicion = 80.0
	g2.fsm = EventBus.GuardState.SUSPICIOUS
	g2.suspicion = 35.0
	_light.register_light(6, Vector3.ZERO)
	_light.set_light_state(6, EventBus.LightState.LIT)
	var ent = _registry.spawn(EventBus.InteractableType.LIGHT_TOGGLE, Vector3.ZERO)
	_registry.charges().consume(ent.entity_id, EventBus.InteractableType.LIGHT_TOGGLE)
	_registry.charges().consume(ent.entity_id, EventBus.InteractableType.LIGHT_TOGGLE)  # remaining 1

	var state := {
		"checkpoint_id": "cp_cistern_01",
		"player_pose": {"pos": Vector3(3.0, 0.0, 4.0), "facing": 0.5, "gait": 0},
		"suspicion": {1: 0.0, 2: 0.0},
		"guard_states": {1: EventBus.GuardState.RETURN, 2: EventBus.GuardState.RETURN},
		"interactable_charges": {1: 2},
		"light_states": {6: false},
	}
	_apply_restored(state)

	# Player rolled back to the snapshot pose.
	assert_eq(_player.global_position, Vector3(3.0, 0.0, 4.0))
	assert_almost_eq(float(_player.rotation.y), 0.5, 0.0001)
	# Both live guards unwound to RETURN / suspicion 0 (even g1 which had gone
	# ALERT after the snapshot was taken).
	assert_eq(g1.get_state(), EventBus.GuardState.RETURN)
	assert_eq(g2.get_state(), EventBus.GuardState.RETURN)
	assert_almost_eq(g1.suspicion, 0.0, 0.0001)
	assert_almost_eq(g2.suspicion, 0.0, 0.0001)
	# Light restored to extinguished.
	assert_eq(_light.get_light_state(6), EventBus.LightState.EXTINGUISHED)
	# Charge restored to the snapshot value.
	assert_eq(_registry.charges().remaining(ent.entity_id, EventBus.InteractableType.LIGHT_TOGGLE), 2)


func test_applier_resets_guards_without_emitting_capture() -> void:
	# apply_checkpoint_reset must NOT emit exposure_detected — a rollback is not a
	# re-catch, or it would re-trigger the very soft fail it is cancelling.
	var g1 := _spawn_guard(1)
	g1.fsm = EventBus.GuardState.ALERT
	g1.suspicion = 70.0
	var exposure_events: Array = []
	_bus.exposure_detected.connect(func(_gid, _t): exposure_events.append(1))

	_apply_restored({
		"checkpoint_id": "cp_q",
		"player_pose": {"pos": Vector3.ZERO, "facing": 0.0, "gait": 0},
		"suspicion": {1: 0.0},
		"guard_states": {1: EventBus.GuardState.RETURN},
		"interactable_charges": {},
		"light_states": {},
	})

	assert_eq(g1.get_state(), EventBus.GuardState.RETURN)
	assert_almost_eq(g1.suspicion, 0.0, 0.0001)
	assert_eq(exposure_events.size(), 0,
		"restoring a checkpoint must NOT emit exposure_detected")
