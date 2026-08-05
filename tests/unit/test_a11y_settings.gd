# tests/unit/test_a11y_settings.gd
# GUT unit tests for the Sprint 2 · Batch C accessibility Tier2 model (E09).
#
# Exit hooks:
#   E09-S5a  test_colorblind_enum_maps_danger_color        (C-05 / C-06 / C-07)
#   E09-S5b  test_time_slider_bounds_default_0_25          (T-01 / T-02 / V-06)
#   E09-S5c  test_fog_option_tri_state_and_motion_blur_off (V-01 / V-03 / V-04 / V-05)
#   E09-S5d  test_text_scale_range_and_subtitles           (X-01 / X-02)
#   E09-S7   test_a11y_settings_full_model_roundtrip       (field model + FLAG-J)
#   CI       test_ci_a11y_values_scan_reverse              (@ci:a11y-values-in-range)
#
# ── Why so many REVERSE assertions ───────────────────────────────────────────
# Every positive assertion here has a mirror that proves the mechanism can still
# FAIL. An accessibility feature is uniquely prone to rotting green: switch off
# the substitution, neuter the clamp, or drop the subtitle, and nothing crashes,
# no frame budget moves, and no other test notices — the game simply becomes
# unplayable for the people the feature exists for. So each hook asserts both
# "the setting does what it says" and "the setting is still load-bearing".
#
# Headless by construction: the model is a bare Node, HudColors is pure
# arithmetic and every HudSlice resolver is null-guarded, so only the X-01 layout
# hook needs a live tree.
#
# Run: godot --headless -s res://addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit

extends GutTest

# Preloaded under *Script / *Model names rather than their `class_name`s: these
# scripts declare globals (A11ySettings / HudSlice / TimeController) and a
# same-named const would shadow them for the whole file.
const A11yModel := preload("res://src/core/a11y_settings.gd")
const HudColors := preload("res://src/ui/hud_colors.gd")
const HudSliceScript := preload("res://src/ui/hud_slice.gd")
const TimeControllerScript := preload("res://src/core/time_controller.gd")
const BudgetChecks := preload("res://tests/ci/budget_checks.gd")

const A11Y_SRC := "res://src/core/a11y_settings.gd"
const HUD_SLICE_SRC := "res://src/ui/hud_slice.gd"
const SAVE_MANAGER_SRC := "res://src/core/save_manager.gd"
const TEST_SAVE_MANAGER_SRC := "res://tests/unit/test_save_manager.gd"

# C-03「非文本图形对比度 >= 3:1」— the gate every DANGER carrier must clear.
const CONTRAST_MIN_C03 := 3.0

# The three substituting modes. OFF is handled separately everywhere, because
# "no substitution" is a different contract from "substituted".
const CB_SUBSTITUTING := [
	A11yModel.ColorBlindMode.PROTAN,
	A11yModel.ColorBlindMode.DEUTAN,
	A11yModel.ColorBlindMode.TRITAN,
]


# Hermetic SaveManager double. A Node (the real service is an autoload Node) that
# records the section dictionary verbatim, so the delegation contract can be
# proven without touching a developer's real user://prefs.json.
#
# ★ It is deliberately FIELD-AGNOSTIC — it never names an a11y field. That is
#   FLAG-J restated as an executable object: if A11ySettings ever needed the
#   store to know a field name, this stub could not satisfy it.
class PrefsStub extends Node:
	var sections: Dictionary = {}
	var save_calls: int = 0
	var load_calls: int = 0

	func save_prefs(section: String, data: Dictionary) -> void:
		save_calls += 1
		sections[section] = data.duplicate(true)

	func load_prefs(section: String) -> Dictionary:
		load_calls += 1
		if not sections.has(section):
			return {}
		var data: Dictionary = sections[section]
		return data.duplicate(true)


func _new_settings() -> A11ySettings:
	var s: A11ySettings = autofree(A11ySettings.new())
	return s


