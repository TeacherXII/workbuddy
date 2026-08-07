# tests/unit/test_audio_settings_panel.gd
# GUT tests for A-05「分路音量 +「UI 音」开关」— src/ui/audio_settings_panel.gd.
#
# Rules: docs/architecture/control-manifest.md §8 A-05 (= AUD-A5)
# ADR:   docs/architecture/adr/adr-005-audio-bus-architecture-and-world-mode-presets.md (D-1)
# Store: SaveManager.save_prefs("audio", …)
#
# ── ★ THIS FILE MOVES THE GLOBAL MIXER ★ ───────────────────────────────────
# Constructing the panel writes AudioServer bus volumes, which are process-wide.
# tests/unit/test_audio_bus_layout.gd asserts the AUTHORED calibration
# (Master/World/SFX_UI all at 0 dB) by reading the live server, so if this file
# ran before it and left a slider at 50%, that file would go red for a reason
# invisible in its own source.
#
# Today the directory sorts test_audio_bus_layout.gd ahead of this file, but a
# test that is only correct because of a filename is not correct. after_each()
# AND after_all() therefore reload the authored layout, exactly as
# test_audio_bus_layout.gd's own after_all() does, so the ordering assumption is
# removed rather than relied upon.
#
# ★ TEST ISOLATION ★
#   The panel is given an isolated SaveManager (configure_paths) BEFORE it is
#   added to the tree, because _ready() is what reads the store. The real
#   user://prefs.json is never opened.
#
# ★ N-7 / N-7b ★
#   Every test is a normal `func test_*` with assertions, and no line here
#   matches the N-7b loader/parse pattern in .github/workflows/ci.yml.
#
# Run: godot --headless -s res://addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit

extends GutTest

const AudioSettingsPanelScript = preload("res://src/ui/audio_settings_panel.gd")
const SaveManagerScript = preload("res://src/core/save_manager.gd")
const EventBus = preload("res://src/core/event_bus.gd")

const PANEL_SCENE := "res://src/ui/audio_settings_panel.tscn"
const BUS_LAYOUT_RES := "res://arts/audio/audio_bus_layout.tres"

const TEST_SAVE_DIR := "user://__test_audiopanel/"
const TEST_PREFS_PATH := "user://__test_audiopanel_prefs.json"

const DB_TOLERANCE := 0.001
# linear_to_db(0.5) — the one value a reader is most likely to expect to be -50.
const HALF_DB := -6.0206

var _bus: EventBus
var _sm: Node
var _director: Node


func before_all() -> void:
	DirAccess.make_dir_recursive_absolute(TEST_SAVE_DIR)


func before_each() -> void:
	_purge_test_files()
	_bus = autofree(EventBus.new())
	_sm = SaveManagerScript.new()
	add_child_autofree(_sm)
	_sm.set_event_bus(_bus)
	_sm.configure_paths(TEST_SAVE_DIR, TEST_PREFS_PATH)

	_director = get_node_or_null("/root/AudioDirector")
	if _director == null:
		return
	_director.set_ui_sound_enabled(true)
	_director.set_retrigger_ladder_enabled(false)
	_director.cue_log.clear()
	_director._missing_warned.clear()


func after_each() -> void:
	_restore_authored_mix()
	_purge_test_files()
	_bus = null
	_sm = null


func after_all() -> void:
	_restore_authored_mix()
	var d := get_node_or_null("/root/AudioDirector")
	if d != null:
		d.set_ui_sound_enabled(true)
		d.set_retrigger_ladder_enabled(true)
		d.cue_log.clear()
	_purge_test_files()
	DirAccess.remove_absolute(TEST_SAVE_DIR)


# ---- helpers ----------------------------------------------------------------
## Reload the authored bus layout so no later file inherits a moved fader.
func _restore_authored_mix() -> void:
	var layout: AudioBusLayout = load(BUS_LAYOUT_RES) as AudioBusLayout
	if layout != null:
		AudioServer.set_bus_layout(layout)


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


## The store and the director are injected BEFORE add_child(), because _ready()
## is what reads prefs and pushes the UI-sound flag.
func _make_panel() -> Control:
	var p: Control = AudioSettingsPanelScript.new()
	p.set_save_manager(_sm)
	p.set_audio_director(_director)
	add_child_autofree(p)
	return p


