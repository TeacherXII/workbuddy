class_name SaveUiModel
extends RefCounted

# ASHEN STEP — Sprint 3, Batch B. E11 · SAV-S5 manual save/load UI, LOGIC HALF.
#
# Authority: production/sprints/sprint3-sav-s5-ux-spec.md v1.1 (§1 flow, §1.5
#            states, §1.6 checkpoint coexistence, §1.7 EC-1..EC-12, §2 a11y) ·
#            production/epics/E11-save-manager.md (SAV-S5 AC) ·
#            design/gdd/systems/save-system.md §5/§7/§8.
#
# ── Why this file exists at all (and is not just part of the CanvasLayer) ────
# CI runs GUT headless: no viewport, no fonts, no input, no pixels. A save
# screen whose rules live inside _draw() and _gui_input() is a screen whose
# rules cannot be asserted — it can only be eyeballed. So every DECISION the UI
# makes (which row is focused, whether an action is legal, what the confirm
# dialog says, which subtitle fires, how long a state may last) lives here as
# pure functions over plain data, and src/ui/save_slots_screen.gd is a thin
# renderer that owns nothing but widgets. The screen can be wrong about pixels;
# it cannot be wrong about rules.
#
# ── Zero new signals (E01-S9 vocabulary freeze, sprint3-plan.md §4) ──────────
# This model emits NOTHING. It has no bus reference and no signal of its own.
# Callers push facts in (on_save_completed / on_load_completed) and pull INTENTS
# out — a Dictionary saying "write slot 1" / "deny, empty slot" / "close". The
# screen executes those intents against the EXISTING SaveManager API. That is
# what keeps a whole new UI surface inside a frozen event vocabulary.
#
# ── Colour discipline ────────────────────────────────────────────────────────
# No colour literal in this file. Everything routes through src/ui/hud_colors.gd
# (the signed palette), same rule hud_slice.gd obeys.

const HudColors = preload("res://src/ui/hud_colors.gd")
# Constants only — this never instantiates the L2 service. MAX_MANUAL_SLOTS and
# CHECKPOINT_SLOT_ID are GDD-frozen there, and mirroring them here would create
# a second source of truth that drifts the first time the cap changes.
const SaveManagerScript = preload("res://src/core/save_manager.gd")

enum Mode { SAVE, LOAD }
enum RowStatus { EMPTY, FILLED, CORRUPT, BUSY }
enum State { BROWSING, CONFIRMING, BUSY_WRITING, BUSY_READING, RESULT_TOAST, LOADING_FADE }
enum ConfirmKind { NONE, OVERWRITE, LOAD, DELETE }
enum Action { PRIMARY, DELETE, CANCEL }

# ── Layout / list shape (spec §1.3, §1.6) ────────────────────────────────────
# Row 0 is ALWAYS the read-only checkpoint row. It is in the list rather than
# hidden because "how long ago did the game last save for me?" is the only
# basis a player has for deciding whether to save manually — hiding it turns a
# deliberate act into a blind one (pillar 3, 自主掌控).
const CHECKPOINT_ROW := 0
const FIRST_MANUAL_ROW := 1
const ROW_COUNT := 1 + SaveManagerScript.MAX_MANUAL_SLOTS

# ── Timings (spec §1.2 state table) ──────────────────────────────────────────
# BUSY_TIMEOUT_SEC is EC-2 and it is load-bearing: write_slot() is fire-and-
# forget with no cancel API, so if save_completed never arrives the UI would sit
# in a locked busy state forever. A UI that can hang is worse than a UI that
# reports a failure it is not sure about.
const BUSY_TIMEOUT_SEC := 3.0
const TOAST_SEC := 1.6
const LOAD_FADE_SEC := 0.4

# ── Motion budget (V-01: no periodic modulation above 3Hz) ───────────────────
# ★ FOCUS_RING_HZ IS ZERO ON PURPOSE AND MUST STAY ZERO.
# In colour-blind mode HUD_COLOR_FOCUS and the C-06 danger substitute are the
# same hex (FLAG-L). When a CORRUPT row is focused, hue separation between the
# ring and the badge collapses to 1.00:1. What still tells them apart is that
# the ring is steady and rectangular while the badge beats at 2.0Hz behind a
# solid triangle. Pulsing the ring would erase the frequency channel and take
# C-05's triple coding down with it.
const FOCUS_RING_HZ := 0.0
const FOCUS_RING_WIDTH_PX := 2
const CORRUPT_PULSE_HZ := 2.0
const FLICKER_HZ_MAX := 3.0