# =============================================================================
# E09-S5a — colour-blind enum -> danger colour (C-05 / C-06 / C-07)
# =============================================================================
func test_colorblind_enum_maps_danger_color() -> void:
	# ① The enum is a FULL four-state, and OFF is 0 so a zeroed or absent field
	#    degrades to "no substitution" rather than to a mode nobody chose.
	assert_eq(A11yModel.ColorBlindMode.OFF, 0, "C-06: OFF must be 0 (safe zero value)")
	assert_eq(A11yModel.ColorBlindMode.PROTAN, 1, "C-06: PROTAN must be 1")
	assert_eq(A11yModel.ColorBlindMode.DEUTAN, 2, "C-06: DEUTAN must be 2")
	assert_eq(A11yModel.ColorBlindMode.TRITAN, 3, "C-06: TRITAN must be 3")
	assert_eq(A11yModel.CB_MODE_NAMES.size(), 4,
		"C-06: exactly four colour-blind modes are named")

	# ② OFF ships the signed alarm hue UNCHANGED — the a11y feature must not
	#    repaint the game for players who never enabled it.
	assert_eq(HudColors.danger_color(A11yModel.ColorBlindMode.OFF),
		HudColors.HUD_COLOR_ALARM,
		"C-06: mode OFF must return the signed HUD_COLOR_ALARM unchanged")

	# ③ Every substituting mode maps to the v0.2 danger substitute.
	for mode in CB_SUBSTITUTING:
		var danger: Color = HudColors.danger_color(mode)
		assert_eq(danger, HudColors.HUD_COLOR_DANGER_CB,
			"C-06: mode %s must map danger onto HUD_COLOR_DANGER_CB"
				% A11yModel.canonical_name_of(mode))

		# ★ REVERSE (control-manifest v0.2). The SUPERSEDED Sprint 1 mapping sent
		# danger to #C8862F — which IS 警戒 — collapsing two semantic rungs to a
		# 1.00:1 luminance ratio: a C-05 violation committed inside the C-06 fix.
		# This is the line that stops anyone re-adopting the voided 口径.
		assert_ne(danger, HudColors.HUD_COLOR_CAUTION,
			"C-05/C-06 reverse: the danger substitute must NEVER collapse onto Caution (v0.2 voids the old #C8862F mapping)")
		var vs_caution: float = HudColors.wcag_contrast(danger, HudColors.HUD_COLOR_CAUTION)
		assert_gte(vs_caution, HudColors.DANGER_CB_MIN_SEPARATION,
			"C-05: substitute vs Caution must stay separated by luminance (%.2f:1)" % vs_caution)
		var vs_alarm: float = HudColors.wcag_contrast(danger, HudColors.HUD_COLOR_ALARM)
		assert_gte(vs_alarm, HudColors.DANGER_CB_MIN_SEPARATION,
			"C-05: substitute vs Alarm must stay separated by luminance (%.2f:1)" % vs_alarm)

		# C-03: a substitute that is unreadable is not an accessibility feature.
		var vs_panel: float = HudColors.wcag_contrast(danger, HudColors.HUD_COLOR_PANEL_BASE)
		assert_gte(vs_panel, CONTRAST_MIN_C03,
			"C-03: substitute vs panel must clear 3:1 (%.2f:1)" % vs_panel)

	# ④ C-07「危险提示绝不单独使用」. The glyph is returned for EVERY mode
	#    INCLUDING OFF — the shape channel is permanent, not a fallback.
	for mode in [A11yModel.ColorBlindMode.OFF, A11yModel.ColorBlindMode.PROTAN,
			A11yModel.ColorBlindMode.DEUTAN, A11yModel.ColorBlindMode.TRITAN]:
		assert_ne(HudColors.danger_icon(mode), "",
			"C-07: danger must carry a glyph at mode %s, including OFF"
				% A11yModel.canonical_name_of(mode))
		assert_true(HudColors.danger_read_is_multi_channel(mode),
			"C-05/C-07: the danger read must stay multi-channel at mode %s"
				% A11yModel.canonical_name_of(mode))

	# ⑤ Junk degrades to OFF, never to an arbitrary mode.
	assert_eq(A11yModel.normalize_colorblind_mode(99), A11yModel.ColorBlindMode.OFF,
		"C-06: an unknown enum int must degrade to OFF")
	assert_eq(A11yModel.normalize_colorblind_mode(-3), A11yModel.ColorBlindMode.OFF,
		"C-06: a negative enum int must degrade to OFF")

	# ⑥ The Sprint 0 string facade still resolves both spelling generations.
	var s := _new_settings()
	s.color_blind_mode = "DEUTERANO"
	assert_eq(s.colorblind_mode, A11yModel.ColorBlindMode.DEUTAN,
		"facade: the Sprint 0 spelling DEUTERANO must resolve to DEUTAN")
	assert_eq(s.color_blind_mode, "DEUTERANO",
		"facade: the legacy spelling must round-trip unchanged for Sprint 0 callers")
	s.colorblind_mode = A11yModel.ColorBlindMode.TRITAN
	assert_eq(s.color_blind_mode, "TRITANO",
		"facade: a Tier2 write must be readable through the legacy string view")

	# ★ REVERSE: an unrecognised spelling must land on OFF. Guessing a mode for
	# a corrupted preference file would silently repaint the HUD for a player
	# who never asked for it.
	s.color_blind_mode = "PURPLE-ISH"
	assert_eq(s.color_blind_mode, "OFF",
		"facade reverse: an unknown spelling must degrade to OFF, never to a guessed mode")


