# tests/unit/test_save_ui.gd
# GUT tests for E11 · SAV-S5 手动存档/读档 UI — Sprint 3, Batch B (S3-B).
#
# Units under test:
#   src/ui/save_ui_model.gd      pure decision layer (SCR_SLOTS / SCR_CONFIRM)
#   src/ui/save_slots_screen.gd  CanvasLayer view + bus wiring
#   src/core/save_manager.gd     O-3 atomic slot write (the only production
#                                behaviour this batch changes)
#
# ── Why so much of this is assertable at all ────────────────────────────────
# Every rule the save screen enforces lives in SaveUiModel as a pure function
# over plain data, so "which row is focused", "may I delete this", "what does
# the confirm dialog say" and "how long may a busy state last" are all decided
# without a viewport. CI has no pixels; a screen whose rules live in _draw()
# can only be eyeballed, and eyeballs do not run on pull requests.
#
# ★ TEST ISOLATION (sprint2-stories.md §4「SaveManager 测试隔离」) ★
#   Nothing here touches the real user://saves/ or user://prefs.json. Every
#   manager under test is re-pointed at user://__test_saveui/ via
#   configure_paths() and that directory is purged before AND after each test.
#   The purge removes DIRECTORIES too, because one test deliberately creates a
#   directory where a staging file belongs (see the note on that test).
#
# ★ EXPECTED ERROR OUTPUT ★
#   test_failed_write_leaves_the_previous_slot_intact drives SaveManager's
#   staging-write failure path on purpose, which calls push_error(). The ERROR
#   lines it prints are the PROOF that the failure was reported rather than
#   swallowed (GDD §6「绝不静默吞错」) — they are not test failures.
#
# ★ N-7 (CI gate G4) ★
#   Every test below is a normal `func test_*` with at least one assertion, and
#   this file emits no GUT risky/pending token of any kind, so the N-7 gate
#   regex in .github/workflows/ci.yml cannot match it.
#
# Run: godot --headless -s res://addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit

extends GutTest

const SaveUiModelScript = preload("res://src/ui/save_ui_model.gd")
const SaveSlotsScreenScript = preload("res://src/ui/save_slots_screen.gd")
const SaveManagerScript = preload("res://src/core/save_manager.gd")
const HudColorsScript = preload("res://src/ui/hud_colors.gd")
const EventBus = preload("res://src/core/event_bus.gd")

const TEST_SAVE_DIR := "user://__test_saveui/"
const TEST_PREFS_PATH := "user://__test_saveui_prefs.json"

const SIGNAL_TIMEOUT := 1.0

# A fixed instant so the timestamp assertions compare against a STRING the test
# computes the same way the UI does, instead of against a clock.
const FIXED_TS := 1_700_000_000.0

# ── Accessibility gates (docs/architecture/control-manifest.md v0.2) ────────
const C01_MIN := 4.5
const C02_MIN := 7.0
const C03_MIN := 3.0
# V-01: no periodic modulation above 3Hz anywhere in the UI.
const V01_MAX_HZ := 3.0


var _bus: EventBus
var _sm: Node

var _save_events: Array = []
var _load_events: Array = []

# Injected sinks — the screen has no outgoing signal (E01-S9 freeze), so this
# is how its side effects are observed.
var _subtitles: Array = []
var _cues: Array = []
var _closes: int = 0


func before_all() -> void:
	DirAccess.make_dir_recursive_absolute(TEST_SAVE_DIR)


func after_all() -> void:
	_purge_test_files()
	DirAccess.remove_absolute(TEST_SAVE_DIR)


func before_each() -> void:
	_purge_test_files()

	_bus = autofree(EventBus.new())
	_sm = SaveManagerScript.new()
	add_child_autofree(_sm)
	_sm.set_event_bus(_bus)
	_sm.configure_paths(TEST_SAVE_DIR, TEST_PREFS_PATH)

	_save_events = []
	_load_events = []
	_subtitles = []
	_cues = []
	_closes = 0

	_bus.save_completed.connect(_on_save)
	_bus.load_completed.connect(_on_load)


func after_each() -> void:
	_purge_test_files()
	_bus = null
	_sm = null


# ---- ledger sinks -----------------------------------------------------------
func _on_save(slot_id: int, success: bool) -> void:
	_save_events.append({"slot_id": slot_id, "success": success})


func _on_load(slot_id: int, success: bool) -> void:
	_load_events.append({"slot_id": slot_id, "success": success})


func _sink_subtitle(speaker: String, line: String) -> void:
	_subtitles.append({"speaker": speaker, "line": line})


func _sink_audio(cue: String, gain_db: float) -> void:
	_cues.append({"cue": cue, "gain_db": gain_db})


func _sink_close() -> void:
	_closes += 1


func _provide_snapshot() -> Dictionary:
	return {"timestamp": FIXED_TS, "checkpoint_id": "cp_test"}


# ---- helpers ----------------------------------------------------------------
## Removes files AND directories. One test parks a directory on a staging path
## to force an IO failure; a file-only purge would leak it into the next test.
func _purge_test_files() -> void:
	var d := DirAccess.open(TEST_SAVE_DIR)
	if d != null:
		d.list_dir_begin()
		var n := d.get_next()
		while n != "":
			d.remove(n)
			n = d.get_next()
		d.list_dir_end()
	if FileAccess.file_exists(TEST_PREFS_PATH):
		DirAccess.remove_absolute(TEST_PREFS_PATH)