# ── Surface alphas (spec §1.3 layer table) ───────────────────────────────────
# ROW_ALPHA is 1.0 by contrast MATHEMATICS, not by taste: at panel alpha 0.88
# over the 0.60 world scrim, the #4E6E8A information stroke drops to 3.01:1 and
# C-03 (>=3:1) survives on 0.01 of margin. Opaque rows pin every ratio in the
# spec's §2.1 table to a constant a headless test can assert.
const SCRIM_ALPHA := 0.60
const PANEL_ALPHA := 0.88
const ROW_ALPHA := 1.0
# Disabled carriers stay at 70%, composited ~7.10:1 — still clearing C-02.
# A 40-50% grey would read ~3.7:1 and break C-01. "Disabled" is not a licence
# to be unreadable; it is a licence to be quiet.
const DISABLED_ALPHA := 0.70
# Third channel of the focus read (position + BRIGHTNESS + ring). A focus state
# carried by the ring alone would vanish for anyone who cannot separate
# #F0C070 from the badge beside it.
const FOCUS_ROW_LIFT_ALPHA := 0.10

# ── Glyphs (C-05/C-07 shape channel — never colour alone) ────────────────────
const GLYPH_THUMB := "⊟"
const GLYPH_THUMB_CORRUPT := "⊘"
const GLYPH_THUMB_EMPTY := "──"

# ── Strings ──────────────────────────────────────────────────────────────────
# X-02 speaker. The save UI speaks as「系统」, not as hud_slice's「环境」
# fallback. Declared HERE and passed as an argument to show_subtitle(speaker,
# line), so the X-02 gap the UX spec flagged is closed WITHOUT editing
# hud_slice.gd — which S3-C (TD-S1/TD-S2) owns this sprint.
const SUBTITLE_SPEAKER_SYSTEM := "系统"

const LABEL_CHECKPOINT := "自动 · 检查点"
const LABEL_SLOT_FMT := "槽 %d"
const TEXT_EMPTY_SLOT := "— 空槽位 —"
const BADGE_READONLY := "〔只读〕"
const BADGE_CORRUPT := "〔⚠ 损坏〕"
const BADGE_BUSY_WRITE := "〔写入中…〕"
const BADGE_BUSY_READ := "〔读取中…〕"

const TITLE_SAVE := "存档"
const TITLE_LOAD := "读档"

# EC-4: with MAX_MANUAL_SLOTS hard at 3 there is no "new slot" path, so the cap
# is stated up front instead of being discovered by a player hunting for a
# button that does not exist.
const NOTICE_SLOT_CAP := "手动存档上限 3 个，存档将覆盖所选槽位"
const NOTICE_NO_MANUAL_SAVES := "尚无手动存档。可在暂停菜单选择『存档』写入。"

const REASON_CORRUPT_VERSION := "存档版本不匹配"
const REASON_CORRUPT_PARSE := "存档已损坏"
const REASON_WRITE_TIMEOUT := "存档失败 · 写入超时"
const REASON_WRITE_FAILED := "存档失败 · 磁盘写入未完成"
const REASON_READ_TIMEOUT := "读取失败 · 读取超时"

const DENY_CHECKPOINT_SAVE := "检查点由系统写入，无法手动存档"
const DENY_CHECKPOINT_LOAD := "检查点为只读，无法手动读取"
const DENY_CHECKPOINT_DELETE := "检查点无法删除"
const DENY_EMPTY_LOAD := "空槽位无法读取"
const DENY_EMPTY_DELETE := "空槽位无需删除"
const DENY_CORRUPT_LOAD := "损坏的存档无法读取"
const DENY_BUSY := "正在写入 / 读取，请稍候"

# ── State ────────────────────────────────────────────────────────────────────
var _mode: int = Mode.SAVE
var _state: int = State.BROWSING
var _rows: Array = []
var _focus: int = FIRST_MANUAL_ROW
var _confirm_kind: int = ConfirmKind.NONE
var _pending_slot: int = SaveManagerScript.CHECKPOINT_SLOT_ID

var _busy_t: float = 0.0
var _toast_t: float = 0.0
var _fade_t: float = 0.0

var _toast: Dictionary = {}
var _denial: String = ""
# EC-1: Esc during a locked write is QUEUED, never dropped. The player's intent
# is honoured, just deferred — a swallowed cancel teaches players the UI is
# unreliable, and they start mashing.
var _cancel_queued: bool = false