# =============================================================================
# E09-S5b — time-scale slider [0.1, 1.0], default 0.25 (T-01 / T-02 / V-06)
# =============================================================================
func test_time_slider_bounds_default_0_25() -> void:
	# ① The shipped range and default.
	assert_almost_eq(A11yModel.TIME_SCALE_MIN, 0.1, 0.0001, "T-01: lower bound is 0.1")
	assert_almost_eq(A11yModel.TIME_SCALE_MAX, 1.0, 0.0001, "T-01: upper bound is 1.0")
	assert_almost_eq(A11yModel.TIME_SCALE_DEFAULT, 0.25, 0.0001, "T-02: default is 0.25")

	var s := _new_settings()
	assert_almost_eq(s.time_scale_user, 0.25, 0.0001,
		"T-02: a fresh model must ship 凝神 at 0.25")

	# ② Clamped on WRITE, not merely on save. An out-of-range value must be
	#    impossible to STORE — that is what makes the CI scan a real invariant.
	s.time_scale_user = 5.0
	assert_almost_eq(s.time_scale_user, A11yModel.TIME_SCALE_MAX, 0.0001,
		"T-01: an over-range write must clamp to 1.0")
	s.time_scale_user = -1.0
	assert_almost_eq(s.time_scale_user, A11yModel.TIME_SCALE_MIN, 0.0001,
		"T-02: an under-range write must clamp to the 0.1 physics floor")
	s.time_scale_user = 0.4
	assert_almost_eq(s.time_scale_user, 0.4, 0.0001, "T-01: an in-range write is preserved")

	# ③ The settings screen must not advertise a number the clock does not use.
	assert_almost_eq(A11yModel.TIME_SCALE_DEFAULT, TimeControllerScript.FOCUS_SCALE, 0.0001,
		"T-02: A11ySettings default must equal TimeController.FOCUS_SCALE")
	assert_almost_eq(A11yModel.TIME_SCALE_MIN, TimeControllerScript.USER_MIN, 0.0001,
		"T-01: the two clocks must agree on the lower bound")
	assert_almost_eq(A11yModel.TIME_SCALE_MAX, TimeControllerScript.USER_MAX, 0.0001,
		"T-01: the two clocks must agree on the upper bound")

	# ④ V-06「禁硬切」: the slider moves the TARGET of an eased ramp. A zero-length
	#    ramp would be a hard cut wearing a ramp's name.
	assert_gt(TimeControllerScript.RAMP, 0.0,
		"V-06: the focus transition must be an eased ramp, never a hard cut")

	# ⑤ The clock PULLS the value out of the field model (no new bus signal —
	#    event-vocab-zero-drift). E02 reads E09 data; never the other way round.
	var tc: TimeController = autofree(TimeControllerScript.new())
	tc.apply_a11y(s)
	assert_almost_eq(tc.user_scale, 0.4, 0.0001,
		"E09-S5b: apply_a11y must pull the slider value into the clock")
	assert_almost_eq(tc.focus_target(), 0.4, 0.0001,
		"E09-S5b: 凝神 must ramp to the player's chosen depth, not the constant")

	# ★ REVERSE: a null/freed settings object must leave the clock untouched
	# rather than resetting it to a default the player did not pick.
	tc.apply_a11y(null)
	assert_almost_eq(tc.user_scale, 0.4, 0.0001,
		"E09-S5b reverse: a missing settings object must not silently reset the clock")

	# ★ REVERSE: the clock clamps independently of the model, so a direct
	# assignment that bypasses set_user_scale still cannot leave T-01.
	tc.user_scale = 9.0
	assert_almost_eq(tc.focus_target(), TimeControllerScript.USER_MAX, 0.0001,
		"T-01 reverse: focus_target must clamp even when user_scale was written raw")


