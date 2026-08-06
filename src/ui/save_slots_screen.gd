class_name SaveSlotsScreen
extends CanvasLayer

# ASHEN STEP — Sprint 3, Batch B. E11 · SAV-S5 manual save/load UI, VIEW HALF.
#
# Screens implemented (sprint3-sav-s5-ux-spec.md §1.1):
#   SCR_SLOTS    — mode SAVE / LOAD, one 4-row list (1 read-only checkpoint row
#                  + 3 manual rows), row-level focus + a fixed bottom action bar
#   SCR_CONFIRM  — modal, kind OVERWRITE / LOAD / DELETE, focus-trapped,
#                  default focus on 取消
#   SCR_LOADFADE — transient 0.4s eased fade-in on a successful load
#
# ── Division of labour with save_ui_model.gd ────────────────────────────────
# This file owns WIDGETS. It owns no rules. Every "may I / what does it say /
# how long does it last" question is answered by SaveUiModel, which is pure and
# therefore assertable in a headless CI run. If you find yourself writing an
# `if` about save semantics in here, it belongs in the model.
#
# ── Zero new signals (E01-S9 freeze) ────────────────────────────────────────
# SUBSCRIBES to the three EXISTING bus signals (save_completed / load_completed
# / checkpoint_restored) and CALLS the two existing APIs (write_slot /
# read_slot). It declares no signal of its own and adds nothing to the bus.
# Everything that would traditionally be an outgoing event is delivered through
# an injected Callable instead (subtitle sink, audio sink, close sink).
#
# ── Colour discipline ───────────────────────────────────────────────────────
# No colour literal here. Every colour comes from src/ui/hud_colors.gd.
#
# ── Headless discipline ─────────────────────────────────────────────────────
# Widgets are built in code (no .tscn), nothing samples the framebuffer, nothing
# needs a camera, and every input entry point is a plain public method — so the
# whole screen can be driven from a unit test without an InputMap. Animation
# runs on wall-clock deltas, NOT on _process's scaled delta: this screen lives
# inside the paused / time-scaled state (T-03), and a 0.4s fade that stretches
# with Engine.time_scale is not a 0.4s fade.

const HudColors = preload("res://src/ui/hud_colors.gd")
const SaveUiModelScript = preload("res://src/ui/save_ui_model.gd")
const SaveManagerScript = preload("res://src/core/save_manager.gd")
const EventBus = preload("res://src/core/event_bus.gd")

# ── Audio cue names (spec §3.4) ──────────────────────────────────────────────
# The screen does not synthesise anything; it names the cue and the audio layer
# resolves it. Naming them as constants is what lets a unit test prove「禁用不
# 等于沉默」— that a refused action really did request a sound.
const CUE_SUCCESS := "save_success"        # single low「嗒」, 110-140Hz
const CUE_FAILURE := "save_failure"        # muffled thud, LPF ~900Hz
const CUE_DENIED := "action_denied"        # same thud, -3dB
# Load success deliberately has NO UI cue: the world coming back IS the
# confirmation, and stacking a「嗒」on top would be two success signals for one
# event (spec §3.3).

# ── Layout (fractions of the viewport; X-01 safe because nothing is a fixed
#    pixel height and rows grow with their content) ──────────────────────────
const PANEL_ANCHOR_LEFT := 0.18
const PANEL_ANCHOR_RIGHT := 0.82
const PANEL_ANCHOR_TOP := 0.10
const PANEL_ANCHOR_BOTTOM := 0.86
const ROW_MIN_HEIGHT := 56.0
const THUMB_SIZE := Vector2(64, 36)
const BASE_FONT_SIZE := 16
const TITLE_FONT_SIZE := 24
const ROW_NAME_FONT_SIZE := 18
const ROW_SUB_FONT_SIZE := 14

# Focus ring / boundary stroke widths (spec §2.2 rows 3 and 9).
const BOUNDARY_WIDTH := 1
const CHECKPOINT_BAR_WIDTH := 3

# Corrupt badge icon box (ui-badge-corrupt-spec §2.1: ~18-20px, aligned to the
# row's sub-text height).
const BADGE_ICON_SIZE := Vector2(18, 18)

# ── Collaborators (all injected; none looked up implicitly) ─────────────────
var _bus: EventBus = null
var _sm: SaveManagerScript = null
var _model: SaveUiModelScript = null

## Returns the world snapshot Dictionary to persist. Injected because the save
## screen has no business knowing how a world snapshot is assembled.
var _snapshot_provider: Callable = Callable()
## show_subtitle(speaker, line) — normally hud_slice.gd's. A Callable rather
## than a HudSlice reference keeps L5-to-L5 coupling out and lets the X-02
## assertions run without a HUD in the tree.
var _subtitle_sink: Callable = Callable()
## play_cue(name, gain_db)
var _audio_sink: Callable = Callable()
## Called when the screen wants to go back to SCR_PAUSE.
var _close_sink: Callable = Callable()
## E-6. fade_sink(phase: String, alpha: float), phase ∈ "begin" | "tick" | "end".
##
## The FOURTH sink, and the reason it is a sink rather than a direct
## AudioDirector call: the 0.4s load fade must have exactly ONE clock. If the
## audio layer subscribed to load_completed and ran its own 0.4s timer, that is
## two clocks, and two clocks are the whole mechanism behind「先听到后看到」
## (AUD-F2). Here the screen hands out the same float it just fed the veil, in
## the same frame, so the drift is structurally zero rather than merely small.
var _fade_sink: Callable = Callable()

