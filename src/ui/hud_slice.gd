class_name HudSlice
extends CanvasLayer

# ASHEN STEP — Sprint 1 Batch C. E09 core HUD + a11y.
# Stories: E09-S1 (focus readout / aim preview, Sprint 0) · E09-S2 (suspicion
# bar) · E09-S3 (world-element readability orchestration) · E09-S4 (item /
# charges slot) · E09-S6 (exposure ALERT overlay + soft-restart hint).
#
# 色值权威 / colour authority: design/art/hud-a11y-signature.md v1.0
# (art-signed per D7), surfaced through src/ui/hud_colors.gd.
# ★ This file must contain NO hard-coded colour literal. Every colour is read
#   from HudColors.HUD_COLOR_*. (The Sprint 0 literals #10141C / #C8862F /
#   #3E5C76 / #DCE3EC were removed by landmine 3.)
#
# ★ LANDMINE 1 (E09-S2): _on_suspicion_changed is the SOLE writer of
#   _suspicion.value. The Sprint 0 _on_vision_stimulus handler — which wrote
#   visibility*100 into the same bar — has been DELETED along with its
#   subscription. Two writers would have fought at 10Hz once GuardBrain started
#   emitting, flickering the bar between instantaneous visibility and
#   accumulated suspicion.
#
# Near-diegetic, low-glare panel. No flashing UI (V-06); every pulse is capped
# at EXPOSURE_PULSE_HZ (V-02).

const HudColors = preload("res://src/ui/hud_colors.gd")
const EventBus = preload("res://src/core/event_bus.gd")

# --- E09-S2: suspicion bar (C7 aggregation + NEW-1 brightness ladder) --------
# Below this value every guard counts as quiet and the bar hides entirely
# (pillar 4: the HUD falls silent). Mirrors GuardBrain.SUS_EMIT_EPS.
const SUS_BAR_HIDE_EPS := 0.5

# NEW-1 (spec §2.3.3): the fill is a Carrier-white ALPHA ladder, not the semantic
# hues. The signed palette's relative luminance runs CALM 0.100 -> CAUTION 0.295
# -> ALARM 0.190, i.e. NOT monotonic — using it as the fill would invert the
# brightness coding the GDD requires. An alpha ladder is strictly monotonic and
# introduces no new hue (art-bible §2.4). Semantic hues stay on the BORDER.
const SUS_FILL_ALPHA := {
	EventBus.SusTier.CALM: 0.30,
	EventBus.SusTier.SUSPICIOUS: 0.60,
	EventBus.SusTier.SEARCH: 0.75,
	EventBus.SusTier.ALERT: 0.92,
}
const SUS_BORDER := {
	EventBus.SusTier.CALM: HudColors.HUD_COLOR_CALM,
	EventBus.SusTier.SUSPICIOUS: HudColors.HUD_COLOR_CAUTION,
	EventBus.SusTier.SEARCH: HudColors.HUD_COLOR_CAUTION,
	EventBus.SusTier.ALERT: HudColors.HUD_COLOR_ALARM,
}
# C-05 shape coding: the tier is legible from the glyph alone.
const SUS_ICON := {
	EventBus.SusTier.CALM: "◉",
	EventBus.SusTier.SUSPICIOUS: "?",
	EventBus.SusTier.SEARCH: "⌕",
	EventBus.SusTier.ALERT: "!",
}

# --- E09-S4: item / charges slot (D8) ---------------------------------------
const ITEM_LABEL := {
	EventBus.InteractableType.DECOY: "DECOY",
	EventBus.InteractableType.LIGHT_TOGGLE: "LIGHT",
	EventBus.InteractableType.TRAP: "TRAP",
	EventBus.InteractableType.SMOKE: "SMOKE",
}
# charges == 0 dims the ICON only; the numeral stays fully bright, so
# "unavailable" is carried by alpha AND by the digit — never by hue (C-05).
const CHARGES_DIM_ALPHA := 0.4

# --- E09-S6: exposure overlay -----------------------------------------------
const EXPOSURE_PULSE_HZ := 2.0   # V-02 ceiling (matches vision_cone.gd:30)
const EXPOSURE_FADE_SEC := 0.4   # V-06 eased fade-in; hard cuts are forbidden
const EXPOSURE_PULSE_MIN_A := 0.55
const EXPOSURE_PULSE_MAX_A := 1.0

var _bus: EventBus = null

