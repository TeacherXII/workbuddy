# tests/unit/test_save_manager.gd
# GUT tests for E11 SaveManager data layer (src/core/save_manager.gd)
# — Sprint 2, Batch A.
#
# Story coverage (sprint2-stories.md §2 Batch A exit hooks, 9 tests):
#   SAV-S1  test_save_slot_roundtrip
#   SAV-S2  test_write_read_slot_roundtrip · test_checkpoint_write_cooldown_0_5s
#   SAV-S3  test_checkpoint_sink_arity_contract · test_restore_resets_suspicion_and_guards
#   SAV-S4  test_prefs_delegation_roundtrip · test_legacy_a11y_cfg_migrated_once
#   SAV-S6  test_version_mismatch_rejected_not_crash · test_corrupt_json_rejected_not_swallowed
#
# ★ TEST ISOLATION (sprint2-stories.md §4「SaveManager 测试隔离」) ★
#   NOTHING here touches the real user://saves/, user://prefs.json or
#   user://a11y.cfg. Every manager under test is re-pointed at
#   user://__test_saves/ + user://__test_prefs.json + user://__test_a11y.cfg via
#   configure_paths(), and those files are purged in before_each AND after_each.
#   The a11y.cfg migration test FABRICATES its own legacy file first — a
#   developer's real settings are never read and never deleted.
#
# ★ EXPECTED ERROR OUTPUT ★
#   test_version_mismatch_rejected_not_crash and
#   test_corrupt_json_rejected_not_swallowed intentionally drive SaveManager's
#   reject path, which calls push_error(). The ERROR lines they print are the
#   PROOF of GDD §6「绝不静默吞错」— they are not test failures. Every test here
#   is a normal `func test_*`; this file emits no GUT risky/pending token at all,
#   so the N-7 gate regex cannot match it (N-7).
#
# Node discipline: SaveManager IS added to the tree (add_child_autofree) because
#   its async contract runs through call_deferred; GuardBrain is deliberately NOT
#   (same rule as test_patrol_ai.gd — its _ready() would inject the production
#   autoload sink and the soft-fail path must stay hand-driven).
#
# Run: godot --headless -s res://addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit

extends GutTest

const SaveManagerScript = preload("res://src/core/save_manager.gd")
const EventBus = preload("res://src/core/event_bus.gd")
const GuardBrain = preload("res://src/game/patrol_ai.gd")
const A11ySettings = preload("res://src/core/a11y_settings.gd")

const TEST_SAVE_DIR := "user://__test_saves/"
const TEST_PREFS_PATH := "user://__test_prefs.json"
const TEST_LEGACY_CFG := "user://__test_a11y.cfg"

# Sentinel for the arity probe below. A plain default value is enough: GDScript
# fills unpassed parameters with their defaults, so counting the params that are
# NOT the sentinel yields the ACTUAL argument count at the call site.
const ARG_UNSET := "__arg_unset__"

const SIGNAL_TIMEOUT := 1.0

# a11y field names that MUST NOT appear in save_manager.gd (FLAG-J: the prefs API
# is field-agnostic, otherwise SAV-S4 <-> E09-S7 becomes a dependency cycle).
#
# ★ This list is the LIVE half of FLAG-J and must GROW with the field model.
#   Batch C (E09-S7) added the Tier2 fields below the divider; if a future story
#   adds a field and forgets to register it here, SaveManager can start naming it
#   and the cycle re-forms silently — the scan would still be green because it
#   only checks the names it was told about.
const A11Y_FIELD_NAMES := [
	# Sprint 0 / Sprint 1 fields (some are now backward-compat facades).
	"color_blind_mode",
	"time_scale_min",
	"screen_shake",
	"fog_enabled",
	"motion_blur",
	"text_scale",
	# --- Sprint 2 · Batch C, E09-S7 Tier2 model -----------------------------
	"colorblind_mode",   # E09-S5a, the four-state enum behind color_blind_mode
	"time_scale_user",   # E09-S5b, T-01 slider value
	"fog_option",        # E09-S5c, the three-state rung behind fog_enabled
	"subtitles",         # E09-S5d, X-02
]


var _bus: EventBus
var _sm: Node

# Manual signal ledgers (same rationale as test_patrol_ai.gd: several assertions
# need the exact tuple and the exact emission count).
var _save_events: Array = []
var _load_events: Array = []
var _restored_events: Array = []

