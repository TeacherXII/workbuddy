class_name A11ySettings
extends Node

# ASHEN STEP — Sprint 0 vertical slice (Phase 5), Sprint 2 Batch A persistence,
# Sprint 2 Batch C full Tier2 model (E09-S5a/S5b/S5c/S5d/S7).
#
# L2 accessibility settings. This class owns the FIELD MODEL — names, defaults,
# enums and clamping — and nothing else. It draws no pixels, drives no VFX and
# emits no signals; TimeController (E02) and HudSlice (E09) READ it.
#
# Defaults follow control-manifest v0.2:
#   C-06  colorblind_mode  = OFF          (four-state enum, E09-S5a)
#   T-01  time_scale_user in [0.1, 1.0]   (E09-S5b)
#   T-02  time_scale_user  = 0.25 default, time_scale_min 0.1 hard floor
#   V-03  screen_shake     = false
#   V-04  fog_option       = FULL         (three-state, E09-S5c)
#   V-05  motion_blur      = false
#   X-01  text_scale in [1.0, 1.5], default 1.0
#   X-02  subtitles        = true         (E09-S5d)
#
# [Sprint 2 · Batch A / SAV-S4] Persistence NO LONGER goes through the legacy
# Sprint 0 .cfg config-file API.
# save()/load() now delegate to the L2 SaveManager preference store
# (user://prefs.json) via the FIELD-AGNOSTIC API save_prefs(section, dict) /
# load_prefs(section). The split of responsibilities is deliberate:
#   · A11ySettings owns the FIELD MODEL (names, defaults, clamping) — E09-S7
#     grows it in Batch C without SaveManager knowing a single field name.
#   · SaveManager owns the STORE (path, JSON, versioning, a11y.cfg migration).
# That one-way dependency (SAV-S4 -> E09-S7) is what breaks the FLAG-J cycle.
#
# The legacy user://a11y.cfg is migrated ONCE, by SaveManager, on the first
# load_prefs() call — see save_manager.gd::_migrate_legacy_config_once(). This
# class must NOT do migration itself, or the file would be consumed twice.
#
# ── ★ BACKWARD-COMPAT FACADE (Batch C, E09-S7) ──────────────────────────────
# The Sprint 0 slice shipped `color_blind_mode: String` and `fog_enabled: bool`.
# Both are now COMPUTED VIEWS over the Tier2 fields and remain fully writable:
#   color_blind_mode <-> colorblind_mode   ("DEUTERANO" <-> ColorBlindMode.DEUTAN)
#   fog_enabled      <-> fog_option        (false <-> FogOption.OFF)
# Removing them would break every Sprint 0/1 caller AND a shipped assertion in
# tests/unit/test_save_manager.gd::test_prefs_delegation_roundtrip, which round-
# trips the STRING "DEUTERANO" through the store. Keep the facade until that
# test is deliberately rewritten.

## Legacy Sprint 0 path. Kept for reference only — nothing here reads or writes
## it any more. The one-time migration is owned by
## SaveManager.LEGACY_A11Y_PATH (SAV-S4). @deprecated
const CONFIG_PATH := "user://a11y.cfg"

## Preference store section key. Opaque to SaveManager by design (FLAG-J).
const PREFS_SECTION := "a11y"


# --- E09-S5a: colour-blind mode (C-05 / C-06 / C-07) -------------------------
## Full four-state enum. OFF is 0 so an absent/zeroed field degrades to "off",
## never to a mode the player never chose.
enum ColorBlindMode { OFF = 0, PROTAN = 1, DEUTAN = 2, TRITAN = 3 }

## Canonical names for the Tier2 field (settings UI + telemetry).
const CB_MODE_NAMES := {
	ColorBlindMode.OFF: "OFF",
	ColorBlindMode.PROTAN: "PROTAN",
	ColorBlindMode.DEUTAN: "DEUTAN",
	ColorBlindMode.TRITAN: "TRITAN",
}