# Sprint 0 widgets
var _dim: ColorRect = null
var _status: Label = null
var _preview: Control = null

# E09-S2
var _suspicion: ProgressBar = null
var _sus_value: Label = null
var _sus_icon: Label = null
var _sus_fill_style: StyleBoxFlat = null
var _sus_border_style: StyleBoxFlat = null
var _suspicion_by_guard: Dictionary = {}     # guard_id -> {"value": float, "tier": int}
var _top_guard_id: int = -1

# E09-S3
var _world_elements: Array[Object] = []

# E09-S4
var _item_slot: Control = null
var _item_icon: ColorRect = null
var _item_label: Label = null
var _item_charges: Label = null
var _has_item: bool = false
var _item_type: int = -1
var _item_charge_count: int = 0

# E09-S6
var _exposure: Control = null
var _exposure_fill: ColorRect = null
var _exposure_frame: Panel = null
var _exposure_border_style: StyleBoxFlat = null
var _exposure_icon: Label = null
var _exposure_text: Label = null
var _exposure_hint: Label = null
var _exposure_on: bool = false
var _exposure_fade_t: float = 0.0
var _pulse_t: float = 0.0
var _last_ms: int = 0


func _ready() -> void:
	# Prefer an explicitly injected bus (set_event_bus). The group lookup is only
	# a fallback for scene-driven wiring: get_first_node_in_group returns the
	# FIRST registered EventBus, which is not necessarily the one this HUD is
	# meant to observe when several buses exist in the tree.
	if _bus == null:
		_bus = get_tree().get_first_node_in_group("event_bus") as EventBus
	_build_ui()
	_connect_bus()


# Explicit dependency injection (preferred over the group lookup). Safe to call
# before or after the node enters the tree: the UI widgets are null-guarded in
# every handler, and _connect_bus is idempotent.
func set_event_bus(bus: EventBus) -> void:
	_bus = bus
	_connect_bus()


func _connect_bus() -> void:
	if _bus == null or not is_instance_valid(_bus):
		return
	# Idempotent: _ready and set_event_bus may both run, in either order.
	if not _bus.time_scale_changed.is_connected(_on_time_scale_changed):
		_bus.time_scale_changed.connect(_on_time_scale_changed)
	# ★ LANDMINE 1: there is deliberately NO vision_stimulus subscription here.
	# The suspicion bar has exactly one data source, suspicion_changed, which is
	# emitted by GuardBrain (E08-S6). Re-adding a vision_stimulus handler would
	# resurrect the 10Hz double-write flicker.
	if not _bus.suspicion_changed.is_connected(_on_suspicion_changed):
		_bus.suspicion_changed.connect(_on_suspicion_changed)
	if not _bus.player_step_committed.is_connected(_on_step_committed):
		_bus.player_step_committed.connect(_on_step_committed)
	if not _bus.interactable_triggered.is_connected(_on_interactable_triggered):
		_bus.interactable_triggered.connect(_on_interactable_triggered)
	if not _bus.exposure_detected.is_connected(_on_exposure_detected):
		_bus.exposure_detected.connect(_on_exposure_detected)


func _build_ui() -> void:
	# Focus dim overlay (covers viewport, only visible while focusing). Uses the
	# signed panel base rather than the retired #10141C literal (landmine 3).
	_dim = ColorRect.new()
	_dim.color = _with_alpha(HudColors.HUD_COLOR_PANEL_BASE, 0.35)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.visible = false
	add_child(_dim)

	# Status / focus readout (top-left).
	_status = Label.new()
	_status.text = "灰烬之步 · Sprint1"
	_status.add_theme_color_override("font_color", HudColors.HUD_COLOR_CARRIER)
	_status.position = Vector2(16, 12)
	add_child(_status)

	_build_suspicion_bar()
	_build_item_slot()
	_build_exposure_overlay()

	# Landing preview footprint (shape-coded, signed Caution amber) — hidden
	# until the player aims.
	_preview = Control.new()
	_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview.custom_minimum_size = Vector2(28, 28)
	var fp := ColorRect.new()
	fp.color = _with_alpha(HudColors.HUD_COLOR_CAUTION, 0.85)
	fp.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_preview.add_child(fp)
	_preview.visible = false
	add_child(_preview)