func _bus_db(bus_name: String) -> float:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return NAN
	return AudioServer.get_bus_volume_db(idx)


# =============================================================================
# The percent -> dB mapping (pure, static, no instance required)
# =============================================================================
func test_percent_maps_to_db_amplitude_linearly() -> void:
	assert_almost_eq(AudioSettingsPanelScript.percent_to_db(100.0), 0.0, DB_TOLERANCE,
		"100%% is UNITY — the ADR-005 D-1 calibration, untouched")
	assert_almost_eq(AudioSettingsPanelScript.percent_to_db(50.0), HALF_DB, DB_TOLERANCE,
		"50%% is half AMPLITUDE (-6.02 dB). A dB-linear slider would put it at " +
		"-20 dB and make the bottom half of the travel useless")
	assert_almost_eq(AudioSettingsPanelScript.percent_to_db(25.0), -12.0412, DB_TOLERANCE)


## 0% must be a finite floor, not -INF. linear_to_db(0.0) is -INF, and an
## infinity reaching AudioServer is undefined behaviour dressed as a volume.
func test_zero_percent_is_a_finite_floor() -> void:
	var db := AudioSettingsPanelScript.percent_to_db(0.0)
	assert_true(is_finite(db), "0%% must not produce an infinity; got %f" % db)
	assert_almost_eq(db, AudioSettingsPanelScript.MIN_DB, DB_TOLERANCE)


## Out-of-range input is clamped rather than trusted: a hand-edited prefs file
## is the realistic source, and a +40 dB master is a blown speaker.
func test_out_of_range_percent_is_clamped_both_ways() -> void:
	assert_almost_eq(AudioSettingsPanelScript.percent_to_db(-25.0),
		AudioSettingsPanelScript.MIN_DB, DB_TOLERANCE)
	assert_almost_eq(AudioSettingsPanelScript.percent_to_db(400.0), 0.0, DB_TOLERANCE,
		"the slider tops out at unity, so no percent can boost the bus")
	assert_lte(AudioSettingsPanelScript.percent_to_db(400.0),
		AudioSettingsPanelScript.MAX_DB,
		"and nothing may ever exceed the +6 dB ceiling")

	# The inverse survives the same abuse.
	assert_almost_eq(AudioSettingsPanelScript.db_to_percent(0.0), 100.0, 0.01)
	assert_almost_eq(AudioSettingsPanelScript.db_to_percent(HALF_DB), 50.0, 0.01)
	assert_almost_eq(AudioSettingsPanelScript.db_to_percent(999.0), 100.0, 0.01)


# =============================================================================
# The slider actually moves the bus
# =============================================================================
func test_each_slider_drives_its_own_bus_and_no_other() -> void:
	var p := _make_panel()

	p.set_bus_percent("SFX_UI", 50.0)
	assert_almost_eq(_bus_db("SFX_UI"), HALF_DB, DB_TOLERANCE,
		"the SFX_UI fader must reach the live mixer, not just the field model")
	assert_almost_eq(_bus_db("Master"), 0.0, DB_TOLERANCE,
		"and it must not touch Master — five independent routes is the whole "
		+ "of A-05")
	assert_almost_eq(_bus_db("World"), 0.0, DB_TOLERANCE)

	p.set_bus_percent("Master", 25.0)
	assert_almost_eq(_bus_db("Master"), -12.0412, DB_TOLERANCE)
	assert_almost_eq(_bus_db("SFX_UI"), HALF_DB, DB_TOLERANCE,
		"and moving Master must not disturb the fader already set")

	assert_almost_eq(p.bus_percent("SFX_UI"), 50.0, 0.001)
	assert_almost_eq(p.bus_db("Master"), -12.0412, DB_TOLERANCE)