var _probe_calls: int = 0
var _probe_actual_args: int = -1


func before_all() -> void:
	DirAccess.make_dir_recursive_absolute(TEST_SAVE_DIR)


func after_all() -> void:
	_purge_test_files()
	DirAccess.remove_absolute(TEST_SAVE_DIR)


func before_each() -> void:
	_purge_test_files()

	_bus = autofree(EventBus.new())
	_sm = add_child_autofree(SaveManagerScript.new())
	_sm.set_event_bus(_bus)
	_sm.configure_paths(TEST_SAVE_DIR, TEST_PREFS_PATH, TEST_LEGACY_CFG)

	_save_events = []
	_load_events = []
	_restored_events = []
	_probe_calls = 0
	_probe_actual_args = -1

	_bus.save_completed.connect(_on_save)
	_bus.load_completed.connect(_on_load)
	_bus.checkpoint_restored.connect(_on_restored)


func after_each() -> void:
	Engine.time_scale = 1.0
	_purge_test_files()
	_bus = null
	_sm = null


# ---- ledger sinks -----------------------------------------------------------
func _on_save(slot_id: int, success: bool) -> void:
	_save_events.append({"slot_id": slot_id, "success": success})


func _on_load(slot_id: int, success: bool) -> void:
	_load_events.append({"slot_id": slot_id, "success": success})


func _on_restored(checkpoint_id: String) -> void:
	_restored_events.append(checkpoint_id)


# ---- helpers ----------------------------------------------------------------
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


