# tests/unit/test_audio_cues.gd
# END-TO-END audio cue tests — the batch that proves the save screen really
# MAKES A SOUND, rather than proving it politely asked for one.
#
# Spec:  design/audio/s3b-save-load-audio-spec.md §2.5 / §5.5
# ADR:   docs/architecture/adr/adr-005-audio-bus-architecture-and-world-mode-presets.md
# Rules: docs/architecture/control-manifest.md §8 (A-02, A-03, A-05)
#
# ── Why this file exists, when test_save_ui.gd already asserts the cue ──────
# test_save_ui.gd injects its OWN Callable as the audio sink and asserts what
# the screen passed to it. That is the right test for the SCREEN, and it is
# completely blind to everything downstream: the cue name could be unresolvable,
# the .wav could be absent, the player pool could be empty, and every assertion
# in that file would still be green. For most of S3-B it genuinely was — the two
# assets had not landed, so play_cue() took its "asset not present" early return
# on every call and the whole suite was green over a silent game.
#
# So this file wires the REAL /root/AudioDirector autoload into the REAL screen
# through the REAL wire_audio() entry point, triggers a REAL save, and then
# looks at the engine: is there a stream on a voice, and is that voice playing.
#
# ── ★ THIS FILE DRIVES A GLOBAL SINGLETON ★ ────────────────────────────────
# AudioDirector is an autoload, so cue_log, the retrigger ladder and
# ui_sound_enabled are process-wide and survive between tests. before_each()
# resets all of them and after_all() puts the shipped defaults back, so no
# ordering assumption is made about the rest of the suite. Nothing here touches
# the mixer's bus volumes (that is the settings panel's file, which restores the
# authored layout for the same reason).
#
# ★ TEST ISOLATION ★
#   The SaveManager under test is re-pointed at user://__test_audiocue/ via
#   configure_paths(); the real user://saves/ and user://prefs.json are never
#   opened. Mirrors tests/unit/test_save_ui.gd.
#
# ★ N-7 (CI gate G4) / N-7b ★
#   Every test is a normal `func test_*` with assertions, and no line in this
#   file matches the N-7b loader/parse pattern from .github/workflows/ci.yml
#   (reverse-asserted by test_ci_gates.gd, which scans this very directory).
#
# Run: godot --headless -s res://addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit

extends GutTest

const SaveUiModelScript = preload("res://src/ui/save_ui_model.gd")
const SaveSlotsScreenScript = preload("res://src/ui/save_slots_screen.gd")
const SaveManagerScript = preload("res://src/core/save_manager.gd")
const EventBus = preload("res://src/core/event_bus.gd")

const TEST_SAVE_DIR := "user://__test_audiocue/"
const TEST_PREFS_PATH := "user://__test_audiocue_prefs.json"

const SIGNAL_TIMEOUT := 1.0
const FIXED_TS := 1_700_000_000.0

# Appendix B of the audio spec. Asserted as LITERALS rather than read out of
# CUE_TABLE: reading the table would make the test agree with the code by
# construction, and the thing under test is precisely whether the table points
# at files that exist.
const WAV_SUCCESS := "res://arts/audio/ui/sfx_ui_save_success.wav"
const WAV_FAILURE := "res://arts/audio/ui/sfx_ui_save_failure.wav"

const CUE_SAVE_SUCCESS := "save_success"

var _bus: EventBus
var _sm: Node
var _director: Node

var _subtitles: Array = []
var _closes: int = 0


func before_all() -> void:
	DirAccess.make_dir_recursive_absolute(TEST_SAVE_DIR)


## Put the autoload back the way the game ships it. Every one of these is
## process-wide state that a later test file would otherwise inherit.
func after_all() -> void:
	var d := get_node_or_null("/root/AudioDirector")
	if d != null:
		d.set_ui_sound_enabled(true)
		d.set_retrigger_ladder_enabled(true)
		d.cue_log.clear()
		d.fade_log.clear()
		_silence_voices(d)
	_purge_test_files()
	DirAccess.remove_absolute(TEST_SAVE_DIR)