# =============================================================================
# Construction / list building
# =============================================================================
## Blank row in the shape every consumer expects. One constructor so a field
## can never exist on some rows and not others.
static func make_row(slot_id: int, readonly: bool = false) -> Dictionary:
	return {
		"slot_id": slot_id,
		"status": RowStatus.EMPTY,
		"timestamp": 0.0,
		"checkpoint_id": "",
		"readonly": readonly,
		"reason": "",
	}


## The 4-row skeleton: 1 read-only checkpoint row + MAX_MANUAL_SLOTS manual
## rows. Always this many rows — manual slots never appear or disappear, so the
## list never reflows under the player's focus.
static func blank_rows() -> Array:
	var rows: Array = [make_row(SaveManagerScript.CHECKPOINT_SLOT_ID, true)]
	for i in range(SaveManagerScript.MAX_MANUAL_SLOTS):
		rows.append(make_row(i, false))
	return rows


## Classify one slot from its RAW FILE TEXT. Pure so the whole empty / filled /
## corrupt decision is testable without a disk.
##
## This deliberately mirrors read_slot()'s version-first gate rather than
## calling it: read_slot() broadcasts load_completed(), and building a list must
## not look to the rest of the game like the player just loaded three saves.
## It is a READ-ONLY peek — it never writes, never emits, never caches.
static func peek_row(slot_id: int, text: String, readonly: bool = false) -> Dictionary:
	var row := make_row(slot_id, readonly)
	if text == "":
		return row
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		row["status"] = RowStatus.CORRUPT
		row["reason"] = REASON_CORRUPT_PARSE
		return row
	var raw: Dictionary = parsed
	# Version FIRST, exactly like SAV-S1's wire invariant. Nothing below this
	# gate reads any other field.
	if not raw.has("version"):
		row["status"] = RowStatus.CORRUPT
		row["reason"] = REASON_CORRUPT_PARSE
		return row
	if int(raw["version"]) != SaveManagerScript.SAVE_VERSION:
		row["status"] = RowStatus.CORRUPT
		row["reason"] = REASON_CORRUPT_VERSION
		return row
	row["status"] = RowStatus.FILLED
	row["timestamp"] = float(raw.get("timestamp", 0.0))
	row["checkpoint_id"] = str(raw.get("checkpoint_id", ""))
	return row


## EC-6: the list is a SNAPSHOT taken when the screen opens and is not refreshed
## while the player browses. An in-flight checkpoint write mutating the row
## under the cursor would move the meaning of "this row" mid-read and interrupt
## any screen reader parked on it.
func open(mode: int, rows: Array) -> void:
	_mode = mode
	_rows = rows.duplicate(true)
	_state = State.BROWSING
	_confirm_kind = ConfirmKind.NONE
	_pending_slot = SaveManagerScript.CHECKPOINT_SLOT_ID
	_busy_t = 0.0
	_toast_t = 0.0
	_fade_t = 0.0
	_toast = {}
	_denial = ""
	_cancel_queued = false
	_focus = default_focus()


# =============================================================================
# Read-only accessors
# =============================================================================
func mode() -> int:
	return _mode


func state() -> int:
	return _state


func rows() -> Array:
	return _rows.duplicate(true)


func row_count() -> int:
	return _rows.size()


func focus_index() -> int:
	return _focus


func confirm_kind() -> int:
	return _confirm_kind


func toast() -> Dictionary:
	return _toast.duplicate(true)


func denial_hint() -> String:
	return _denial


func title() -> String:
	return TITLE_SAVE if _mode == Mode.SAVE else TITLE_LOAD


func row_at(index: int) -> Dictionary:
	if index < 0 or index >= _rows.size():
		return make_row(SaveManagerScript.CHECKPOINT_SLOT_ID, true)
	return _rows[index]


func focused_row() -> Dictionary:
	return row_at(_focus)


## 0.0 -> 1.0 over LOAD_FADE_SEC. The screen eases this; the model only counts.
func fade_progress() -> float:
	if LOAD_FADE_SEC <= 0.0:
		return 1.0
	return clampf(_fade_t / LOAD_FADE_SEC, 0.0, 1.0)


func is_input_locked() -> bool:
	return (_state == State.BUSY_WRITING
		or _state == State.BUSY_READING
		or _state == State.LOADING_FADE)


## EC-1 drain. Returns true ONCE if a cancel was queued behind an input lock.
func take_queued_cancel() -> bool:
	var queued := _cancel_queued
	_cancel_queued = false
	return queued