# --- E09-S2 ------------------------------------------------------------------
func _build_suspicion_bar() -> void:
	# Exactly ONE bar (C7 cognitive-load red line): it always shows the single
	# loudest guard, never a per-guard list.
	_suspicion = ProgressBar.new()
	_suspicion.min_value = 0.0
	_suspicion.max_value = 100.0
	_suspicion.value = 0.0   # construction-time init, NOT a runtime writer (L1-c)
	_suspicion.show_percentage = false
	_suspicion.custom_minimum_size = Vector2(240, 18)
	_suspicion.position = Vector2(16, 40)
	_suspicion.visible = false            # silent until a guard actually stirs

	# Fill = Carrier alpha ladder (NEW-1). Background carries the tier border and
	# a Carrier inner stroke, which is the element C-02 is measured on.
	_sus_fill_style = StyleBoxFlat.new()
	_sus_fill_style.bg_color = _with_alpha(
		HudColors.HUD_COLOR_CARRIER, SUS_FILL_ALPHA[EventBus.SusTier.CALM])
	_sus_border_style = StyleBoxFlat.new()
	_sus_border_style.bg_color = _with_alpha(HudColors.HUD_COLOR_PANEL_BASE, 0.85)
	_sus_border_style.set_border_width_all(1)
	_sus_border_style.border_color = SUS_BORDER[EventBus.SusTier.CALM]
	_suspicion.add_theme_stylebox_override("fill", _sus_fill_style)
	_suspicion.add_theme_stylebox_override("background", _sus_border_style)
	add_child(_suspicion)

	# Numeric readout — Carrier white, 13.74:1 (C-02).
	_sus_value = Label.new()
	_sus_value.text = "0"
	_sus_value.add_theme_color_override("font_color", HudColors.HUD_COLOR_CARRIER)
	_sus_value.position = Vector2(264, 40)
	_sus_value.visible = false
	add_child(_sus_value)

	# Tier glyph — shape coding (C-05), Carrier fill (C-02).
	_sus_icon = Label.new()
	_sus_icon.text = SUS_ICON[EventBus.SusTier.CALM]
	_sus_icon.add_theme_color_override("font_color", HudColors.HUD_COLOR_CARRIER)
	_sus_icon.position = Vector2(292, 40)
	_sus_icon.visible = false
	add_child(_sus_icon)


# ★ LANDMINE 1: the ONLY writer of _suspicion.value.
func _on_suspicion_changed(guard_id: int, value: float, tier: int) -> void:
	_suspicion_by_guard[guard_id] = {"value": value, "tier": tier}
	_refresh_top_guard()


func _refresh_top_guard() -> void:
	if _suspicion == null:
		return
	# argmax by value; ties resolve to the LOWEST guard_id so the display is
	# deterministic (and therefore testable).
	var best_id := -1
	var best_val := -1.0
	for gid in _suspicion_by_guard:
		var v: float = _suspicion_by_guard[gid]["value"]
		if v > best_val or (is_equal_approx(v, best_val) and gid < best_id):
			best_val = v
			best_id = gid
	_top_guard_id = best_id

	# N-4: clamp ONCE, then drive EVERY readout from that one figure. Deriving
	# the number from the raw `best_val` let an out-of-range emission print
	# "150" next to a bar pinned at 100 — and per C-02 the number is the
	# authoritative carrier, so the two must never disagree.
	var shown := clampf(best_val, 0.0, 100.0)
	# ★ LANDMINE 1: this is the single write site, and it runs on BOTH branches.
	# Writing it only on the visible branch left a hidden bar holding the last
	# value, which then flashed for one frame when the next guard stirred.
	_suspicion.value = shown

	if best_id < 0 or best_val < SUS_BAR_HIDE_EPS:
		_set_bar_visible(false)
		return
	_set_bar_visible(true)
	_sus_value.text = "%d" % roundi(shown)
	_apply_tier_visuals(int(_suspicion_by_guard[best_id]["tier"]))


func _set_bar_visible(on: bool) -> void:
	if _suspicion != null:
		_suspicion.visible = on
	if _sus_value != null:
		_sus_value.visible = on
	if _sus_icon != null:
		_sus_icon.visible = on


func _apply_tier_visuals(tier: int) -> void:
	# Fill: brightness step only. Border: semantic hue. Glyph: shape. Three
	# independent channels, so no single one of them is load-bearing (C-05/C-07).
	if _sus_fill_style != null:
		var alpha: float = SUS_FILL_ALPHA.get(tier, SUS_FILL_ALPHA[EventBus.SusTier.CALM])
		_sus_fill_style.bg_color = _with_alpha(HudColors.HUD_COLOR_CARRIER, alpha)
	if _sus_border_style != null:
		_sus_border_style.border_color = SUS_BORDER.get(tier, HudColors.HUD_COLOR_CALM)
	if _sus_icon != null:
		_sus_icon.text = SUS_ICON.get(tier, SUS_ICON[EventBus.SusTier.CALM])


