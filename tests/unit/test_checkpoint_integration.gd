# tests/unit/test_checkpoint_integration.gd
# GUT integration test for D1 — the CLOSED checkpoint loop.
#
# Acceptance (team-lead): a REAL soft fail -> checkpoint slot file is produced
# -> restore_checkpoint() is a non-no-op -> CheckpointApplier applies the
# snapshot -> player pose / guards / lights / charges roll back. This is the
# end-to-end path the D1 playtest flagged as half-open.
#
# Chain under test:
#   CheckpointProducer.produce()  -> SaveManager.write_slot(CHECKPOINT_SLOT_ID)
#   GuardBrain soft fail           -> restore_checkpoint() (zero-arg seam)
#   EventBus.checkpoint_restored  -> CheckpointApplier applies restored_state
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
const CheckpointProducer = preload("res://src/game/checkpoint_producer.gd")
const CheckpointApplier = preload("res://src/game/checkpoint_applier.gd")
const GuardBrain = preload("res://src/game/patrol_ai.gd")

const TEST_SAVE_DIR := "user://__test_saves_cpi/"
const TEST_PREFS_PATH := "user://__test_prefs_cpi.json"
const TEST_LEGACY_CFG := "user://__test_a11y_cpi.cfg"
const SIGNAL_TIMEOUT := 1.0


var _bus: EventBus
var _sm: Node
var _spawner: GuardSpawner
var _light: LightModel
var _registry: InteractableRegistry
var _player: Marker3D
var _producer: CheckpointProducer
var _applier: CheckpointApplier

var _save_events: Array = []
var _restored_events: Array = []


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
	_producer = CheckpointProducer.new()
	_producer.guard_spawner = _spawner
	_producer.light_model = _light
	_producer.interactable_registry = _registry
	_producer.player_node = _player
	add_child_autofree(_producer)
	_applier = CheckpointApplier.new()
	_applier.guard_spawner = _spawner
	_applier.light_model = _light
	_applier.interactable_registry = _registry
	_applier.player_node = _player
	add_child_autofree(_applier)
	_save_events = []
	_restored_events = []
	_bus.save_completed.connect(_on_save)
	_bus.checkpoint_restored.connect(_on_restored)


func after_each() -> void:
	_purge_test_files()
	_bus = null
	_sm = null
	_spawner = null
	_light = null
	_registry = null
	_player = null
	_producer = null
	_applier = null


func _on_save(slot_id: int, success: bool) -> void:
	_save_events.append({"slot_id": slot_id, "success": success})


func _on_restored(checkpoint_id: String) -> void:
	_restored_events.append(checkpoint_id)


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


# =============================================================================
# Full loop: real soft fail -> checkpoint file -> restore -> world rollback
# =============================================================================
func test_soft_fail_restores_world_from_checkpoint() -> void:
	var g1 := _spawn_guard(1)   # the captor
	var g2 := _spawn_guard(2)
	# The captor's D9 seam points at the real SaveManager (zero-arg, FLAG-A).
	g1.set_checkpoint_sink(Callable(_sm, "restore_checkpoint"))

	# ── 1. Establish a safe checkpoint (player at the volume, guards calm) ──
	_player.global_position = Vector3(10.0, 0.0, 10.0)
	_player.rotation.y = 0.0
	_light.register_light(5, Vector3.ZERO)
	_light.set_light_state(5, EventBus.LightState.LIT)
	_light.register_light(6, Vector3.ZERO)
	_light.set_light_state(6, EventBus.LightState.EXTINGUISHED)
	var ent = _registry.spawn(EventBus.InteractableType.LIGHT_TOGGLE, Vector3.ZERO)
	_registry.charges().consume(ent.entity_id, EventBus.InteractableType.LIGHT_TOGGLE)  # remaining 2

	# A "safe progress" trigger writes the checkpoint (LIGHT_TOGGLE success).
	_bus.interactable_triggered.emit(ent.entity_id, EventBus.InteractableType.LIGHT_TOGGLE,
		{"charges": 2, "entity_id": ent.entity_id, "lit": false})
	assert_true(await wait_for_signal(_bus.save_completed, SIGNAL_TIMEOUT))
	assert_true(_sm.has_checkpoint(), "a checkpoint must exist before the soft fail")
	var slot_path: String = _sm.slot_path(SaveManagerScript.CHECKPOINT_SLOT_ID)
	assert_true(FileAccess.file_exists(slot_path),
		"the checkpoint slot FILE must be produced on disk")

	# ── 2. Corrupt the world away from the checkpoint ──
	_player.global_position = Vector3(99.0, 0.0, 99.0)
	g1.fsm = EventBus.GuardState.ALERT
	g1.suspicion = 80.0
	g2.fsm = EventBus.GuardState.SUSPICIOUS
	g2.suspicion = 40.0
	_light.set_light_state(6, EventBus.LightState.LIT)   # was extinguished
	_registry.charges().consume(ent.entity_id, EventBus.InteractableType.LIGHT_TOGGLE)  # remaining 1

	# ── 3. Trigger a REAL soft fail on g1 (ALERT + exposure past 1.2s grace) ──
	g1.exposure_timer = GuardBrain.GRACE_RT - GuardBrain.TICK_DT
	g1._pending_target = null
	g1._pending_vision = 1.0
	g1._decide(GuardBrain.TICK_DT)

	# restore_checkpoint() must be a NON-no-op and broadcast checkpoint_restored.
	assert_true(await wait_for_signal(_bus.checkpoint_restored, SIGNAL_TIMEOUT),
		"soft fail must drive a real restore (non-no-op checkpoint_restored)")
	assert_false(_sm.restored_state.is_empty(),
		"restore must publish a non-empty restored_state")

	# ── 4. Assert the world rolled back to the checkpoint ──
	assert_eq(_player.global_position, Vector3(10.0, 0.0, 10.0),
		"player rolled back to the checkpoint volume position")
	assert_eq(g1.get_state(), EventBus.GuardState.RETURN,
		"captor guard forced back to RETURN")
	assert_almost_eq(g1.suspicion, 0.0, 0.0001, "captor suspicion zeroed")
	assert_eq(g2.get_state(), EventBus.GuardState.RETURN,
		"the other live guard also unwound to RETURN")
	assert_almost_eq(g2.suspicion, 0.0, 0.0001, "other guard suspicion zeroed")
	assert_eq(_light.get_light_state(6), EventBus.LightState.EXTINGUISHED,
		"light rolled back to its checkpoint state")
	assert_eq(_registry.charges().remaining(ent.entity_id, EventBus.InteractableType.LIGHT_TOGGLE), 2,
		"interactable charge rolled back to the checkpoint value")

	# ── 5. restored_state shape confirms the normalisation (spec §③) ──
	var st: Dictionary = _sm.restored_state
	assert_eq(int(st["guard_states"][1]), EventBus.GuardState.RETURN)
	assert_eq(int(st["guard_states"][2]), EventBus.GuardState.RETURN)
	assert_almost_eq(float(st["suspicion"][1]), 0.0, 0.0001)
	assert_almost_eq(float(st["suspicion"][2]), 0.0, 0.0001)