## What the LEGACY `color_blind_mode: String` facade emits. These are the exact
## spellings the Sprint 0 slice wrote to disk, so an old preference file and an
## old caller both keep working.
const LEGACY_CB_NAMES := {
	ColorBlindMode.OFF: "OFF",
	ColorBlindMode.PROTAN: "PROTANO",
	ColorBlindMode.DEUTAN: "DEUTERANO",
	ColorBlindMode.TRITAN: "TRITANO",
}

## Every spelling the facade ACCEPTS. Both the Sprint 0 "-ANO" forms and the
## canonical Tier2 names resolve to the same enum value, so a preference file
## written by either generation loads without a migration step.
const CB_MODE_ALIASES := {
	"OFF": ColorBlindMode.OFF,
	"NONE": ColorBlindMode.OFF,
	"PROTAN": ColorBlindMode.PROTAN,
	"PROTANO": ColorBlindMode.PROTAN,
	"PROTANOPIA": ColorBlindMode.PROTAN,
	"DEUTAN": ColorBlindMode.DEUTAN,
	"DEUTERANO": ColorBlindMode.DEUTAN,
	"DEUTERANOPIA": ColorBlindMode.DEUTAN,
	"TRITAN": ColorBlindMode.TRITAN,
	"TRITANO": ColorBlindMode.TRITAN,
	"TRITANOPIA": ColorBlindMode.TRITAN,
}


# --- E09-S5c: dizziness controls (V-03 / V-04 / V-05) ------------------------
## V-04「减弱雾 / 关闭雾」. FULL is 0 so a zeroed/absent field means "unchanged
## from the artistic baseline" rather than silently disabling the fog look.
enum FogOption { FULL = 0, REDUCED = 1, OFF = 2 }

const FOG_OPTION_NAMES := {
	FogOption.FULL: "FULL",
	FogOption.REDUCED: "REDUCED",
	FogOption.OFF: "OFF",
}


# --- E09-S5b / E09-S5d: numeric ranges (T-01 / T-02 / X-01) ------------------
## T-01 user-adjustable time-scale range. TIME_SCALE_MIN doubles as the physics
## stability floor (T-02) — nothing in the codebase may drive Engine.time_scale
## below it.
const TIME_SCALE_MIN := 0.1
const TIME_SCALE_MAX := 1.0
## T-02 凝神默认缩放. Must stay equal to TimeController.FOCUS_SCALE; the
## @ci:a11y-values-in-range scan cross-checks the two so they cannot drift.
const TIME_SCALE_DEFAULT := 0.25

## X-01「100% – 150% 不破版」.
const TEXT_SCALE_MIN := 1.0
const TEXT_SCALE_MAX := 1.5
const TEXT_SCALE_DEFAULT := 1.0


# --- backing storage ---------------------------------------------------------
# Distinct backing names (not the property names) so the getters/setters below
# can never recurse into themselves. Every range-critical field is a validating
# property: an out-of-range value is impossible to STORE, not merely impossible
# to save, which is what makes @ci:a11y-values-in-range a real invariant instead
# of a hope.
var _colorblind_mode: int = ColorBlindMode.OFF
var _time_scale_user: float = TIME_SCALE_DEFAULT
var _fog_option: int = FogOption.FULL
var _text_scale: float = TEXT_SCALE_DEFAULT


# --- Tier2 field model -------------------------------------------------------
## E09-S5a. Assigning an unknown int falls back to OFF rather than storing junk.
var colorblind_mode: int:
	get:
		return _colorblind_mode
	set(value):
		_colorblind_mode = normalize_colorblind_mode(value)

## E09-S5b. Clamped into T-01 on every write.
var time_scale_user: float:
	get:
		return _time_scale_user
	set(value):
		_time_scale_user = clampf(value, TIME_SCALE_MIN, TIME_SCALE_MAX)