## The widget and the field model are one value, not two that happen to agree.
func test_the_slider_widget_tracks_the_field_model() -> void:
	var p := _make_panel()
	var slider: HSlider = p._sliders["SFX_UI"]
	assert_not_null(slider, "fixture: the SFX_UI row must have been built")
	assert_almost_eq(slider.value, 100.0, 0.001, "defaults are unity")

	p.set_bus_percent("SFX_UI", 40.0)
	assert_almost_eq(slider.value, 40.0, 0.001, "a programmatic set moves the widget")

	# And the reverse: driving the WIDGET must move the bus, because that is the
	# only direction a real player ever uses.
	slider.value = 75.0
	assert_almost_eq(p.bus_percent("SFX_UI"), 75.0, 0.001,
		"value_changed must feed back into the field model")
	assert_almost_eq(_bus_db("SFX_UI"), AudioSettingsPanelScript.percent_to_db(75.0),
		DB_TOLERANCE, "and onto the bus")


func test_an_unknown_bus_is_refused_rather_than_silently_dropped() -> void:
	var p := _make_panel()
	assert_false(AudioSettingsPanelScript.is_known_bus("Nonexistent"))
	assert_true(AudioSettingsPanelScript.is_known_bus("SFX_UI"))
	p.set_bus_percent("Nonexistent", 10.0)
	assert_almost_eq(p.bus_percent("SFX_UI"), 100.0, 0.001,
		"a typo'd bus name must not land on some other fader")


# =============================================================================
# ★ The「UI 音」switch reaches AudioDirector ★
# =============================================================================
## The panel's checkbox is only meaningful if it silences the real cue path.
func test_unticking_ui_sound_stops_play_cue_writing_the_ledger() -> void:
	var p := _make_panel()
	assert_true(_director.ui_sound_enabled, "shipped default is ON")

	_director.cue_log.clear()
	_director.play_cue("save_success", 0.0)
	assert_eq(_director.cue_log.size(), 1, "fixture: the cue path works while enabled")

	p.set_ui_sound_enabled(false)
	assert_false(_director.ui_sound_enabled,
		"the panel must push the flag onto the director, not merely remember it")

	_director.cue_log.clear()
	_director.play_cue("save_success", 0.0)
	_director.play_cue("save_failure", -1.0)
	_director.play_cue("action_denied", -3.0)
	assert_eq(_director.cue_log.size(), 0,
		"with UI sound off, no cue may be logged or sounded")

	p.set_ui_sound_enabled(true)
	_director.cue_log.clear()
	_director.play_cue("save_success", 0.0)
	assert_eq(_director.cue_log.size(), 1, "and the switch is not a one-way door")


func test_the_checkbox_widget_and_the_flag_stay_in_step() -> void:
	var p := _make_panel()
	var box: CheckBox = p._ui_check
	assert_not_null(box, "fixture: the UI-sound checkbox must have been built")
	assert_true(box.button_pressed, "ticked = UI sound on")

	p.set_ui_sound_enabled(false)
	assert_false(box.button_pressed, "a programmatic set moves the widget")

	# Driving the WIDGET is the direction a player uses.
	box.button_pressed = true
	assert_true(p.ui_sound_enabled(), "toggled must feed back into the field model")
	assert_true(_director.ui_sound_enabled, "and all the way through to the director")


## The switch gates UI feedback ONLY. It must not become a global mute by
## reaching for the mixer.
func test_the_ui_sound_switch_leaves_every_bus_volume_alone() -> void:
	var p := _make_panel()
	p.set_ui_sound_enabled(false)
	assert_almost_eq(_bus_db("SFX_UI"), 0.0, DB_TOLERANCE,
		"muting UI FEEDBACK is not the same as pulling the SFX_UI fader down; "
		+ "the two are independent controls and the panel offers both")
	assert_almost_eq(_bus_db("Master"), 0.0, DB_TOLERANCE)
	assert_almost_eq(_bus_db("World"), 0.0, DB_TOLERANCE)


