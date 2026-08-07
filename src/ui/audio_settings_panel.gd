extends Control

# ASHEN STEP — A-05「分路音量 +「UI 音」开关」 (docs/architecture/control-manifest.md §8).
#
# Spec:  control-manifest §8 A-05  (= AUD-A5, audio spec §1.7)
# ADR:   docs/architecture/adr/adr-005-audio-bus-architecture-and-world-mode-presets.md (D-1 bus tree)
# Store: SaveManager.save_prefs("audio", …) — the channel project.godot's
#        [autoload] comment reserved for exactly this panel.
#
# ── ⚠ NO `class_name` ───────────────────────────────────────────────────────
# Not because of the autoload trap (this is not an autoload) but because no
# caller needs a global symbol: the scene references the script by path and the
# tests preload it. One less name in the global class table.
#
# ── Division of labour ──────────────────────────────────────────────────────
# This panel owns WIDGETS and the PERSISTED FIELD MODEL. It owns no audio
# policy: what a cue costs in dB is AudioDirector's business, and the bus tree
# is ADR-005's. All this file does is move five numbers onto five buses and
# one bool onto AudioDirector.
#
# ── Headless discipline (mirrors save_slots_screen.gd) ──────────────────────
# Widgets are built in code, every entry point is a plain public method, and no
# behaviour is parked in a signal handler that only a real InputMap could fire.
# So the whole panel is drivable from a unit test with no viewport — see
# tests/unit/test_audio_settings_panel.gd. The .tscn is a one-node wrapper that
# exists so a screen-flow batch can instance it; it carries no layout state.
#
# ── ⚠ This file MUTATES GLOBAL MIXER STATE ─────────────────────────────────
# AudioServer.set_bus_volume_db() is process-wide. Any test that constructs this
# panel must restore the authored layout in after_all(), or it silently poisons
# tests/unit/test_audio_bus_layout.gd::test_bus_volumes_match_the_d1_calibration
# for every file that happens to run afterwards.

## Preference store section. Opaque to SaveManager by design (same FLAG-J
## one-way dependency A11ySettings.PREFS_SECTION relies on).
const PREFS_SECTION := "audio"

const BUS_MASTER := "Master"
const BUS_MUSIC := "Music"
const BUS_AMBIENCE := "Ambience"
const BUS_SFX_WORLD := "SFX_World"
const BUS_SFX_UI := "SFX_UI"

## Slider range. 100% is UNITY (0 dB), which is where ADR-005 D-1 calibrated
## every one of these buses — so a default install hears exactly the authored
## mix and the panel is a pure attenuator until the player touches it.
const PERCENT_MIN := 0.0
const PERCENT_MAX := 100.0
const PERCENT_STEP := 1.0
const DEFAULT_PERCENT := 100.0

## dB clamp. The floor is -40 rather than -60/-inf because below roughly -40 dB
## a slider stops being a volume control and becomes a mute switch with extra
## steps; 0% snaps to the floor explicitly (see percent_to_db). The +6 ceiling
## is unreachable from a 0-100 slider and exists purely so a hand-edited or
## corrupted prefs file cannot install a boost that clips the master.
const MIN_DB := -40.0
const MAX_DB := 6.0

## The shipped rows, as DATA. A-05's five independent routes
## (Master / Music / Ambience / SFX_World / SFX_UI) are now all exposed; the
## parent World bus is intentionally NOT a slider (its three children are
## individually controllable).
const BUS_ROWS := [
	{"bus": BUS_MASTER, "key": "master_percent", "label": "主音量"},
	{"bus": BUS_MUSIC, "key": "music_percent", "label": "音乐音量"},
	{"bus": BUS_AMBIENCE, "key": "ambience_percent", "label": "环境音量"},
	{"bus": BUS_SFX_WORLD, "key": "sfx_world_percent", "label": "世界音效音量"},
	{"bus": BUS_SFX_UI, "key": "sfx_ui_percent", "label": "界面音效音量"},
]

const KEY_UI_SOUND := "ui_sound_enabled"
const UI_SOUND_LABEL := "UI 音效"

const PANEL_SEPARATION := 8
const SLIDER_MIN_WIDTH := 220.0


# ── Widgets ─────────────────────────────────────────────────────────────────
var _sliders: Dictionary = {}          # bus name -> HSlider
var _value_labels: Dictionary = {}     # bus name -> Label
var _ui_check: CheckBox = null

# ── Field model ─────────────────────────────────────────────────────────────
# `_percent` is AUTHORITATIVE; the slider is a display of it. The two can differ
# by less than one step, because HSlider snaps to PERCENT_STEP and a value
# arriving from a prefs file need not be integral.
var _percent: Dictionary = {}
var _ui_sound_enabled := true