# =============================================================================
# E09-S5c — dizziness controls (V-01 / V-03 / V-04 / V-05)
# =============================================================================
func test_fog_option_tri_state_and_motion_blur_off() -> void:
	# ① V-04 is a THREE-state rung, and FULL is 0 so an absent field keeps the
	#    artistic baseline instead of silently disabling the fog look.
	assert_eq(A11yModel.FogOption.FULL, 0, "V-04: FULL must be 0 (safe zero value)")
	assert_eq(A11yModel.FogOption.REDUCED, 1, "V-04: REDUCED must be 1")
	assert_eq(A11yModel.FogOption.OFF, 2, "V-04: OFF must be 2")
	assert_eq(A11yModel.FOG_OPTION_NAMES.size(), 3,
		"V-04: the fog control is three-state (FULL / REDUCED / OFF)")

	var s := _new_settings()
	assert_eq(s.fog_option, A11yModel.FogOption.FULL, "V-04: default fog rung is FULL")
	assert_false(s.screen_shake, "V-03: screen shake must ship OFF")
	assert_false(s.motion_blur, "V-05: motion blur must ship OFF")

	# ② The three rungs must be STRICTLY DECREASING. A "reduced" fog that is not
	#    actually weaker than FULL is an accessibility setting that lies.
	var a_full: float = HudSliceScript.dim_alpha_for(A11yModel.FogOption.FULL)
	var a_red: float = HudSliceScript.dim_alpha_for(A11yModel.FogOption.REDUCED)
	var a_off: float = HudSliceScript.dim_alpha_for(A11yModel.FogOption.OFF)
	assert_gt(a_full, a_red, "V-04: REDUCED must be strictly weaker than FULL")
	assert_gt(a_red, a_off, "V-04: OFF must be strictly weaker than REDUCED")
	assert_almost_eq(a_off, 0.0, 0.0001, "V-04: OFF must remove the veil entirely")
	assert_almost_eq(a_full, 0.35, 0.0001,
		"V-04: FULL must stay the Sprint 0/1 shipped 0.35 (default look unchanged)")

	# ③ The HUD consumes the model. Built outside a tree on purpose: every
	#    resolver is null-guarded, so this asserts the POLICY, not the widgets.
	var hud: HudSlice = autofree(HudSliceScript.new())
	hud.set_a11y_settings(s)
	assert_eq(hud.fog_option(), A11yModel.FogOption.FULL, "V-04: HUD reads the FULL default")
	assert_almost_eq(hud.dim_alpha(), a_full, 0.0001, "V-04: HUD resolves the FULL rung")
	assert_true(hud.world_boost_allowed(),
		"V-04: FULL must keep the E09-S3 readability boost (the veil is still there)")

	s.fog_option = A11yModel.FogOption.REDUCED
	hud.apply_a11y()
	assert_almost_eq(hud.dim_alpha(), a_red, 0.0001, "V-04: HUD follows the REDUCED rung")
	assert_true(hud.world_boost_allowed(),
		"V-04: REDUCED keeps the boost — the veil is thinner, not gone")

	s.fog_option = A11yModel.FogOption.OFF
	hud.apply_a11y()
	assert_almost_eq(hud.dim_alpha(), 0.0, 0.0001, "V-04: HUD drops the veil at OFF")
	assert_false(hud.world_boost_allowed(),
		"V-04: with no veil to punch through, the boost is gratuitous on-screen change")

	# ④ V-03 / V-05: the resolvers are the ONLY way shake or blur can reach the
	#    screen, and both are 0.0 at the shipped default.
	assert_almost_eq(hud.shake_amplitude(), 0.0, 0.0001,
		"V-03: no HUD displacement may exist at the default")
	assert_almost_eq(hud.motion_blur_strength(), 0.0, 0.0001,
		"V-05: no blur strength may exist at the default")

	# ★ REVERSE: opting IN must actually produce a non-zero figure. Without this
	# the two resolvers could be hard-wired to 0.0 and the "default off" tests
	# above would still pass — a setting that cannot be turned on is not a
	# setting, and the V-03/V-05 seam would be dead code instead of a policy gate.
	s.screen_shake = true
	s.motion_blur = true
	hud.apply_a11y()
	assert_almost_eq(hud.shake_amplitude(), HudSliceScript.SHAKE_AMPLITUDE_PX, 0.0001,
		"V-03 reverse: an opted-in player must actually get the shake amplitude")
	assert_almost_eq(hud.motion_blur_strength(), HudSliceScript.MOTION_BLUR_STRENGTH, 0.0001,
		"V-05 reverse: an opted-in player must actually get the blur strength")
	assert_gt(HudSliceScript.SHAKE_AMPLITUDE_PX, 0.0,
		"V-03 reverse: the amplitude constant must be a real displacement")

	# ⑤ V-01「无 >3Hz 闪烁」is a ceiling on EVERY periodic modulation this layer
	#    can produce. Enumerated from the SOURCE, not from a hand-kept list, so a
	#    frequency added next sprint is caught even if nobody updates this test.
	var declared := _declared_hz_constants(HUD_SLICE_SRC)
	assert_gt(declared.size(), 0,
		"V-01: the *_HZ enumeration must find at least one declared frequency")
	for hz_name in declared:
		var hz: float = declared[hz_name]
		assert_lte(hz, HudSliceScript.FLICKER_HZ_MAX,
			"V-01: %s = %.2fHz exceeds the %.1fHz flicker ceiling"
				% [hz_name, hz, HudSliceScript.FLICKER_HZ_MAX])
	assert_true(declared.has("SHAKE_HZ"),
		"V-01: the shake frequency must be a declared constant the scan can see")

	# ⑥ Junk degrades to the artistic baseline, and the two-state facade still
	#    speaks for Sprint 0/1 callers.
	assert_eq(A11yModel.normalize_fog_option(7), A11yModel.FogOption.FULL,
		"V-04: an unknown fog rung must degrade to FULL")
	s.fog_enabled = false
	assert_eq(s.fog_option, A11yModel.FogOption.OFF, "facade: fog_enabled=false maps to OFF")
	s.fog_enabled = true
	assert_eq(s.fog_option, A11yModel.FogOption.FULL, "facade: fog_enabled=true restores FULL")
	s.fog_option = A11yModel.FogOption.REDUCED
	assert_true(s.fog_enabled,
		"facade: REDUCED must read back as `on` — from a two-state caller's view the fog IS still on")


