# tests/unit/test_hud_slice.gd
# GUT tests for the real E09 HudSlice (core-hud-a11y §2) — Sprint 1, Batch C.
#
# Hook coverage (batchc-impl-spec §8): H12 H13 H14 H15 H16 H17, plus the E09-S1
# focus-readout / aim-preview tests carried over from Sprint 0.
#
# ⚠ N-3 (spec §8.1): `test_suspicion_bar_updates_on_vision_stimulus` USED to live
#   here and asserted that vision_stimulus wrote the suspicion bar. That is
#   exactly the behaviour landmine 1 removes (the bar had TWO writers and would
#   flicker at 10Hz once GuardBrain started emitting suspicion_changed). It is
#   rewritten below as H13 `test_suspicion_bar_updates_on_suspicion_changed`,
#   which now asserts the OPPOSITE: vision_stimulus must NOT move the bar.
#
# NOTE (N2 / §6.1 of sprint0-qa-plan): this test requires a live scene tree
# (EventBus must be in group "event_bus" so HudSlice._ready can connect) and a
# Camera3D for set_aim_preview's unproject.
#
# Run: godot --headless -s res://addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit

extends GutTest

const HudSlice = preload("res://src/ui/hud_slice.gd")
const HudColors = preload("res://src/ui/hud_colors.gd")
const EventBus = preload("res://src/core/event_bus.gd")
const A11ySettings = preload("res://src/core/a11y_settings.gd")


# E09-S3 orchestration stub. RefCounted (not Node) so it is reference-freed and
# never shows up in the orphan count.
class BoostStub extends RefCounted:
	var boost_calls: Array = []

	func set_readability_boost(on: bool) -> void:
		boost_calls.append(on)


var _bus: EventBus
var _hud: HudSlice


func before_each() -> void:
	# Mirror sprint0_bootstrap._spawn_event_bus: create the bus, add it to the
	# tree so its _ready registers group "event_bus", then add the HUD which
	# grabs the bus from that group in its own _ready.
	#
	# add_child_autofree (NOT plain add_child): GUT frees autofree'd nodes right
	# after each test (gut.gd _run_test -> _autofree.free_all()). Freeing takes
	# the node out of the tree, which de-registers it from group "event_bus", so
	# the next test's bus is the ONLY member of that group. Plain add_child never
	# frees: group membership grew 1,2,3... and get_first_node_in_group returned
	# the FIRST (stale) bus -- the ADDCHILD-AUTOFREE-01 root cause.
	_bus = EventBus.new()
	add_child_autofree(_bus)
	_hud = HudSlice.new()
	# Defense in depth: inject THIS test's bus explicitly before the HUD enters
	# the tree. With autofree in place HudSlice._ready's group fallback would now
	# resolve to the correct bus on its own, but explicit injection keeps the
	# wiring deterministic regardless of group state.
	_hud.set_event_bus(_bus)
	add_child_autofree(_hud)
	watch_signals(_bus)


func after_each() -> void:
	# add_child_autofree releases these nodes AFTER this method returns, so just
	# drop our handles here; nothing below may touch a freed node.
	_bus = null
	_hud = null


# =============================================================================
# E09-S1 — focus readout + aim preview (carried over from Sprint 0)
# =============================================================================
func test_focus_readout_updates_on_focus():
	# E09-S1: entering FOCUS must update the status readout to "凝神 0.25×".
	_bus.time_scale_changed.emit(1.0, 0.25, "FOCUS")
	assert_eq(_hud._status.text, "凝神 0.25×",
		"status readout must show focus state after time_scale_changed(FOCUS)")
	assert_true(_hud._dim.visible,
		"focus dim overlay must be visible while focusing")


func test_focus_readout_restores_on_flowing():
	# E09-S1 + E02-S1: leaving FOCUS restores the flowing readout.
	_bus.time_scale_changed.emit(1.0, 0.25, "FOCUS")
	_bus.time_scale_changed.emit(0.25, 1.0, "FLOWING")
	assert_eq(_hud._status.text, "FLOWING 1.0×",
		"status readout must restore after leaving FOCUS")
	assert_false(_hud._dim.visible,
		"focus dim overlay must hide after leaving FOCUS")