## L2 time controller (E-11). Injected, never looked up. The save screen is a
## T-03 explicit-pause context: opening it freezes the world and closing it —
## by EITHER exit path — thaws it. Null is a supported state; the screen simply
## does not pause, which is what every headless test does.
var _time: Node = null
## A11ySettings. Only ever asked one question: colorblind_mode, for the C-06
## danger resolver on the corrupt badge. Null means「OFF」.
var _a11y: Node = null

# ── Observability for tests (never used for control flow) ───────────────────
var cue_log: Array = []
var subtitle_log: Array = []
var fade_log: Array = []
var close_count: int = 0

# ── Widgets ─────────────────────────────────────────────────────────────────
var _root: Control = null
var _scrim: ColorRect = null
var _panel: Panel = null
var _panel_style: StyleBoxFlat = null
var _title: Label = null
var _rows_box: VBoxContainer = null
var _row_widgets: Array = []
var _divider: Panel = null
var _notice: Label = null
var _hint: Label = null
var _toast: Label = null
var _action_primary: Label = null
var _action_delete: Label = null
var _action_cancel: Label = null

var _confirm: Control = null
var _confirm_title: Label = null
var _confirm_body: Label = null
var _confirm_cancel: Label = null
var _confirm_accept: Label = null
var _confirm_focus_cancel: bool = true

var _fade: ColorRect = null

## The corrupt badge's SHAPE channel (C-05), resolved once and shared by every
## row — all three manual slots can be corrupt at the same time, and the 2.0Hz
## pulse would otherwise re-resolve the same path three times a frame.
##
## Deliberately NOT a preload(). preload() is resolved at PARSE time, so an
## .svg that is missing or not yet imported would take this entire script down
## with it — and a decorative glyph on an error row must never be able to stop
## the save screen from opening. When it is unavailable the row still reads
## 「〔损坏〕」 in text, which is the channel that was load-bearing all along.
var _corrupt_icon: Texture2D = null
var _corrupt_icon_resolved: bool = false

var _pulse_t: float = 0.0
var _last_ms: int = 0


func _ready() -> void:
	if _model == null:
		_model = SaveUiModelScript.new()
	_build_ui()
	_connect_bus()
	_refresh()
	visible = false


# =============================================================================
# Wiring
# =============================================================================
func set_event_bus(bus: EventBus) -> void:
	_bus = bus
	_connect_bus()


func set_save_manager(sm: SaveManagerScript) -> void:
	_sm = sm


func set_snapshot_provider(provider: Callable) -> void:
	_snapshot_provider = provider


func set_subtitle_sink(sink: Callable) -> void:
	_subtitle_sink = sink


func set_audio_sink(sink: Callable) -> void:
	_audio_sink = sink


## E-6. See _fade_sink above for why the audio layer is not allowed to time the
## load fade itself.
func set_fade_sink(sink: Callable) -> void:
	_fade_sink = sink


## E-7. The canonical audio wiring, as ONE call.
##
## ★ It is one call on purpose. The cue sink and the fade sink look independent
## and are not: wire only the cue sink and a load leaves the World bus parked at
## the PAUSED preset (-12 dB / LPF 700 Hz) forever, because end_load_fade() is
## the sole reset point on that path. That failure does not crash, does not log
## and does not fail CI — it just makes the game quietly muffled from then on.
## A single entry point is what stops a future screen-flow batch from wiring
## half of it.
##
## `director` is duck-typed so a test can pass a stub with the same two methods.
func wire_audio(director: Node) -> void:
	if director == null or not is_instance_valid(director):
		return
	if director.has_method("play_cue"):
		set_audio_sink(Callable(director, "play_cue"))
	if director.has_method("fade_sink"):
		set_fade_sink(Callable(director, "fade_sink"))


## E-11. Optional. Without it the screen still works, it just does not pause.
func set_time_controller(tc: Node) -> void:
	_time = tc


func set_a11y_settings(a11y: Node) -> void:
	_a11y = a11y


## C-06 input. A11ySettings.ColorBlindMode.OFF == 0, so an absent settings node
## reads as「OFF」— the un-substituted palette, which is the correct default and
## never the more dangerous one.
func colorblind_mode() -> int:
	if _a11y == null or not is_instance_valid(_a11y):
		return 0
	if not ("colorblind_mode" in _a11y):
		return 0
	return int(_a11y.colorblind_mode)


func set_close_sink(sink: Callable) -> void:
	_close_sink = sink


func model() -> SaveUiModelScript:
	if _model == null:
		_model = SaveUiModelScript.new()
	return _model


## Idempotent — _ready() and set_event_bus() may both run, in either order.
func _connect_bus() -> void:
	if _bus == null or not is_instance_valid(_bus):
		return
	if not _bus.save_completed.is_connected(_on_save_completed):
		_bus.save_completed.connect(_on_save_completed)
	if not _bus.load_completed.is_connected(_on_load_completed):
		_bus.load_completed.connect(_on_load_completed)
	if not _bus.checkpoint_restored.is_connected(_on_checkpoint_restored):
		_bus.checkpoint_restored.connect(_on_checkpoint_restored)