## E09-S5c. Assigning an unknown int falls back to FULL (the artistic baseline).
var fog_option: int:
	get:
		return _fog_option
	set(value):
		_fog_option = normalize_fog_option(value)

## E09-S5d. Clamped into X-01 on every write.
var text_scale: float:
	get:
		return _text_scale
	set(value):
		_text_scale = clampf(value, TEXT_SCALE_MIN, TEXT_SCALE_MAX)

## T-02 lower clamp (physics stability). Kept as a stored field, not derived,
## because a platform-specific build may need to raise the floor.
var time_scale_min: float = TIME_SCALE_MIN
var screen_shake: bool = false         # V-03 default off
var motion_blur: bool = false          # V-05 default off
var subtitles: bool = true             # X-02 default on


# --- Sprint 0 / Sprint 1 compatibility facade --------------------------------
## @deprecated — prefer `colorblind_mode`. Reads/writes the Tier2 enum through
## the Sprint 0 string spelling ("OFF" | "PROTANO" | "DEUTERANO" | "TRITANO").
var color_blind_mode: String:
	get:
		return legacy_name_of(_colorblind_mode)
	set(value):
		_colorblind_mode = mode_from_alias(value)

## @deprecated — prefer `fog_option`. `false` maps to the OFF rung; `true`
## restores FULL. A REDUCED setting reads back as `true`, because from a
## two-state caller's point of view the fog is indeed still on.
var fog_enabled: bool:
	get:
		return _fog_option != FogOption.OFF
	set(value):
		_fog_option = FogOption.FULL if value else FogOption.OFF


# Injected L2 service. Left untyped (Node) on purpose: save_manager.gd has no
# `class_name` because it is the `SaveManager` autoload (see its header).
var _save: Node = null


# --- validation helpers (static: usable by CI scans without an instance) -----

## Any int -> a legal ColorBlindMode. Unknown values degrade to OFF.
static func normalize_colorblind_mode(value: int) -> int:
	if CB_MODE_NAMES.has(value):
		return value
	return ColorBlindMode.OFF


## Any int -> a legal FogOption. Unknown values degrade to FULL.
static func normalize_fog_option(value: int) -> int:
	if FOG_OPTION_NAMES.has(value):
		return value
	return FogOption.FULL


## Tier2 enum -> the Sprint 0 string spelling (facade output).
static func legacy_name_of(mode: int) -> String:
	return str(LEGACY_CB_NAMES.get(normalize_colorblind_mode(mode), "OFF"))


## Tier2 enum -> the canonical Tier2 name (settings UI / telemetry).
static func canonical_name_of(mode: int) -> String:
	return str(CB_MODE_NAMES.get(normalize_colorblind_mode(mode), "OFF"))


## Any accepted spelling -> Tier2 enum. Unknown spellings degrade to OFF, which
## is the only safe failure mode: a player never silently lands in a mode they
## did not pick.
static func mode_from_alias(alias: String) -> int:
	return int(CB_MODE_ALIASES.get(alias.strip_edges().to_upper(), ColorBlindMode.OFF))


## FogOption -> name.
static func fog_name_of(option: int) -> String:
	return str(FOG_OPTION_NAMES.get(normalize_fog_option(option), "FULL"))


## The SHIPPED defaults, as data, without constructing a Node. tests/ci/
## budget_checks.gd scans this for @ci:a11y-values-in-range: if someone edits a
## default out of its control-manifest range the CI scan sees it, which it could
## not do if the defaults only existed as member initialisers.
static func default_values() -> Dictionary:
	return {
		"colorblind_mode": ColorBlindMode.OFF,
		"time_scale_user": TIME_SCALE_DEFAULT,
		"time_scale_min": TIME_SCALE_MIN,
		"fog_option": FogOption.FULL,
		"screen_shake": false,
		"motion_blur": false,
		"text_scale": TEXT_SCALE_DEFAULT,
		"subtitles": true,
	}


# --- convenience reads (HUD / VFX consumers) ---------------------------------

