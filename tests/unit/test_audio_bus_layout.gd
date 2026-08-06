# tests/unit/test_audio_bus_layout.gd
# GUT unit tests for the S3-B audio subsystem's STRUCTURE (E-10).
#
# Spec:  design/audio/oos-resolution.md §4.5 (the seven assertions, verbatim)
# ADR:   docs/architecture/adr/adr-005-audio-bus-architecture-and-world-mode-presets.md
# Rules: docs/architecture/control-manifest.md §8 — this file is the machine-
#        checkable half of A-05 (five independent buses are the PRECONDITION for
#        per-bus volume control; there is nothing to put a slider on until the
#        tree exists). A-01/A-03/A-04 are asset- and level-side and are reviewed,
#        not asserted here; A-02 lives in test_save_ui.gd.
#
# Exit hooks:
#   E-10/1  test_bus_tree_is_the_seven_buses_in_d1_order          (D-1, A-05 pre)
#   E-10/2  test_routing_hangs_sfx_ui_off_master_not_world        (D-2)
#   E-10/3  test_bus_volumes_match_the_d1_calibration             (D-1)
#   E-10/4  test_world_carries_exactly_one_lowpass                (D-2, D-7, D-8)
#   E-10/5  test_sfx_ui_effect_chain_is_empty                     (D-4)
#   E-10/6  test_master_effect_chain_is_empty                     (D-5)
#   E-10/7  test_audio_director_owns_no_tween_and_no_timer        (AUD-F2)
#   E-3     test_project_settings_point_at_the_layout_and_48k     (E-2 / E-3)
#   F-5     test_no_source_file_wires_only_half_of_the_audio      (F-5)
#
# ── Why a bus LAYOUT deserves a test ────────────────────────────────────────
# audio_bus_layout.tres is a positional file: Godot writes buses as bus/N/…, and
# `send` is resolved by NAME at load. Drag one bus in the editor's audio panel
# and the indices renumber; every routing decision in ADR-005 then holds or
# breaks depending on a diff nobody reads. Worse, a broken routing is INAUDIBLE
# as a bug — the game still makes sound, it just makes it in the wrong place.
# The one that actually matters is D-2: if SFX_UI ever ends up under World, then
# every UI cue gets ducked by the very pause menu that raised it, and the save
# screen goes quiet at exactly the moment it needs to confirm an action.
#
# ── Ordering assumption (deliberate, and load-bearing) ──────────────────────
# The seven assertions read the LIVE AudioServer, not the .tres. That is the
# point: reading the resource would only prove the file's contents, whereas
# reading the server proves project.godot actually pointed the engine at it
# during boot. The cost is that this file asserts global mutable state, so it
# must not run after anything that moves a bus. Nothing in the suite does today
# (test_save_ui.gd injects its own cue sink and never attaches a fade sink), and
# after_all() restores the authored layout so that stays true as the suite grows.
#
# ── Headless ────────────────────────────────────────────────────────────────
# Under the Dummy audio driver the mixer produces no samples, but the bus graph
# is still fully constructed and every AudioServer query below resolves. Nothing
# here plays anything.
#
# Run: godot --headless -s res://addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit

extends GutTest

const AUDIO_DIRECTOR_SRC := "res://src/core/audio_director.gd"
const BUS_LAYOUT_RES := "res://arts/audio/audio_bus_layout.tres"
const SRC_ROOT := "res://src"

# ADR-005 D-1. The INDEX is part of the contract, not just the name set: Godot
# stores buses positionally and a reordered layout is a different layout.
const EXPECTED_BUSES := [
	"Master", "World", "Music", "Ambience", "SFX_World", "Voice", "SFX_UI",
]

# ADR-005 D-2. ★ The SFX_UI row is the one this whole file exists to protect.
# Master is omitted on purpose: bus 0 sends to itself by construction.
const EXPECTED_SENDS := {
	"World": "Master",
	"Music": "World",
	"Ambience": "World",
	"SFX_World": "World",
	"Voice": "World",
	"SFX_UI": "Master",
}