# =============================================================================
# Opening / closing
# =============================================================================
## EC-6: the list is snapshotted HERE and not refreshed while the player
## browses. A row mutating under the cursor would move the meaning of "this
## row" mid-read and cut off any screen reader parked on it.
func open_screen(mode: int) -> void:
	model().open(mode, scan_rows())
	_confirm_focus_cancel = true
	_pulse_t = 0.0
	_last_ms = Time.get_ticks_msec()
	visible = true
	# T-03: the save screen IS an explicit pause context. The world freezing is
	# also what drives the World bus to its PAUSED preset, via
	# time_scale_changed — the screen never talks to the audio layer about it.
	_enter_pause()
	_refresh()


## Exit path 1 of 2 — cancel / back. Path 2 is _end_load_fade(), which does NOT
## come through here. Anything that must happen on「the screen is going away」
## has to be in BOTH.
func close_screen() -> void:
	visible = false
	_exit_pause()
	close_count += 1
	if _close_sink.is_valid():
		_close_sink.call()


## Read-only metadata peek over the slot files. It never writes and never emits
## — building a list must not look to the rest of the game like the player just
## loaded three saves, which is exactly what calling read_slot() three times
## would broadcast.
func scan_rows() -> Array:
	var rows: Array = SaveUiModelScript.blank_rows()
	if _sm == null or not is_instance_valid(_sm):
		return rows
	# O-3b: this is the「首次枚举槽位」trigger for orphaned-staging recovery. It
	# has to happen BEFORE the rows are peeked, because this scan is what decides
	# a row is EMPTY — and an empty row is offered to the player as free space.
	# Without this, a save interrupted between writing and promoting would be
	# shown as an empty slot and then overwritten by the next save. The call is
	# idempotent and emits nothing on the bus, so it cannot make building the
	# list look like a load (test_building_the_list_never_looks_like_a_load).
	_sm.ensure_staging_recovered()
	for i in range(rows.size()):
		var slot_id := int(rows[i]["slot_id"])
		var readonly := bool(rows[i]["readonly"])
		var path: String = _sm.slot_path(slot_id)
		var text := ""
		if FileAccess.file_exists(path):
			text = FileAccess.get_file_as_string(path)
		rows[i] = SaveUiModelScript.peek_row(slot_id, text, readonly)
	return rows


# =============================================================================
# Input entry points (plain methods so tests need no InputMap; a real binding
# layer maps A12/A13/A14/A15 onto these)
# =============================================================================
func navigate(delta: int) -> void:
	if _confirm != null and _confirm.visible:
		# Focus trap (spec §2.4): inside the modal, navigation only ever toggles
		# between 取消 and the affirmative button. Tab must not escape to the
		# list underneath.
		_confirm_focus_cancel = not _confirm_focus_cancel
		_refresh_confirm()
		return
	model().move_focus(delta)
	_refresh()


func press_primary() -> void:
	_handle(model().press_primary())


func press_delete() -> void:
	_handle(model().press_delete())


func press_cancel() -> void:
	_handle(model().press_cancel())


## The affirmative / negative buttons of SCR_CONFIRM. `accept_focused()` routes
## A12 inside the modal to whichever button currently holds focus, which is what
## makes 取消 the safe default actually mean something.
func accept_focused() -> void:
	if _confirm_focus_cancel:
		_handle(model().confirm_cancel())
	else:
		_handle(model().confirm_accept())
	_confirm_focus_cancel = true


func confirm_accept() -> void:
	_handle(model().confirm_accept())
	_confirm_focus_cancel = true


func confirm_cancel() -> void:
	_handle(model().confirm_cancel())
	_confirm_focus_cancel = true


# =============================================================================
# Intent execution — the ONLY place this screen touches SaveManager
# =============================================================================
func _handle(intent: Dictionary) -> void:
	var op := str(intent.get("op", "none"))
	var slot_id := int(intent.get("slot_id", -99))
	match op:
		"deny":
			# 「禁用不等于沉默」: a muffled cue plus one line of plain reason.
			# Silence here is the single largest source of "is this thing
			# broken?" in a menu.
			_cue(CUE_DENIED, -3.0)
		"write":
			if _sm != null and is_instance_valid(_sm):
				_sm.write_slot(slot_id, _snapshot())
		"read":
			if _sm != null and is_instance_valid(_sm):
				_sm.read_slot(slot_id)
		"delete":
			_delete_slot_file(slot_id)
			# Deleting is also「操作成立」, so it reuses the success cue rather
			# than minting a new one (spec §3.1: avoid sound-effect inflation).
			_cue(CUE_SUCCESS, -1.0)
			_subtitle("已删除 · 槽 %d" % (slot_id + 1))
		"saved":
			_cue(CUE_SUCCESS, 0.0)
			_subtitle(str(intent.get("reason", "")))
		"save_failed", "load_failed", "timeout":
			_cue(CUE_FAILURE, 0.0)
			_subtitle(str(intent.get("reason", "")))
		"load_fade_begin":
			# SCR_SLOTS and the scrim leave at t=0 so they cannot ghost through
			# the fade; only the fade overlay survives.
			_begin_load_fade()
		"load_fade_end":
			_subtitle(str(intent.get("reason", "")))
			_end_load_fade()
		"close":
			close_screen()
	_refresh()


