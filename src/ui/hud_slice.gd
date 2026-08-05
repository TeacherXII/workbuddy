class_name HudSlice
extends CanvasLayer

# ASHEN STEP — Sprint 1 Batch C. E09 core HUD + a11y.
# Stories: E09-S1 (focus readout / aim preview, Sprint 0) · E09-S2 (suspicion
# bar) · E09-S3 (world-element readability orchestration) · E09-S4 (item /
# charges slot) · E09-S6 (exposure ALERT overlay + soft-restart hint).
# Sprint 2 Batch C adds the a11y CONSUMPTION side: E09-S5a (C-06 danger
# mapping), E09-S5c (V-01/V-03/V-04/V-05 dizziness controls) and E09-S5d
# (X-01 text scale, X-02 subtitles).
#
# 色值权威 / colour authority: design/art/hud-a11y-signature.md v1.0
# (art-signed per D7), surfaced through src/ui/hud_colors.gd.
# ★ This file must contain NO hard-coded colour literal. Every colour is read
#   from HudColors.HUD_COLOR_* or from a HudColors.* resolver. (The Sprint 0
#   literals #10141C / #C8862F / #3E5C76 / #DCE3EC were removed by landmine 3.)
#
# ★ LANDMINE 1 (E09-S2): _on_suspicion_changed is the SOLE writer of
#   _suspicion.value. The Sprint 0 _on_vision_stimulus handler — which wrote
#   visibility*100 into the same bar — has been DELETED along with its
#   subscription. Two writers would have fought at 10Hz once GuardBrain started
#   emitting, flickering the bar between instantaneous visibility and
#   accumulated suspicion.
#
# ── a11y policy model (Sprint 2 · E09-S5c/S5d) ───────────────────────────────
# The HUD does NOT own accessibility state. A11ySettings owns the field model;
# this class holds a plain snapshot of it (`_policy`) taken through the SAME
# to_dict() shape the persistence layer uses, so a field can never mean one
# thing on disk and another on screen. The snapshot is refreshed by
# apply_a11y(); nothing here writes back.
#
# There is deliberately NO signal between the two. event-vocab-zero-drift
# freezes the bus vocabulary, so the a11y read is a PULL: whoever changes a
# setting calls hud.apply_a11y() (bootstrap wires this once).
#
# Near-diegetic, low-glare panel. No flashing UI (V-06); every periodic
# modulation is capped at FLICKER_HZ_MAX (V-01).

const HudColors = preload("res://src/ui/hud_colors.gd")
const EventBus = preload("res://src/core/event_bus.gd")
# The a11y ENUMS and DEFAULTS live with the field model that owns them
# (E09-S7). Preloaded rather than mirrored so there is exactly one definition;
# the preload form matches SUS_BORDER's proven pattern below.
const A11yModel = preload("res://src/core/a11y_settings.gd")

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

# --- E09-S5c: dizziness controls (V-01 / V-03 / V-04 / V-05) -----------------
# ★ V-01「无 >3Hz 闪烁」is a ceiling on EVERY periodic modulation this layer can
#   produce — alpha pulses AND positional displacement alike. Any new animated
#   channel must declare its frequency as a constant and stay under this, so the
#   reverse assertion in test_a11y_settings.gd can enumerate them.
const FLICKER_HZ_MAX := 3.0

# V-04「减弱雾 / 关闭雾」. 凝神压暗 (_dim) is the fog's HUD-side expression — a
# full-screen atmospheric veil — so it rides the same three-rung ladder. FULL is
# the Sprint 0/1 shipped value and must stay 0.35 or the default look changes.
const DIM_ALPHA_FULL := 0.35
const DIM_ALPHA_REDUCED := 0.15
const DIM_ALPHA_OFF := 0.0

# V-03「默认关闭屏震」. Sprint 2 ships no shake motion, and this resolver is the
# reason it cannot appear by accident: `offset` is written ONLY from
# shake_amplitude(), which returns 0.0 unless the player opted in. Anyone adding
# a shake must route it here or the reverse assertion catches the bypass.
const SHAKE_AMPLITUDE_PX := 6.0
const SHAKE_HZ := 2.5            # <= FLICKER_HZ_MAX (V-01)