# ADR-005 D-1 calibration. Music sits -8 dB so a bed never has to be mixed
# against the world by ear; every other bus is unity and stays that way.
const EXPECTED_DB := {
	"Master": 0.0,
	"World": 0.0,
	"Music": -8.0,
	"Ambience": 0.0,
	"SFX_World": 0.0,
	"Voice": 0.0,
	"SFX_UI": 0.0,
}

const DB_TOLERANCE := 0.001


## Leave the mixer exactly as it was authored. This file mutates nothing today;
## the restore is here so that the first test which DOES drive a fade cannot
## quietly poison whatever runs next.
func after_all() -> void:
	var layout: AudioBusLayout = load(BUS_LAYOUT_RES) as AudioBusLayout
	if layout != null:
		AudioServer.set_bus_layout(layout)


# =============================================================================
# E-10 / 1 — the tree itself (D-1)
# =============================================================================
func test_bus_tree_is_the_seven_buses_in_d1_order() -> void:
	# A bus_count of 1 means the engine fell back to its built-in single-Master
	# default, i.e. the layout never reached it. Say so plainly, because every
	# other assertion in this file would then fail for the same one reason.
	assert_eq(AudioServer.bus_count, EXPECTED_BUSES.size(),
		"the authored 7-bus layout must be the live layout (1 = engine default, " +
		"meaning project.godot's buses/default_bus_layout did not resolve)")

	for i in range(EXPECTED_BUSES.size()):
		if i >= AudioServer.bus_count:
			break
		assert_eq(AudioServer.get_bus_name(i), str(EXPECTED_BUSES[i]),
			"bus index %d must be %s — indices are the contract, ADR-005 D-1" %
				[i, str(EXPECTED_BUSES[i])])


# =============================================================================
# E-10 / 2 — routing (D-2). The load-bearing one.
# =============================================================================
func test_routing_hangs_sfx_ui_off_master_not_world() -> void:
	for bus_name in EXPECTED_SENDS.keys():
		var idx := AudioServer.get_bus_index(str(bus_name))
		assert_gt(idx, -1, "bus %s must exist before its routing can mean anything" % str(bus_name))
		if idx < 0:
			continue
		assert_eq(str(AudioServer.get_bus_send(idx)), str(EXPECTED_SENDS[bus_name]),
			"%s must send to %s (ADR-005 D-2)" % [str(bus_name), str(EXPECTED_SENDS[bus_name])])

	# Reverse assertion. The positive test above passes just as happily if
	# SFX_UI were renamed and a second bus called SFX_UI were parented to World,
	# so state the prohibition directly: a UI cue must never be duckable by the
	# menu that produced it.
	var ui := AudioServer.get_bus_index("SFX_UI")
	var world := AudioServer.get_bus_index("World")
	var ui_under_world := false
	if ui >= 0 and world >= 0:
		ui_under_world = str(AudioServer.get_bus_send(ui)) == "World"
	assert_false(ui_under_world,
		"SFX_UI under World would duck every save confirmation by -12 dB the " +
		"instant the pause preset engages — the exact defect D-2 forbids")


# =============================================================================
# E-10 / 3 — calibration (D-1)
# =============================================================================
func test_bus_volumes_match_the_d1_calibration() -> void:
	for bus_name in EXPECTED_DB.keys():
		var idx := AudioServer.get_bus_index(str(bus_name))
		if idx < 0:
			assert_gt(idx, -1, "bus %s must exist" % str(bus_name))
			continue
		assert_almost_eq(AudioServer.get_bus_volume_db(idx),
			float(EXPECTED_DB[bus_name]), DB_TOLERANCE,
			"%s volume_db is part of the standing mix, not a runtime knob" % str(bus_name))