func _snapshot() -> Dictionary:
	if _snapshot_provider.is_valid():
		var snap: Variant = _snapshot_provider.call()
		if snap is Dictionary:
			return snap
	return {}


## SaveManager exposes no delete API and its surface is frozen for this batch,
## so the unlink happens here, routed through slot_path() so the UI never builds
## a save path of its own.
##
## ⚠ ARCHITECTURE NOTE (follow-up, not this batch): file removal is L2 work
## living in L5. The clean fix is SaveManager.delete_slot(id), which is an L2
## API ADDITION and therefore out of scope while the surface is pinned. Logged
## for the lead rather than smuggled in.
func _delete_slot_file(slot_id: int) -> void:
	if _sm == null or not is_instance_valid(_sm):
		return
	var path: String = _sm.slot_path(slot_id)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _cue(name: String, gain_db: float) -> void:
	cue_log.append({"cue": name, "gain_db": gain_db})
	if _audio_sink.is_valid():
		_audio_sink.call(name, gain_db)


## E-6. Logged unconditionally so the phase sequence is assertable with no audio
## layer present at all —「begin exactly once, then ticks, then end exactly
## once」is a property of THIS file, not of the thing on the other end.
func _emit_fade(phase: String, alpha: float) -> void:
	fade_log.append({"phase": phase, "alpha": alpha})
	if _fade_sink.is_valid():
		_fade_sink.call(phase, alpha)


## E-11 / T-03. No-ops without an injected controller.
func _enter_pause() -> void:
	if _time == null or not is_instance_valid(_time):
		return
	if _time.has_method("enter_paused"):
		_time.enter_paused()


func _exit_pause() -> void:
	if _time == null or not is_instance_valid(_time):
		return
	if _time.has_method("exit_paused"):
		_time.exit_paused()


## X-02. Speaker is「系统」, never the hud_slice「环境」fallback — a UI sound has
## no diegetic source, and mislabelling it as ambience tells a deaf player the
## world made a noise when in fact their menu did.
func _subtitle(line: String) -> void:
	if line == "":
		return
	subtitle_log.append(line)
	if _subtitle_sink.is_valid():
		_subtitle_sink.call(SaveUiModelScript.SUBTITLE_SPEAKER_SYSTEM, line)


# =============================================================================
# Bus handlers (subscribe only)
# =============================================================================
func _on_save_completed(slot_id: int, success: bool) -> void:
	var stamp := Time.get_unix_time_from_system()
	var cp := ""
	var snap := _snapshot()
	if snap.has("checkpoint_id"):
		cp = str(snap["checkpoint_id"])
	_handle(model().on_save_completed(slot_id, success, stamp, cp))


func _on_load_completed(slot_id: int, success: bool) -> void:
	var reason := ""
	if not success and _sm != null and is_instance_valid(_sm):
		# Reuse SaveManager's own classification instead of re-deciding what
		# "broken" means — two definitions of corruption would eventually
		# disagree, and the player would get a message the log contradicts.
		var raw: String = _sm.get_corrupt_reason(slot_id)
		if raw == SaveManagerScript.REASON_VERSION_MISMATCH:
			reason = SaveUiModelScript.REASON_CORRUPT_VERSION
		elif raw != "":
			reason = SaveUiModelScript.REASON_CORRUPT_PARSE
	_handle(model().on_load_completed(slot_id, success, reason))


func _on_checkpoint_restored(checkpoint_id: String) -> void:
	model().on_checkpoint_restored(checkpoint_id)
	_refresh()


# =============================================================================
# Build
# =============================================================================
func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# L0 — world scrim. Eased in by the caller's transition (V-06 forbids a
	# hard cut); the colour and alpha are the spec's §1.3 layer table.
	_scrim = ColorRect.new()
	_scrim.color = _with_alpha(HudColors.HUD_COLOR_SCRIM, SaveUiModelScript.SCRIM_ALPHA)
	_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_scrim)

	# L1 — panel chrome at 88%.
	_panel = Panel.new()
	_panel.anchor_left = PANEL_ANCHOR_LEFT
	_panel.anchor_right = PANEL_ANCHOR_RIGHT
	_panel.anchor_top = PANEL_ANCHOR_TOP
	_panel.anchor_bottom = PANEL_ANCHOR_BOTTOM
	_panel_style = StyleBoxFlat.new()
	_panel_style.bg_color = _with_alpha(
		HudColors.HUD_COLOR_PANEL_SLOT, SaveUiModelScript.PANEL_ALPHA)
	_panel_style.set_border_width_all(BOUNDARY_WIDTH)
	_panel_style.border_color = HudColors.HUD_COLOR_BOUNDARY
	_panel.add_theme_stylebox_override("panel", _panel_style)
	_root.add_child(_panel)

	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", 8)
	_panel.add_child(col)

	# Serif title (art-bible §8.3「石碑铭文」); every other string is sans, because
	# timestamps and ids are numeric data and legibility beats character there.
	_title = _make_label("", TITLE_FONT_SIZE)
	col.add_child(_title)

	_rows_box = VBoxContainer.new()
	_rows_box.add_theme_constant_override("separation", 4)
	col.add_child(_rows_box)

	_build_rows()

	_notice = _make_label("", BASE_FONT_SIZE)
	col.add_child(_notice)

	_hint = _make_label("", BASE_FONT_SIZE)
	col.add_child(_hint)

	_toast = _make_label("", BASE_FONT_SIZE)
	_toast.visible = false
	col.add_child(_toast)

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 24)
	_action_primary = _make_label("", BASE_FONT_SIZE)
	_action_delete = _make_label("", BASE_FONT_SIZE)
	_action_cancel = _make_label("", BASE_FONT_SIZE)
	bar.add_child(_action_primary)
	bar.add_child(_action_delete)
	bar.add_child(_action_cancel)
	col.add_child(bar)

	_build_confirm()
	_build_fade()