# --- E09-S3 ------------------------------------------------------------------
# Duck-typed orchestration: E09 only ever calls set_readability_boost(on) and
# never reaches into anyone's material or shader ("orchestrate, don't repaint").
func register_world_element(obj: Object) -> void:
	if obj != null and not _world_elements.has(obj):
		_world_elements.append(obj)


func _set_world_boost(on: bool) -> void:
	for element in _world_elements:
		if is_instance_valid(element) and element.has_method("set_readability_boost"):
			element.set_readability_boost(on)


# --- E09-S4 ------------------------------------------------------------------
func _build_item_slot() -> void:
	_item_slot = Control.new()
	_item_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_item_slot.position = Vector2(16, 70)
	_item_slot.custom_minimum_size = Vector2(140, 24)
	_item_slot.visible = false

	# Shape swatch. Its ALPHA (not its hue) encodes availability.
	_item_icon = ColorRect.new()
	_item_icon.color = _with_alpha(HudColors.HUD_COLOR_CARRIER, 0.85)
	_item_icon.custom_minimum_size = Vector2(18, 18)
	_item_icon.size = Vector2(18, 18)
	_item_slot.add_child(_item_icon)

	# X-01: Labels with theme font sizes, never hard pixel metrics, so the
	# Sprint 2 100-150% text scale drops in without a relayout.
	_item_label = Label.new()
	_item_label.add_theme_color_override("font_color", HudColors.HUD_COLOR_CARRIER)
	_item_label.position = Vector2(24, 0)
	_item_slot.add_child(_item_label)

	_item_charges = Label.new()
	_item_charges.add_theme_color_override("font_color", HudColors.HUD_COLOR_CARRIER)
	_item_charges.position = Vector2(96, 0)
	_item_slot.add_child(_item_charges)

	add_child(_item_slot)


# [D8] (obj_id, type: InteractableType, payload). payload minimal shape:
# {"charges": int}; Sprint 2 may add keys without breaking this contract.
func _on_interactable_triggered(_obj_id: int, type: int, payload: Dictionary) -> void:
	_item_type = type
	_item_charge_count = int(payload.get("charges", 0))
	_has_item = true
	_refresh_item_slot()


func _refresh_item_slot() -> void:
	if _item_slot == null:
		return
	if not _has_item:
		_item_slot.visible = false
		return
	_item_slot.visible = true
	_item_label.text = ITEM_LABEL.get(_item_type, "ITEM")
	_item_charges.text = "%d" % _item_charge_count
	# Dual encoding: icon alpha AND the digit. An exhausted item stays on screen
	# (dimmed) rather than vanishing, so the player keeps the spatial memory.
	_set_modulate_alpha(_item_icon, 1.0 if _item_charge_count > 0 else CHARGES_DIM_ALPHA)
	_set_modulate_alpha(_item_charges, 1.0)


