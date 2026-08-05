class_name A11ySettings
extends Node

# ASHEN STEP — Sprint 0 vertical slice (Phase 5), Sprint 2 Batch A persistence.
# L2 accessibility settings persistence (E01-S6). Slice = interface + defaults
# only; the full settings panel lands in Part 2 / Sprint 2 (a11y package).
# Defaults follow control-manifest: screen_shake off (V-03), motion_blur off
# (V-05), fog on (V-04 base cap, no OFF in Basic), text_scale 1.0 (X-01),
# color_blind off (C-06), time_scale_min 0.1 (T-02 lower clamp).
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

## Legacy Sprint 0 path. Kept for reference only — nothing here reads or writes
## it any more. The one-time migration is owned by
## SaveManager.LEGACY_A11Y_PATH (SAV-S4). @deprecated
const CONFIG_PATH := "user://a11y.cfg"

## Preference store section key. Opaque to SaveManager by design (FLAG-J).
const PREFS_SECTION := "a11y"

var color_blind_mode: String = "OFF"   # OFF | DEUTERANO | PROTANO | TRITANO
var time_scale_min: float = 0.1        # T-02 lower clamp (physics stability)
var screen_shake: bool = false         # V-03 default off
var fog_enabled: bool = true           # V-04 (Basic hard cap, no OFF)
var motion_blur: bool = false          # V-05 default off
var text_scale: float = 1.0            # X-01 default 100%

# Injected L2 service. Left untyped (Node) on purpose: save_manager.gd has no
# `class_name` because it is the `SaveManager` autoload (see its header).
var _save: Node = null


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


## Field model -> plain Dictionary. This is the ONLY place field names appear on
## the persistence path; SaveManager stores it verbatim.
func to_dict() -> Dictionary:
	return {
		"color_blind_mode": color_blind_mode,
		"time_scale_min": time_scale_min,
		"screen_shake": screen_shake,
		"fog_enabled": fog_enabled,
		"motion_blur": motion_blur,
		"text_scale": text_scale,
	}


## Dictionary -> field model. Missing keys keep the current (default) value, so
## a preference file written by an older/newer build is forward/backward
## compatible field-by-field (SAV-S4: "缺字段用默认值补全").
func from_dict(data: Dictionary) -> void:
	color_blind_mode = str(data.get("color_blind_mode", color_blind_mode))
	time_scale_min = float(data.get("time_scale_min", time_scale_min))
	screen_shake = bool(data.get("screen_shake", screen_shake))
	fog_enabled = bool(data.get("fog_enabled", fog_enabled))
	motion_blur = bool(data.get("motion_blur", motion_blur))
	text_scale = float(data.get("text_scale", text_scale))


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
