# tests/unit/test_checkpoint_producer.gd
# GUT tests for the D1 checkpoint write-end coordinator (src/game/checkpoint_producer.gd).
#
# Coverage:
#   • produce() collects exactly the §② seven-field snapshot and writes a
#     checkpoint slot via SaveManager.write_slot(CHECKPOINT_SLOT_ID, data).
#   • interactable_triggered (LIGHT_TOGGLE / DECOY success) drives a write.
#   • guard_fsm_changed(RETURN) drives a write ONLY for a genuine return
#     (SUSPICIOUS/SEARCH -> RETURN), NEVER for the soft-fail / restore reset
#     (ALERT -> RETURN) — that gate protects the rollback-to-volume contract.
#
# Test isolation: nothing touches real user://saves/; re-point SaveManager at a
# per-file test dir, purged in before_each / after_each.
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
const GuardBrain = preload("res://src/game/patrol_ai.gd")

const TEST_SAVE_DIR := "user://__test_saves_cpp/"
const TEST_PREFS_PATH := "user://__test_prefs_cpp.json"
const TEST_LEGACY_CFG := "user://__test_a11y_cpp.cfg"
const SIGNAL_TIMEOUT := 1.0


var _bus: EventBus
var _sm: Node
var _spawner: GuardSpawner
var _light: LightModel
var _registry: InteractableRegistry
var _player: Marker3D
var _producer: CheckpointProducer

var _save_events: Array = []


func before_all() -> void:
	DirAccess.make_dir_recursive_absolute(TEST_SAVE_DIR)


func after_all() -> void:
	_purge_test_files()
	DirAccess.remove_absolute(TEST_SAVE_DIR)


func before_each() -> void:
	_purge_test_files()
	_bus = autofree(EventBus.new())
	add_child_autofree(_bus)
	# Resolve SaveManager the SAME way CheckpointProducer does (group
	# "save_manager"): in a GUT run the SaveManager AUTOLOAD is already first in
	# that group, so we must point _sm at it — otherwise the producer silently
	# writes to the autoload while we assert on a separate instance (has_checkpoint
	# would read false and read_slot would return {}).
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
	_save_events = []
	_bus.save_completed.connect(_on_save)


func after_each() -> void:
	_purge_test_files()
	_bus = null
	_sm = null
	_spawner = null
	_light = null
	_registry = null
	_player = null
	_producer = null


func _on_save(slot_id: int, success: bool) -> void:
	_save_events.append({"slot_id": slot_id, "success": success})


func _make_producer() -> CheckpointProducer:
	var p := CheckpointProducer.new()
	p.guard_spawner = _spawner
	p.light_model = _light
	p.interactable_registry = _registry
	p.player_node = _player
	add_child_autofree(p)
	_producer = p
	return p


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
# produce() -> seven-field snapshot
# =============================================================================
func test_produce_writes_checkpoint_with_seven_fields() -> void:
	var g1 := _spawn_guard(1)
	var g2 := _spawn_guard(2)
	_player.global_position = Vector3(3.0, 0.0, 4.0)
	_player.rotation.y = 0.5
	_light.register_light(5, Vector3.ZERO)
	_light.set_light_state(5, EventBus.LightState.EXTINGUISHED)
	_light.register_light(6, Vector3.ZERO)
	_light.set_light_state(6, EventBus.LightState.LIT)
	var ent = _registry.spawn(EventBus.InteractableType.LIGHT_TOGGLE, Vector3.ZERO)
	_registry.charges().consume(ent.entity_id, EventBus.InteractableType.LIGHT_TOGGLE)

	var p := _make_producer()
	p.produce("cp_atrium_01")

	assert_true(await wait_for_signal(_bus.save_completed, SIGNAL_TIMEOUT))
	assert_true(_sm.has_checkpoint(), "produce must write a checkpoint")

	var slot: Dictionary = _sm.read_slot(SaveManagerScript.CHECKPOINT_SLOT_ID)
	assert_true(await wait_for_signal(_bus.load_completed, SIGNAL_TIMEOUT))

	assert_eq(str(slot["checkpoint_id"]), "cp_atrium_01")
	# player pose round-trips through the Vector3 -> [x,y,z] encode/decode
	assert_eq(slot["player_pose"]["pos"], Vector3(3.0, 0.0, 4.0))
	assert_almost_eq(float(slot["player_pose"]["facing"]), 0.5, 0.0001)
	# guard_states MUST enumerate every live guard (restore resets exactly these)
	assert_eq(int(slot["guard_states"][1]), EventBus.GuardState.CALM)
	assert_eq(int(slot["guard_states"][2]), EventBus.GuardState.CALM)
	# suspicion captured (optional field, restored to 0 later)
	assert_almost_eq(float(slot["suspicion"][1]), 0.0, 0.0001)
	# light_states: LIT -> true / EXTINGUISHED -> false
	assert_false(bool(slot["light_states"][5]), "extinguished light -> false")
	assert_true(bool(slot["light_states"][6]), "lit light -> true")
	# interactable_charges: world entity id 1 (remaining 2) + carried pool ids
	assert_eq(int(slot["interactable_charges"][1]), 2,
		"consumed world charge must be snapshotted")


