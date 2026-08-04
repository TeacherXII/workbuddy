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

extends SceneTree

const BudgetChecks := preload("res://tests/ci/budget_checks.gd")

const EXIT_OK := 0


func _initialize() -> void:
	prints("[CI:budget] ===== ASHEN STEP budget + Sprint0 exit gate (warn-only) =====")
	_report_smoke_requirement()      # Exit criterion ⑤ (epic-overview §3)
	var bc := BudgetChecks.new()
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