# =============================================================================
# E09-S5d — text scale [1.0, 1.5] + subtitles (X-01 / X-02)
# =============================================================================
func test_text_scale_range_and_subtitles() -> void:
	# ① X-01 range.
	assert_almost_eq(A11yModel.TEXT_SCALE_MIN, 1.0, 0.0001, "X-01: lower bound is 100%")
	assert_almost_eq(A11yModel.TEXT_SCALE_MAX, 1.5, 0.0001, "X-01: upper bound is 150%")
	assert_almost_eq(A11yModel.TEXT_SCALE_DEFAULT, 1.0, 0.0001, "X-01: default is 100%")

	var s := _new_settings()
	assert_almost_eq(s.text_scale, 1.0, 0.0001, "X-01: a fresh model ships at 100%")
	s.text_scale = 3.0
	assert_almost_eq(s.text_scale, 1.5, 0.0001, "X-01: an over-range write clamps to 150%")
	s.text_scale = 0.1
	assert_almost_eq(s.text_scale, 1.0, 0.0001, "X-01: an under-range write clamps to 100%")

	# ② X-02 default + the rendered SHAPE of a line. A bare line cannot say WHO
	#    or WHAT made the sound, which is the entire point of a subtitle for a
	#    player who cannot hear it.
	assert_true(s.subtitles, "X-02: subtitles must ship ON")
	var line: String = HudSliceScript.subtitle_text("守卫", "脚步声")
	assert_true(line.contains("守卫"), "X-02: the subtitle must name the speaker")
	assert_true(line.contains("脚步声"), "X-02: the subtitle must carry the line")
	assert_true(line.contains(HudSliceScript.SUBTITLE_ICON),
		"X-02: the subtitle must carry the sound icon")
	assert_eq(HudSliceScript.subtitle_text("", "远处的锁响"),
		"%s %s：远处的锁响" % [HudSliceScript.SUBTITLE_ICON, HudSliceScript.SUBTITLE_SPEAKER_FALLBACK],
		"X-02: an unattributed sound must fall back to a named speaker, never to a bare line")

	# ③ A LIVE tree, because X-01 is a layout claim and only real widgets can
	#    answer it. No EventBus is wired: _connect_bus is null-safe and this hook
	#    asserts geometry, not signals.
	var hud: HudSlice = HudSliceScript.new()
	add_child_autofree(hud)
	hud.set_a11y_settings(s)

	s.text_scale = 1.0
	hud.apply_a11y()
	var status_1x: Vector2 = hud._status.position
	var bar_1x: Vector2 = hud._suspicion.position
	assert_almost_eq(status_1x.x, HudSliceScript.STATUS_BASE_POS.x, 0.01,
		"X-01: at 100% the shipped layout must be bit-for-bit unchanged")

	s.text_scale = 1.5
	hud.apply_a11y()
	assert_almost_eq(hud.text_scale(), 1.5, 0.0001, "X-01: the HUD reads the 150% setting")
	assert_almost_eq(hud._status.position.x, HudSliceScript.STATUS_BASE_POS.x * 1.5, 0.01,
		"X-01: the status readout must MOVE with the scale, not grow into a fixed box")
	assert_almost_eq(hud._suspicion.custom_minimum_size.x,
		HudSliceScript.SUS_BAR_BASE_SIZE.x * 1.5, 0.01,
		"X-01: the suspicion bar must scale with the text it labels")

	# ★ REVERSE「不破版」: growing the type must not collapse the vertical
	# ordering. If positions were fixed while glyphs grew, the bar would climb
	# into the status line — the exact failure X-01 forbids.
	assert_gt(hud._suspicion.position.y, hud._status.position.y,
		"X-01 reverse: at 150% the suspicion bar must still sit BELOW the status line")
	assert_gt(hud._suspicion.position.y, bar_1x.y,
		"X-01 reverse: the layout must actually move at 150% (a frozen layout would overlap)")
	assert_gt(hud._status.position.x, status_1x.x,
		"X-01 reverse: 150% must be observably different from 100%")

	# ④ X-02 on the live widget.
	assert_true(hud.show_subtitle("守卫", "脚步声"),
		"X-02: an enabled subtitle must actually be shown")
	assert_true(hud._subtitle.visible, "X-02: the subtitle widget must be visible")
	assert_true(hud._subtitle.text.contains("守卫"),
		"X-02: the rendered subtitle must name the speaker")

	# ★ REVERSE: switching subtitles OFF must actually suppress them. Without
	# this the setting could be cosmetic and every assertion above would pass.
	s.subtitles = false
	hud.apply_a11y()
	assert_false(hud.subtitles_enabled(), "X-02: the HUD must read the disabled setting")
	assert_false(hud.show_subtitle("守卫", "脚步声"),
		"X-02 reverse: a disabled subtitle must report that it was suppressed")
	assert_false(hud._subtitle.visible,
		"X-02 reverse: a disabled subtitle must not remain on screen")