# =============================================================================
# Display text (pure — asserted directly by the unit suite)
# =============================================================================
## Manual slots are 1-based ON SCREEN and 0-based INSIDE. The mapping lives in
## exactly one function so the two numbering systems cannot leak into each
## other; "槽 1" is slot_id 0 everywhere, forever.
static func row_label(row: Dictionary) -> String:
	var slot_id := int(row.get("slot_id", SaveManagerScript.CHECKPOINT_SLOT_ID))
	if slot_id == SaveManagerScript.CHECKPOINT_SLOT_ID:
		return LABEL_CHECKPOINT
	return LABEL_SLOT_FMT % (slot_id + 1)


## UTC, deliberately: a locale-dependent string cannot be asserted in CI, and a
## save timestamp is a comparison aid, not a calendar appointment.
static func format_timestamp(unix_time: float) -> String:
	var d := Time.get_datetime_dict_from_unix_time(int(unix_time))
	return "%04d-%02d-%02d %02d:%02d" % [
		int(d["year"]), int(d["month"]), int(d["day"]),
		int(d["hour"]), int(d["minute"]),
	]


## The line that lets a player decide whether a slot is expendable.
static func row_subtitle(row: Dictionary) -> String:
	var status := int(row.get("status", RowStatus.EMPTY))
	if status == RowStatus.CORRUPT:
		return str(row.get("reason", REASON_CORRUPT_PARSE))
	if status == RowStatus.EMPTY:
		return TEXT_EMPTY_SLOT
	var stamp := format_timestamp(float(row.get("timestamp", 0.0)))
	var cp := str(row.get("checkpoint_id", ""))
	if cp == "":
		return stamp
	return "%s · #%s" % [stamp, cp]


static func row_badge(row: Dictionary) -> String:
	var status := int(row.get("status", RowStatus.EMPTY))
	if status == RowStatus.BUSY:
		return BADGE_BUSY_WRITE
	if status == RowStatus.CORRUPT:
		return BADGE_CORRUPT
	if bool(row.get("readonly", false)):
		return BADGE_READONLY
	return ""


static func row_thumb_glyph(row: Dictionary) -> String:
	var status := int(row.get("status", RowStatus.EMPTY))
	if status == RowStatus.CORRUPT:
		return GLYPH_THUMB_CORRUPT
	if status == RowStatus.EMPTY:
		return GLYPH_THUMB_EMPTY
	# A placeholder must look like a PLACEHOLDER, not like a broken image —
	# a torn-page icon would read as "your save is damaged".
	return GLYPH_THUMB


## Footer guidance. LOAD with nothing to load must say so and say what to do
## about it; three silent empty rows is a dead end.
func footer_notice() -> String:
	if _mode == Mode.LOAD and not _has_any_loadable():
		return NOTICE_NO_MANUAL_SAVES
	if _mode == Mode.SAVE and _all_manual_filled():
		return NOTICE_SLOT_CAP
	return ""


func _has_any_loadable() -> bool:
	for i in range(FIRST_MANUAL_ROW, _rows.size()):
		if int(_rows[i].get("status", RowStatus.EMPTY)) == RowStatus.FILLED:
			return true
	return false


func _all_manual_filled() -> bool:
	if _rows.size() <= FIRST_MANUAL_ROW:
		return false
	for i in range(FIRST_MANUAL_ROW, _rows.size()):
		if int(_rows[i].get("status", RowStatus.EMPTY)) == RowStatus.EMPTY:
			return false
	return true


# =============================================================================
# Focus (spec §2.4)
# =============================================================================
## SAVE lands on the first WRITEABLE row, never on the checkpoint row — opening
## "save" with the cursor on the one row you can never save to is a trap.
## LOAD lands on the most recent loadable row, which is what the player almost
## always wants.
func default_focus() -> int:
	if _mode == Mode.SAVE:
		return FIRST_MANUAL_ROW if _rows.size() > FIRST_MANUAL_ROW else CHECKPOINT_ROW
	var best := -1
	var best_ts := -1.0
	for i in range(FIRST_MANUAL_ROW, _rows.size()):
		var row: Dictionary = _rows[i]
		if int(row.get("status", RowStatus.EMPTY)) != RowStatus.FILLED:
			continue
		var ts := float(row.get("timestamp", 0.0))
		if ts > best_ts:
			best_ts = ts
			best = i
	if best >= 0:
		return best
	return FIRST_MANUAL_ROW if _rows.size() > FIRST_MANUAL_ROW else CHECKPOINT_ROW