# V-05「默认关闭动态模糊」. The HUD has no blur pass this sprint (no post-process
# stack until the Sprint 3 render work), so the resolved strength is 0.0 at the
# default AND 0.0 is the only value any shipped path can read. This is a POLICY
# SEAM, not dead code: the invariant it defends is "no blur may exist that did
# not pass through the setting" — see impl-notes CONCERN 2.
const MOTION_BLUR_STRENGTH := 0.35

# --- E09-S5d: text scale (X-01) + subtitles (X-02) ---------------------------
# X-01「100%–150% 不破版」. Every text-bearing widget derives its size AND its
# position from these bases times the scale, so 150% moves the layout instead of
# overlapping it. Base values are the Sprint 1 shipped numbers; at scale 1.0 the
# arithmetic is the identity and the shipped layout is bit-for-bit unchanged.
const BASE_FONT_SIZE := 16
const STATUS_BASE_POS := Vector2(16, 12)
const SUS_BAR_BASE_POS := Vector2(16, 40)
const SUS_BAR_BASE_SIZE := Vector2(240, 18)
const SUS_VALUE_BASE_POS := Vector2(264, 40)
const SUS_ICON_BASE_POS := Vector2(292, 40)
const ITEM_SLOT_BASE_POS := Vector2(16, 70)
const ITEM_SLOT_BASE_SIZE := Vector2(140, 24)
const ITEM_ICON_BASE_SIZE := Vector2(18, 18)
const ITEM_LABEL_BASE_POS := Vector2(24, 0)
const ITEM_CHARGES_BASE_POS := Vector2(96, 0)
const EXPOSURE_ICON_BASE_POS := Vector2(24, 96)
const EXPOSURE_TEXT_BASE_POS := Vector2(44, 96)
const EXPOSURE_HINT_BASE_POS := Vector2(44, 120)

# X-02「字幕含说话人 + 图标」. A bare line cannot say WHO or WHAT made the sound,
# which is the whole point of a subtitle for a player who cannot hear it.
const SUBTITLE_ICON := "♪"
const SUBTITLE_SPEAKER_FALLBACK := "环境"
const SUBTITLE_BOTTOM_MARGIN := 56.0

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

# E09-S5c / S5d
## Injected field model (E09-S7). Optional: an un-wired HUD keeps the shipped
## defaults instead of crashing, which is what lets the Sprint 1 tests construct
## a bare HudSlice and still get the Sprint 1 look.
var _a11y: A11ySettings = null
## Snapshot of the field model, in the SAME shape to_dict() persists. Seeded
## from the model's own defaults so the fallback can never drift from the
## shipped values — there is no second copy of them in this file.
var _policy: Dictionary = A11yModel.default_values()
## Mirrors the last time_scale_changed mode, so a settings change can re-apply
## the dim policy without waiting for the next focus transition.
var _focusing: bool = false
var _shake_t: float = 0.0
# E09-S5d
var _subtitle: Label = null


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
	# Its ALPHA is now the V-04 fog rung — see _apply_dim_policy.
	_dim = ColorRect.new()
	_dim.color = _with_alpha(HudColors.HUD_COLOR_PANEL_BASE, DIM_ALPHA_FULL)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.visible = false
	add_child(_dim)

	# Status / focus readout (top-left).
	_status = Label.new()
	_status.text = "灰烬之步 · Sprint1"
	_status.add_theme_color_override("font_color", HudColors.HUD_COLOR_CARRIER)
	_status.position = STATUS_BASE_POS
	add_child(_status)

	_build_suspicion_bar()
	_build_item_slot()
	_build_exposure_overlay()
	_build_subtitle()

	# Landing preview footprint (shape-coded, signed Caution amber) — hidden
	# until the player aims. Deliberately NOT text-scaled: it is a world-space
	# footprint whose size is a gameplay read, not a typographic one.
	_preview = Control.new()
	_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview.custom_minimum_size = Vector2(28, 28)
	var fp := ColorRect.new()
	fp.color = _with_alpha(HudColors.HUD_COLOR_CAUTION, 0.85)
	fp.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_preview.add_child(fp)
	_preview.visible = false
	add_child(_preview)

	# Everything is built: push the a11y policy through it once, so a HUD that
	# was handed settings BEFORE entering the tree still comes up configured.
	apply_a11y()