func _write_raw(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(TEST_SAVE_DIR)
	var f := FileAccess.open(path, FileAccess.WRITE)
	assert_not_null(f, "test fixture must be writable: %s" % path)
	if f == null:
		return
	f.store_string(text)
	f.close()


## Declared parameter count of a method, read off the SCRIPT (no instance
## required, so this cannot be fooled by a bound Callable).
func _declared_arg_count(script: Script, method: String) -> int:
	for m in script.get_script_method_list():
		if str(m["name"]) == method:
			var args: Array = m["args"]
			return args.size()
	return -1


## Arity probe used as a checkpoint sink. Every parameter is optional, so the
## number of NON-sentinel parameters is exactly how many arguments the call site
## actually passed.
func _probe_sink(a0: Variant = ARG_UNSET, a1: Variant = ARG_UNSET,
		a2: Variant = ARG_UNSET) -> void:
	_probe_calls += 1
	_probe_actual_args = 0
	for a in [a0, a1, a2]:
		if not (typeof(a) == TYPE_STRING and str(a) == ARG_UNSET):
			_probe_actual_args += 1


## Drive the real E08-S4 soft-fail path on a tree-free GuardBrain, exactly like
## test_patrol_ai.gd::_tick does.
func _soft_fail(brain: GuardBrain) -> void:
	brain._set_fsm(EventBus.GuardState.ALERT)
	brain.suspicion = 80.0
	brain.exposure_timer = GuardBrain.GRACE_RT - GuardBrain.TICK_DT
	brain._pending_target = null
	brain._pending_vision = 1.0
	brain._decide(GuardBrain.TICK_DT)


func _make_brain(id: int) -> GuardBrain:
	var brain: GuardBrain = autofree(GuardBrain.new())
	brain.guard_id = id
	brain.set_event_bus(_bus)
	return brain


# =============================================================================
# SAV-S1 — data model + version-first serialisation
# =============================================================================
func test_save_slot_roundtrip() -> void:
	var src := {
		"timestamp": 1234.5,
		"checkpoint_id": "cp_atrium_02",
		"player_pose": {"pos": Vector3(1.5, 0.0, -2.25), "facing": 1.25, "gait": 1},
		"suspicion": {1: 42.5, 2: 0.0},
		"guard_states": {1: EventBus.GuardState.ALERT, 2: EventBus.GuardState.CALM},
		"interactable_charges": {900: 2, 901: 0},
		"light_states": {5: false, 6: true},
		"a11y_prefs": {"text_scale": 1.25},
		"static_level_geometry": "must not be persisted",
	}
	var slot: Dictionary = SaveManagerScript.make_slot(0, false, src)

	# ── FLAG-A mitigation ①: version is the FIRST field and equals SAVE_VERSION.
	var keys: Array = slot.keys()
	assert_eq(SaveManagerScript.SAVE_VERSION, 2, "SAVE_VERSION is locked to 2 (GDD §3)")
	assert_eq(str(keys[0]), "version", "`version` must be the FIRST field of a slot")
	assert_eq(slot["version"], SaveManagerScript.SAVE_VERSION,
		"`version` must always equal SAVE_VERSION on write")
	assert_eq(str(SaveManagerScript.SLOT_FIELD_ORDER[0]), "version",
		"the declared wire order must start with `version`")
	assert_eq(keys.size(), SaveManagerScript.SLOT_FIELD_ORDER.size(),
		"a slot carries exactly the 11 GDD §3 fields")

	# Only "world diff state" is persisted — unknown keys are dropped (GDD §3).
	assert_false(slot.has("static_level_geometry"),
		"static level geometry must never enter a slot")

	# ── The BYTES on disk, not just the Dictionary, must lead with the version.
	var json: String = SaveManagerScript.slot_to_json(slot)
	assert_true(json.begins_with("{\"version\":2"),
		"serialised slot must literally begin with the version field; got: %s"
			% json.substr(0, 40))

	# ── Reversible.
	var parsed: Variant = JSON.parse_string(json)
	assert_true(parsed is Dictionary, "serialised slot must parse back to a Dictionary")
	if not (parsed is Dictionary):
		return
	var back: Dictionary = SaveManagerScript.decode_slot(parsed)
	assert_eq(back["version"], 2)
	assert_eq(back["slot_id"], 0)
	assert_false(bool(back["is_checkpoint"]))
	assert_almost_eq(float(back["timestamp"]), 1234.5, 0.0001)
	assert_eq(str(back["checkpoint_id"]), "cp_atrium_02")
	assert_eq(back["player_pose"]["pos"], Vector3(1.5, 0.0, -2.25),
		"Vector3 pose must survive the JSON hop")
	assert_almost_eq(float(back["player_pose"]["facing"]), 1.25, 0.0001)
	assert_eq(int(back["player_pose"]["gait"]), 1)
	assert_almost_eq(float(back["suspicion"][1]), 42.5, 0.0001,
		"int-keyed maps must come back int-keyed, not string-keyed")
	assert_eq(int(back["guard_states"][2]), EventBus.GuardState.CALM)
	assert_eq(int(back["interactable_charges"][900]), 2)
	assert_false(bool(back["light_states"][5]))
	assert_true(bool(back["light_states"][6]))
	assert_almost_eq(float(back["a11y_prefs"]["text_scale"]), 1.25, 0.0001)


# =============================================================================
# SAV-S2 — write_slot / read_slot (async, manual slots)
# =============================================================================
func test_write_read_slot_roundtrip() -> void:
	var path: String = _sm.slot_path(1)
	assert_false(FileAccess.file_exists(path), "fixture precondition: slot 1 is empty")

	_sm.write_slot(1, {
		"checkpoint_id": "manual_1",
		"player_pose": {"pos": Vector3(7.0, 0.0, -3.5), "facing": 0.75, "gait": 2},
		"suspicion": {4: 12.5},
		"guard_states": {4: EventBus.GuardState.SUSPICIOUS},
		"interactable_charges": {910: 3},
		"light_states": {11: true},
	})

	# GDD §6: write_slot returns IMMEDIATELY; the disk hit is deferred.
	assert_false(FileAccess.file_exists(path),
		"write_slot must return before the disk write (async, non-blocking)")
	assert_eq(_save_events.size(), 0, "save_completed must not fire synchronously")

	assert_true(await wait_for_signal(_bus.save_completed, SIGNAL_TIMEOUT),
		"save_completed must fire after the deferred flush")
	assert_eq(_save_events.size(), 1, "exactly one save_completed for one write")
	assert_eq(_save_events[0]["slot_id"], 1)
	assert_true(_save_events[0]["success"], "a valid manual-slot write must report success")
	assert_true(FileAccess.file_exists(path), "the slot file must exist after the flush")
	assert_true(_sm.last_slot_size_bytes <= SaveManagerScript.SLOT_SIZE_BUDGET_BYTES,
		"@ci:save-size-budget — a slot must stay within 32 KB (got %d)"
			% _sm.last_slot_size_bytes)

	var slot: Dictionary = _sm.read_slot(1)
	assert_true(await wait_for_signal(_bus.load_completed, SIGNAL_TIMEOUT),
		"load_completed must fire after read_slot")
	assert_eq(_load_events.size(), 1)
	assert_eq(_load_events[0]["slot_id"], 1)
	assert_true(_load_events[0]["success"])

	assert_false(slot.is_empty(), "read_slot must return the stored slot")
	assert_eq(int(slot["version"]), SaveManagerScript.SAVE_VERSION)
	assert_eq(int(slot["slot_id"]), 1)
	assert_false(bool(slot["is_checkpoint"]), "manual slots are not checkpoints")
	assert_eq(str(slot["checkpoint_id"]), "manual_1")
	assert_eq(slot["player_pose"]["pos"], Vector3(7.0, 0.0, -3.5))
	assert_almost_eq(float(slot["suspicion"][4]), 12.5, 0.0001)
	assert_eq(int(slot["guard_states"][4]), EventBus.GuardState.SUSPICIOUS)
	assert_eq(int(slot["interactable_charges"][910]), 3)
	assert_true(bool(slot["light_states"][11]))
	assert_false(_sm.is_slot_corrupt(1), "a clean roundtrip must not mark the slot corrupt")

	# Slot-id domain: -1 plus 0..MAX_MANUAL_SLOTS-1, nothing else.
	assert_eq(SaveManagerScript.MAX_MANUAL_SLOTS, 3)
	assert_true(SaveManagerScript.is_valid_slot_id(SaveManagerScript.CHECKPOINT_SLOT_ID))
	assert_true(SaveManagerScript.is_valid_slot_id(2))
	assert_false(SaveManagerScript.is_valid_slot_id(3),
		"slot 3 is out of range for MAX_MANUAL_SLOTS=3")


func test_checkpoint_write_cooldown_0_5s() -> void:
	assert_true(SaveManagerScript.CHECKPOINT_WRITE_COOLDOWN >= 0.5,
		"GDD §6 floors the checkpoint write cooldown at 0.5s")
	assert_eq(SaveManagerScript.CHECKPOINT_SLOT_ID, -1)

	var cp: int = SaveManagerScript.CHECKPOINT_SLOT_ID
	_sm.write_slot(cp, {"checkpoint_id": "cp_a"})
	# Same frame, same checkpoint volume: this is the "写每帧" case the cooldown
	# exists to kill.
	_sm.write_slot(cp, {"checkpoint_id": "cp_b"})

	assert_true(await wait_for_signal(_bus.save_completed, SIGNAL_TIMEOUT),
		"the first checkpoint write must complete")
	assert_eq(_sm.checkpoint_write_count, 1,
		"a second checkpoint write inside the cooldown must NOT reach the disk")
	assert_eq(_save_events.size(), 2,
		"the throttled write must still be reported, never silently dropped")
	assert_true(_save_events[0]["success"], "first checkpoint write succeeds")
	assert_false(_save_events[1]["success"],
		"the throttled write reports success=false")
	assert_eq(_save_events[1]["slot_id"], cp)

	# The cached checkpoint must still be the FIRST one — the throttled call may
	# not clobber it.
	_sm.restore_checkpoint()
	assert_true(await wait_for_signal(_bus.checkpoint_restored, SIGNAL_TIMEOUT))
	assert_eq(_restored_events[-1], "cp_a",
		"the throttled write must not overwrite the rolling checkpoint")

	# Once the cooldown has elapsed the next write goes through again.
	_sm._last_checkpoint_write_ms -= int(SaveManagerScript.CHECKPOINT_WRITE_COOLDOWN * 1000.0) + 100
	_sm.write_slot(cp, {"checkpoint_id": "cp_c"})
	assert_true(await wait_for_signal(_bus.save_completed, SIGNAL_TIMEOUT))
	assert_eq(_sm.checkpoint_write_count, 2,
		"after the cooldown elapses the checkpoint slot is writable again")
	assert_true(_save_events[-1]["success"])


# =============================================================================
# SAV-S3 — restore_checkpoint + the D9 seam
# =============================================================================
func test_checkpoint_sink_arity_contract() -> void:
	# ★ FLAG-A mitigation ②. This test and test_patrol_ai.gd:413's reverse
	# assertion are a PAIR: they lock both sides of the seam to the same arity.
	# Changing one without the other is exactly the batchd-R7 / N-8 drift.

	# ① The DECLARED arity of the sink target is zero.
	var declared: int = _declared_arg_count(SaveManagerScript, "restore_checkpoint")
	assert_eq(declared, 0,
		"FLAG-A(a): SaveManager.restore_checkpoint must stay ZERO-ARG (got %d)" % declared)

	# ② The bound Callable agrees with the declaration.
	var sink := Callable(_sm, "restore_checkpoint")
	assert_true(sink.is_valid(), "restore_checkpoint must be a valid Callable target")
	assert_eq(sink.get_argument_count(), 0,
		"the injected Callable must take zero arguments")

	# ③ The ACTUAL arg count at the real call site (patrol_ai.gd `_checkpoint_sink
	#    .call()`) must equal the declared arity.
	var brain := _make_brain(42)
	brain.set_checkpoint_sink(_probe_sink)
	_soft_fail(brain)
	assert_eq(_probe_calls, 1, "soft fail must invoke the checkpoint sink exactly once")
	assert_eq(_probe_actual_args, declared,
		"args passed at the call site (%d) must equal restore_checkpoint's arity (%d)"
			% [_probe_actual_args, declared])

	# ④ End to end with the REAL sink: the zero-arg call actually restores.
	_sm.write_slot(SaveManagerScript.CHECKPOINT_SLOT_ID, {"checkpoint_id": "cp_arity"})
	assert_true(await wait_for_signal(_bus.save_completed, SIGNAL_TIMEOUT))

	var brain2 := _make_brain(43)
	brain2.set_checkpoint_sink(sink)
	_soft_fail(brain2)
	assert_true(await wait_for_signal(_bus.checkpoint_restored, SIGNAL_TIMEOUT),
		"the zero-arg seam must drive a real restore end to end")
	assert_eq(_restored_events[-1], "cp_arity")


func test_restore_resets_suspicion_and_guards() -> void:
	_sm.write_slot(SaveManagerScript.CHECKPOINT_SLOT_ID, {
		"checkpoint_id": "cp_cistern_01",
		"player_pose": {"pos": Vector3(3.0, 0.0, 4.0), "facing": 0.5, "gait": 0},
		"suspicion": {1: 80.0, 2: 35.0},
		"guard_states": {1: EventBus.GuardState.ALERT, 2: EventBus.GuardState.SEARCH},
		"interactable_charges": {900: 1},
		"light_states": {5: false, 6: true},
	})
	assert_true(await wait_for_signal(_bus.save_completed, SIGNAL_TIMEOUT))
	assert_true(_sm.has_checkpoint(), "a written checkpoint must be reported as available")

	_sm.restore_checkpoint()
	assert_true(await wait_for_signal(_bus.checkpoint_restored, SIGNAL_TIMEOUT),
		"restore must broadcast checkpoint_restored")
	assert_eq(_restored_events.size(), 1, "exactly one checkpoint_restored per restore")
	assert_eq(_restored_events[0], "cp_cistern_01",
		"checkpoint_restored must carry the checkpoint id")

	var st: Dictionary = _sm.restored_state
	assert_false(st.is_empty(), "restore must publish the restored world snapshot")

	# GDD §2: suspicion is zeroed and every known guard goes back to RETURN.
	assert_almost_eq(float(st["suspicion"][1]), 0.0, 0.0001,
		"restoring a checkpoint must zero suspicion")
	assert_almost_eq(float(st["suspicion"][2]), 0.0, 0.0001)
	assert_eq(int(st["guard_states"][1]), EventBus.GuardState.RETURN,
		"an ALERT guard must fall back to RETURN after a restore")
	assert_eq(int(st["guard_states"][2]), EventBus.GuardState.RETURN,
		"a SEARCH guard must fall back to RETURN after a restore")

	# World diff state comes back verbatim.
	assert_eq(st["player_pose"]["pos"], Vector3(3.0, 0.0, 4.0))
	assert_almost_eq(float(st["player_pose"]["facing"]), 0.5, 0.0001)
	assert_eq(int(st["interactable_charges"][900]), 1)
	assert_false(bool(st["light_states"][5]), "an extinguished light stays extinguished")
	assert_true(bool(st["light_states"][6]))


# =============================================================================
# SAV-S4 — field-agnostic preference delegation + one-time a11y.cfg migration
# =============================================================================
func test_prefs_delegation_roundtrip() -> void:
	# ① The API is a generic section->Dictionary store: a NON-a11y section must
	#    round-trip with no code change (GDD §2「其他 L2 偏好同机制扩展」).
	_sm.save_prefs("audio", {"master": 0.8, "muted": true})
	var audio: Dictionary = _sm.load_prefs("audio")
	assert_almost_eq(float(audio["master"]), 0.8, 0.0001)
	assert_true(bool(audio["muted"]))
	assert_true(FileAccess.file_exists(_sm.get_prefs_path()),
		"prefs must land in the configured prefs file")
	assert_eq(_sm.get_prefs_path(), TEST_PREFS_PATH,
		"the test must be writing to the ISOLATED prefs path")

	# ② FLAG-J: SaveManager must not hardcode a single a11y field name, or
	#    SAV-S4 <-> E09-S7 becomes a cycle and Batch A cannot exit alone.
	var src_text := FileAccess.get_file_as_string("res://src/core/save_manager.gd")
	assert_ne(src_text, "", "save_manager.gd must be readable for the FLAG-J scan")
	for field in A11Y_FIELD_NAMES:
		assert_false(src_text.contains(field),
			"FLAG-J: save_manager.gd must not mention the a11y field `%s`" % field)

	# ③ A11ySettings persists THROUGH SaveManager, not ConfigFile.
	#    Asserted at source level rather than by probing user://a11y.cfg — that
	#    file may legitimately exist on a developer machine and this suite must
	#    never depend on (or touch) it.
	var a11y_src := FileAccess.get_file_as_string("res://src/core/a11y_settings.gd")
	assert_ne(a11y_src, "", "a11y_settings.gd must be readable")
	assert_false(a11y_src.contains("ConfigFile"),
		"A11ySettings must delegate to SaveManager, not use ConfigFile directly")
	assert_true(a11y_src.contains("save_prefs") and a11y_src.contains("load_prefs"),
		"A11ySettings must persist through the SaveManager prefs API")

	var a := A11ySettings.new()
	autofree(a)
	a.set_save_manager(_sm)
	a.color_blind_mode = "DEUTERANO"
	a.text_scale = 1.25
	a.screen_shake = true
	a.save()

	var b := A11ySettings.new()
	autofree(b)
	b.set_save_manager(_sm)
	b.load()
	assert_eq(b.color_blind_mode, "DEUTERANO")
	assert_almost_eq(b.text_scale, 1.25, 0.0001)
	assert_true(b.screen_shake)

	# ④ Missing fields fall back to defaults (forward/backward compatible).
	_sm.save_prefs("a11y", {"text_scale": 1.5})
	var c := A11ySettings.new()
	autofree(c)
	c.set_save_manager(_sm)
	c.load()
	assert_almost_eq(c.text_scale, 1.5, 0.0001)
	assert_eq(c.color_blind_mode, "OFF",
		"a key absent from the store must fall back to the default")
	assert_false(c.motion_blur, "V-05 default survives a partial prefs payload")


func test_legacy_a11y_cfg_migrated_once() -> void:
	# Fabricate a FAKE legacy file at the isolated path. The developer's real
	# user://a11y.cfg is never read and never deleted by this test.
	var cfg := ConfigFile.new()
	cfg.set_value("a11y", "color_blind_mode", "TRITANO")
	cfg.set_value("a11y", "text_scale", 1.4)
	# A second section proves the migration walks get_sections() generically
	# instead of knowing anything about a11y (FLAG-J).
	cfg.set_value("audio", "master", 0.5)
	assert_eq(cfg.save(TEST_LEGACY_CFG), OK, "test fixture: legacy cfg must be writable")
	assert_true(FileAccess.file_exists(TEST_LEGACY_CFG))
	assert_false(_sm.legacy_a11y_migrated, "migration must not run before the first read")

	var migrated: Dictionary = _sm.load_prefs("a11y")
	assert_eq(str(migrated["color_blind_mode"]), "TRITANO",
		"legacy a11y values must survive into the prefs store")
	assert_almost_eq(float(migrated["text_scale"]), 1.4, 0.0001)
	assert_almost_eq(float(_sm.load_prefs("audio")["master"]), 0.5, 0.0001,
		"migration must be section-agnostic, not a11y-specific")
	assert_true(_sm.legacy_a11y_migrated, "the migration must be recorded")
	assert_true(FileAccess.file_exists(TEST_PREFS_PATH),
		"migrated preferences must be persisted to prefs.json")

	# ONCE: the legacy file is consumed, so nothing can migrate a second time.
	assert_false(FileAccess.file_exists(TEST_LEGACY_CFG),
		"the legacy a11y.cfg must be deleted after a successful migration")

	# A newer value must not be clobbered by a re-run.
	_sm.save_prefs("a11y", {"color_blind_mode": "OFF"})
	var sm2: Node = add_child_autofree(SaveManagerScript.new())
	sm2.set_event_bus(_bus)
	sm2.configure_paths(TEST_SAVE_DIR, TEST_PREFS_PATH, TEST_LEGACY_CFG)
	assert_eq(str(sm2.load_prefs("a11y")["color_blind_mode"]), "OFF",
		"a second boot must read the store, not re-import the legacy file")
	assert_false(sm2.legacy_a11y_migrated, "migration must run exactly once")


# =============================================================================
# SAV-S6 — version rejection + corruption (never crash, never swallow)
# =============================================================================
func test_version_mismatch_rejected_not_crash() -> void:
	# NOTE: this test intentionally triggers push_error() — the ERROR line in the
	# log is the proof of「绝不静默吞错」, not a failure.
	var path: String = _sm.slot_path(0)
	var stale := "{\"version\":1,\"slot_id\":0,\"is_checkpoint\":false,\"timestamp\":1.0,\"checkpoint_id\":\"v1_legacy\"}"
	_write_raw(path, stale)

	var slot: Dictionary = _sm.read_slot(0)
	assert_true(slot.is_empty(),
		"a slot whose version != SAVE_VERSION must be rejected, not partially parsed")

	assert_true(await wait_for_signal(_bus.load_completed, SIGNAL_TIMEOUT),
		"a rejected read must still report load_completed")
	assert_eq(_load_events.size(), 1)
	assert_eq(_load_events[0]["slot_id"], 0)
	assert_false(_load_events[0]["success"],
		"load_completed must carry success=false so ⑧ can surface 「存档版本不匹配」")

	assert_true(_sm.is_slot_corrupt(0), "the slot must be MARKED, not silently skipped")
	assert_eq(_sm.get_corrupt_reason(0), SaveManagerScript.REASON_VERSION_MISMATCH)

	# GDD §6: never overwrite a rejected slot back.
	assert_eq(FileAccess.get_file_as_string(path), stale,
		"a rejected slot file must be left byte-for-byte untouched")

	# GDD §2: v1 is reject-and-rebuild, NOT migrate.
	assert_false(_sm.has_checkpoint(),
		"a rejected manual slot must not masquerade as a usable checkpoint")


func test_corrupt_json_rejected_not_swallowed() -> void:
	# NOTE: intentionally triggers push_error() — see the note above.
	var path: String = _sm.slot_path(2)
	var garbage := "{ this is not json at all ]]"
	_write_raw(path, garbage)

	var slot: Dictionary = _sm.read_slot(2)
	assert_true(slot.is_empty(), "unparseable JSON must yield no slot")

	assert_true(await wait_for_signal(_bus.load_completed, SIGNAL_TIMEOUT))
	assert_eq(_load_events.size(), 1)
	assert_eq(_load_events[0]["slot_id"], 2)
	assert_false(_load_events[0]["success"])

	assert_true(_sm.is_slot_corrupt(2), "a corrupt slot must be flagged")
	assert_eq(_sm.get_corrupt_reason(2), SaveManagerScript.REASON_PARSE_FAILED)
	assert_eq(FileAccess.get_file_as_string(path), garbage,
		"a corrupt slot must never be overwritten back")

	# And the process is still perfectly usable afterwards — no crash, no
	# poisoned state: a clean write/read on another slot still works.
	_sm.write_slot(1, {"checkpoint_id": "still_alive"})
	assert_true(await wait_for_signal(_bus.save_completed, SIGNAL_TIMEOUT))
	assert_true(_save_events[-1]["success"],
		"a corrupt slot must not poison unrelated slots")
	var ok_slot: Dictionary = _sm.read_slot(1)
	assert_eq(str(ok_slot["checkpoint_id"]), "still_alive")
	assert_false(_sm.is_slot_corrupt(1))