func before_each() -> void:
	_purge_test_files()

	_bus = autofree(EventBus.new())
	_sm = SaveManagerScript.new()
	add_child_autofree(_sm)
	_sm.set_event_bus(_bus)
	_sm.configure_paths(TEST_SAVE_DIR, TEST_PREFS_PATH)

	_subtitles = []
	_closes = 0

	_director = get_node_or_null("/root/AudioDirector")
	if _director == null:
		return
	# Deterministic start: an empty ledger, no suppression window carried over
	# from a previous test (80 ms is easily shorter than one GUT test), no voice
	# still sounding, and the「UI 音」switch in its shipped position.
	_director.set_ui_sound_enabled(true)
	_director.set_retrigger_ladder_enabled(false)
	_director.cue_log.clear()
	_director.fade_log.clear()
	_director._missing_warned.clear()
	_silence_voices(_director)


func after_each() -> void:
	_purge_test_files()
	_bus = null
	_sm = null


# ---- helpers ----------------------------------------------------------------
func _sink_subtitle(speaker: String, line: String) -> void:
	_subtitles.append({"speaker": speaker, "line": line})


func _sink_close() -> void:
	_closes += 1


func _provide_snapshot() -> Dictionary:
	return {"timestamp": FIXED_TS, "checkpoint_id": "cp_audio"}


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


func _silence_voices(director: Node) -> void:
	for p in director._ui_players:
		if p != null and is_instance_valid(p):
			p.stop()
			p.stream = null


## The screen from test_save_ui.gd's _make_screen(), with ONE difference that is
## the entire point of this file: the audio sink is not a test Callable, it is
## the real autoload attached through wire_audio().
func _make_wired_screen() -> SaveSlotsScreenScript:
	var s := SaveSlotsScreenScript.new()
	s.set_event_bus(_bus)
	s.set_save_manager(_sm)
	s.set_snapshot_provider(_provide_snapshot)
	s.set_subtitle_sink(_sink_subtitle)
	s.set_close_sink(_sink_close)
	s.wire_audio(_director)
	add_child_autofree(s)
	s.set_process(false)
	return s


## Drives one successful manual save exactly the way test_save_ui.gd does.
##
## The confirm step is NOT optional padding: the second save of a test lands on
## a slot the first one filled, and saving over a filled slot is always
## confirmed (UX spec AC 3). Without this branch the helper silently leaves the
## model sitting in CONFIRMING, no write is ever issued, and the failure
## surfaces as a signal timeout that reads like an audio bug.
func _save_once(s: SaveSlotsScreenScript) -> void:
	s.open_screen(SaveUiModelScript.Mode.SAVE)
	s.press_primary()
	if s.model().state() == SaveUiModelScript.State.CONFIRMING:
		s.confirm_accept()
	assert_true(await wait_for_signal(_bus.save_completed, SIGNAL_TIMEOUT),
		"fixture: the write must complete on the bus")
	await get_tree().process_frame


func _cue_entries(cue: String) -> Array:
	var out: Array = []
	for entry in _director.cue_log:
		if str(entry.get("cue", "")) == cue:
			out.append(entry)
	return out


## Index of a voice that is currently sounding, or -1.
func _playing_voice() -> int:
	for i in range(_director._ui_players.size()):
		var p: AudioStreamPlayer = _director._ui_players[i]
		if p != null and is_instance_valid(p) and p.playing:
			return i
	return -1


## Index of a voice that has been handed a stream, or -1. Weaker than
## _playing_voice() but clock-independent: a stream can only be on a voice if
## play_cue() got past the resolve + load stage.
func _loaded_voice() -> int:
	for i in range(_director._ui_players.size()):
		var p: AudioStreamPlayer = _director._ui_players[i]
		if p != null and is_instance_valid(p) and p.stream != null:
			return i
	return -1