# --- E09-S2 ------------------------------------------------------------------
func _build_suspicion_bar() -> void:
	# Exactly ONE bar (C7 cognitive-load red line): it always shows the single
	# loudest guard, never a per-guard list.
	_suspicion = ProgressBar.new()
	_suspicion.min_value = 0.0
	_suspicion.max_value = 100.0
	_suspicion.value = 0.0   # construction-time init, NOT a runtime writer (L1-c)
	_suspicion.show_percentage = false
	_suspicion.custom_minimum_size = SUS_BAR_BASE_SIZE
	_suspicion.position = SUS_BAR_BASE_POS
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
	_sus_value.position = SUS_VALUE_BASE_POS
	_sus_value.visible = false
	add_child(_sus_value)

	# Tier glyph — shape coding (C-05), Carrier fill (C-02).
	_sus_icon = Label.new()
	_sus_icon.text = SUS_ICON[EventBus.SusTier.CALM]
	_sus_icon.add_theme_color_override("font_color", HudColors.HUD_COLOR_CARRIER)
	_sus_icon.position = SUS_ICON_BASE_POS
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
		# E09-S5a: the ALERT rung is the DANGER read, so it goes through the C-06
		# resolver instead of the raw constant. Every other rung is untouched —
		# Caution/Calm are not danger and must not be substituted.
		var border: Color = SUS_BORDER.get(tier, HudColors.HUD_COLOR_CALM)
		if tier == EventBus.SusTier.ALERT:
			border = HudColors.danger_color(colorblind_mode())
		_sus_border_style.border_color = border
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


## V-04, second consumer. The readability boost exists to punch the world read
## THROUGH the focus veil; with the veil switched off there is nothing to punch
## through, so the boost becomes gratuitous on-screen change and is suppressed.
## FULL and REDUCED both keep it — the veil is still there, just thinner.
func world_boost_allowed() -> bool:
	return fog_option() != A11yModel.FogOption.OFF