func test_set_aim_preview_hides_without_camera():
	# E09-S1: with no camera in the viewport, the preview must safely hide
	# (no crash, no ghost footprint left visible).
	_hud.set_aim_preview(Vector3(0, 0, 3))
	assert_false(_hud._preview.visible,
		"preview must hide when no camera can project the aim point")


func test_set_aim_preview_shows_and_matches_projection():
	# E09-S1 / C-03 / C-05: with a camera present, the landing preview Control
	# must show and sit at the camera projection of the aim point (offset by
	# half its minimum size, matching hud_slice.gd math).
	var cam := Camera3D.new()
	cam.current = true
	cam.position = Vector3(0, 12, -12)
	cam.look_at(Vector3.ZERO, Vector3.UP)
	# autofree: a leaked `current` camera would stay in the viewport for every
	# later test in this script and silently break the sibling test that asserts
	# NO camera is available (it only passes today because it happens to be
	# declared earlier). Freeing per test removes that order dependency.
	add_child_autofree(cam)

	var world_pos := Vector3(0, 0, 3)
	_hud.set_aim_preview(world_pos)
	assert_true(_hud._preview.visible,
		"preview must show when a camera can project the aim point")

	var expected := cam.unproject_position(world_pos) \
		- _hud._preview.custom_minimum_size * 0.5
	# NaN guard: unproject may be non-finite under a 0-size headless viewport;
	# only compare when the projection is finite (N2 runtime confirmation).
	if expected.x == expected.x and expected.y == expected.y:
		var delta := _hud._preview.position.distance_to(expected)
		assert_true(delta < 0.001,
			"preview position must match camera projection of aim point (delta=%f)" % delta)


# =============================================================================
# H12 · E09-S2 — contrast budget (@ci:C-02) + ★ LANDMINE 3 reverse guard
# =============================================================================
func test_suspicion_bar_contrast():
	var panel: Color = HudColors.HUD_COLOR_PANEL_BASE

	# C-02: every information CARRIER (numbers, glyph fills, inner strokes).
	assert_gt(HudColors.wcag_contrast(HudColors.HUD_COLOR_CARRIER, panel), 7.0,
		"C-02: the Carrier white must clear 7:1 on the reference panel")
	for variant in HudColors.PANEL_VARIANTS:
		assert_gt(HudColors.wcag_contrast(HudColors.HUD_COLOR_CARRIER, variant), 7.0,
			"C-02: the Carrier white must clear 7:1 on panel variant %s" % variant.to_html(false))

	# C-03: semantic BORDERS.
	assert_gt(HudColors.wcag_contrast(HudColors.HUD_COLOR_CAUTION, panel), 3.0,
		"C-03: the SUSPICIOUS border colour must clear 3:1")
	assert_gt(HudColors.wcag_contrast(HudColors.HUD_COLOR_ALARM, panel), 3.0,
		"C-03: the ALERT border colour must clear 3:1")

	# ★ LANDMINE 3 — reverse assertion. #7A2E2E is 1.91:1; it can NEVER satisfy
	# C-02/C-03. This assertion exists so that anyone who "promotes" it to a text
	# or border colour breaks the build instead of shipping an unreadable HUD.
	assert_lt(HudColors.wcag_contrast(HudColors.HUD_COLOR_ALARM_FILL, panel), 3.0,
		"★landmine 3: HUD_COLOR_ALARM_FILL is mathematically incapable of C-03 — "
			+ "it is a FILL-only colour and must never be used as text/border/icon")
	assert_lte(HudColors.ALARM_FILL_ALPHA_MAX, 0.35,
		"★landmine 3: the ALARM_FILL alpha ceiling is hard-capped at 0.35 (D7 §3)")

	# ...and it must not have leaked into any tier border in the process.
	for tier in HudSlice.SUS_BORDER:
		assert_ne(HudSlice.SUS_BORDER[tier], HudColors.HUD_COLOR_ALARM_FILL,
			"★landmine 3: tier %d must not use the fill-only colour as its border" % tier)

	# NEW-1: the suspicion-bar fill is a Carrier-white alpha ladder, which must be
	# STRICTLY MONOTONIC in luminance. (The signed semantic palette is not:
	# CALM 0.100 -> CAUTION 0.295 -> ALARM 0.190 would invert the brightness
	# coding required by C-04/C-05.)
	var ladder := [
		EventBus.SusTier.CALM, EventBus.SusTier.SUSPICIOUS,
		EventBus.SusTier.SEARCH, EventBus.SusTier.ALERT,
	]
	var prev_lum := -1.0
	for tier in ladder:
		var alpha: float = HudSlice.SUS_FILL_ALPHA[tier]
		var composited: Color = HudColors.composite(HudColors.HUD_COLOR_CARRIER, panel, alpha)
		var lum: float = HudColors.relative_luminance(composited)
		assert_gt(lum, prev_lum,
			"NEW-1: the suspicion fill ladder must be strictly monotonic (tier %d, a=%.2f)"
				% [tier, alpha])
		prev_lum = lum
	assert_gt(HudColors.wcag_contrast(
			HudColors.composite(HudColors.HUD_COLOR_CARRIER, panel,
				HudSlice.SUS_FILL_ALPHA[EventBus.SusTier.ALERT]), panel), 3.0,
		"the top fill step must still read against the panel")

	# The bar's own readouts are Carrier white, not a semantic hue.
	assert_eq(_hud._sus_value.get_theme_color("font_color"), HudColors.HUD_COLOR_CARRIER,
		"C-02: the suspicion NUMBER must be the Carrier white")
	assert_eq(_hud._sus_icon.get_theme_color("font_color"), HudColors.HUD_COLOR_CARRIER,
		"C-02: the tier glyph fill must be the Carrier white")