# =============================================================================
# E09-S7 — the full Tier2 model: round-trip, precedence, FLAG-J
# =============================================================================
func test_a11y_settings_full_model_roundtrip() -> void:
	# ① Every Tier2 field survives a to_dict -> from_dict round-trip.
	var src := _new_settings()
	src.colorblind_mode = A11yModel.ColorBlindMode.TRITAN
	src.time_scale_user = 0.6
	src.fog_option = A11yModel.FogOption.REDUCED
	src.screen_shake = true
	src.motion_blur = true
	src.text_scale = 1.25
	src.subtitles = false

	var wire: Dictionary = src.to_dict()
	var dst := _new_settings()
	dst.from_dict(wire)

	assert_eq(dst.colorblind_mode, A11yModel.ColorBlindMode.TRITAN, "E09-S7: colorblind_mode round-trips")
	assert_almost_eq(dst.time_scale_user, 0.6, 0.0001, "E09-S7: time_scale_user round-trips")
	assert_eq(dst.fog_option, A11yModel.FogOption.REDUCED, "E09-S7: fog_option round-trips")
	assert_true(dst.screen_shake, "E09-S7: screen_shake round-trips")
	assert_true(dst.motion_blur, "E09-S7: motion_blur round-trips")
	assert_almost_eq(dst.text_scale, 1.25, 0.0001, "E09-S7: text_scale round-trips")
	assert_false(dst.subtitles, "E09-S7: subtitles round-trips")

	# ② Tier2-first precedence. A Batch C file carries BOTH the Tier2 field and
	#    its legacy mirror; if the mirror ever won, saving on a Tier2 build and
	#    loading on the same build would quietly downgrade the setting.
	var conflict := _new_settings()
	conflict.from_dict({
		"colorblind_mode": A11yModel.ColorBlindMode.TRITAN,
		"color_blind_mode": "OFF",
		"fog_option": A11yModel.FogOption.OFF,
		"fog_enabled": true,
	})
	assert_eq(conflict.colorblind_mode, A11yModel.ColorBlindMode.TRITAN,
		"E09-S7: `colorblind_mode` must beat the legacy `color_blind_mode` mirror")
	assert_eq(conflict.fog_option, A11yModel.FogOption.OFF,
		"E09-S7: `fog_option` must beat the legacy `fog_enabled` mirror")

	# ③ A Sprint 0 file carries ONLY the legacy keys and must upgrade in place.
	var legacy := _new_settings()
	legacy.from_dict({"color_blind_mode": "PROTANO", "fog_enabled": false})
	assert_eq(legacy.colorblind_mode, A11yModel.ColorBlindMode.PROTAN,
		"E09-S7: a Sprint 0 preference file must upgrade into the Tier2 enum")
	assert_eq(legacy.fog_option, A11yModel.FogOption.OFF,
		"E09-S7: a Sprint 0 fog_enabled=false must land on the OFF rung")

	# ④ Missing keys keep defaults; corrupt values are normalised on the way in.
	var partial := _new_settings()
	partial.from_dict({"text_scale": 9.0, "colorblind_mode": 42})
	assert_almost_eq(partial.time_scale_user, A11yModel.TIME_SCALE_DEFAULT, 0.0001,
		"SAV-S4: a missing field must fall back to its default, not to zero")
	assert_true(partial.subtitles, "SAV-S4: a missing bool must keep its shipped default")
	assert_almost_eq(partial.text_scale, A11yModel.TEXT_SCALE_MAX, 0.0001,
		"E09-S7: a hand-edited out-of-range value must be clamped on load")
	assert_eq(partial.colorblind_mode, A11yModel.ColorBlindMode.OFF,
		"E09-S7: a corrupt enum must degrade to OFF on load")

	# ⑤ Persistence delegates to the FIELD-AGNOSTIC prefs API. The stub never
	#    names a field, which is FLAG-J proven as behaviour rather than as text.
	var stub: PrefsStub = autofree(PrefsStub.new())
	src.set_save_manager(stub)
	src.save()
	assert_eq(stub.save_calls, 1, "SAV-S4: save() must delegate to save_prefs exactly once")
	assert_true(stub.sections.has(A11yModel.PREFS_SECTION),
		"SAV-S4: the section key must be the one A11ySettings owns")

	var restored := _new_settings()
	restored.set_save_manager(stub)
	restored.load()
	assert_eq(restored.colorblind_mode, A11yModel.ColorBlindMode.TRITAN,
		"SAV-S4: a value written through save_prefs must come back through load_prefs")
	assert_almost_eq(restored.text_scale, 1.25, 0.0001,
		"SAV-S4: the whole Tier2 model survives the store, not just the Sprint 0 fields")

	# ★ REVERSE: a store that yields NOTHING (fresh install, empty section) must
	# leave the shipped defaults intact rather than zeroing the model — a new
	# player must never boot into time_scale 0.0 / text_scale 0.0.
	#
	# Deliberately driven by an EMPTY stub rather than by omitting the injection:
	# `SaveManager` is a real autoload (project.godot :18), so an un-injected
	# A11ySettings would resolve the LIVE service and read a developer's real
	# user://prefs.json. That test would pass on a clean CI runner and fail on
	# any machine that had ever launched the game. Hermetic by construction.
	var empty_store: PrefsStub = autofree(PrefsStub.new())
	var orphan := _new_settings()
	orphan.set_save_manager(empty_store)
	orphan.load()
	assert_eq(empty_store.load_calls, 1, "SAV-S4: load() must consult the store exactly once")
	assert_almost_eq(orphan.time_scale_user, A11yModel.TIME_SCALE_DEFAULT, 0.0001,
		"SAV-S4 reverse: an empty store must leave the shipped 凝神 default intact")
	assert_almost_eq(orphan.text_scale, A11yModel.TEXT_SCALE_DEFAULT, 0.0001,
		"SAV-S4 reverse: an empty store must leave the shipped text scale intact")
	assert_true(orphan.subtitles,
		"SAV-S4 reverse: an empty store must not silently switch subtitles off")

	# ⑥ ★ MINE 2 — A11ySettings must never reach for the legacy .cfg API itself.
	#    The one-time migration belongs to SaveManager; doing it here would
	#    consume the legacy file twice.
	var a11y_src: String = FileAccess.get_file_as_string(A11Y_SRC)
	assert_ne(a11y_src, "", "a11y_settings.gd must be readable for the source scans")
	assert_false(a11y_src.contains("ConfigFile"),
		"E09-S7: a11y_settings.gd must not touch the config-file API — persistence goes through SaveManager")
	assert_true(a11y_src.contains("save_prefs("),
		"SAV-S4: persistence must go through the field-agnostic save_prefs API")
	assert_true(a11y_src.contains("load_prefs("),
		"SAV-S4: persistence must go through the field-agnostic load_prefs API")

	# ⑦ ★ MINE 1 / FLAG-J, model-driven. test_save_manager.gd scans a HAND-KEPT
	#    blacklist, so it can only catch names it was told about. This closes
	#    that gap from the other side: every key the model actually persists must
	#    be registered there AND absent from save_manager.gd. Add a field without
	#    registering it and this goes red the same day, not the sprint the cycle
	#    silently re-forms.
	var sm_src: String = FileAccess.get_file_as_string(SAVE_MANAGER_SRC)
	assert_ne(sm_src, "", "save_manager.gd must be readable for the FLAG-J scan")
	var tsm_src: String = FileAccess.get_file_as_string(TEST_SAVE_MANAGER_SRC)
	var blacklist := _registered_a11y_field_names(tsm_src)
	assert_gt(blacklist.size(), 0, "FLAG-J: the A11Y_FIELD_NAMES blacklist must be parseable")
	for key in wire.keys():
		var field := str(key)
		assert_true(blacklist.has(field),
			"FLAG-J: `%s` is persisted but NOT registered in test_save_manager.gd::A11Y_FIELD_NAMES" % field)
		assert_false(sm_src.contains(field),
			"FLAG-J: save_manager.gd must stay field-agnostic — it must not mention `%s`" % field)