## Wrapping, linear navigation. Every row is reachable INCLUDING the read-only
## checkpoint row: it is focusable so its timestamp can be read (and spoken)
## even though every action on it is refused.
func move_focus(delta: int) -> int:
	if is_input_locked() or _state == State.CONFIRMING:
		return _focus
	if _rows.is_empty():
		return _focus
	var n := _rows.size()
	_focus = ((_focus + delta) % n + n) % n
	# Moving the cursor answers the previous refusal; keeping the hint up would
	# leave a stale explanation pointing at a row it no longer describes.
	_denial = ""
	return _focus


func set_focus(index: int) -> int:
	if is_input_locked() or _state == State.CONFIRMING:
		return _focus
	if index < 0 or index >= _rows.size():
		return _focus
	_focus = index
	_denial = ""
	return _focus


# =============================================================================
# Action legality (spec §1.5 / §1.6)
# =============================================================================
func is_action_enabled(action: int, index: int = -1) -> bool:
	return action_denial(action, index) == ""


## The single source of truth for "may I?" AND for "why not?". One function so a
## refusal can never be rendered without a reason attached — spec §0 立场 3,
## 「禁用不等于沉默」.
func action_denial(action: int, index: int = -1) -> String:
	if action == Action.CANCEL:
		return ""
	if is_input_locked():
		return DENY_BUSY
	var i := _focus if index < 0 else index
	var row := row_at(i)
	var status := int(row.get("status", RowStatus.EMPTY))
	var readonly := bool(row.get("readonly", false))

	if action == Action.DELETE:
		if readonly:
			return DENY_CHECKPOINT_DELETE
		if status == RowStatus.EMPTY:
			return DENY_EMPTY_DELETE
		# CORRUPT is deliberately deletable: it is the player's only way to
		# clear a broken save, and refusing here would strand them with it.
		return ""

	# Action.PRIMARY
	if _mode == Mode.SAVE:
		if readonly:
			return DENY_CHECKPOINT_SAVE
		# Overwriting a corrupt slot IS the cleanup path, so it stays enabled.
		return ""
	if readonly:
		return DENY_CHECKPOINT_LOAD
	if status == RowStatus.EMPTY:
		return DENY_EMPTY_LOAD
	if status == RowStatus.CORRUPT:
		return DENY_CORRUPT_LOAD
	return ""


## Which confirmation a legal PRIMARY needs. Empty-slot SAVE is the one path
## with no dialog: nothing is destroyed, so a prompt would be pure friction.
func primary_confirm_kind(index: int = -1) -> int:
	var i := _focus if index < 0 else index
	var row := row_at(i)
	if _mode == Mode.LOAD:
		# LOAD is ALWAYS destructive — it discards unsaved progress — so it is
		# always confirmed, even from a pristine slot.
		return ConfirmKind.LOAD
	if int(row.get("status", RowStatus.EMPTY)) == RowStatus.EMPTY:
		return ConfirmKind.NONE
	return ConfirmKind.OVERWRITE


# =============================================================================
# Confirm dialog copy (spec §1.4 b/c/d)
# =============================================================================
## ★ AC 3 / spec §0 立场 1: the dialog RESTATES THE AFFECTED OBJECT. "确定吗？"
## is not a confirmation, it is a speed bump — the player has no way to tell
## whether the slot under the cursor is the throwaway one or the two-hour one
## without being told which slot and which timestamp is about to go. The unit
## suite asserts the body contains both.
func confirm_dialog(kind: int, index: int = -1) -> Dictionary:
	var i := _focus if index < 0 else index
	var row := row_at(i)
	var label := row_label(row)
	var detail := row_subtitle(row)
	var out := {
		"kind": kind,
		"slot_id": int(row.get("slot_id", SaveManagerScript.CHECKPOINT_SLOT_ID)),
		"title": "",
		"body": "",
		"confirm_label": "",
		"cancel_label": "取消",
		# Safe default on every destructive dialog: the button that does
		# nothing is the one already selected.
		"default_focus": "cancel",
	}
	match kind:
		ConfirmKind.OVERWRITE:
			out["title"] = "覆盖存档？"
			out["body"] = "%s 现存：%s\n覆盖后该记录将无法找回。" % [label, detail]
			out["confirm_label"] = "覆盖"
		ConfirmKind.LOAD:
			out["title"] = "读取存档？"
			# The LABEL is here as well as the timestamp on purpose. A player
			# who mis-navigated one row needs to see WHICH slot they are about
			# to jump into, not just a date they cannot place.
			out["body"] = "将回到 %s：%s。\n当前未存进度将丢失。" % [label, detail]
			out["confirm_label"] = "读取"
		ConfirmKind.DELETE:
			out["title"] = "删除存档？"
			out["body"] = "%s：%s" % [label, detail]
			out["confirm_label"] = "删除"
		_:
			out["title"] = ""
			out["body"] = ""
			out["confirm_label"] = "确定"
	return out