# =============================================================================
# Persistence
# =============================================================================
func test_settings_round_trip_through_the_preference_store() -> void:
	var p := _make_panel()
	p.set_bus_percent("Master", 60.0)
	p.set_bus_percent("World", 30.0)
	p.set_bus_percent("SFX_UI", 45.0)
	p.set_ui_sound_enabled(false)
	p.save_settings()

	assert_true(_sm.has_prefs_section("audio"),
		"the panel must persist into the 'audio' section project.godot reserved")

	# A SECOND panel over the same store — i.e. the next session.
	var p2 := _make_panel()
	assert_almost_eq(p2.bus_percent("Master"), 60.0, 0.001)
	assert_almost_eq(p2.bus_percent("World"), 30.0, 0.001)
	assert_almost_eq(p2.bus_percent("SFX_UI"), 45.0, 0.001)
	assert_false(p2.ui_sound_enabled(), "the UI-sound choice must survive a restart")

	# _ready() backfills the WIDGETS too, not just the numbers.
	assert_almost_eq(float(p2._sliders["World"].value), 30.0, 0.001,
		"the restored value must be visible on the control the player looks at")
	assert_false(p2._ui_check.button_pressed)

	# And the restored state is on the live mixer, not merely in memory.
	assert_almost_eq(_bus_db("World"), AudioSettingsPanelScript.percent_to_db(30.0),
		DB_TOLERANCE)
	assert_false(_director.ui_sound_enabled,
		"restoring prefs must re-apply the silence the player chose")


## A store with no audio section is the FIRST RUN, and must produce the shipped
## mix rather than zeros. `float({}.get(k, 100.0))` returning 0.0 by accident is
## exactly the bug that ships a silent game.
func test_a_missing_audio_section_installs_the_shipped_defaults() -> void:
	assert_false(_sm.has_prefs_section("audio"), "fixture: a virgin store")
	var p := _make_panel()

	assert_almost_eq(p.bus_percent("Master"), 100.0, 0.001)
	assert_almost_eq(p.bus_percent("World"), 100.0, 0.001)
	assert_almost_eq(p.bus_percent("SFX_UI"), 100.0, 0.001)
	assert_true(p.ui_sound_enabled(), "UI sound ships ON")
	assert_almost_eq(_bus_db("Master"), 0.0, DB_TOLERANCE,
		"a first run must leave the authored D-1 calibration exactly as it is")


## Field-by-field fallback: a prefs file written before a fader existed must not
## zero the faders it does not mention.
func test_a_partial_audio_section_fills_the_gaps_with_defaults() -> void:
	_sm.save_prefs("audio", {"world_percent": 20.0})
	var p := _make_panel()

	assert_almost_eq(p.bus_percent("World"), 20.0, 0.001, "the stored key wins")
	assert_almost_eq(p.bus_percent("Master"), 100.0, 0.001,
		"an absent key falls back to the default, never to 0")
	assert_almost_eq(p.bus_percent("SFX_UI"), 100.0, 0.001)
	assert_true(p.ui_sound_enabled(), "an absent switch reads as ON")


## The panel writes ONLY its own section. A-05 shares user://prefs.json with the
## a11y model, and a settings screen that clobbers a neighbouring section is a
## data-loss bug that only shows up on the next boot.
func test_saving_audio_prefs_leaves_the_a11y_section_intact() -> void:
	_sm.save_prefs("a11y", {"subtitles": true, "text_scale": 1.25})
	var p := _make_panel()
	p.set_bus_percent("Master", 55.0)
	p.save_settings()

	var a11y: Dictionary = _sm.load_prefs("a11y")
	assert_eq(a11y.size(), 2, "the neighbouring section must survive untouched")
	assert_almost_eq(float(a11y.get("text_scale", 0.0)), 1.25, 0.001)
	assert_almost_eq(float(_sm.load_prefs("audio").get("master_percent", 0.0)), 55.0, 0.001)


# =============================================================================
# The scene wrapper
# =============================================================================
## The .tscn must instantiate and carry the script. A scene that fails to
## resolve its ext_resource still "exists" as a file, so asserting the PATH
## proves nothing.
func test_the_panel_scene_instantiates_with_its_script_attached() -> void:
	assert_true(ResourceLoader.exists(PANEL_SCENE), "the panel scene must exist")
	var packed: PackedScene = load(PANEL_SCENE) as PackedScene
	assert_not_null(packed, "the panel scene must load as a PackedScene")
	if packed == null:
		return

	var inst := packed.instantiate()
	assert_not_null(inst)
	if inst == null:
		return
	autofree(inst)
	assert_true(inst is Control, "the panel is a self-contained Control")
	assert_true(inst.has_method("set_bus_percent"),
		"and the scene really carries audio_settings_panel.gd")
	assert_true(inst.has_method("set_ui_sound_enabled"))