## C-06: is any colour-blind substitution active? HudColors.danger_color() is
## the only place that decides WHICH colour; this only answers "substituting?".
func is_colorblind() -> bool:
	return _colorblind_mode != ColorBlindMode.OFF


## V-04: does the dizziness setting still allow a full-strength fog/dim pass?
func fog_is_full() -> bool:
	return _fog_option == FogOption.FULL


# --- DI ----------------------------------------------------------------------

## DI hook, mirroring set_event_bus / set_sound_system elsewhere in the codebase.
## Tests inject an isolated SaveManager so they never touch the real user:// files.
func set_save_manager(sm: Node) -> void:
	_save = sm


## Injected instance first, autoload second. Resolved through the MainLoop rather
## than the parse-time `SaveManager` global so this class still loads (and simply
## keeps its defaults) when the autoload is absent.
func _resolve_save_manager() -> Node:
	if _save != null and is_instance_valid(_save):
		return _save
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		var tree: SceneTree = loop
		if tree.root != null:
			_save = tree.root.get_node_or_null("SaveManager")
	return _save


# --- persistence -------------------------------------------------------------

## Field model -> plain Dictionary. This is the ONLY place field names appear on
## the persistence path; SaveManager stores it verbatim.
##
## The last two keys are DERIVED MIRRORS of the Tier2 fields, written so a
## Sprint 0/1 build can still read a Batch C preference file. They are never
## authoritative on the way back in — see from_dict().
func to_dict() -> Dictionary:
	return {
		"colorblind_mode": _colorblind_mode,
		"time_scale_user": _time_scale_user,
		"time_scale_min": time_scale_min,
		"fog_option": _fog_option,
		"screen_shake": screen_shake,
		"motion_blur": motion_blur,
		"text_scale": _text_scale,
		"subtitles": subtitles,
		"color_blind_mode": legacy_name_of(_colorblind_mode),
		"fog_enabled": _fog_option != FogOption.OFF,
	}


## Dictionary -> field model. Missing keys keep the current (default) value, so
## a preference file written by an older/newer build is forward/backward
## compatible field-by-field (SAV-S4: "缺字段用默认值补全").
##
## Precedence is Tier2-first: `colorblind_mode` beats `color_blind_mode` and
## `fog_option` beats `fog_enabled`. A Sprint 0 file carries only the legacy
## keys and is upgraded in place; a Batch C file carries both and the mirrors
## are ignored, so the two can never disagree on load.
##
## Every assignment below goes through the validating properties, so a hand-
## edited or corrupted preference file cannot install an out-of-range value.
func from_dict(data: Dictionary) -> void:
	if data.has("colorblind_mode"):
		colorblind_mode = int(data["colorblind_mode"])
	elif data.has("color_blind_mode"):
		color_blind_mode = str(data["color_blind_mode"])

	time_scale_user = float(data.get("time_scale_user", _time_scale_user))
	time_scale_min = float(data.get("time_scale_min", time_scale_min))

	if data.has("fog_option"):
		fog_option = int(data["fog_option"])
	elif data.has("fog_enabled"):
		fog_enabled = bool(data["fog_enabled"])

	screen_shake = bool(data.get("screen_shake", screen_shake))
	motion_blur = bool(data.get("motion_blur", motion_blur))
	text_scale = float(data.get("text_scale", _text_scale))
	subtitles = bool(data.get("subtitles", subtitles))


func save() -> void:
	var sm := _resolve_save_manager()
	if sm == null:
		# Loud, not silent (GDD §6 discipline) — but non-fatal: a11y defaults
		# remain correct in memory, only persistence is lost.
		push_error("A11ySettings: SaveManager unavailable — preferences not persisted.")
		return
	sm.save_prefs(PREFS_SECTION, to_dict())


func load() -> void:
	var sm := _resolve_save_manager()
	if sm == null:
		return  # No store reachable yet; keep defaults.
	from_dict(sm.load_prefs(PREFS_SECTION))