# Re-entrancy guard: writing HSlider.value emits value_changed, which lands back
# in _on_slider_changed. Without this, restoring prefs would re-enter and
# re-persist on every backfill.
var _applying := false

# ── Injected collaborators (autoload is the FALLBACK, never the assumption) ─
var _save: Node = null
var _director: Node = null


func _ready() -> void:
	_build_widgets()
	load_settings()


# =============================================================================
# DI — mirrors A11ySettings.set_save_manager / save_slots_screen's sinks
# =============================================================================
## Tests inject an isolated SaveManager (configure_paths) so the suite never
## touches the real user://prefs.json. MUST be called BEFORE add_child(), since
## _ready() is what reads the store.
func set_save_manager(sm: Node) -> void:
	_save = sm


## Duck-typed: a test may pass any Node exposing set_ui_sound_enabled().
func set_audio_director(director: Node) -> void:
	_director = director


## Injected instance first, autoload second. Resolved through the MainLoop
## rather than the parse-time global so this class still loads (and simply keeps
## its defaults) when the autoload is absent — same reasoning as A11ySettings.
func _resolve_save_manager() -> Node:
	if _save != null and is_instance_valid(_save):
		return _save
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		var tree: SceneTree = loop
		if tree.root != null:
			_save = tree.root.get_node_or_null("SaveManager")
	return _save


func _resolve_director() -> Node:
	if _director != null and is_instance_valid(_director):
		return _director
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		var tree: SceneTree = loop
		if tree.root != null:
			_director = tree.root.get_node_or_null("AudioDirector")
	return _director


# =============================================================================
# Pure mapping — static so a test (or a CI scan) can assert it with no instance
# =============================================================================
## percent -> dB. AMPLITUDE-linear, exactly like the load fade (AUD-F1): a
## dB-linear slider would put 50% at -20 dB and the bottom half of the travel
## would be inaudible, which reads as a broken control rather than a quiet one.
##
## 0% returns the floor DIRECTLY instead of via linear_to_db(0.0), which is -INF
## — clampf() would in fact catch it, but relying on a clamp to launder an
## infinity is the kind of thing that survives until the one platform where it
## does not.
static func percent_to_db(percent: float) -> float:
	var p := clampf(percent, PERCENT_MIN, PERCENT_MAX)
	if p <= 0.0:
		return MIN_DB
	return clampf(linear_to_db(p / 100.0), MIN_DB, MAX_DB)


## dB -> percent. The inverse of percent_to_db over the open interval; the floor
## is deliberately NOT round-tripped back to 0% (db_to_linear(-40) is ~1%),
## because -40 dB and true silence are different states and only one of them is
## what the player selected.
static func db_to_percent(db: float) -> float:
	return clampf(db_to_linear(clampf(db, MIN_DB, MAX_DB)) * 100.0,
		PERCENT_MIN, PERCENT_MAX)


static func is_known_bus(bus_name: String) -> bool:
	for row in BUS_ROWS:
		if str(row["bus"]) == bus_name:
			return true
	return false


# =============================================================================
# Public API (the whole panel is drivable through these — no input required)
# =============================================================================
## Applies to the live mixer AND the slider. Unknown buses are refused loudly:
## a typo'd bus name would otherwise be a slider that moves and does nothing.
func set_bus_percent(bus_name: String, percent: float) -> void:
	if not is_known_bus(bus_name):
		push_warning("AudioSettingsPanel: unknown bus '%s'" % bus_name)
		return
	var p := clampf(percent, PERCENT_MIN, PERCENT_MAX)
	_percent[bus_name] = p
	_apply_bus_db(bus_name, p)
	_sync_slider(bus_name, p)


func bus_percent(bus_name: String) -> float:
	return float(_percent.get(bus_name, DEFAULT_PERCENT))


func bus_db(bus_name: String) -> float:
	return percent_to_db(bus_percent(bus_name))


## A-05's second half. Pushes straight through to AudioDirector, which gates
## play_cue() and nothing else — the subtitle and visual twins are untouched,
## which is the ★ clause of A-05 (backed by A-02).
func set_ui_sound_enabled(on: bool) -> void:
	_ui_sound_enabled = on
	var d := _resolve_director()
	if d != null and is_instance_valid(d) and d.has_method("set_ui_sound_enabled"):
		d.set_ui_sound_enabled(on)
	_sync_check(on)


func ui_sound_enabled() -> bool:
	return _ui_sound_enabled


# =============================================================================
# Persistence
# =============================================================================
## Field model -> plain Dictionary. The ONLY place these key names appear on the
## persistence path; SaveManager stores the payload verbatim.
func to_dict() -> Dictionary:
	var out: Dictionary = {}
	for row in BUS_ROWS:
		out[str(row["key"])] = bus_percent(str(row["bus"]))
	out[KEY_UI_SOUND] = _ui_sound_enabled
	return out