func _build_rows() -> void:
	_row_widgets = []
	for i in range(SaveUiModelScript.ROW_COUNT):
		# The divider between the checkpoint row and the manual rows is a
		# SEMANTIC partition (system-written vs player-written), not decoration,
		# so it uses the information-boundary stroke.
		if i == SaveUiModelScript.FIRST_MANUAL_ROW:
			_divider = Panel.new()
			_divider.custom_minimum_size = Vector2(0, BOUNDARY_WIDTH)
			var dstyle := StyleBoxFlat.new()
			dstyle.bg_color = HudColors.HUD_COLOR_BOUNDARY
			_divider.add_theme_stylebox_override("panel", dstyle)
			_rows_box.add_child(_divider)

		var row_panel := Panel.new()
		row_panel.custom_minimum_size = Vector2(0, ROW_MIN_HEIGHT)
		var style := StyleBoxFlat.new()
		# L2 — rows are OPAQUE. This is the contrast denominator for the whole
		# screen (see SaveUiModel.ROW_ALPHA).
		style.bg_color = _with_alpha(
			HudColors.HUD_COLOR_PANEL_SLOT, SaveUiModelScript.ROW_ALPHA)
		style.set_border_width_all(BOUNDARY_WIDTH)
		style.border_color = HudColors.HUD_COLOR_BOUNDARY
		row_panel.add_theme_stylebox_override("panel", style)
		_rows_box.add_child(row_panel)

		var hb := HBoxContainer.new()
		hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		hb.add_theme_constant_override("separation", 12)
		row_panel.add_child(hb)

		# Left rule marking「system writes this one」on the checkpoint row.
		var sysbar := Panel.new()
		sysbar.custom_minimum_size = Vector2(CHECKPOINT_BAR_WIDTH, 0)
		var sbstyle := StyleBoxFlat.new()
		sbstyle.bg_color = HudColors.HUD_COLOR_BOUNDARY
		sysbar.add_theme_stylebox_override("panel", sbstyle)
		sysbar.visible = i == SaveUiModelScript.CHECKPOINT_ROW
		hb.add_child(sysbar)

		var thumb := Panel.new()
		thumb.custom_minimum_size = THUMB_SIZE
		var tstyle := StyleBoxFlat.new()
		tstyle.bg_color = HudColors.HUD_COLOR_THUMB_FILL
		tstyle.set_border_width_all(BOUNDARY_WIDTH)
		# Decorative frame on the read-only row, information frame on the rows
		# the player can act on (art-bible §8.1 stroke dichotomy).
		tstyle.border_color = (HudColors.HUD_COLOR_CALM
			if i == SaveUiModelScript.CHECKPOINT_ROW
			else HudColors.HUD_COLOR_BOUNDARY)
		thumb.add_theme_stylebox_override("panel", tstyle)
		hb.add_child(thumb)

		var thumb_glyph := _make_label("", BASE_FONT_SIZE)
		thumb.add_child(thumb_glyph)

		var text_col := VBoxContainer.new()
		hb.add_child(text_col)
		var name_label := _make_label("", ROW_NAME_FONT_SIZE)
		var sub_label := _make_label("", ROW_SUB_FONT_SIZE)
		text_col.add_child(name_label)
		text_col.add_child(sub_label)

		# ART-OOS-2 交付 D. The corrupt badge's SHAPE channel used to be a ⚠
		# inside the label's string, i.e. at the mercy of whatever emoji font
		# the platform ships. A TextureRect cannot be font-substituted, and its
		# modulate turns one white asset into both C-06 colour states.
		var badge_icon := TextureRect.new()
		badge_icon.custom_minimum_size = BADGE_ICON_SIZE
		badge_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		badge_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		badge_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge_icon.visible = false
		hb.add_child(badge_icon)

		var badge := _make_label("", ROW_SUB_FONT_SIZE)
		hb.add_child(badge)

		_row_widgets.append({
			"panel": row_panel,
			"style": style,
			"thumb_style": tstyle,
			"thumb_glyph": thumb_glyph,
			"name": name_label,
			"sub": sub_label,
			"badge": badge,
			"badge_icon": badge_icon,
			"sysbar": sysbar,
		})