# --- E09-S6 ------------------------------------------------------------------
func _build_exposure_overlay() -> void:
	_exposure = Control.new()
	_exposure.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_exposure.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_exposure.visible = false

	# ★ LANDMINE 3, the one legal home of #7A2E2E: a FILL, at alpha <= 0.35,
	# with white carriers on top. Composited over the panel this is L~0.020, so
	# Carrier text reads 11.6:1 (C-02) and the alarm border 3.4:1 (C-03) on it.
	_exposure_fill = ColorRect.new()
	_exposure_fill.color = _with_alpha(
		HudColors.HUD_COLOR_ALARM_FILL, HudColors.ALARM_FILL_ALPHA_MAX)
	_exposure_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_exposure_fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_exposure.add_child(_exposure_fill)

	# Border: the SIGNED alarm colour, never the fill colour.
	_exposure_frame = Panel.new()
	_exposure_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_exposure_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_exposure_border_style = StyleBoxFlat.new()
	_exposure_border_style.bg_color = _with_alpha(HudColors.HUD_COLOR_ALARM_FILL, 0.0)
	_exposure_border_style.set_border_width_all(3)
	_exposure_border_style.border_color = HudColors.HUD_COLOR_ALARM
	_exposure_frame.add_theme_stylebox_override("panel", _exposure_border_style)
	_exposure.add_child(_exposure_frame)

	# Shape channel (C-07): the '!' glyph carries the danger read on its own.
	_exposure_icon = Label.new()
	_exposure_icon.text = "!"
	_exposure_icon.add_theme_color_override("font_color", HudColors.HUD_COLOR_CARRIER)
	_exposure_icon.position = Vector2(24, 96)
	_exposure.add_child(_exposure_icon)

	# Word channel (C-05/C-07).
	_exposure_text = Label.new()
	_exposure_text.text = "暴露"
	_exposure_text.add_theme_color_override("font_color", HudColors.HUD_COLOR_CARRIER)
	_exposure_text.position = Vector2(44, 96)
	_exposure.add_child(_exposure_text)

	# Sprint 1 delivers a STATIC hint only. The real soft restart (SaveManager,
	# respawn, confirmation flow) is D9 -> Sprint 2.
	_exposure_hint = Label.new()
	_exposure_hint.text = "被发现 · 将从上一处安全点重来"
	_exposure_hint.add_theme_color_override("font_color", HudColors.HUD_COLOR_CARRIER)
	_exposure_hint.position = Vector2(44, 120)
	_exposure.add_child(_exposure_hint)

	add_child(_exposure)


func _on_exposure_detected(_guard_id: int, _target: Node) -> void:
	if _exposure == null:
		return
	_exposure_on = true
	_exposure_fade_t = 0.0
	_exposure.visible = true
	_set_modulate_alpha(_exposure, 0.0)
	# V-03: screen shake stays governed by A11ySettings.screen_shake (default
	# false). Sprint 1 ships no shake at all, so the default is honoured.


func is_exposure_visible() -> bool:
	return _exposure != null and _exposure.visible


# --- shared ------------------------------------------------------------------
func set_aim_preview(world_pos: Vector3) -> void:
	if _preview == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		_preview.visible = false
		return
	var screen := cam.unproject_position(world_pos)
	_preview.position = screen - _preview.custom_minimum_size * 0.5
	_preview.visible = true


func _on_time_scale_changed(_old: float, _new: float, mode: String) -> void:
	var focusing := mode == "FOCUS"
	if _status != null:
		_status.text = "凝神 0.25×" if focusing else "FLOWING 1.0×"
	if _dim != null:
		_dim.visible = focusing
	# E09-S3: FOCUS is also the readability beat for world-space elements.
	_set_world_boost(focusing)


func _on_step_committed(_payload: Dictionary) -> void:
	# Optional: confirm footprint on commit.
	if _preview != null:
		_preview.visible = true


# Real-time animation for the exposure overlay. Deliberately NOT a Tween:
# a looping tween outlives the test that created it and shows up as an orphan,
# and the fade must not be scaled by Engine.time_scale (the player needs the
# same read speed in FOCUS). Same wall-clock pattern as vision_cone.gd:154-160.
func _process(_scaled: float) -> void:
	var now := Time.get_ticks_msec()
	var rd := 0.0
	if _last_ms > 0:
		rd = float(now - _last_ms) / 1000.0
	_last_ms = now
	if rd <= 0.0 or not _exposure_on or _exposure == null:
		return

	# V-06: eased fade-in, never a hard cut.
	if _exposure_fade_t < 1.0:
		_exposure_fade_t = minf(1.0, _exposure_fade_t + rd / EXPOSURE_FADE_SEC)
	var eased := ease(_exposure_fade_t, 0.5)
	_set_modulate_alpha(_exposure, eased)

	# V-02: pulse the BORDER and ICON only (never the fill colour, never the
	# border hue) at a frequency capped by EXPOSURE_PULSE_HZ.
	_pulse_t = fmod(_pulse_t + rd * EXPOSURE_PULSE_HZ, 1.0)
	var wave := 0.5 - 0.5 * cos(_pulse_t * TAU)
	var pulse_a: float = lerpf(EXPOSURE_PULSE_MIN_A, EXPOSURE_PULSE_MAX_A, wave)
	_set_modulate_alpha(_exposure_frame, pulse_a)
	_set_modulate_alpha(_exposure_icon, pulse_a)


static func _with_alpha(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, a)


static func _set_modulate_alpha(node: CanvasItem, a: float) -> void:
	if node == null:
		return
	var m := node.modulate
	m.a = a
	node.modulate = m