# =============================================================================
# H13 · E09-S2 — ★ LANDMINE 1: suspicion_changed is the ONLY writer
# =============================================================================
func test_suspicion_bar_updates_on_suspicion_changed():
	_bus.suspicion_changed.emit(1, 42.0, EventBus.SusTier.SUSPICIOUS)
	assert_true(_hud._suspicion.visible, "an active guard must show the bar")
	assert_almost_eq(_hud._suspicion.value, 42.0, 0.0001,
		"the bar must take its value from suspicion_changed")
	assert_eq(_hud._sus_value.text, "42", "the numeric readout must match")
	assert_eq(_hud._sus_icon.text, HudSlice.SUS_ICON[EventBus.SusTier.SUSPICIOUS],
		"C-05: the tier must also be shape-coded via its glyph")

	# ★ LANDMINE 1 — the reverse proof. Before this fix hud_slice.gd had TWO
	# writers of _suspicion.value: _on_vision_stimulus wrote visibility*100 and
	# _on_suspicion_changed wrote the accumulated value. Once GuardBrain starts
	# emitting at 10Hz they would overwrite each other every tick and the bar
	# would flicker between "instantaneous visibility" and "accumulated
	# suspicion", destroying the core read of E09-S2.
	_bus.vision_stimulus.emit(1, null, 1.0)
	assert_almost_eq(_hud._suspicion.value, 42.0, 0.0001,
		"★landmine 1: vision_stimulus must NOT write the suspicion bar any more")
	assert_false(_hud.has_method("_on_vision_stimulus"),
		"★landmine 1: the _on_vision_stimulus handler must be deleted, not just unhooked")
	# Count only the HUD's own subscriptions — watch_signals() in before_each
	# attaches GUT's recorder to every signal on the bus, so a bare
	# get_connections().size() would always be >= 1.
	var hud_connections := 0
	for connection in _bus.vision_stimulus.get_connections():
		var callable: Callable = connection["callable"]
		if callable.get_object() == _hud:
			hud_connections += 1
	assert_eq(hud_connections, 0,
		"★landmine 1: the HUD must not be connected to vision_stimulus at all")

	# A tier change must re-skin the bar (glyph + fill step + border).
	_bus.suspicion_changed.emit(1, 80.0, EventBus.SusTier.ALERT)
	assert_eq(_hud._sus_icon.text, HudSlice.SUS_ICON[EventBus.SusTier.ALERT],
		"the glyph must follow the tier")
	assert_eq(_hud._sus_border_style.border_color, HudColors.HUD_COLOR_ALARM,
		"the ALERT border must be the signed alarm colour")
	assert_almost_eq(_hud._sus_fill_style.bg_color.a,
		HudSlice.SUS_FILL_ALPHA[EventBus.SusTier.ALERT], 0.0001,
		"the fill must step to the ALERT rung of the alpha ladder")