# =============================================================================
# E-10 / 4 — the one and only World filter (D-2 / D-7 / D-8)
# =============================================================================
func test_world_carries_exactly_one_lowpass() -> void:
	var idx := AudioServer.get_bus_index("World")
	assert_gt(idx, -1, "World must exist")
	if idx < 0:
		return

	assert_eq(AudioServer.get_bus_effect_count(idx), 1,
		"World carries EXACTLY one effect. A second filter would mean two " +
		"cutoffs racing over one ramp, and AudioDirector only ever writes slot 0")

	if AudioServer.get_bus_effect_count(idx) < 1:
		return
	var fx := AudioServer.get_bus_effect(idx, 0)
	var is_lpf := fx is AudioEffectLowPassFilter
	assert_true(is_lpf, "World effect 0 must be an AudioEffectLowPassFilter (D-2)")
	if not is_lpf:
		return

	var lpf := fx as AudioEffectLowPassFilter

	# D-8. Godot's default resonance is 0.5, which puts an audible ring right on
	# the cutoff — at the PAUSED preset's 700 Hz that is a whistle sitting on top
	# of a menu, and art-bible §1 rules out exactly that kind of artefact. This
	# assertion is here because the wrong value is the DEFAULT: anyone who
	# re-creates this effect from the editor gets 0.5 unless they know better.
	assert_almost_eq(lpf.resonance, 0.0, 0.0001,
		"World LPF resonance must be 0.0 — 0.5 is Godot's default and it rings (D-8)")

	# D-7. 12 dB/oct: a door between the player and the world, not a wall.
	assert_eq(lpf.db, AudioEffectFilter.FILTER_12DB,
		"World LPF slope must be 12 dB/oct (D-7)")

	# cutoff_hz is deliberately NOT asserted: it is the one property the 120 ms
	# world-mode ramp is supposed to move (20500 / 1200 / 700), so pinning it
	# here would assert a moment in time rather than a decision.


# =============================================================================
# E-10 / 5 — SFX_UI chain is empty (D-4)
# =============================================================================
func test_sfx_ui_effect_chain_is_empty() -> void:
	var idx := AudioServer.get_bus_index("SFX_UI")
	assert_gt(idx, -1, "SFX_UI must exist")
	if idx < 0:
		return
	assert_eq(AudioServer.get_bus_effect_count(idx), 0,
		"D-4: UI filtering and space are BAKED INTO THE ASSET. An effect here " +
		"would make the shipped .wav and what the player hears two different " +
		"things, and only one of them is reviewable")


# =============================================================================
# E-10 / 6 — Master chain is empty (D-5)
# =============================================================================
func test_master_effect_chain_is_empty() -> void:
	var idx := AudioServer.get_bus_index("Master")
	assert_gt(idx, -1, "Master must exist")
	if idx < 0:
		return
	assert_eq(AudioServer.get_bus_effect_count(idx), 0,
		"D-5: no limiter, no compressor. This game's tension is built out of " +
		"quiet and transient; a master limiter would flatten both, and it would " +
		"do it to a mix that is already arithmetically safe by bus calibration")


# =============================================================================
# E-10 / 7 — the audio layer owns no clock of its own (AUD-F2)
# =============================================================================
## §4.5's seventh assertion, written twice on purpose.
##
## The literal form ("no Tween among AudioDirector's children") is kept for
## traceability, but it is weak in Godot 4 and the reader should know why: Tween
## stopped being a Node in 4.0 and is now RefCounted, so a tween created by this
## autoload would NEVER appear in get_children() and the scan can only ever pass.
## The assertion that actually bites is the source scan below it.
func test_audio_director_owns_no_tween_and_no_timer() -> void:
	var director := get_node_or_null("/root/AudioDirector")
	assert_not_null(director, "AudioDirector must be registered as an autoload")
	if director == null:
		return

	var tween_children := 0
	for child in director.get_children():
		if child is Tween:
			tween_children += 1
	assert_eq(tween_children, 0, "AudioDirector must own no Tween node (§4.5 assertion 7)")

	# The one that can fail. AUD-F2: the 0.4 s load fade has exactly ONE clock,
	# and it belongs to the screen. A second interpolator in the audio layer does
	# not desynchronise loudly — it desynchronises by a frame or two, which is
	# heard as the veil and the volume disagreeing, and is unreproducible.
	var src: String = FileAccess.get_file_as_string(AUDIO_DIRECTOR_SRC)
	assert_gt(src.length(), 0, "fixture: audio_director.gd must be readable")

	var forbidden := ["create_tween(", "Tween.new(", "create_timer(", "Timer.new("]
	var found: Array = []
	for token in forbidden:
		if src.contains(token):
			found.append(token)
	assert_eq(found.size(), 0,
		"AUD-F2: the audio layer must not construct its own time source; found " +
		str(found))