func active_confirm_dialog() -> Dictionary:
	return confirm_dialog(_confirm_kind, _pending_slot_row())


func _pending_slot_row() -> int:
	for i in range(_rows.size()):
		if int(_rows[i].get("slot_id", -99)) == _pending_slot:
			return i
	return _focus


# =============================================================================
# Intents — the model's entire output surface
# =============================================================================
static func _intent(op: String, slot_id: int = -99, reason: String = "") -> Dictionary:
	return {"op": op, "slot_id": slot_id, "reason": reason}


## A12 (Enter / A). Returns one of:
##   deny    — refused, `reason` is the line to show alongside the muffled cue
##   confirm — a modal is now open
##   write   — caller must call SaveManager.write_slot(slot_id, snapshot)
##   read    — caller must call SaveManager.read_slot(slot_id)
##   none    — swallowed (wrong state)
func press_primary() -> Dictionary:
	if _state == State.CONFIRMING:
		return _intent("none")
	if is_input_locked():
		# EC-1: PRIMARY is DROPPED (not queued) during a lock. Queueing it would
		# let an impatient double-tap fire a second write at a slot the first
		# one is still writing.
		return _intent("none")
	if _state == State.RESULT_TOAST:
		_clear_toast()

	var deny := action_denial(Action.PRIMARY)
	if deny != "":
		return _deny(deny)

	var row := focused_row()
	var slot_id := int(row.get("slot_id", SaveManagerScript.CHECKPOINT_SLOT_ID))
	var kind := primary_confirm_kind()
	if kind == ConfirmKind.NONE:
		return _begin_write(slot_id)
	_confirm_kind = kind
	_pending_slot = slot_id
	_state = State.CONFIRMING
	_denial = ""
	return _intent("confirm", slot_id)


## A15 (Del / Y).
func press_delete() -> Dictionary:
	if _state == State.CONFIRMING:
		return _intent("none")
	if is_input_locked():
		return _intent("none")
	if _state == State.RESULT_TOAST:
		_clear_toast()

	var deny := action_denial(Action.DELETE)
	if deny != "":
		return _deny(deny)

	var row := focused_row()
	_confirm_kind = ConfirmKind.DELETE
	_pending_slot = int(row.get("slot_id", SaveManagerScript.CHECKPOINT_SLOT_ID))
	_state = State.CONFIRMING
	_denial = ""
	return _intent("confirm", _pending_slot)


## A13 (Esc / B).
func press_cancel() -> Dictionary:
	if _state == State.CONFIRMING:
		return confirm_cancel()
	if is_input_locked():
		# EC-1: held, not dropped. Drained by take_queued_cancel() when the lock
		# lifts, so the player's escape still happens — just late.
		_cancel_queued = true
		return _intent("queued")
	_clear_toast()
	return _intent("close")


func confirm_cancel() -> Dictionary:
	if _state != State.CONFIRMING:
		return _intent("none")
	_state = State.BROWSING
	_confirm_kind = ConfirmKind.NONE
	# Focus returns to the row the dialog was about, not to the top of the list.
	_focus = _pending_slot_row()
	return _intent("none")


## The affirmative button in SCR_CONFIRM.
func confirm_accept() -> Dictionary:
	if _state != State.CONFIRMING:
		return _intent("none")
	var kind := _confirm_kind
	var slot_id := _pending_slot
	_confirm_kind = ConfirmKind.NONE
	match kind:
		ConfirmKind.OVERWRITE:
			return _begin_write(slot_id)
		ConfirmKind.LOAD:
			return _begin_read(slot_id)
		ConfirmKind.DELETE:
			# Deletion is synchronous (no SaveManager round trip and no event),
			# so the row flips here and the caller only has to unlink the file.
			_state = State.BROWSING
			_apply_delete(slot_id)
			_set_toast("已删除 · 槽 %d" % (slot_id + 1), true)
			return _intent("delete", slot_id)
	_state = State.BROWSING
	return _intent("none")