# =============================================================================
# H14 · E09-S2 — one bar, showing the loudest guard only (C7)
# =============================================================================
func test_suspicion_bar_shows_top_guard_only():
	_bus.suspicion_changed.emit(1, 10.0, EventBus.SusTier.CALM)
	_bus.suspicion_changed.emit(2, 70.0, EventBus.SusTier.ALERT)
	_bus.suspicion_changed.emit(3, 40.0, EventBus.SusTier.SUSPICIOUS)
	assert_almost_eq(_hud._suspicion.value, 70.0, 0.0001,
		"the single bar must show the highest suspicion across all guards")
	assert_eq(_hud._top_guard_id, 2, "guard 2 is the argmax")
	assert_eq(_hud._sus_icon.text, HudSlice.SUS_ICON[EventBus.SusTier.ALERT],
		"the glyph must be the top guard's tier")

	# Ties resolve to the LOWEST guard_id so the display is deterministic.
	_bus.suspicion_changed.emit(5, 70.0, EventBus.SusTier.ALERT)
	assert_eq(_hud._top_guard_id, 2,
		"on a tie the lowest guard_id must win (deterministic display)")

	# Pillar 4: when every guard is quiet the HUD falls silent.
	for gid in [1, 2, 3, 5]:
		_bus.suspicion_changed.emit(gid, 0.0, EventBus.SusTier.CALM)
	assert_false(_hud._suspicion.visible,
		"with every guard below SUS_BAR_HIDE_EPS the whole bar must hide")


# =============================================================================
# H15 · E09-S3 — world-element readability orchestration (C8)
# =============================================================================
func test_world_element_visibility_toggle():
	var stubs: Array = []
	for i in range(3):
		var stub := BoostStub.new()
		stubs.append(stub)
		_hud.register_world_element(stub)

	_bus.time_scale_changed.emit(1.0, 0.25, "FOCUS")
	for stub in stubs:
		assert_eq(stub.boost_calls, [true],
			"entering FOCUS must boost every registered world element")

	_bus.time_scale_changed.emit(0.25, 1.0, "FLOWING")
	for stub in stubs:
		assert_eq(stub.boost_calls, [true, false],
			"leaving FOCUS must return every element to its normal read")

	# Registering twice must not double-drive the element.
	_hud.register_world_element(stubs[0])
	_bus.time_scale_changed.emit(1.0, 0.25, "FOCUS")
	assert_eq(stubs[0].boost_calls, [true, false, true],
		"a duplicate registration must not produce a duplicate call")

	# The three real drawing systems must honour the duck-typed contract; E09
	# only ever calls this method and never touches their material/shader.
	for path in [
		"res://src/game/vision_cone.gd",
		"res://src/game/sound_propagation.gd",
		"res://src/game/footfall_vfx.gd",
	]:
		var node = load(path).new()
		autofree(node)
		assert_true(node.has_method("set_readability_boost"),
			"%s must implement set_readability_boost(on) for E09-S3" % path)


# =============================================================================
# H16 · E09-S4 — item / charges slot (D8 signature)
# =============================================================================
func test_charges_display():
	assert_false(_hud._item_slot.visible, "with no item held the slot stays hidden")

	# [D8] the new 3-arg signature with the InteractableType enum.
	_bus.interactable_triggered.emit(1, EventBus.InteractableType.DECOY, {"charges": 2})
	assert_true(_hud._item_slot.visible, "a triggered interactable must reveal the slot")
	assert_eq(_hud._item_label.text, "DECOY",
		"C-05: the type must be readable as a WORD, not only as a colour")
	assert_eq(_hud._item_charges.text, "2", "charges must display as a numeral")
	assert_eq(_hud._item_charges.get_theme_color("font_color"), HudColors.HUD_COLOR_CARRIER,
		"C-01/C-02: the charges numeral must be the Carrier white")
	assert_almost_eq(_hud._item_icon.modulate.a, 1.0, 0.0001,
		"an item with charges left must be drawn at full strength")

	# charges == 0 -> dual encoding: the ICON dims, the NUMBER stays bright.
	# "Unavailable" is never expressed with colour alone.
	_bus.interactable_triggered.emit(1, EventBus.InteractableType.DECOY, {"charges": 0})
	assert_true(_hud._item_slot.visible,
		"an exhausted item stays visible (dimmed), it is not hidden")
	assert_almost_eq(_hud._item_icon.modulate.a, HudSlice.CHARGES_DIM_ALPHA, 0.0001,
		"an exhausted item must dim its icon to CHARGES_DIM_ALPHA")
	assert_almost_eq(_hud._item_charges.modulate.a, 1.0, 0.0001,
		"the charges numeral must stay fully bright so the 0 is legible")
	assert_eq(_hud._item_charges.text, "0", "the exhausted count must read 0")

	# Other types map to their own words.
	_bus.interactable_triggered.emit(2, EventBus.InteractableType.SMOKE, {"charges": 3})
	assert_eq(_hud._item_label.text, "SMOKE", "each InteractableType needs its own label")