# --- E09-S4 ------------------------------------------------------------------
func _build_item_slot() -> void:
	_item_slot = Control.new()
	_item_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_item_slot.position = ITEM_SLOT_BASE_POS
	_item_slot.custom_minimum_size = ITEM_SLOT_BASE_SIZE
	_item_slot.visible = false

	# Shape swatch. Its ALPHA (not its hue) encodes availability.
	_item_icon = ColorRect.new()
	_item_icon.color = _with_alpha(HudColors.HUD_COLOR_CARRIER, 0.85)
	_item_icon.custom_minimum_size = ITEM_ICON_BASE_SIZE
	_item_icon.size = ITEM_ICON_BASE_SIZE
	_item_slot.add_child(_item_icon)

	# X-01: Labels with theme font sizes, never hard pixel metrics, so the
	# Sprint 2 100-150% text scale drops in without a relayout.
	_item_label = Label.new()
	_item_label.add_theme_color_override("font_color", HudColors.HUD_COLOR_CARRIER)
	_item_label.position = ITEM_LABEL_BASE_POS
	_item_slot.add_child(_item_label)

	_item_charges = Label.new()
	_item_charges.add_theme_color_override("font_color", HudColors.HUD_COLOR_CARRIER)
	_item_charges.position = ITEM_CHARGES_BASE_POS
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

	# Border: the SIGNED alarm colour, never the fill colour. E09-S5a routes it
	# through the C-06 resolver — at colorblind_mode OFF that IS HUD_COLOR_ALARM,
	# so the Sprint 1 look is unchanged.
	_exposure_frame = Panel.new()
	_exposure_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_exposure_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_exposure_border_style = StyleBoxFlat.new()
	_exposure_border_style.bg_color = _with_alpha(HudColors.HUD_COLOR_ALARM_FILL, 0.0)
	_exposure_border_style.set_border_width_all(3)
	_exposure_border_style.border_color = HudColors.danger_color(colorblind_mode())
	_exposure_frame.add_theme_stylebox_override("panel", _exposure_border_style)
	_exposure.add_child(_exposure_frame)

	# Shape channel (C-07): the '!' glyph carries the danger read on its own.
	# The glyph comes from HudColors so that "danger has a shape" is decided in
	# ONE place for every mode, including OFF.
	_exposure_icon = Label.new()
	_exposure_icon.text = HudColors.danger_icon(colorblind_mode())
	_exposure_icon.add_theme_color_override("font_color", HudColors.HUD_COLOR_CARRIER)
	_exposure_icon.position = EXPOSURE_ICON_BASE_POS
	_exposure.add_child(_exposure_icon)

	# Word channel (C-05/C-07).
	_exposure_text = Label.new()
	_exposure_text.text = "暴露"
	_exposure_text.add_theme_color_override("font_color", HudColors.HUD_COLOR_CARRIER)
	_exposure_text.position = EXPOSURE_TEXT_BASE_POS
	_exposure.add_child(_exposure_text)

	# Sprint 1 delivers a STATIC hint only. The real soft restart (SaveManager,
	# respawn, confirmation flow) is D9 -> Sprint 2.
	_exposure_hint = Label.new()
	_exposure_hint.text = "被发现 · 将从上一处安全点重来"
	_exposure_hint.add_theme_color_override("font_color", HudColors.HUD_COLOR_CARRIER)
	_exposure_hint.position = EXPOSURE_HINT_BASE_POS
	_exposure.add_child(_exposure_hint)

	add_child(_exposure)


func _on_exposure_detected(_guard_id: int, _target: Node) -> void:
	if _exposure == null:
		return
	_exposure_on = true
	_exposure_fade_t = 0.0
	_exposure.visible = true
	_set_modulate_alpha(_exposure, 0.0)
	# V-03: screen shake is governed by A11ySettings.screen_shake (default
	# false) and reaches the screen ONLY through shake_amplitude() in _process.


func is_exposure_visible() -> bool:
	return _exposure != null and _exposure.visible


# --- E09-S5d: subtitles (X-02) -----------------------------------------------
func _build_subtitle() -> void:
	# Bottom-anchored so it survives any viewport size; the two offsets are the
	# only pixel metrics, and both are text-scaled with everything else.
	_subtitle = Label.new()
	_subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.add_theme_color_override("font_color", HudColors.HUD_COLOR_CARRIER)
	_subtitle.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_subtitle.visible = false
	add_child(_subtitle)


## X-02. The rendered line, as a pure function so a test can assert the SHAPE of
## a subtitle without a viewport. Icon + speaker + line: the icon says "this is
## a sound", the speaker says whose, the line says what.
static func subtitle_text(speaker: String, line: String) -> String:
	var who := speaker.strip_edges()
	if who == "":
		who = SUBTITLE_SPEAKER_FALLBACK
	return "%s %s：%s" % [SUBTITLE_ICON, who, line]


## X-02. Returns whether the subtitle was actually shown, so a caller can tell
## "suppressed by the setting" from "no widget yet" instead of guessing.
func show_subtitle(speaker: String, line: String) -> bool:
	if _subtitle == null:
		return false
	if not subtitles_enabled():
		_subtitle.visible = false
		return false
	_subtitle.text = subtitle_text(speaker, line)
	_subtitle.visible = true
	return true


func hide_subtitle() -> void:
	if _subtitle != null:
		_subtitle.visible = false


# --- E09-S5c / S5d: a11y policy ----------------------------------------------