func _begin_write(slot_id: int) -> Dictionary:
	_state = State.BUSY_WRITING
	_pending_slot = slot_id
	_busy_t = 0.0
	_denial = ""
	_mark_row_busy(slot_id, true)
	return _intent("write", slot_id)


func _begin_read(slot_id: int) -> Dictionary:
	_state = State.BUSY_READING
	_pending_slot = slot_id
	_busy_t = 0.0
	_denial = ""
	_mark_row_busy(slot_id, true)
	return _intent("read", slot_id)


func _deny(reason: String) -> Dictionary:
	_denial = reason
	return _intent("deny", -99, reason)


# =============================================================================
# Facts pushed in from the bus (subscribe-only — no new signals)
# =============================================================================
## `save_completed(slot_id, success)`.
func on_save_completed(slot_id: int, success: bool, timestamp: float = -1.0,
		checkpoint_id: String = "") -> Dictionary:
	if _state != State.BUSY_WRITING or slot_id != _pending_slot:
		# Not ours: the rolling checkpoint slot writes on its own schedule and
		# must not be able to close a dialog the player is looking at.
		return _intent("none")
	_mark_row_busy(slot_id, false)
	_state = State.RESULT_TOAST
	_toast_t = 0.0
	if success:
		var ts := timestamp if timestamp >= 0.0 else Time.get_unix_time_from_system()
		_apply_write(slot_id, ts, checkpoint_id)
		var line := "已存档 · 槽 %d" % (slot_id + 1)
		_set_toast(line, true)
		return _intent("saved", slot_id, line)
	# EC-7: the row keeps its ORIGINAL content. O-3's atomic write is what makes
	# that claim true on disk as well as on screen.
	_set_toast(REASON_WRITE_FAILED, false)
	return _intent("save_failed", slot_id, REASON_WRITE_FAILED)


## `load_completed(slot_id, success)`.
func on_load_completed(slot_id: int, success: bool, reason: String = "") -> Dictionary:
	if _state != State.BUSY_READING or slot_id != _pending_slot:
		return _intent("none")
	_mark_row_busy(slot_id, false)
	if success:
		_state = State.LOADING_FADE
		_fade_t = 0.0
		return _intent("load_fade_begin", slot_id)
	# EC-3: the row转损坏态 and STAYS that way. A toast that scrolls off is not
	# a record; the next time the player looks at this list they must still see
	# that this slot is broken.
	_state = State.RESULT_TOAST
	_toast_t = 0.0
	var why := reason if reason != "" else REASON_CORRUPT_PARSE
	_apply_corrupt(slot_id, why)
	_set_toast(why, false)
	return _intent("load_failed", slot_id, why)


## `checkpoint_restored(checkpoint_id)` — refresh the read-only row in place.
func on_checkpoint_restored(checkpoint_id: String) -> void:
	for row in _rows:
		if int(row.get("slot_id", -99)) == SaveManagerScript.CHECKPOINT_SLOT_ID:
			row["checkpoint_id"] = checkpoint_id
			row["status"] = RowStatus.FILLED
			return


# =============================================================================
# Time
# =============================================================================
## Wall-clock seconds. Driven from the screen's _process with REAL delta, never
## a scaled one: the save UI runs inside the paused / time-scaled state (T-03),
## and a 3s timeout that stretches with Engine.time_scale is not a timeout.
func tick(delta: float) -> Dictionary:
	if delta <= 0.0:
		return _intent("none")
	match _state:
		State.BUSY_WRITING, State.BUSY_READING:
			_busy_t += delta
			if _busy_t >= BUSY_TIMEOUT_SEC:
				return _on_timeout()
		State.RESULT_TOAST:
			_toast_t += delta
			if _toast_t >= TOAST_SEC:
				_clear_toast()
				_state = State.BROWSING
				return _intent("toast_end")
		State.LOADING_FADE:
			_fade_t += delta
			if _fade_t >= LOAD_FADE_SEC:
				# X-02 fires HERE, not at t=0: during the fade the screen is
				# still dark and a subtitle would hang in the void with nothing
				# to attach itself to.
				_state = State.BROWSING
				var line := "已读取存档 · 槽 %d" % (_pending_slot + 1)
				return _intent("load_fade_end", _pending_slot, line)
	return _intent("none")


