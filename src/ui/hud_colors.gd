class_name HudColors
extends RefCounted

# ASHEN STEP — Sprint 1 Batch C. E09 HUD colour authority (decision D7).
#
# 色值权威 / colour authority: design/art/hud-a11y-signature.md v1.0
# (林绘澄 Art Sign-off, D7 PASS). Engineering must NOT invent or retune values
# here — the palette is signed art, and hud_slice.gd is forbidden from carrying
# any hard-coded colour literal of its own.
#
# Contrast is computed against the reference panel #16181D; the two shipped
# panel variants (#1B1B1F / #1C1F26) also clear their gates — see PANEL_VARIANTS.
#
# ★ HARD RULE (landmine 3): #7A2E2E is 1.91:1 against the panel. It is
# mathematically incapable of ever satisfying C-02 (7:1) or C-03 (3:1). It may
# be used ONLY as a background fill at alpha <= ALARM_FILL_ALPHA_MAX, never as
# text, never as a bar body, never as a border, never as an icon. The reverse
# assertion in tests/unit/test_hud_slice.gd::test_suspicion_bar_contrast exists
# to break the build if anyone promotes it.
#
# ── Spec deviation (exactly one, values identical) ──────────────────────────
# batchc-impl-spec §2.3.1 writes these as `Color.from_string("#16181D", ...)`.
# GDScript 4.4 only accepts CONSTANT EXPRESSIONS in a `const`, and a static
# method call is not one — `Color.from_string()` fails to compile with
# "Assigned value for constant isn't a constant expression" (verified against
# Godot_v4.4-stable). The constant-foldable `Color("#hex")` constructor is used
# instead: the hex literals are copied verbatim from the signature document and
# the runtime values are identical; only the compile-time evaluation differs.

const HUD_COLOR_PANEL_BASE := Color("#16181D")   #  ----   contrast reference panel
const HUD_COLOR_CARRIER := Color("#DCE3EC")      # 13.74:1  C-02 ✅ every carrier
const HUD_COLOR_CALM := Color("#3E5C76")         #  2.53:1  decorative stroke only
const HUD_COLOR_CAUTION := Color("#C8862F")      #  5.84:1  C-01/C-03 ✅
const HUD_COLOR_ALARM := Color("#D64545")        #  4.06:1  C-03 ✅ borders + icons
const HUD_COLOR_ALARM_FILL := Color("#7A2E2E")   #  1.91:1  ★ FILL ONLY, a <= 0.35
const HUD_COLOR_ALARM_CB := HUD_COLOR_CAUTION    #          C-06 substitute
# Pre-approved alternative, used ONLY if an audit demands the alarm border clear
# C-01 on its own. Do not invent a different one.
const HUD_COLOR_ALARM_ALT := Color("#E0584F")    #  4.80:1  C-01 ✅

# ★ The hard ceiling on #7A2E2E (signature document §3).
const ALARM_FILL_ALPHA_MAX := 0.35

# Cross-check panels from the signature document §1. Every carrier must clear
# its gate on these too, not just on the reference panel.
const PANEL_VARIANTS := [Color("#1B1B1F"), Color("#1C1F26")]


# --- WCAG 2.x pure functions -------------------------------------------------
# Headless-safe by construction: these are arithmetic on Color values and never
# sample a pixel, so C-02/C-03 can be asserted in a GUT unit test rather than in
# a screenshot diff.

static func relative_luminance(c: Color) -> float:
	return 0.2126 * _linearize(c.r) + 0.7152 * _linearize(c.g) + 0.0722 * _linearize(c.b)


static func wcag_contrast(fg: Color, bg: Color) -> float:
	var l1 := relative_luminance(fg)
	var l2 := relative_luminance(bg)
	var hi := maxf(l1, l2)
	var lo := minf(l1, l2)
	return (hi + 0.05) / (lo + 0.05)


# Pre-composite a translucent colour over an opaque one. Used to evaluate the
# contrast of carriers drawn ON TOP of a semi-transparent fill (the exposure
# overlay, the suspicion-bar alpha ladder) without ever reading the framebuffer.
static func composite(fg: Color, bg: Color, alpha: float) -> Color:
	var a := clampf(alpha, 0.0, 1.0)
	return Color(
		fg.r * a + bg.r * (1.0 - a),
		fg.g * a + bg.g * (1.0 - a),
		fg.b * a + bg.b * (1.0 - a),
		1.0)


static func _linearize(channel: float) -> float:
	if channel <= 0.03928:
		return channel / 12.92
	return pow((channel + 0.055) / 1.055, 2.4)