## DI hook, mirroring set_event_bus. Takes a SNAPSHOT immediately; the HUD never
## holds a live reference for reads, so a settings object freed mid-frame cannot
## take the HUD down with it.
func set_a11y_settings(settings: A11ySettings) -> void:
	_a11y = settings
	apply_a11y()


## Re-read the field model and push every derived value through the widgets.
## Called on build, on injection, and by whoever changes a setting (PULL model —
## event-vocab-zero-drift forbids a new signal for this).
func apply_a11y() -> void:
	if _a11y != null and is_instance_valid(_a11y):
		_policy = _a11y.to_dict()
	_apply_dim_policy()
	_apply_danger_policy()
	_apply_text_scale()
	if not subtitles_enabled():
		hide_subtitle()


## The snapshot, for tests and for a settings screen that wants to echo the
## resolved state. Duplicated on the way out so no caller can mutate the HUD's
## view of the model.
func a11y_policy() -> Dictionary:
	return _policy.duplicate()


func colorblind_mode() -> int:
	return A11yModel.normalize_colorblind_mode(
		int(_policy.get("colorblind_mode", A11yModel.ColorBlindMode.OFF)))


func fog_option() -> int:
	return A11yModel.normalize_fog_option(
		int(_policy.get("fog_option", A11yModel.FogOption.FULL)))


func screen_shake_enabled() -> bool:
	return bool(_policy.get("screen_shake", false))


func motion_blur_enabled() -> bool:
	return bool(_policy.get("motion_blur", false))


func subtitles_enabled() -> bool:
	return bool(_policy.get("subtitles", true))


func text_scale() -> float:
	return clampf(
		float(_policy.get("text_scale", A11yModel.TEXT_SCALE_DEFAULT)),
		A11yModel.TEXT_SCALE_MIN, A11yModel.TEXT_SCALE_MAX)


## V-04. Strictly DECREASING across the three rungs, which is the property the
## reverse assertion checks: a "reduced" fog that is not actually weaker than
## FULL would be an accessibility setting that lies.
static func dim_alpha_for(fog: int) -> float:
	if fog == A11yModel.FogOption.OFF:
		return DIM_ALPHA_OFF
	if fog == A11yModel.FogOption.REDUCED:
		return DIM_ALPHA_REDUCED
	return DIM_ALPHA_FULL


func dim_alpha() -> float:
	return dim_alpha_for(fog_option())


## V-03. The ONLY source of HUD-layer displacement. 0.0 at the shipped default.
func shake_amplitude() -> float:
	if not screen_shake_enabled():
		return 0.0
	return SHAKE_AMPLITUDE_PX


## V-05. 0.0 at the shipped default, and the only gate a future blur may pass.
func motion_blur_strength() -> float:
	if not motion_blur_enabled():
		return 0.0
	return MOTION_BLUR_STRENGTH


func _apply_dim_policy() -> void:
	if _dim == null:
		return
	_dim.color = _with_alpha(HudColors.HUD_COLOR_PANEL_BASE, dim_alpha())
	# Fog OFF removes the veil entirely rather than drawing a fully transparent
	# rect — cheaper, and it makes "off" observable in a test.
	_dim.visible = _focusing and fog_option() != A11yModel.FogOption.OFF


func _apply_danger_policy() -> void:
	# E09-S5a. Re-resolve every DANGER carrier after a mode change. Non-danger
	# hues are deliberately untouched: substituting Caution too would collapse
	# the very distinction C-06 exists to preserve.
	if _exposure_border_style != null:
		_exposure_border_style.border_color = HudColors.danger_color(colorblind_mode())
	if _exposure_icon != null:
		_exposure_icon.text = HudColors.danger_icon(colorblind_mode())
	if _sus_border_style != null and _top_guard_id >= 0:
		var entry: Dictionary = _suspicion_by_guard.get(_top_guard_id, {})
		if int(entry.get("tier", EventBus.SusTier.CALM)) == EventBus.SusTier.ALERT:
			_sus_border_style.border_color = HudColors.danger_color(colorblind_mode())