## EC-2. write_slot() has no cancel and no progress, so silence past the budget
## has to be TREATED as failure. Reporting a timeout we are not certain about is
## strictly better than a locked screen the player cannot leave.
func _on_timeout() -> Dictionary:
	var slot_id := _pending_slot
	var writing := _state == State.BUSY_WRITING
	_mark_row_busy(slot_id, false)
	_state = State.RESULT_TOAST
	_toast_t = 0.0
	var why := REASON_WRITE_TIMEOUT if writing else REASON_READ_TIMEOUT
	_set_toast(why, false)
	return _intent("timeout", slot_id, why)


# =============================================================================
# Row mutation (EC-5: the model IS the truth while the screen is open —
# no disk re-scan, no directory polling)
# =============================================================================
func _row_index_of(slot_id: int) -> int:
	for i in range(_rows.size()):
		if int(_rows[i].get("slot_id", -99)) == slot_id:
			return i
	return -1


func _mark_row_busy(slot_id: int, busy: bool) -> void:
	var i := _row_index_of(slot_id)
	if i < 0:
		return
	if busy:
		_rows[i]["_prev_status"] = int(_rows[i].get("status", RowStatus.EMPTY))
		_rows[i]["status"] = RowStatus.BUSY
	elif _rows[i].has("_prev_status"):
		_rows[i]["status"] = int(_rows[i]["_prev_status"])
		_rows[i].erase("_prev_status")


func _apply_write(slot_id: int, timestamp: float, checkpoint_id: String) -> void:
	var i := _row_index_of(slot_id)
	if i < 0:
		return
	_rows[i]["status"] = RowStatus.FILLED
	_rows[i]["timestamp"] = timestamp
	_rows[i]["checkpoint_id"] = checkpoint_id
	# A successful overwrite clears a previous corruption mark — the bytes that
	# were broken are gone.
	_rows[i]["reason"] = ""


func _apply_delete(slot_id: int) -> void:
	var i := _row_index_of(slot_id)
	if i < 0:
		return
	_rows[i]["status"] = RowStatus.EMPTY
	_rows[i]["timestamp"] = 0.0
	_rows[i]["checkpoint_id"] = ""
	_rows[i]["reason"] = ""
	# EC-10: focus stays on the SAME INDEX, which is now an empty row. Jumping
	# to the top of the list would lose the player's place as a punishment for
	# tidying up.
	_focus = i


func _apply_corrupt(slot_id: int, reason: String) -> void:
	var i := _row_index_of(slot_id)
	if i < 0:
		return
	_rows[i]["status"] = RowStatus.CORRUPT
	_rows[i]["reason"] = reason


func _set_toast(text: String, success: bool) -> void:
	_toast = {"text": text, "success": success}
	_denial = ""


func _clear_toast() -> void:
	_toast = {}
	_toast_t = 0.0


# =============================================================================
# a11y self-description (asserted by tests/unit/test_save_ui.gd)
# =============================================================================
## Every periodic modulation this screen can produce, by name and frequency.
## ★ A new animated channel MUST be registered here. The V-01 test walks this
## list, so an unregistered pulse is invisible to the gate — the list is the
## audit, not a comment about the audit.
static func animation_channels() -> Array:
	return [
		{"name": "focus_ring", "hz": FOCUS_RING_HZ},
		{"name": "corrupt_badge", "hz": CORRUPT_PULSE_HZ},
	]


static func max_animation_hz() -> float:
	var top := 0.0
	for ch in animation_channels():
		top = maxf(top, float(ch["hz"]))
	return top


## Contrast of the focus ring against the row it is drawn on. The denominator is
## the OPAQUE row base, which is the whole reason rows are opaque.
static func focus_ring_contrast() -> float:
	return HudColors.wcag_contrast(HudColors.HUD_COLOR_FOCUS, HudColors.HUD_COLOR_PANEL_SLOT)


static func carrier_contrast() -> float:
	return HudColors.wcag_contrast(HudColors.HUD_COLOR_CARRIER, HudColors.HUD_COLOR_PANEL_SLOT)


## Disabled text is pre-composited at DISABLED_ALPHA over the row base and then
## measured — the alpha is part of the colour, so measuring the raw carrier
## would flatter the result.
static func disabled_carrier_contrast() -> float:
	var composited := HudColors.composite(
		HudColors.HUD_COLOR_CARRIER, HudColors.HUD_COLOR_PANEL_SLOT, DISABLED_ALPHA)
	return HudColors.wcag_contrast(composited, HudColors.HUD_COLOR_PANEL_SLOT)


static func boundary_contrast() -> float:
	return HudColors.wcag_contrast(HudColors.HUD_COLOR_BOUNDARY, HudColors.HUD_COLOR_PANEL_SLOT)