# =============================================================================
# The assets exist (the precondition the whole batch turned on)
# =============================================================================
## Both files, not just the one this file plays: save_failure is the asset
## behind BOTH the failure cue and the action_denied alias, so its absence would
## silence two of the six save/load events while every existing test stayed
## green.
func test_both_ui_cue_assets_resolve() -> void:
	assert_true(ResourceLoader.exists(WAV_SUCCESS),
		"the save-success asset must be importable at %s" % WAV_SUCCESS)
	assert_true(ResourceLoader.exists(WAV_FAILURE),
		"the save-failure asset must be importable at %s" % WAV_FAILURE)

	# The cue table must point AT those files, or their existence is irrelevant.
	assert_eq(_director.resolve_stream_path(CUE_SAVE_SUCCESS), WAV_SUCCESS)
	assert_eq(_director.resolve_stream_path("save_failure"), WAV_FAILURE)
	assert_eq(_director.resolve_stream_path("action_denied"), WAV_FAILURE,
		"action_denied is an ALIAS of the failure asset, not a second file")

	# And they must load as audio, not merely exist as bytes.
	var stream: AudioStream = load(WAV_SUCCESS) as AudioStream
	assert_not_null(stream, "the success asset must load as an AudioStream")


# =============================================================================
# ★ THE END-TO-END ASSERTION ★
# =============================================================================
## Screen -> wire_audio() -> AudioDirector -> AudioServer, with nothing stubbed.
func test_manual_save_success_actually_sounds_a_ui_voice() -> void:
	var s := _make_wired_screen()
	await _save_once(s)

	# (b) the ledger says the cue was requested at the caller's stated level.
	var hits: Array = _cue_entries(CUE_SAVE_SUCCESS)
	assert_eq(hits.size(), 1, "exactly one save_success cue per successful save")
	if hits.is_empty():
		return
	assert_almost_eq(float(hits[0]["gain_db"]), 0.0, 0.0001,
		"AUD-G1: the caller passes 0.0 dB and the table adds nothing")
	assert_almost_eq(float(hits[0]["level_db"]), 0.0, 0.0001,
		"effective_level_db() must resolve to unity for this cue")
	assert_almost_eq(_director.effective_level_db(CUE_SAVE_SUCCESS, 0.0), 0.0, 0.0001)

	# (d) the no-op branch was NOT taken. This is the assertion that would have
	# failed for the whole of S3-B, and the reason the suite could be green over
	# a silent game.
	assert_false(_director._missing_warned.has(WAV_SUCCESS),
		"the success asset must resolve — a missing-asset warning here means "
		+ "play_cue() returned before ever reaching a player")
	assert_eq(_director._missing_warned.size(), 0,
		"no cue asset may be reported missing now that both .wav files exist")

	# (c) an actual voice, with an actual stream, actually playing.
	var loaded := _loaded_voice()
	assert_gt(loaded, -1,
		"a UI voice must have been handed the loaded stream (proves resolve+load ran)")
	if loaded >= 0:
		assert_eq(_director._ui_players[loaded].stream.resource_path, WAV_SUCCESS,
			"and it must be the success asset on that voice, not some other cue")
	assert_gt(_playing_voice(), -1,
		"at least one SFX_UI voice must report playing == true: this is the "
		+ "engine-level evidence that the game made a sound, not merely that it "
		+ "asked to")


## The bus a cue lands on is as much a part of "it sounded" as the file: SFX_UI
## under World would be ducked to -12 dB by the very pause state the save screen
## puts the game into (ADR-005 D-2).
func test_the_sounding_voice_is_on_the_sfx_ui_bus() -> void:
	var s := _make_wired_screen()
	await _save_once(s)

	var i := _loaded_voice()
	assert_gt(i, -1, "fixture: a voice must have taken the cue")
	if i < 0:
		return
	assert_eq(str(_director._ui_players[i].bus), "SFX_UI",
		"UI cues play on SFX_UI, which hangs off Master and is therefore immune "
		+ "to the world-mode ducking the save screen itself triggers")
	assert_almost_eq(float(_director._ui_players[i].volume_db), 0.0, 0.0001,
		"the voice level is the resolved cue level, not a second gain stage")


## wire_audio() is one call attaching two sinks (F-5). This asserts the screen
## in front of us really got BOTH — the half-wired failure has no symptom a
## machine can otherwise see, and test_audio_bus_layout.gd only guards the
## source-scan half of that rule.
func test_wire_audio_attached_both_sinks_to_this_screen() -> void:
	var s := _make_wired_screen()

	await _save_once(s)
	assert_gt(_cue_entries(CUE_SAVE_SUCCESS).size(), 0,
		"the cue sink is attached (a save produced a cue on the director)")

	# The fade sink is proven by driving the OTHER path end to end: the director
	# only ever appends to fade_log from fade_sink().
	_director.fade_log.clear()
	s._emit_fade("begin", 0.0)
	s._emit_fade("end", 1.0)
	assert_eq(_director.fade_log.size(), 2,
		"the fade sink is attached — without it the World bus would stay parked "
		+ "at the pause preset for the rest of the session")
	assert_false(_director.is_load_fading(),
		"and the end phase really reset the fade state")