# =============================================================================
# CI — @ci:a11y-values-in-range reverse assertion (N-11 / N-12)
# =============================================================================
func test_ci_a11y_values_scan_reverse() -> void:
	# Mirrors test_budget_assert.gd::test_budget_assert_emits_warn_on_violation:
	# a scan that cannot go red is decoration. WARN-ONLY per [D15-A], so this
	# asserts the emitted ids — never an exit code, and never the N-7 risky token.
	var bc := BudgetChecks.new()

	# ① The SHIPPED defaults must scan clean. If this goes red, the game is
	#    shipping an out-of-range accessibility default right now.
	var clean: PackedStringArray = bc.scan_a11y_values(
		A11yModel.default_values(), "shipped defaults")
	assert_eq(clean.size(), 0,
		"@ci:a11y-values-in-range: the shipped defaults must scan clean (got %s)" % str(clean))

	# ② ★ REVERSE — a real out-of-range value must surface a warning.
	var low: Dictionary = A11yModel.default_values()
	low["time_scale_user"] = 0.05
	assert_true(bc.scan_a11y_values(low, "<injected>").has("a11y-values-in-range"),
		"@ci reverse: time_scale_user 0.05 (< T-01 floor 0.1) MUST emit a warning")

	var big: Dictionary = A11yModel.default_values()
	big["text_scale"] = 2.5
	assert_true(bc.scan_a11y_values(big, "<injected>").has("a11y-values-in-range"),
		"@ci reverse: text_scale 2.5 (> X-01 ceiling 1.5) MUST emit a warning")

	# ③ ★ REVERSE — an illegal enum value must surface a warning.
	var bad_fog: Dictionary = A11yModel.default_values()
	bad_fog["fog_option"] = 7
	assert_true(bc.scan_a11y_values(bad_fog, "<injected>").has("a11y-values-in-range"),
		"@ci reverse: fog_option 7 is not a legal rung and MUST emit a warning")

	var bad_cb: Dictionary = A11yModel.default_values()
	bad_cb["colorblind_mode"] = 42
	assert_true(bc.scan_a11y_values(bad_cb, "<injected>").has("a11y-values-in-range"),
		"@ci reverse: colorblind_mode 42 is not a legal mode and MUST emit a warning")

	# ④ ★ REVERSE — a DELETED field must surface too. Silence on a missing key
	#    is how a scan rots green while the model quietly loses a setting.
	var missing: Dictionary = A11yModel.default_values()
	missing.erase("text_scale")
	assert_true(bc.scan_a11y_values(missing, "<injected>").has("a11y-values-in-range"),
		"@ci reverse: a field removed from the model MUST emit a warning, not silence")