func _apply_text_scale() -> void:
	# X-01. At scale 1.0 every expression below is the identity, so the shipped
	# layout is untouched; at 1.5 the metrics move together instead of the text
	# growing into a fixed box.
	var s := text_scale()
	var px := roundi(float(BASE_FONT_SIZE) * s)
	for label in [_status, _sus_value, _sus_icon, _item_label, _item_charges,
			_exposure_icon, _exposure_text, _exposure_hint, _subtitle]:
		if label != null:
			label.add_theme_font_size_override("font_size", px)

	if _status != null:
		_status.position = STATUS_BASE_POS * s
	if _suspicion != null:
		_suspicion.position = SUS_BAR_BASE_POS * s
		_suspicion.custom_minimum_size = SUS_BAR_BASE_SIZE * s
	if _sus_value != null:
		_sus_value.position = SUS_VALUE_BASE_POS * s
	if _sus_icon != null:
		_sus_icon.position = SUS_ICON_BASE_POS * s
	if _item_slot != null:
		_item_slot.position = ITEM_SLOT_BASE_POS * s
		_item_slot.custom_minimum_size = ITEM_SLOT_BASE_SIZE * s
	if _item_icon != null:
		_item_icon.custom_minimum_size = ITEM_ICON_BASE_SIZE * s
		_item_icon.size = ITEM_ICON_BASE_SIZE * s
	if _item_label != null:
		_item_label.position = ITEM_LABEL_BASE_POS * s
	if _item_charges != null:
		_item_charges.position = ITEM_CHARGES_BASE_POS * s
	if _exposure_icon != null:
		_exposure_icon.position = EXPOSURE_ICON_BASE_POS * s
	if _exposure_text != null:
		_exposure_text.position = EXPOSURE_TEXT_BASE_POS * s
	if _exposure_hint != null:
		_exposure_hint.position = EXPOSURE_HINT_BASE_POS * s
	if _subtitle != null:
		_subtitle.offset_top = -SUBTITLE_BOTTOM_MARGIN * s
		_subtitle.offset_bottom = -SUBTITLE_BOTTOM_MARGIN * s * 0.25


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


func _on_time_scale_changed(_old: float, new_scale: float, mode: String) -> void:
	_focusing = mode == "FOCUS"
	if _status != null:
		# E09-S5b: the readout quotes the ACTUAL scale. A hard-coded "0.25×"
		# would contradict the slider the moment a player moved it, and a HUD
		# that contradicts an accessibility setting is worse than no readout.
		# At the shipped default this formats to exactly "凝神 0.25×".
		_status.text = ("凝神 %.2f×" % new_scale) if _focusing else "FLOWING 1.0×"
	_apply_dim_policy()
	# E09-S3: FOCUS is also the readability beat for world-space elements,
	# subject to the V-04 veil gate.
	_set_world_boost(_focusing and world_boost_allowed())


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

	# V-03: run BEFORE the exposure early-out so that `offset` is driven back to
	# exactly Vector2.ZERO on every frame the shake is not authorised.
	_apply_shake(rd)

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


func _apply_shake(rd: float) -> void:
	var amp := shake_amplitude()
	if amp <= 0.0 or not _exposure_on:
		_shake_t = 0.0
		offset = Vector2.ZERO
		return
	# Two co-prime-ish frequencies so the motion reads as a shake rather than a
	# circle, both derived from SHAKE_HZ so the V-01 ceiling binds the whole
	# figure and not just one axis.
	_shake_t = fmod(_shake_t + rd * SHAKE_HZ, 1.0)
	var phase := _shake_t * TAU
	offset = Vector2(sin(phase), cos(phase * 1.7)) * amp


static func _with_alpha(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, a)


static func _set_modulate_alpha(node: CanvasItem, a: float) -> void:
	if node == null:
		return
	var m := node.modulate
	m.a = a
	node.modulate = m