# =============================================================================
# E-2 / E-3 — the project actually asks for this layout, at 48 kHz
# =============================================================================
## Without this, all six assertions above can pass against a layout the shipped
## game never loads (e.g. someone left the editor pointing at a scratch copy).
func test_project_settings_point_at_the_layout_and_48k() -> void:
	assert_eq(str(ProjectSettings.get_setting("audio/buses/default_bus_layout", "")),
		BUS_LAYOUT_RES,
		"project.godot must load the audited layout, not the engine default")

	assert_true(ResourceLoader.exists(BUS_LAYOUT_RES),
		"the layout resource must exist at the path project.godot names")

	# The SETTING, not AudioServer.get_mix_rate(): under the headless Dummy
	# driver the running mixer reports whatever the null device felt like, so
	# asserting the live rate would be asserting the CI container. Every shipped
	# asset is 48 kHz; leaving Godot's 44100 default resamples all of them at
	# runtime, on every platform, silently.
	assert_eq(int(ProjectSettings.get_setting("audio/driver/mix_rate", 0)), 48000,
		"mix_rate must be 48000 to match the asset spec (E-3)")


# =============================================================================
# F-5 — nobody may wire half the audio
# =============================================================================
## The defect this guards has no symptom a machine can see: attach the screen's
## cue sink but forget its fade sink and the game still saves, still plays the
## 「嗒」, still loads — and then keeps the World bus at -12 dB / LPF 700 Hz for
## the remainder of the session, because end_load_fade() is the only reset on
## that path and it arrives through the sink that was never attached.
##
## wire_audio() attaches both in one call, so the rule is mechanical: any source
## file that reaches for the cue sink must go through wire_audio(), or attach
## the fade sink itself. Today there is no production construction site at all
## and this passes on the strength of comments alone — which is precisely when
## the guard needs to already exist, because the person who adds the first one
## will not have read §4.6.
func test_no_source_file_wires_only_half_of_the_audio() -> void:
	var files := _gd_files_under(SRC_ROOT)
	assert_gt(files.size(), 5, "anti-vacuity: the src scan must have found files")

	var offenders: Array = []
	for path in files:
		var src: String = FileAccess.get_file_as_string(path)
		if not src.contains("set_audio_sink("):
			continue
		if src.contains("wire_audio(") or src.contains("set_fade_sink("):
			continue
		offenders.append(path)

	assert_eq(offenders.size(), 0,
		"F-5: these files attach the cue sink without the fade sink, which " +
		"parks the World bus at the pause preset forever: " + str(offenders))


# =============================================================================
# Helpers
# =============================================================================
func _gd_files_under(root: String) -> Array:
	var out: Array = []
	var pending: Array = [root]
	while not pending.is_empty():
		var dir_path: String = str(pending.pop_back())
		var d := DirAccess.open(dir_path)
		if d == null:
			continue
		d.list_dir_begin()
		var entry := d.get_next()
		while entry != "":
			if entry.begins_with("."):
				entry = d.get_next()
				continue
			var full := dir_path + "/" + entry
			if d.current_is_dir():
				pending.append(full)
			elif entry.ends_with(".gd"):
				out.append(full)
			entry = d.get_next()
		d.list_dir_end()
	out.sort()
	return out