# =============================================================================
# helpers
# =============================================================================

## Enumerate every `const <NAME>_HZ := <float>` declared in a script, so the V-01
## ceiling binds frequencies that do not exist yet. Returns name -> Hz.
## `FLICKER_HZ_MAX` is excluded by construction: it ends in `_MAX`, and it is the
## ceiling itself rather than a modulation.
func _declared_hz_constants(path: String) -> Dictionary:
	var out: Dictionary = {}
	var text: String = FileAccess.get_file_as_string(path)
	if text == "":
		return out
	for raw in text.split("\n"):
		var line: String = raw.strip_edges()
		if not line.begins_with("const "):
			continue
		var eq: int = line.find(":=")
		if eq < 0:
			continue
		# `const_name`, not `name`: this script extends GutTest -> Node, and a
		# local called `name` would shadow Node.name (GDScript 4 warning).
		var const_name: String = line.substr(6, eq - 6).strip_edges()
		if not const_name.ends_with("_HZ"):
			continue
		var rhs: String = line.substr(eq + 2)
		var hash_at: int = rhs.find("#")
		if hash_at >= 0:
			rhs = rhs.substr(0, hash_at)
		out[const_name] = rhs.strip_edges().to_float()
	return out


## Parse the FLAG-J blacklist out of test_save_manager.gd. Reading the sibling
## test's source (rather than importing it) keeps the two suites independent:
## neither can be made green by editing the other's constants alone.
func _registered_a11y_field_names(text: String) -> Array:
	var out: Array = []
	if text == "":
		return out
	var parts: PackedStringArray = text.split("const A11Y_FIELD_NAMES := [")
	if parts.size() < 2:
		return out
	var block: String = parts[1].split("]")[0]
	for raw in block.split("\n"):
		var line: String = raw.strip_edges()
		if line.begins_with("#"):
			continue
		var q1: int = line.find("\"")
		if q1 < 0:
			continue
		var q2: int = line.find("\"", q1 + 1)
		if q2 < 0:
			continue
		out.append(line.substr(q1 + 1, q2 - q1 - 1))
	return out