## Dictionary -> field model. Missing keys fall back to the shipped defaults, so
## a prefs file written by an older build (or one that predates this panel) is
## upgraded field-by-field instead of rejected — same contract as A11ySettings.
func from_dict(data: Dictionary) -> void:
	for row in BUS_ROWS:
		set_bus_percent(str(row["bus"]), float(data.get(str(row["key"]), DEFAULT_PERCENT)))
	set_ui_sound_enabled(bool(data.get(KEY_UI_SOUND, true)))


func save_settings() -> void:
	var sm := _resolve_save_manager()
	if sm == null or not is_instance_valid(sm) or not sm.has_method("save_prefs"):
		# Loud, not silent (GDD §6) — but non-fatal: the live mix is already
		# correct, only its persistence is lost.
		push_error("AudioSettingsPanel: SaveManager unavailable — audio prefs not persisted.")
		return
	sm.save_prefs(PREFS_SECTION, to_dict())


func load_settings() -> void:
	var sm := _resolve_save_manager()
	if sm == null or not is_instance_valid(sm) or not sm.has_method("load_prefs"):
		from_dict({})   # No store reachable; install the shipped defaults.
		return
	from_dict(sm.load_prefs(PREFS_SECTION))


# =============================================================================
# Widgets
# =============================================================================
func _build_widgets() -> void:
	var box := VBoxContainer.new()
	box.name = "AudioSettingsRows"
	box.add_theme_constant_override("separation", PANEL_SEPARATION)
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(box)

	for row in BUS_ROWS:
		box.add_child(_build_slider_row(str(row["bus"]), str(row["label"])))

	_ui_check = CheckBox.new()
	_ui_check.name = "UiSoundCheck"
	_ui_check.text = UI_SOUND_LABEL
	_ui_check.button_pressed = _ui_sound_enabled
	_ui_check.toggled.connect(_on_ui_sound_toggled)
	box.add_child(_ui_check)


func _build_slider_row(bus_name: String, label_text: String) -> Control:
	var row := HBoxContainer.new()
	row.name = "%sRow" % bus_name

	var caption := Label.new()
	caption.text = label_text
	row.add_child(caption)

	var slider := HSlider.new()
	slider.name = "%sSlider" % bus_name
	slider.min_value = PERCENT_MIN
	slider.max_value = PERCENT_MAX
	slider.step = PERCENT_STEP
	slider.value = bus_percent(bus_name)
	slider.custom_minimum_size = Vector2(SLIDER_MIN_WIDTH, 0.0)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# value_changed APPLIES (so the player hears the drag); drag_ended PERSISTS.
	# Writing prefs on value_changed would put a JSON file write on every pixel
	# of slider travel.
	slider.value_changed.connect(_on_slider_changed.bind(bus_name))
	slider.drag_ended.connect(_on_slider_drag_ended)
	row.add_child(slider)

	var value_label := Label.new()
	value_label.name = "%sValue" % bus_name
	value_label.text = _percent_text(bus_percent(bus_name))
	row.add_child(value_label)

	_sliders[bus_name] = slider
	_value_labels[bus_name] = value_label
	return row


func _on_slider_changed(value: float, bus_name: String) -> void:
	if _applying:
		return
	set_bus_percent(bus_name, value)


## `_value_changed` is unused: the slider already holds the value, and the panel
## persists whatever the field model currently says.
func _on_slider_drag_ended(_value_changed: bool) -> void:
	save_settings()


func _on_ui_sound_toggled(pressed: bool) -> void:
	if _applying:
		return
	set_ui_sound_enabled(pressed)
	save_settings()


func _apply_bus_db(bus_name: String, percent: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return   # Survives a missing bus layout, like every AudioDirector helper.
	AudioServer.set_bus_volume_db(idx, percent_to_db(percent))


func _sync_slider(bus_name: String, percent: float) -> void:
	var label: Label = _value_labels.get(bus_name, null)
	if label != null and is_instance_valid(label):
		label.text = _percent_text(percent)

	var slider: HSlider = _sliders.get(bus_name, null)
	if slider == null or not is_instance_valid(slider):
		return
	if is_equal_approx(slider.value, percent):
		return
	_applying = true
	slider.value = percent
	_applying = false


func _sync_check(on: bool) -> void:
	if _ui_check == null or not is_instance_valid(_ui_check):
		return
	if _ui_check.button_pressed == on:
		return
	_applying = true
	_ui_check.button_pressed = on
	_applying = false


static func _percent_text(percent: float) -> String:
	return "%d%%" % int(roundf(percent))