func test_produce_omits_unknown_keys() -> void:
	# make_slot silently drops any key outside the 11 GDD fields. The producer
	# must not smuggle in non-checkpoint fields (e.g. objective_progress), or the
	# write would silently lose them. Verify the written slot carries exactly
	# the 11 wire fields and nothing from the live world beyond the 6 collected.
	var _g := _spawn_guard(1)
	var p := _make_producer()
	p.produce("cp_clean")

	assert_true(await wait_for_signal(_bus.save_completed, SIGNAL_TIMEOUT))
	var slot: Dictionary = _sm.read_slot(SaveManagerScript.CHECKPOINT_SLOT_ID)
	assert_true(await wait_for_signal(_bus.load_completed, SIGNAL_TIMEOUT))
	assert_eq(slot.keys().size(), SaveManagerScript.SLOT_FIELD_ORDER.size(),
		"a checkpoint slot carries exactly the 11 GDD §3 fields (no leakage)")


# =============================================================================
# Interim trigger: interactable_triggered (LIGHT_TOGGLE / DECOY success)
# =============================================================================
func test_interactable_triggered_light_toggle_writes_checkpoint() -> void:
	var _g := _spawn_guard(1)
	var p := _make_producer()
	# A successful LIGHT_TOGGLE emit (payload non-empty, as interactable_entity
	# only emits on a real trigger).
	_bus.interactable_triggered.emit(900, EventBus.InteractableType.LIGHT_TOGGLE,
		{"charges": 2, "entity_id": 900, "lit": false})
	assert_true(await wait_for_signal(_bus.save_completed, SIGNAL_TIMEOUT))
	assert_true(_sm.has_checkpoint(), "LIGHT_TOGGLE success must write a checkpoint")
	assert_eq(_sm.checkpoint_write_count, 1)


func test_interactable_triggered_decoy_writes_checkpoint() -> void:
	var _g := _spawn_guard(1)
	var p := _make_producer()
	_bus.interactable_triggered.emit(901, EventBus.InteractableType.DECOY,
		{"charges": 1, "entity_id": 901})
	assert_true(await wait_for_signal(_bus.save_completed, SIGNAL_TIMEOUT))
	assert_true(_sm.has_checkpoint(), "DECOY success must write a checkpoint")


func test_interactable_triggered_trap_does_not_write() -> void:
	var _g := _spawn_guard(1)
	var p := _make_producer()
	_bus.interactable_triggered.emit(902, EventBus.InteractableType.TRAP,
		{"charges": 1, "entity_id": 902})
	# No checkpoint write is expected; give the deferred flush a moment.
	await get_tree().process_frame
	assert_false(_sm.has_checkpoint(), "TRAP trigger must NOT write a checkpoint")


# =============================================================================
# Correctness gate: guard_fsm_changed(RETURN) must NOT write on a reset
# =============================================================================
func test_soft_fail_reset_does_not_write_checkpoint() -> void:
	# The soft-fail path forces RETURN from ALERT. If the producer wrote a
	# checkpoint there, it would snapshot the CAPTURE position and corrupt the
	# rollback-to-volume contract. Assert no write happens.
	var g1 := _spawn_guard(1)
	g1.set_checkpoint_sink(Callable(_sm, "restore_checkpoint"))
	var p := _make_producer()

	# Drive a real soft fail: ALERT + exposure past the 1.2s grace.
	g1.fsm = EventBus.GuardState.ALERT
	g1.suspicion = 80.0
	g1.exposure_timer = GuardBrain.GRACE_RT - GuardBrain.TICK_DT
	g1._pending_target = null
	g1._pending_vision = 1.0
	g1._decide(GuardBrain.TICK_DT)

	await get_tree().process_frame
	assert_false(_sm.has_checkpoint(),
		"soft-fail reset (ALERT->RETURN) must NOT write a checkpoint")
	# The guard did reset, proving the signal fired and the gate is what blocked
	# the write (not a missing connection).
	assert_eq(g1.get_state(), EventBus.GuardState.RETURN,
		"the soft-fail reset still happened (guard_fsm_changed fired)")


func test_genuine_return_writes_checkpoint() -> void:
	# A guard VOLUNTARILY settling back to patrol (SUSPICIOUS -> RETURN) is a
	# legitimate "safe again" checkpoint moment and must write.
	var g1 := _spawn_guard(1)
	g1.fsm = EventBus.GuardState.SUSPICIOUS
	g1.suspicion = 5.0
	var p := _make_producer()

	g1._pending_vision = 0.0
	g1._decide(GuardBrain.TICK_DT)   # decay keeps suspicion < THR_RETURN -> RETURN

	assert_true(await wait_for_signal(_bus.save_completed, SIGNAL_TIMEOUT))
	assert_true(_sm.has_checkpoint(),
		"genuine SUSPICIOUS->RETURN must write a checkpoint")
	assert_eq(g1.get_state(), EventBus.GuardState.RETURN)
