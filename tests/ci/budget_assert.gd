# tests/ci/budget_assert.gd
# Headless budget static-assertion runner (control-manifest §7; WARN-ONLY).
#
# [D14-A] STATIC-FEASIBLE budgets are scanned (delegated to budget_checks.gd).
# [D15-A] WARN-ONLY in Batch D: always exit 0, never print "[Risky]",
#         and this file MUST NOT be referenced from .github/workflows/ci.yml.
#         Gate promotion is a Sprint 2 decision. [N-12]
#
# Thin SceneTree entry: real scan logic lives in tests/ci/budget_checks.gd
# (RefCounted) so it is directly unit-testable (see test_budget_assert.gd).
# This file only drives that logic for headless CI and quits 0.

#
# [Sprint 2 · Batch A] Two save-layer assertions joined the WARN-ONLY roster:
#   @ci:save-schema-has-version  (SAV-S1) — `version` present, FIRST field, == 2
#   @ci:save-size-budget         (SAV-S2) — single slot JSON <= 32 KB
# Both stay WARN-ONLY (exit 0 unchanged). Their scan logic lives in
# budget_checks.gd like every other check; this entry point is what wires the
# LIVE user:// save directory into the size scan (unit tests leave it empty so
# they never read a developer's real slots).
#
# [Sprint 2 · Batch B] Two interactable assertions joined the WARN-ONLY roster:
#   @ci:no-orphan-interactables    (E07-S7) — every interactable script is on a
#                                   RefCounted lineage and none is attached to a
#                                   scene node
#   @ci:interactable-instance-cap  (E07-S8) — INSTANCE_CAP stays inside R-02 and
#                                   no scene declares more than the cap
# sprint2-stories E07-S7 pins these as WARN-ONLY: they do NOT enter the N-7 gate
# and MUST NOT change this script's exit code. The pre-existing R-02 (dynamic
# light scan) and G-02 (runtime, test_sound_propagation.gd) assertions are
# untouched — E07-S8 requires that adding DECOY/LIGHT_TOGGLE does not break them.
#
# [Sprint 3 · Batch A] G-01 guard-instance budget joined the WARN-ONLY roster:
#   @ci:guard-instance-budget  (E08-S9 / G-01) — peak active guards per area
#                                   MVP <= 8 / Tier2 <= 16. The REAL enforcement
#                                   (REFUSE-over-cap + rejection ledger) lives in
#                                   GuardSpawner and is asserted by
#                                   tests/unit/test_guard_variants.gd; this CI
#                                   scan (budget_checks.gd::_check_guard_budget)
#                                   checks the shipped caps against the
#                                   control-manifest authority and counts any
#                                   scene-placed guard brains. WARN-ONLY, exit 0.

extends SceneTree

const BudgetChecks := preload("res://tests/ci/budget_checks.gd")
const SaveManagerScript := preload("res://src/core/save_manager.gd")

const EXIT_OK := 0


func _initialize() -> void:
	prints("[CI:budget] ===== ASHEN STEP budget + Sprint0 exit gate (warn-only) =====")
	_report_smoke_requirement()      # Exit criterion ⑤ (epic-overview §3)
	var bc := BudgetChecks.new()
	# @ci:save-size-budget: measure the real slots on disk, if any exist.
	bc.save_scan_dir = SaveManagerScript.SAVE_DIR
	var warns := bc.run("res://")
	if warns.is_empty():
		prints("[CI:budget] All scans clean (no [WARN] emitted).")
	else:
		prints("[CI:budget] %d warning(s) emitted: %s" % [warns.size(), " ".join(warns)])
	prints("[CI:budget] All checks are WARN-ONLY. Exit 0 (lean: build not blocked).")
	prints("[CI:budget] Review any [WARN] lines and route drift to the lead for adjudication.")
	quit(EXIT_OK)


func _report_smoke_requirement() -> void:
	# epic-overview §3 退出标准⑤: GUT smoke must be green under godot --headless.
	prints("[CI:budget][GATE-⑤] Sprint 0 exit: GUT smoke green under headless REQUIRED.")
	prints("[CI:budget][GATE-⑤]   cmd: godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit")
	prints("[CI:budget][GATE-⑤]   status: SMOKE-RUNNER-EXTERNAL (invoke from CI; this script only records the gate)")