# =============================================================================
# H17 · E09-S6 — exposure ALERT overlay (@ci:V-02/V-03/C-07)
# =============================================================================
func test_exposure_alert_ui_non_color():
	assert_false(_hud.is_exposure_visible(), "no exposure overlay at rest")

	_bus.exposure_detected.emit(1, null)
	assert_true(_hud.is_exposure_visible(), "exposure_detected must raise the overlay")

	# C-07: the danger read is carried by SHAPE and WORDS, never by hue alone.
	assert_not_null(_hud._exposure_icon, "the overlay must carry an icon node")
	assert_eq(_hud._exposure_icon.text, "!", "the icon glyph must be the '!' shape")
	assert_not_null(_hud._exposure_text, "the overlay must carry a text label")
	assert_ne(_hud._exposure_hint.text, "", "the soft-restart hint must not be empty")

	# V-02: pulse frequency is capped.
	assert_lte(HudSlice.EXPOSURE_PULSE_HZ, 2.0, "V-02: the pulse must stay at or below 2Hz")
	# V-06: eased fade, never a hard cut.
	assert_gt(HudSlice.EXPOSURE_FADE_SEC, 0.0, "V-06: the overlay must fade in, not hard-cut")

	# V-03: screen shake is off by default and the overlay honours that.
	var a11y := A11ySettings.new()
	autofree(a11y)
	assert_false(a11y.screen_shake, "V-03: screen shake must default to off")

	# ★ LANDMINE 3, second site. #7A2E2E is legal here and ONLY here: as a fill,
	# at alpha <= 0.35, with white carriers on top.
	assert_eq(_hud._exposure_border_style.border_color, HudColors.HUD_COLOR_ALARM,
		"the exposure BORDER must be HUD_COLOR_ALARM (#D64545)")
	assert_ne(_hud._exposure_border_style.border_color, HudColors.HUD_COLOR_ALARM_FILL,
		"★landmine 3: the fill-only colour must never be promoted to a border")
	assert_almost_eq(_hud._exposure_fill.color.r, HudColors.HUD_COLOR_ALARM_FILL.r, 0.001,
		"the exposure fill must be the signed ALARM_FILL colour")
	assert_lte(_hud._exposure_fill.color.a, HudColors.ALARM_FILL_ALPHA_MAX,
		"★landmine 3: the ALARM_FILL alpha must stay at or under 0.35")

	# Even on its own red backdrop the carriers stay legible.
	var backdrop: Color = HudColors.composite(
		HudColors.HUD_COLOR_ALARM_FILL, HudColors.HUD_COLOR_PANEL_BASE,
		HudColors.ALARM_FILL_ALPHA_MAX)
	assert_gt(HudColors.wcag_contrast(
			_hud._exposure_text.get_theme_color("font_color"), backdrop), 7.0,
		"C-02: overlay text must clear 7:1 against the composited red backdrop")
	assert_gt(HudColors.wcag_contrast(HudColors.HUD_COLOR_ALARM, backdrop), 3.0,
		"C-03: the alarm border must clear 3:1 against its own fill")

	# C-06 is only a READ POINT this sprint (the switch itself is Sprint 2), but
	# the substitute colour must already be wired to the signed value.
	assert_eq(HudColors.HUD_COLOR_ALARM_CB, HudColors.HUD_COLOR_CAUTION,
		"C-06: the colour-blind substitute for ALARM is the signed Caution amber")