func _build_confirm() -> void:
	_confirm = Control.new()
	_confirm.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_confirm.visible = false
	_root.add_child(_confirm)

	# The modal scrim is what makes the focus trap legible: everything behind it
	# is visibly out of play.
	var mscrim := ColorRect.new()
	mscrim.color = _with_alpha(HudColors.HUD_COLOR_SCRIM, SaveUiModelScript.SCRIM_ALPHA)
	mscrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_confirm.add_child(mscrim)

	var box := Panel.new()
	box.anchor_left = 0.28
	box.anchor_right = 0.72
	box.anchor_top = 0.34
	box.anchor_bottom = 0.62
	var style := StyleBoxFlat.new()
	# The dialog is fully opaque: it is asking about an irreversible action and
	# must not be read against a moving background.
	style.bg_color = _with_alpha(HudColors.HUD_COLOR_PANEL_SLOT, 1.0)
	style.set_border_width_all(BOUNDARY_WIDTH)
	style.border_color = HudColors.HUD_COLOR_BOUNDARY
	box.add_theme_stylebox_override("panel", style)
	_confirm.add_child(box)

	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", 10)
	box.add_child(col)

	_confirm_title = _make_label("", ROW_NAME_FONT_SIZE + 2)
	_confirm_body = _make_label("", BASE_FONT_SIZE)
	_confirm_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_confirm_title)
	col.add_child(_confirm_body)

	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 24)
	_confirm_cancel = _make_label("", BASE_FONT_SIZE)
	_confirm_accept = _make_label("", BASE_FONT_SIZE)
	btns.add_child(_confirm_cancel)
	btns.add_child(_confirm_accept)
	col.add_child(btns)