# =============================================================================
# A-05 — the「UI 音」switch
# =============================================================================
## The gate is on play_cue() and is the first thing it does, so a silenced cue
## costs nothing and leaves no trace in the ledger.
func test_disabling_ui_sound_stops_the_cue_reaching_a_voice() -> void:
	var s := _make_wired_screen()
	_director.set_ui_sound_enabled(false)

	await _save_once(s)

	assert_eq(_director.cue_log.size(), 0,
		"a cue that never sounds must not be written to cue_log — the ledger "
		+ "records what SOUNDED, and a lying ledger is worse than none")
	assert_eq(_loaded_voice(), -1, "and no voice may be handed a stream")
	assert_eq(_playing_voice(), -1, "and nothing may be playing")


## ★ THE ★ CLAUSE OF A-05, stated as a reverse assertion: switching UI sound off
## must not take the subtitle or the on-screen result with it. Audio is never
## the only channel (A-02), so silencing it must cost the player NO information.
func test_disabling_ui_sound_keeps_the_subtitle_and_the_visual_result() -> void:
	var s := _make_wired_screen()
	_director.set_ui_sound_enabled(false)
	_subtitles.clear()

	await _save_once(s)

	assert_eq(_director.cue_log.size(), 0, "fixture: the cue really is suppressed")
	assert_eq(_subtitles.size(), 1,
		"the outcome must still be SPOKEN — A-02 forbids audio being the only "
		+ "channel, so the UI-sound switch may not silence its twin")
	assert_eq(str(_subtitles[0]["speaker"]), SaveUiModelScript.SUBTITLE_SPEAKER_SYSTEM)
	assert_true(str(_subtitles[0]["line"]).contains("槽 1"),
		"and it must still name the slot; got: %s" % str(_subtitles[0]["line"]))
	assert_eq(s.model().state(), SaveUiModelScript.State.RESULT_TOAST,
		"the visual result toast is likewise unaffected")
	assert_true(FileAccess.file_exists(_sm.slot_path(0)),
		"and the save itself obviously still happened")


## Re-enabling is not a one-way door, and the first cue after it must come back
## at FULL level — this is why the gate sits above the retrigger ladder rather
## than below it. A gate placed after _ladder_tick() would advance the ladder on
## every silent cue, and the first audible one would arrive attenuated.
func test_re_enabling_ui_sound_restores_a_full_level_cue() -> void:
	var s := _make_wired_screen()

	_director.set_ui_sound_enabled(false)
	await _save_once(s)
	assert_eq(_director.cue_log.size(), 0, "fixture: silenced")

	_director.set_ui_sound_enabled(true)
	var s2 := _make_wired_screen()
	await _save_once(s2)

	var hits: Array = _cue_entries(CUE_SAVE_SUCCESS)
	assert_eq(hits.size(), 1, "the cue is audible again")
	if hits.is_empty():
		return
	assert_almost_eq(float(hits[0]["level_db"]), 0.0, 0.0001,
		"and it returns at unity, not stepped down by cues nobody ever heard")
	assert_gt(_loaded_voice(), -1, "and it reached a voice")


## The switch is UI-ONLY. Silencing interface feedback must not touch the world
## mix, or「关掉提示音」quietly becomes「关掉游戏声音」.
func test_the_ui_sound_switch_does_not_gate_the_load_fade() -> void:
	var s := _make_wired_screen()
	_director.set_ui_sound_enabled(false)
	_director.fade_log.clear()

	s._emit_fade("begin", 0.0)
	s._emit_fade("tick", 0.5)
	s._emit_fade("end", 1.0)

	assert_eq(_director.fade_log.size(), 3,
		"the world fade is not UI feedback and must run regardless of the "
		+ "UI-sound switch")
	assert_false(_director.is_load_fading(), "and it completed normally")
