# tests/unit/test_checkpoint_volume.gd
# GUT tests for the D1 checkpoint trigger volume (src/game/checkpoint_volume.gd).
#
# Coverage:
#   • body_entered (player) -> CheckpointProducer.produce(checkpoint_id): the
#     GDD §2 diegetic trigger writes a checkpoint under this volume's id.
#   • visit debounce: one write per entry until the body leaves and re-enters.
#
# Headless: no physics overlap is simulated — body_entered is emitted directly
# (the signal is already connected in _ready), which exercises the volume's
# route-to-produce logic without a physics world.
#
# Run: godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit

extends GutTest

const SaveManagerScript = preload("res://src/core/save_manager.gd")
const EventBus = preload("res://src/core/event_bus.gd")
const LightModel = preload("res://src/game/light_model.gd")
const CheckpointProducer = preload("res://src/game/checkpoint_producer.gd")
const CheckpointVolume = preload("res://src/game/checkpoint_volume.gd")

const TEST_SAVE_DIR := "user://__test_saves_cpv/"
const TEST_PREFS_PATH := "user://__test_prefs_cpv.json"
const TEST_LEGACY_CFG := "user://__test_a11y_cpv.cfg"
const SIGNAL_TIMEOUT := 1.0


var _bus: EventBus
var _sm: Node
var _light: LightModel
var _producer: CheckpointProducer
var _volume: CheckpointVolume
var _player: Marker3D

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
	_sm = get_tree().get_first_node_in_group("save_manager")
	if _sm == null:
		_sm = add_child_autofree(SaveManagerScript.new())
	_sm.set_event_bus(_bus)
	_sm.configure_paths(TEST_SAVE_DIR, TEST_PREFS_PATH, TEST_LEGACY_CFG)
	_light = LightModel.new()
	_player = autofree(Marker3D.new())
	_player.name = "Player"
	add_child_autofree(_player)
	# Producer registers itself in group "checkpoint_producer" on _ready, which
	# is how the (level-placed) volume resolves it without an explicit path.
	_producer = CheckpointProducer.new()
	_producer.light_model = _light
	_producer.player_node = _player
	add_child_autofree(_producer)
	_volume = CheckpointVolume.new()
	_volume.checkpoint_id = "cp_atrium_01"
	add_child_autofree(_volume)
	_save_events = []
	_bus.save_completed.connect(_on_save)


func after_each() -> void:
	_purge_test_files()
	_bus = null
	_sm = null
	_light = null
	_producer = null
	_volume = null
	_player = null


func _on_save(slot_id: int, success: bool) -> void:
	_save_events.append({"slot_id": slot_id, "success": success})


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


func test_body_entered_writes_checkpoint_under_volume_id() -> void:
	# Simulate the player entering the volume (no physics: emit the signal).
	_volume.body_entered.emit(_player)

	assert_true(await wait_for_signal(_bus.save_completed, SIGNAL_TIMEOUT))
	assert_true(_sm.has_checkpoint(), "entering a CheckpointVolume must write a checkpoint")
	assert_eq(_sm.checkpoint_write_count, 1)
	var slot: Dictionary = _sm.read_slot(SaveManagerScript.CHECKPOINT_SLOT_ID)
	assert_true(await wait_for_signal(_bus.load_completed, SIGNAL_TIMEOUT))
	assert_eq(str(slot["checkpoint_id"]), "cp_atrium_01",
		"the written checkpoint must carry this volume's id")


func test_visit_debounce_writes_once_per_entry() -> void:
	_volume.body_entered.emit(_player)
	assert_true(await wait_for_signal(_bus.save_completed, SIGNAL_TIMEOUT))
	assert_eq(_sm.checkpoint_write_count, 1)

	# Second entry without leaving: debounced, no second write (even though the
	# 0.5s cooldown may have elapsed — the volume's own latch blocks it).
	_volume.body_entered.emit(_player)
	await get_tree().process_frame
	assert_eq(_sm.checkpoint_write_count, 1, "re-entry while still inside must not re-write")

	# Leaving and re-entering re-arms the latch -> another write. The SaveManager
	# 0.5s write cooldown (CHECKPOINT_WRITE_COOLDOWN) is INDEPENDENT of the volume
	# latch and is wall-clock based on purpose (engine.time_scale must not gate
	# persistence), so let it elapse in REAL time before the re-entry — otherwise
	# the second write is correctly throttled and the count would stay at 1.
	_volume.body_exited.emit(_player)
	await get_tree().create_timer(SaveManagerScript.CHECKPOINT_WRITE_COOLDOWN + 0.15).timeout
	_volume.body_entered.emit(_player)
	assert_true(await wait_for_signal(_bus.save_completed, SIGNAL_TIMEOUT))
	assert_eq(_sm.checkpoint_write_count, 2, "leave + re-enter writes again")