func _write_raw(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(TEST_SAVE_DIR)
	var f := FileAccess.open(path, FileAccess.WRITE)
	assert_not_null(f, "test fixture must be writable: %s" % path)
	if f == null:
		return
	f.store_string(text)
	f.close()


## Build the 4-row skeleton and fill the slots named in `fill` (keyed by
## slot_id, NOT by row index — the two numbering systems are exactly what the
## model exists to keep apart).
func _make_rows(fill: Dictionary) -> Array:
	var rows: Array = SaveUiModelScript.blank_rows()
	for i in range(rows.size()):
		var slot_id := int(rows[i]["slot_id"])
		if not fill.has(slot_id):
			continue
		var spec: Dictionary = fill[slot_id]
		rows[i]["status"] = int(spec.get("status", SaveUiModelScript.RowStatus.FILLED))
		rows[i]["timestamp"] = float(spec.get("timestamp", FIXED_TS))
		rows[i]["checkpoint_id"] = str(spec.get("checkpoint_id", ""))
		rows[i]["reason"] = str(spec.get("reason", ""))
	return rows


func _open(mode: int, fill: Dictionary) -> SaveUiModelScript:
	var m := SaveUiModelScript.new()
	m.open(mode, _make_rows(fill))
	return m


## Screen wired to this test's bus + isolated SaveManager, with _process OFF so
## the suite drives animation deterministically instead of racing a real clock.
func _make_screen() -> SaveSlotsScreenScript:
	var s := SaveSlotsScreenScript.new()
	s.set_event_bus(_bus)
	s.set_save_manager(_sm)
	s.set_snapshot_provider(_provide_snapshot)
	s.set_subtitle_sink(_sink_subtitle)
	s.set_audio_sink(_sink_audio)
	s.set_close_sink(_sink_close)
	add_child_autofree(s)
	s.set_process(false)
	return s


## Every bus signal this object is subscribed to, sorted. Used as a reverse
## lock on the E01-S9 vocabulary freeze.
func _subscriptions_of(who: Object) -> Array:
	var names: Array = []
	for sig in _bus.get_signal_list():
		var sname := str(sig["name"])
		for c in _bus.get_signal_connection_list(sname):
			var cb: Callable = c["callable"]
			if cb.get_object() == who:
				names.append(sname)
	names.sort()
	return names


# =============================================================================
# O-3 — atomic slot write
# =============================================================================
func test_slot_write_goes_through_a_staging_file_and_cleans_up() -> void:
	var tmp: String = _sm.slot_tmp_path(0)
	assert_ne(tmp, _sm.slot_path(0),
		"the staging path must not BE the slot path, or there is nothing atomic about it")
	assert_true(tmp.begins_with(_sm.slot_path(0)),
		"staging is derived from slot_path() so the two cannot drift onto different dirs")

	_sm.write_slot(0, {"checkpoint_id": "cp_a", "timestamp": FIXED_TS})
	assert_true(await wait_for_signal(_bus.save_completed, SIGNAL_TIMEOUT),
		"write_slot must report completion on the bus")
	assert_true(bool(_save_events[0]["success"]), "a normal write succeeds")

	assert_true(FileAccess.file_exists(_sm.slot_path(0)), "the slot must exist after a write")
	assert_false(FileAccess.file_exists(tmp),
		"a successful write leaves no staging litter for later triage to misread")

	var text := FileAccess.get_file_as_string(_sm.slot_path(0))
	assert_true(text.begins_with("{\"version\":2"),
		"the promoted file is a COMPLETE document, version-first; got: %s" % text.substr(0, 40))


## ★ REVERSE ASSERTION (O-3). A write that fails must leave the PREVIOUS save
## byte-for-byte readable. The Sprint 2 implementation could not keep this
## promise: it opened the destination with FileAccess.WRITE, which truncates
## before the first byte lands, so any interruption turned a good save into a
## half-JSON file that read_slot() then rejected as corrupt.
##
## The failure is forced by parking a DIRECTORY on the staging path — opening a
## directory for writing fails on every platform CI runs on, which reproduces
## "the staging write could not complete" without needing to kill the process.
func test_failed_write_leaves_the_previous_slot_intact() -> void:
	_sm.write_slot(0, {"checkpoint_id": "cp_before", "timestamp": FIXED_TS})
	assert_true(await wait_for_signal(_bus.save_completed, SIGNAL_TIMEOUT))
	assert_true(bool(_save_events[0]["success"]), "the first write must land")

	var tmp: String = _sm.slot_tmp_path(0)
	assert_eq(DirAccess.make_dir_absolute(tmp), OK,
		"fixture: a directory must be creatable on the staging path")

	_sm.write_slot(0, {"checkpoint_id": "cp_after", "timestamp": FIXED_TS + 60.0})
	assert_true(await wait_for_signal(_bus.save_completed, SIGNAL_TIMEOUT))
	var last: Dictionary = _save_events[_save_events.size() - 1]
	assert_false(bool(last["success"]),
		"a staging write that cannot open must be reported as failure, never swallowed")

	# ★ The point of the whole exercise.
	var after: Dictionary = _sm.read_slot(0)
	assert_false(after.is_empty(), "the previous slot must still be READABLE after a failed write")
	assert_eq(str(after.get("checkpoint_id", "")), "cp_before",
		"the previous slot must still hold its ORIGINAL content (UX spec EC-7)")
	assert_eq(_sm.get_corrupt_reason(0), "",
		"a failed write must not leave the slot marked corrupt")
	assert_true(await wait_for_signal(_bus.load_completed, SIGNAL_TIMEOUT))

	DirAccess.remove_absolute(tmp)


## A staging file left behind by a killed process is INERT: it is not the slot,
## so it cannot make a good slot unreadable no matter how truncated it is.
func test_leftover_partial_staging_file_cannot_corrupt_a_good_slot() -> void:
	_sm.write_slot(1, {"checkpoint_id": "cp_good", "timestamp": FIXED_TS})
	assert_true(await wait_for_signal(_bus.save_completed, SIGNAL_TIMEOUT))

	# Half a JSON document, exactly what a power cut used to leave IN the slot.
	_write_raw(_sm.slot_tmp_path(1), "{\"version\":2,\"slot_id\":1,\"is_che")

	var slot: Dictionary = _sm.read_slot(1)
	assert_false(slot.is_empty(), "a truncated staging file must not shadow the real slot")
	assert_eq(str(slot.get("checkpoint_id", "")), "cp_good",
		"the slot still reads back as the complete document that was promoted")
	assert_true(await wait_for_signal(_bus.load_completed, SIGNAL_TIMEOUT))
	assert_true(bool(_load_events[_load_events.size() - 1]["success"]))


## ★ REVERSE LOCK, static. The whole guarantee collapses the moment anyone
## re-introduces a truncating open on the destination, and that regression is
## invisible at runtime until a player loses a save. So the source itself is
## asserted: the destination is written ONLY through the staging + rename pair.
func test_slot_destination_is_never_opened_for_truncating_write() -> void:
	var src := FileAccess.get_file_as_string("res://src/core/save_manager.gd")
	assert_ne(src, "", "fixture: save_manager.gd must be readable")
	assert_false(src.contains("FileAccess.open(slot_path("),
		"the slot path must never be opened directly — WRITE truncates it before the bytes land")
	assert_true(src.contains("slot_tmp_path("), "the staging path helper must exist and be used")
	assert_true(src.contains("DirAccess.rename_absolute("),
		"promotion to the real slot must happen through a rename, not a second write")


# =============================================================================
# SCR_SLOTS — list shape and focus
# =============================================================================
func test_list_is_one_readonly_checkpoint_row_plus_three_manual_slots() -> void:
	var rows: Array = SaveUiModelScript.blank_rows()
	assert_eq(rows.size(), 4, "1 checkpoint row + MAX_MANUAL_SLOTS manual rows")
	assert_eq(rows.size(), SaveUiModelScript.ROW_COUNT)
	assert_eq(int(rows[0]["slot_id"]), SaveManagerScript.CHECKPOINT_SLOT_ID,
		"row 0 is the auto checkpoint")
	assert_true(bool(rows[0]["readonly"]), "the checkpoint row is read-only")
	for i in range(1, rows.size()):
		assert_eq(int(rows[i]["slot_id"]), i - 1, "manual slots are 0..2 in row order")
		assert_false(bool(rows[i]["readonly"]), "manual slots are writeable")

	# 1-based on screen, 0-based inside — the mapping lives in one function.
	assert_eq(SaveUiModelScript.row_label(rows[0]), SaveUiModelScript.LABEL_CHECKPOINT)
	assert_eq(SaveUiModelScript.row_label(rows[1]), "槽 1", "slot_id 0 displays as 槽 1")
	assert_eq(SaveUiModelScript.row_label(rows[3]), "槽 3")


func test_save_mode_focus_never_starts_on_the_readonly_row() -> void:
	var m := _open(SaveUiModelScript.Mode.SAVE, {})
	assert_eq(m.focus_index(), SaveUiModelScript.FIRST_MANUAL_ROW,
		"opening 存档 on the one row you can never save to is a trap")
	assert_true(m.is_action_enabled(SaveUiModelScript.Action.PRIMARY),
		"the default focus must be a row the primary action actually works on")


func test_load_mode_focus_starts_on_the_most_recent_save() -> void:
	var m := _open(SaveUiModelScript.Mode.LOAD, {
		0: {"timestamp": FIXED_TS},
		2: {"timestamp": FIXED_TS + 3600.0},
	})
	assert_eq(m.focus_index(), 3, "slot 2 is newer, so 读档 lands there")
	assert_true(m.is_action_enabled(SaveUiModelScript.Action.PRIMARY))


func test_focus_wraps_and_can_still_reach_the_checkpoint_row() -> void:
	var m := _open(SaveUiModelScript.Mode.SAVE, {})
	assert_eq(m.focus_index(), 1)
	m.move_focus(-1)
	assert_eq(m.focus_index(), SaveUiModelScript.CHECKPOINT_ROW,
		"the read-only row is focusable so its timestamp can be read and spoken")
	m.move_focus(-1)
	assert_eq(m.focus_index(), 3, "navigation wraps")
	m.move_focus(1)
	assert_eq(m.focus_index(), 0)


# =============================================================================
# 「禁用不等于沉默」— every refusal carries a reason
# =============================================================================
func test_empty_slot_refuses_load_and_delete_with_a_stated_reason() -> void:
	var m := _open(SaveUiModelScript.Mode.LOAD, {})
	assert_false(m.is_action_enabled(SaveUiModelScript.Action.PRIMARY))
	assert_eq(m.action_denial(SaveUiModelScript.Action.PRIMARY),
		SaveUiModelScript.DENY_EMPTY_LOAD)
	assert_false(m.is_action_enabled(SaveUiModelScript.Action.DELETE))
	assert_eq(m.action_denial(SaveUiModelScript.Action.DELETE),
		SaveUiModelScript.DENY_EMPTY_DELETE)

	var intent: Dictionary = m.press_primary()
	assert_eq(str(intent["op"]), "deny", "a refused press is an EVENT, not a no-op")
	assert_ne(str(intent["reason"]), "", "the refusal must carry its reason to the view")
	assert_eq(m.denial_hint(), SaveUiModelScript.DENY_EMPTY_LOAD)

	# Moving the cursor answers the refusal; a stale hint would point at a row
	# it no longer describes.
	m.move_focus(1)
	assert_eq(m.denial_hint(), "")


func test_checkpoint_row_refuses_every_action_with_its_own_reason() -> void:
	var save_m := _open(SaveUiModelScript.Mode.SAVE, {-1: {"checkpoint_id": "cp_1"}})
	save_m.set_focus(SaveUiModelScript.CHECKPOINT_ROW)
	assert_eq(save_m.action_denial(SaveUiModelScript.Action.PRIMARY),
		SaveUiModelScript.DENY_CHECKPOINT_SAVE)
	assert_eq(save_m.action_denial(SaveUiModelScript.Action.DELETE),
		SaveUiModelScript.DENY_CHECKPOINT_DELETE)
	# 返回 is never refused — a menu you cannot leave is a bug, not a rule.
	assert_true(save_m.is_action_enabled(SaveUiModelScript.Action.CANCEL))

	var load_m := _open(SaveUiModelScript.Mode.LOAD, {-1: {"checkpoint_id": "cp_1"}})
	load_m.set_focus(SaveUiModelScript.CHECKPOINT_ROW)
	assert_eq(load_m.action_denial(SaveUiModelScript.Action.PRIMARY),
		SaveUiModelScript.DENY_CHECKPOINT_LOAD)
	assert_ne(SaveUiModelScript.DENY_CHECKPOINT_LOAD, SaveUiModelScript.DENY_CHECKPOINT_SAVE,
		"the two refusals say different things because they ARE different refusals")


func test_corrupt_slot_can_be_overwritten_and_deleted_but_not_loaded() -> void:
	var fill := {1: {
		"status": SaveUiModelScript.RowStatus.CORRUPT,
		"reason": SaveUiModelScript.REASON_CORRUPT_VERSION,
	}}
	var load_m := _open(SaveUiModelScript.Mode.LOAD, fill)
	load_m.set_focus(2)
	assert_eq(load_m.action_denial(SaveUiModelScript.Action.PRIMARY),
		SaveUiModelScript.DENY_CORRUPT_LOAD)
	assert_true(load_m.is_action_enabled(SaveUiModelScript.Action.DELETE),
		"deleting is the player's only way out of a broken save — never refuse it")

	var save_m := _open(SaveUiModelScript.Mode.SAVE, fill)
	save_m.set_focus(2)
	assert_true(save_m.is_action_enabled(SaveUiModelScript.Action.PRIMARY),
		"overwriting a corrupt slot IS the cleanup path")

	# C-05/C-07: the broken state is carried by SHAPE as well as colour.
	var row: Dictionary = load_m.rows()[2]
	assert_eq(SaveUiModelScript.row_thumb_glyph(row), SaveUiModelScript.GLYPH_THUMB_CORRUPT)
	assert_ne(SaveUiModelScript.row_badge(row), "", "a corrupt row must be labelled, not just tinted")


# =============================================================================
# SCR_CONFIRM — the dialog restates the affected object (AC 3)
# =============================================================================
func test_overwrite_confirm_restates_slot_and_timestamp() -> void:
	var m := _open(SaveUiModelScript.Mode.SAVE,
		{1: {"timestamp": FIXED_TS, "checkpoint_id": "cp_atrium"}})
	m.set_focus(2)
	assert_eq(m.primary_confirm_kind(), SaveUiModelScript.ConfirmKind.OVERWRITE)

	var dlg: Dictionary = m.confirm_dialog(SaveUiModelScript.ConfirmKind.OVERWRITE)
	var body := str(dlg["body"])
	assert_eq(int(dlg["slot_id"]), 1)
	assert_true(body.contains("槽 2"), "the dialog must name WHICH slot; got: %s" % body)
	assert_true(body.contains(SaveUiModelScript.format_timestamp(FIXED_TS)),
		"the dialog must show WHAT is about to be destroyed; got: %s" % body)
	assert_true(body.contains("无法找回"), "and must say the loss is permanent; got: %s" % body)


func test_load_confirm_restates_slot_and_warns_about_unsaved_progress() -> void:
	var m := _open(SaveUiModelScript.Mode.LOAD, {2: {"timestamp": FIXED_TS}})
	assert_eq(m.focus_index(), 3)
	# LOAD is always confirmed — it discards unsaved progress even from a
	# pristine slot.
	assert_eq(m.primary_confirm_kind(), SaveUiModelScript.ConfirmKind.LOAD)

	var dlg: Dictionary = m.confirm_dialog(SaveUiModelScript.ConfirmKind.LOAD)
	var body := str(dlg["body"])
	assert_true(body.contains("槽 3"), "the dialog must name the target slot; got: %s" % body)
	assert_true(body.contains(SaveUiModelScript.format_timestamp(FIXED_TS)),
		"the dialog must name the moment it returns to; got: %s" % body)
	assert_true(body.contains("丢失"), "and must state the cost; got: %s" % body)


func test_delete_confirm_restates_slot_and_timestamp() -> void:
	var m := _open(SaveUiModelScript.Mode.SAVE, {0: {"timestamp": FIXED_TS}})
	m.set_focus(1)
	var intent: Dictionary = m.press_delete()
	assert_eq(str(intent["op"]), "confirm", "deletion is never immediate")
	assert_eq(m.confirm_kind(), SaveUiModelScript.ConfirmKind.DELETE)

	var body := str(m.active_confirm_dialog()["body"])
	assert_true(body.contains("槽 1"), "got: %s" % body)
	assert_true(body.contains(SaveUiModelScript.format_timestamp(FIXED_TS)), "got: %s" % body)


func test_destructive_dialogs_default_to_cancel() -> void:
	var m := _open(SaveUiModelScript.Mode.SAVE, {1: {"timestamp": FIXED_TS}})
	m.set_focus(2)
	var kinds := [
		SaveUiModelScript.ConfirmKind.OVERWRITE,
		SaveUiModelScript.ConfirmKind.LOAD,
		SaveUiModelScript.ConfirmKind.DELETE,
	]
	for kind in kinds:
		var dlg: Dictionary = m.confirm_dialog(int(kind))
		assert_eq(str(dlg["default_focus"]), "cancel",
			"the button that does nothing is the one already selected")
		assert_ne(str(dlg["title"]), "", "every destructive dialog has a title")
		assert_ne(str(dlg["confirm_label"]), "确定",
			"the affirmative button names the ACT, so a blind Enter still reads as a choice")


func test_saving_into_an_empty_slot_needs_no_confirmation() -> void:
	var m := _open(SaveUiModelScript.Mode.SAVE, {})
	assert_eq(m.primary_confirm_kind(), SaveUiModelScript.ConfirmKind.NONE,
		"nothing is destroyed, so a prompt would be pure friction")
	var intent: Dictionary = m.press_primary()
	assert_eq(str(intent["op"]), "write")
	assert_eq(int(intent["slot_id"]), 0)
	assert_eq(m.state(), SaveUiModelScript.State.BUSY_WRITING)


func test_cancelling_a_confirm_returns_to_the_row_it_was_about() -> void:
	var m := _open(SaveUiModelScript.Mode.SAVE, {2: {"timestamp": FIXED_TS}})
	m.set_focus(3)
	m.press_primary()
	assert_eq(m.state(), SaveUiModelScript.State.CONFIRMING)
	m.confirm_cancel()
	assert_eq(m.state(), SaveUiModelScript.State.BROWSING)
	assert_eq(m.confirm_kind(), SaveUiModelScript.ConfirmKind.NONE)
	assert_eq(m.focus_index(), 3, "focus returns to the row, not to the top of the list")


# =============================================================================
# Edge cases (UX spec §1.7)
# =============================================================================
## EC-7 — the model half of the promise O-3 keeps on disk.
func test_failed_write_keeps_the_row_showing_its_original_content() -> void:
	var m := _open(SaveUiModelScript.Mode.SAVE,
		{0: {"timestamp": FIXED_TS, "checkpoint_id": "cp_old"}})
	m.set_focus(1)
	m.press_primary()
	m.confirm_accept()
	assert_eq(m.state(), SaveUiModelScript.State.BUSY_WRITING)

	var out: Dictionary = m.on_save_completed(0, false)
	assert_eq(str(out["op"]), "save_failed")
	var row: Dictionary = m.rows()[1]
	assert_eq(int(row["status"]), SaveUiModelScript.RowStatus.FILLED,
		"a failed write must not blank the row")
	assert_almost_eq(float(row["timestamp"]), FIXED_TS, 0.001)
	assert_eq(str(row["checkpoint_id"]), "cp_old")
	assert_false(bool(m.toast()["success"]), "and the failure must be announced")


## EC-3 — a corrupt row stays corrupt after the toast scrolls away. A toast is
## not a record; the next time the player looks they must still see the damage.
func test_failed_load_marks_the_row_corrupt_and_it_stays_corrupt() -> void:
	var m := _open(SaveUiModelScript.Mode.LOAD, {1: {"timestamp": FIXED_TS}})
	assert_eq(m.focus_index(), 2)
	m.press_primary()
	m.confirm_accept()
	assert_eq(m.state(), SaveUiModelScript.State.BUSY_READING)

	var out: Dictionary = m.on_load_completed(1, false, SaveUiModelScript.REASON_CORRUPT_VERSION)
	assert_eq(str(out["op"]), "load_failed")
	assert_eq(int(m.rows()[2]["status"]), SaveUiModelScript.RowStatus.CORRUPT)

	m.tick(SaveUiModelScript.TOAST_SEC + 0.1)
	assert_eq(m.state(), SaveUiModelScript.State.BROWSING)
	assert_true(m.toast().is_empty(), "the toast expires")
	assert_eq(int(m.rows()[2]["status"]), SaveUiModelScript.RowStatus.CORRUPT,
		"the row does NOT expire")
	assert_eq(str(m.rows()[2]["reason"]), SaveUiModelScript.REASON_CORRUPT_VERSION)


## EC-2 — write_slot() is fire-and-forget with no cancel, so silence past the
## budget has to be treated as failure. A UI that can hang is worse than a UI
## that reports a timeout it is not certain about.
func test_busy_state_times_out_instead_of_locking_the_screen() -> void:
	var m := _open(SaveUiModelScript.Mode.SAVE, {})
	m.press_primary()
	assert_true(m.is_input_locked())

	var quiet: Dictionary = m.tick(SaveUiModelScript.BUSY_TIMEOUT_SEC - 0.1)
	assert_eq(str(quiet["op"]), "none", "the budget has not run out yet")
	assert_true(m.is_input_locked())

	var out: Dictionary = m.tick(0.2)
	assert_eq(str(out["op"]), "timeout")
	assert_eq(str(out["reason"]), SaveUiModelScript.REASON_WRITE_TIMEOUT)
	assert_false(m.is_input_locked(), "the player must get their screen back")


## EC-1 — Esc during a locked write is HELD, not dropped. A swallowed cancel
## teaches players the UI is unreliable and they start mashing.
func test_cancel_during_a_write_is_queued_not_swallowed() -> void:
	var m := _open(SaveUiModelScript.Mode.SAVE, {})
	m.press_primary()
	var out: Dictionary = m.press_cancel()
	assert_eq(str(out["op"]), "queued")
	assert_eq(m.state(), SaveUiModelScript.State.BUSY_WRITING, "the write is not interrupted")

	# A second PRIMARY during the lock is DROPPED, though — queueing it would
	# let an impatient double-tap fire a second write at the same slot.
	assert_eq(str(m.press_primary()["op"]), "none")

	m.on_save_completed(0, true, FIXED_TS, "")
	assert_false(m.is_input_locked())
	assert_true(m.take_queued_cancel(), "the deferred cancel still happens")
	assert_false(m.take_queued_cancel(), "but only once")


## EC-10 — tidying up must not cost the player their place in the list.
func test_delete_keeps_the_cursor_on_the_same_row() -> void:
	var m := _open(SaveUiModelScript.Mode.SAVE, {1: {"timestamp": FIXED_TS}})
	m.set_focus(2)
	m.press_delete()
	var out: Dictionary = m.confirm_accept()
	assert_eq(str(out["op"]), "delete", "the view still has to unlink the file")
	assert_eq(int(out["slot_id"]), 1)
	assert_eq(m.focus_index(), 2, "focus stays on the same INDEX, now an empty row")
	assert_eq(int(m.rows()[2]["status"]), SaveUiModelScript.RowStatus.EMPTY)
	assert_eq(m.state(), SaveUiModelScript.State.BROWSING)


# =============================================================================
# Classification + footer guidance
# =============================================================================
func test_peek_row_rejects_a_version_mismatch_before_reading_anything_else() -> void:
	var stale := JSON.stringify({"version": 1, "slot_id": 0, "timestamp": FIXED_TS}, "", false)
	var row: Dictionary = SaveUiModelScript.peek_row(0, stale)
	assert_eq(int(row["status"]), SaveUiModelScript.RowStatus.CORRUPT)
	assert_eq(str(row["reason"]), SaveUiModelScript.REASON_CORRUPT_VERSION)
	assert_almost_eq(float(row["timestamp"]), 0.0, 0.001,
		"nothing below the version gate may be trusted, so nothing below it is read")

	var junk: Dictionary = SaveUiModelScript.peek_row(0, "{not json")
	assert_eq(int(junk["status"]), SaveUiModelScript.RowStatus.CORRUPT)
	assert_eq(str(junk["reason"]), SaveUiModelScript.REASON_CORRUPT_PARSE)

	var missing: Dictionary = SaveUiModelScript.peek_row(0, "")
	assert_eq(int(missing["status"]), SaveUiModelScript.RowStatus.EMPTY,
		"an absent slot is a legal state, not damage")

	var good := JSON.stringify({
		"version": SaveManagerScript.SAVE_VERSION,
		"timestamp": FIXED_TS,
		"checkpoint_id": "cp_ok",
	}, "", false)
	var ok: Dictionary = SaveUiModelScript.peek_row(0, good)
	assert_eq(int(ok["status"]), SaveUiModelScript.RowStatus.FILLED)
	assert_almost_eq(float(ok["timestamp"]), FIXED_TS, 0.001)


func test_load_mode_with_no_manual_saves_says_what_to_do() -> void:
	var m := _open(SaveUiModelScript.Mode.LOAD, {})
	assert_eq(m.footer_notice(), SaveUiModelScript.NOTICE_NO_MANUAL_SAVES,
		"three silent empty rows is a dead end")
	assert_true(m.footer_notice().contains("存档"),
		"the notice must name the way out, not just the problem")


## EC-4 — MAX_MANUAL_SLOTS is hard at 3, so there is no "new slot" path. The cap
## is stated up front instead of being discovered by hunting for a button that
## does not exist.
func test_save_mode_at_the_slot_cap_states_the_overwrite_rule() -> void:
	var full := {
		0: {"timestamp": FIXED_TS},
		1: {"timestamp": FIXED_TS},
		2: {"timestamp": FIXED_TS},
	}
	var m := _open(SaveUiModelScript.Mode.SAVE, full)
	assert_eq(m.footer_notice(), SaveUiModelScript.NOTICE_SLOT_CAP)

	var partial := _open(SaveUiModelScript.Mode.SAVE, {0: {"timestamp": FIXED_TS}})
	assert_eq(partial.footer_notice(), "",
		"the cap notice only appears when the cap actually bites")


# =============================================================================
# Accessibility — contrast + motion, asserted as arithmetic (no pixels)
# =============================================================================
func test_focus_ring_clears_c02_against_the_save_panel() -> void:
	var ratio := SaveUiModelScript.focus_ring_contrast()
	assert_gt(ratio, C02_MIN,
		"a focus ring is a 关键操作指示 and must clear C-02 (>=7:1), got %.2f" % ratio)
	assert_gt(ratio, 10.0, "O-1 Option A claims 10.20:1 on #1B1B1F; got %.2f" % ratio)
	# The colour lives in the palette file, not in the UI code.
	assert_eq(HudColorsScript.HUD_COLOR_FOCUS, Color("#F0C070"),
		"the focus ring hex is signed art (art-bible §9.4)")
	assert_eq(SaveUiModelScript.FOCUS_RING_WIDTH_PX, 2, "2px solid stroke")
	# Why #C8862F was rejected: it clears C-01 but not C-02 on this panel.
	var rejected := HudColorsScript.wcag_contrast(
		HudColorsScript.HUD_COLOR_CAUTION, HudColorsScript.HUD_COLOR_PANEL_SLOT)
	assert_gt(rejected, C01_MIN)
	assert_lt(rejected, C02_MIN,
		"the Caution amber fails C-02 here — that is WHY the ring moved, got %.2f" % rejected)


func test_disabled_carriers_stay_above_c02() -> void:
	var ratio := SaveUiModelScript.disabled_carrier_contrast()
	assert_gt(ratio, C02_MIN,
		"disabled is a licence to be quiet, not to be unreadable; got %.2f" % ratio)
	assert_gt(SaveUiModelScript.carrier_contrast(), C02_MIN, "and enabled text clears it easily")
	assert_gt(SaveUiModelScript.DISABLED_ALPHA, 0.6,
		"a 40-50%% grey would read ~3.7:1 and break C-01")
	assert_eq(SaveUiModelScript.ROW_ALPHA, 1.0,
		"opaque rows are what make every ratio above a fixed, assertable number")


func test_information_boundary_clears_c03() -> void:
	var ratio := SaveUiModelScript.boundary_contrast()
	assert_gt(ratio, C03_MIN,
		"the row/divider stroke is an information boundary (C-03 >=3:1), got %.2f" % ratio)


## V-01: nothing in this screen may modulate faster than 3Hz.
func test_no_animation_channel_exceeds_the_v01_ceiling() -> void:
	var channels: Array = SaveUiModelScript.animation_channels()
	assert_gt(channels.size(), 0, "the channel registry is the audit, not a comment about it")
	for ch in channels:
		assert_lt(float(ch["hz"]), V01_MAX_HZ + 0.001,
			"channel %s runs at %.2fHz, over the V-01 ceiling" % [str(ch["name"]), float(ch["hz"])])
	assert_lt(SaveUiModelScript.max_animation_hz(), V01_MAX_HZ + 0.001)
	assert_eq(SaveUiModelScript.FLICKER_HZ_MAX, V01_MAX_HZ)


## ★ FLAG-L reverse lock. HUD_COLOR_FOCUS and HUD_COLOR_DANGER_CB currently hold
## the SAME hex, so in colour-blind mode a focused corrupt row draws its ring and
## its badge at 1.00:1 hue separation. That is survivable ONLY because neither
## channel depends on hue: the ring is 0Hz and rectangular, the badge beats at
## 2.0Hz behind a solid glyph. Pulsing the ring would erase the frequency channel
## and take C-05's triple coding down with it — this test breaks the build if
## anyone tries.
func test_focus_ring_and_danger_substitute_survive_a_hue_collapse() -> void:
	var separation := HudColorsScript.wcag_contrast(
		HudColorsScript.HUD_COLOR_FOCUS, HudColorsScript.HUD_COLOR_DANGER_CB)
	if separation >= HudColorsScript.DANGER_CB_MIN_SEPARATION:
		# A future ruling re-pointed one of them; the collapse is gone and the
		# hue channel carries the read on its own.
		assert_gt(separation, 1.0, "the two slots are separated by luminance")
		return

	# The collapse is real, so the OTHER two channels must be intact.
	assert_eq(SaveUiModelScript.FOCUS_RING_HZ, 0.0,
		"the focus ring must stay steady — frequency is the channel that survives the collapse")
	assert_gt(SaveUiModelScript.CORRUPT_PULSE_HZ, 0.0,
		"the corrupt badge must keep beating, or the two become indistinguishable")
	assert_ne(SaveUiModelScript.CORRUPT_PULSE_HZ, SaveUiModelScript.FOCUS_RING_HZ)

	var corrupt := SaveUiModelScript.make_row(0)
	corrupt["status"] = SaveUiModelScript.RowStatus.CORRUPT
	var filled := SaveUiModelScript.make_row(1)
	filled["status"] = SaveUiModelScript.RowStatus.FILLED
	assert_ne(SaveUiModelScript.row_thumb_glyph(corrupt), SaveUiModelScript.row_thumb_glyph(filled),
		"shape is the second surviving channel (C-05 triple coding)")
	assert_gt(SaveUiModelScript.FOCUS_ROW_LIFT_ALPHA, 0.0,
		"and the focused row brightens, so focus is legible by luminance alone")


# =============================================================================
# SCR_SLOTS / SCR_LOADFADE — the view half
# =============================================================================
## ★ E01-S9 vocabulary freeze. A whole new UI surface, zero new signals.
func test_screen_declares_no_signals_and_subscribes_to_exactly_three() -> void:
	assert_eq(SaveSlotsScreenScript.get_script_signal_list().size(), 0,
		"the save screen must not mint a signal of its own")
	assert_eq(SaveUiModelScript.get_script_signal_list().size(), 0,
		"and neither may the model — it reports through return values")

	var s := _make_screen()
	assert_eq(_subscriptions_of(s),
		["checkpoint_restored", "load_completed", "save_completed"],
		"the screen subscribes to the three EXISTING persistence events, and nothing else")


## ★「禁用不等于沉默」— a refused press makes a sound and prints a reason.
## Silence here is the single largest source of "is this thing broken?".
func test_denied_action_is_audible_and_explained() -> void:
	var s := _make_screen()
	s.open_screen(SaveUiModelScript.Mode.LOAD)
	_cues.clear()

	s.press_primary()
	assert_eq(_cues.size(), 1, "a disabled action still requests a cue")
	assert_eq(str(_cues[0]["cue"]), SaveSlotsScreenScript.CUE_DENIED)
	assert_lt(float(_cues[0]["gain_db"]), 0.0, "the refusal thud is quieter than a success")
	assert_eq(s.model().denial_hint(), SaveUiModelScript.DENY_EMPTY_LOAD,
		"and one line of plain reason is on screen")


## Building the list must not look to the rest of the game like the player just
## loaded three saves — which is exactly what calling read_slot() would say.
func test_building_the_list_never_looks_like_a_load() -> void:
	_sm.write_slot(0, {"checkpoint_id": "cp_scan", "timestamp": FIXED_TS})
	assert_true(await wait_for_signal(_bus.save_completed, SIGNAL_TIMEOUT))

	var s := _make_screen()
	_load_events.clear()
	var rows: Array = s.scan_rows()
	await get_tree().process_frame
	await get_tree().process_frame

	assert_eq(_load_events.size(), 0, "scan_rows() must not broadcast load_completed")
	assert_eq(rows.size(), SaveUiModelScript.ROW_COUNT)
	assert_eq(int(rows[0]["slot_id"]), SaveManagerScript.CHECKPOINT_SLOT_ID)
	assert_eq(int(rows[1]["status"]), SaveUiModelScript.RowStatus.FILLED,
		"the written slot shows up as filled")
	assert_eq(int(rows[2]["status"]), SaveUiModelScript.RowStatus.EMPTY)


## X-02: the save UI speaks as「系统」. A UI sound has no diegetic source, and
## labelling it as ambience tells a deaf player the WORLD made a noise.
func test_manual_save_writes_through_save_manager_and_speaks_as_system() -> void:
	var s := _make_screen()
	s.open_screen(SaveUiModelScript.Mode.SAVE)
	_subtitles.clear()
	_cues.clear()

	s.press_primary()
	assert_true(await wait_for_signal(_bus.save_completed, SIGNAL_TIMEOUT))
	await get_tree().process_frame

	assert_true(FileAccess.file_exists(_sm.slot_path(0)), "the slot really was written")
	assert_eq(s.model().state(), SaveUiModelScript.State.RESULT_TOAST)
	assert_eq(_subtitles.size(), 1, "the outcome is spoken exactly once")
	assert_eq(str(_subtitles[0]["speaker"]), SaveUiModelScript.SUBTITLE_SPEAKER_SYSTEM)
	assert_true(str(_subtitles[0]["line"]).contains("槽 1"),
		"and it names the slot; got: %s" % str(_subtitles[0]["line"]))
	assert_eq(str(_cues[0]["cue"]), SaveSlotsScreenScript.CUE_SUCCESS)


## SCR_LOADFADE: 0.4s eased fade, then the screen is gone. Success is signalled
## by the world coming back, NOT by a second confirmation sound.
func test_successful_load_fades_for_0_4s_then_leaves_the_screen() -> void:
	_sm.write_slot(0, {"checkpoint_id": "cp_load", "timestamp": FIXED_TS})
	assert_true(await wait_for_signal(_bus.save_completed, SIGNAL_TIMEOUT))

	var s := _make_screen()
	s.open_screen(SaveUiModelScript.Mode.LOAD)
	assert_eq(s.model().focus_index(), 1, "读档 lands on the only save on disk")

	s.press_primary()
	assert_eq(s.model().state(), SaveUiModelScript.State.CONFIRMING,
		"a load is always confirmed — it discards unsaved progress")
	_cues.clear()
	s.confirm_accept()

	assert_true(await wait_for_signal(_bus.load_completed, SIGNAL_TIMEOUT))
	await get_tree().process_frame
	assert_eq(s.model().state(), SaveUiModelScript.State.LOADING_FADE)
	assert_almost_eq(s.world_fade_alpha(), 0.0, 0.01, "the world starts dark")

	s.tick(SaveUiModelScript.LOAD_FADE_SEC * 0.5)
	var mid := s.world_fade_alpha()
	assert_gt(mid, 0.0, "the fade is eased, not a hard cut (V-06)")
	assert_lt(mid, 1.0)
	assert_eq(s.model().state(), SaveUiModelScript.State.LOADING_FADE,
		"still fading at half the budget")

	s.tick(SaveUiModelScript.LOAD_FADE_SEC)
	assert_eq(s.model().state(), SaveUiModelScript.State.BROWSING)
	assert_eq(_closes, 1, "the screen unloads completely — no pause panel left behind")
	assert_false(s.visible)
	assert_eq(_cues.size(), 0,
		"a successful load plays NO UI cue: the world returning is the confirmation")
