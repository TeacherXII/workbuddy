class_name A11ySettings
extends Node

# ASHEN STEP — Sprint 0 vertical slice (Phase 5).
# L2 accessibility settings persistence (E01-S6). Slice = interface + defaults
# only; the full settings panel lands in Part 2 / Sprint 2 (a11y package).
# Defaults follow control-manifest: screen_shake off (V-03), motion_blur off
# (V-05), fog on (V-04 base cap, no OFF in Basic), text_scale 1.0 (X-01),
# color_blind off (C-06), time_scale_min 0.1 (T-02 lower clamp).

const CONFIG_PATH := "user://a11y.cfg"

var color_blind_mode: String = "OFF"   # OFF | DEUTERANO | PROTANO | TRITANO
var time_scale_min: float = 0.1        # T-02 lower clamp (physics stability)
var screen_shake: bool = false         # V-03 default off
var fog_enabled: bool = true           # V-04 (Basic hard cap, no OFF)
var motion_blur: bool = false          # V-05 default off
var text_scale: float = 1.0            # X-01 default 100%


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("a11y", "color_blind_mode", color_blind_mode)
	cfg.set_value("a11y", "time_scale_min", time_scale_min)
	cfg.set_value("a11y", "screen_shake", screen_shake)
	cfg.set_value("a11y", "fog_enabled", fog_enabled)
	cfg.set_value("a11y", "motion_blur", motion_blur)
	cfg.set_value("a11y", "text_scale", text_scale)
	var err := cfg.save(CONFIG_PATH)
	if err != OK:
		push_error("A11ySettings: failed to save config (err=%d)" % err)


func load() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(CONFIG_PATH)
	if err != OK:
		return  # No saved config yet; keep defaults.
	color_blind_mode = cfg.get_value("a11y", "color_blind_mode", color_blind_mode)
	time_scale_min = cfg.get_value("a11y", "time_scale_min", time_scale_min)
	screen_shake = cfg.get_value("a11y", "screen_shake", screen_shake)
	fog_enabled = cfg.get_value("a11y", "fog_enabled", fog_enabled)
	motion_blur = cfg.get_value("a11y", "motion_blur", motion_blur)
	text_scale = cfg.get_value("a11y", "text_scale", text_scale)