func _build_fade() -> void:
	# SCR_LOADFADE. The world cannot be faded from a CanvasLayer, so the
	# equivalent is an opaque veil whose alpha runs 1 -> 0 while the world's
	# apparent alpha runs 0 -> 1. world_fade_alpha() below reports the WORLD
	# figure, which is the one the spec is written in.
	_fade = ColorRect.new()
	_fade.color = _with_alpha(HudColors.HUD_COLOR_SCRIM, 1.0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.visible = false
	_root.add_child(_fade)


func _make_label(text: String, size_px: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", HudColors.HUD_COLOR_CARRIER)
	l.add_theme_font_size_override("font_size", size_px)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


# =============================================================================
# Refresh
# =============================================================================
func _refresh() -> void:
	if _title == null:
		return
	var m := model()
	_title.text = m.title()

	var rows: Array = m.rows()
	for i in range(_row_widgets.size()):
		if i >= rows.size():
			continue
		_refresh_row(i, rows[i], i == m.focus_index())

	_notice.text = m.footer_notice()
	_notice.visible = _notice.text != ""

	_hint.text = m.denial_hint()
	_hint.visible = _hint.text != ""

	var toast: Dictionary = m.toast()
	if toast.is_empty():
		_toast.visible = false
	else:
		_toast.visible = true
		_toast.text = str(toast.get("text", ""))

	_refresh_action_bar()
	_refresh_confirm()

	if _scrim != null:
		_scrim.visible = m.state() != SaveUiModelScript.State.LOADING_FADE
	if _panel != null:
		_panel.visible = m.state() != SaveUiModelScript.State.LOADING_FADE


func _refresh_row(index: int, row: Dictionary, focused: bool) -> void:
	var w: Dictionary = _row_widgets[index]
	var style: StyleBoxFlat = w["style"]
	var status := int(row.get("status", SaveUiModelScript.RowStatus.EMPTY))

	w["name"].text = SaveUiModelScript.row_label(row)
	w["sub"].text = SaveUiModelScript.row_subtitle(row)
	w["badge"].text = SaveUiModelScript.row_badge(row)
	w["thumb_glyph"].text = SaveUiModelScript.row_thumb_glyph(row)

	# ── Focus read: THREE independent channels (spec §2.2 row 9) ─────────────
	#   position — which row the ring is on
	#   ring     — 2px #F0C070 solid, 10.20:1, and 0Hz FOREVER (see the model)
	#   lift     — the focused row's background gets brighter
	# The lift exists because in colour-blind mode the ring shares a hex with
	# the corrupt badge (FLAG-L). Hue may collapse; brightness and position do
	# not, so the focused row is still identifiable at a glance.
	if focused:
		style.set_border_width_all(SaveUiModelScript.FOCUS_RING_WIDTH_PX)
		style.border_color = HudColors.HUD_COLOR_FOCUS
		style.bg_color = HudColors.composite(
			HudColors.HUD_COLOR_CARRIER,
			HudColors.HUD_COLOR_PANEL_SLOT,
			SaveUiModelScript.FOCUS_ROW_LIFT_ALPHA)
	else:
		style.set_border_width_all(BOUNDARY_WIDTH)
		style.border_color = HudColors.HUD_COLOR_BOUNDARY
		style.bg_color = _with_alpha(
			HudColors.HUD_COLOR_PANEL_SLOT, SaveUiModelScript.ROW_ALPHA)

	# ── Corrupt badge ────────────────────────────────────────────────────────
	# This block used to claim「走 C-06 解析器」in a comment while both branches
	# assigned the same neutral carrier colour: the resolver was never called,
	# so colour-blind mode changed nothing here and the comment was the only
	# evidence of an intent that had not been implemented. Now wired for real.
	#
	# ★ THE ICON IS TINTED, THE TEXT IS NOT — and that is a contrast decision,
	# not a style one. #D64545 is 3.92:1 on the panel: it clears C-03 (>=3:1,
	# icons / world-readable elements) but NOT C-01 (>=4.5:1, UI body text).
	# Colouring the word「损坏」alarm-red would therefore trade an accessibility
	# constraint for decoration. The danger read is carried by shape (filled
	# triangle) + frequency (2.0Hz) + colour ON THE ICON, which is C-05's triple
	# coding satisfied without pushing any text under its floor.
	var badge_label: Label = w["badge"]
	var badge_icon: TextureRect = w["badge_icon"]
	var corrupt := status == SaveUiModelScript.RowStatus.CORRUPT
	badge_label.add_theme_color_override("font_color", HudColors.HUD_COLOR_CARRIER)
	if corrupt:
		# danger_color() is the SINGLE decision point for what danger looks
		# like. Writing #D64545 here by hand would fork it and strand
		# colour-blind players on the unsubstituted hue. Note the substitute is
		# HUD_COLOR_DANGER_CB — HUD_COLOR_ALARM_CB is RETIRED; read the
		# tombstone in hud_colors.gd before reaching for that name again.
		var icon := _corrupt_icon_texture()
		badge_icon.texture = icon
		# An untextured TextureRect is an invisible hole that still takes 18px
		# of the row. If the glyph did not resolve, collapse it rather than
		# leaving a gap the text has to be read around.
		badge_icon.visible = icon != null
		# ★ Carry the label's CURRENT alpha across, do not reset it to 1.0.
		# _apply_corrupt_pulse() writes both alphas at the end of tick(), but a
		# _refresh() triggered by an input arrives BETWEEN ticks — and assigning
		# a fresh opaque colour here would snap the icon to full brightness
		# while the word next to it stays mid-pulse. Two elements beating out of
		# phase read as two unrelated things, which is exactly what the shared
		# wave exists to prevent.
		var tint := HudColors.danger_color(colorblind_mode())
		tint.a = badge_label.modulate.a
		badge_icon.modulate = tint
	else:
		badge_icon.texture = null
		badge_icon.visible = false

	# Empty rows dim their subtitle to 70% — still 7.10:1, still over C-02.
	var sub_label: Label = w["sub"]
	var sub_alpha := (SaveUiModelScript.DISABLED_ALPHA
		if status == SaveUiModelScript.RowStatus.EMPTY else 1.0)
	sub_label.add_theme_color_override("font_color", HudColors.composite(
		HudColors.HUD_COLOR_CARRIER, HudColors.HUD_COLOR_PANEL_SLOT, sub_alpha))


## Resolve the corrupt-badge glyph at most ONCE per screen, successfully or not.
##
## The `_resolved` latch is what stops a missing import from turning into a
## per-frame ResourceLoader probe plus a per-frame warning: the badge pulses at
## 2.0Hz through _refresh_row(), so "retry on every failure" means 60 identical
## warnings a second in the log the moment the asset is absent.
##
## The asset is authored WHITE on purpose (art spec §5): the two-mode danger
## tint is applied by the caller through modulate, so there is exactly one
## coloured triangle in the project and exactly one place that decides its hue.
func _corrupt_icon_texture() -> Texture2D:
	if _corrupt_icon_resolved:
		return _corrupt_icon
	_corrupt_icon_resolved = true
	var path: String = SaveUiModelScript.BADGE_CORRUPT_ICON
	if path == "" or not ResourceLoader.exists(path):
		push_warning("SaveSlotsScreen: corrupt badge glyph unavailable: %s" % path)
		return null
	_corrupt_icon = load(path) as Texture2D
	return _corrupt_icon


func _refresh_action_bar() -> void:
	var m := model()
	var save_mode := m.mode() == SaveUiModelScript.Mode.SAVE
	var primary_word := "存档" if save_mode else "读档"
	_action_primary.text = "[A/Enter] %s" % primary_word
	_action_delete.text = "[Y/Del] 删除"
	_action_cancel.text = "[B/Esc] 返回"

	# Disabled entries lose their FRAME as well as their brightness (shape +
	# luminance), so「unavailable」survives any colour-vision configuration.
	_apply_enabled(_action_primary, m.is_action_enabled(SaveUiModelScript.Action.PRIMARY))
	_apply_enabled(_action_delete, m.is_action_enabled(SaveUiModelScript.Action.DELETE))
	_apply_enabled(_action_cancel, true)


func _apply_enabled(label: Label, enabled: bool) -> void:
	if label == null:
		return
	var alpha := 1.0 if enabled else SaveUiModelScript.DISABLED_ALPHA
	label.add_theme_color_override("font_color", HudColors.composite(
		HudColors.HUD_COLOR_CARRIER, HudColors.HUD_COLOR_PANEL_SLOT, alpha))


func _refresh_confirm() -> void:
	if _confirm == null:
		return
	var m := model()
	var open := m.state() == SaveUiModelScript.State.CONFIRMING
	_confirm.visible = open
	if not open:
		return
	var dlg: Dictionary = m.active_confirm_dialog()
	_confirm_title.text = str(dlg.get("title", ""))
	_confirm_body.text = str(dlg.get("body", ""))
	_confirm_cancel.text = str(dlg.get("cancel_label", "取消"))
	_confirm_accept.text = str(dlg.get("confirm_label", "确定"))
	# The focus ring inside the modal follows the same 0Hz / 2px rule as the
	# list; only its position moves.
	_apply_focus_tint(_confirm_cancel, _confirm_focus_cancel)
	_apply_focus_tint(_confirm_accept, not _confirm_focus_cancel)


func _apply_focus_tint(label: Label, focused: bool) -> void:
	if label == null:
		return
	label.add_theme_color_override(
		"font_color",
		HudColors.HUD_COLOR_FOCUS if focused else HudColors.HUD_COLOR_CARRIER)


# =============================================================================
# SCR_LOADFADE
# =============================================================================
func _begin_load_fade() -> void:
	if _fade == null:
		return
	_fade.visible = true
	_set_alpha(_fade, 1.0)
	# AUD-F6: the floor has to be hit on THIS frame, not on the first tick.
	# One frame of full-level world audio under a black screen is a bang.
	_emit_fade("begin", 0.0)


## Exit path 2 of 2 — a successful load. It deliberately does not call
## close_screen(); the screen is torn down here instead. That is exactly why the
## two resets below have to be repeated rather than inherited.
func _end_load_fade() -> void:
	# ★ ORDER IS LOAD-BEARING ★
	# "end" first: it clears the audio layer's fade lock and snaps World to
	# 0 dB. _exit_pause() second: it emits time_scale_changed(…,"FLOWING"),
	# which the audio layer would REFUSE while the fade lock is still up
	# (AUD-F8). Swap these two lines and World is left at the PAUSED preset.
	_emit_fade("end", 1.0)
	_exit_pause()
	if _fade != null:
		_fade.visible = false
	# The screen unloads completely — no residual pause panel behind the world.
	visible = false
	close_count += 1
	if _close_sink.is_valid():
		_close_sink.call()


## The WORLD's apparent alpha, 0 -> 1, eased. Exposed so the 0.4s contract can
## be asserted without reading pixels, and so the audio bed can ride the exact
## same curve (spec §3.3 requires one shared driver — a separately-tweened bed
## produces the「先听到后看到」mismatch).
func world_fade_alpha() -> float:
	return ease(model().fade_progress(), 0.5)


# =============================================================================
# Animation — wall clock, never Engine.time_scale
# =============================================================================
func _process(_scaled_delta: float) -> void:
	var now := Time.get_ticks_msec()
	var real_delta := 0.0
	if _last_ms > 0:
		real_delta = float(now - _last_ms) / 1000.0
	_last_ms = now
	if real_delta <= 0.0 or not visible:
		return
	tick(real_delta)


## Split out from _process so tests can drive time deterministically instead of
## waiting on a real clock.
func tick(real_delta: float) -> void:
	var m := model()
	var before := m.state()
	_handle(m.tick(real_delta))

	if before == SaveUiModelScript.State.LOADING_FADE and _fade != null and _fade.visible:
		# ★ ONE read of world_fade_alpha(), fed to BOTH consumers (AUD-F3/F4).
		# Calling it twice would sample the same curve at the same nominal time
		# and still be the wrong thing to write: it invites a later refactor to
		# move one of the calls a frame away, and a one-frame audio LEAD is the
		# one direction AUD-F5 tolerates at 0 ms.
		var a := world_fade_alpha()
		_set_alpha(_fade, 1.0 - a)
		_emit_fade("tick", a)

	# EC-1 drain: an Esc pressed during the lock fires the moment it lifts.
	if not m.is_input_locked() and m.take_queued_cancel():
		_handle(m.press_cancel())

	_pulse_t = fmod(_pulse_t + real_delta * SaveUiModelScript.CORRUPT_PULSE_HZ, 1.0)
	_apply_corrupt_pulse()


## V-01: 2.0Hz double-beat on the corrupt badge ONLY. The focus ring is never
## touched here — see the model's FOCUS_RING_HZ note for why that matters.
##
## Icon and text beat TOGETHER, on one wave. In colour-blind mode the badge and
## the focus ring collapse to the same hex, and the two channels left standing
## are shape and frequency; a triangle that pulses while its own label sits
## still would read as two unrelated elements and blunt both of them.
func _apply_corrupt_pulse() -> void:
	var rows: Array = model().rows()
	var wave := 0.5 - 0.5 * cos(_pulse_t * TAU)
	for i in range(_row_widgets.size()):
		if i >= rows.size():
			continue
		var badge: Label = _row_widgets[i]["badge"]
		var badge_icon: TextureRect = _row_widgets[i]["badge_icon"]
		var corrupt := (int(rows[i].get("status", SaveUiModelScript.RowStatus.EMPTY))
			== SaveUiModelScript.RowStatus.CORRUPT)
		var a := lerpf(0.55, 1.0, wave) if corrupt else 1.0
		_set_alpha(badge, a)
		_set_alpha(badge_icon, a)


# =============================================================================
# helpers
# =============================================================================
static func _with_alpha(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, a)


static func _set_alpha(node: CanvasItem, a: float) -> void:
	if node == null:
		return
	var m := node.modulate
	m.a = a
	node.modulate = m
