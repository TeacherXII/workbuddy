#!/usr/bin/env python3
"""
assert_lint.py - catch assertions that silently verify nothing.

Sprint 3 assertion credibility audit (Task #48). The N-7 / N-7b / N-11 / N-12
guards all assume that an assertion which prints [Passed] actually ran and
actually compared something. Three defects shipped in a 184/184 green suite
proved that assumption wrong:

  A-class  the assertion message was passed into a parameter that is NOT `text`
           (e.g. assert_signal_emitted_with_parameters' 4th arg is `index:int`).
           GUT throws internally, the comparison is skipped, and [Passed] is
           still printed - with "got <null>" right there in the message.

  B-class  the expression crashed BEFORE the assertion was evaluated
           (e.g. an out-of-bounds split()[1]). The assertion evaporates; GUT
           reports one fewer assert for that test and the test still passes.

Neither is [Risky] and neither is a load failure, so N-7 / N-7b cannot see them.

Usage
  python tests/ci/assert_lint.py --tests-dir tests                  # A-class only
  python tests/ci/assert_lint.py --tests-dir tests --gut-log g.txt  # A + B class
  python tests/ci/assert_lint.py --selftest                         # verify the linter

Exit codes:  0 clean   1 findings   2 selftest failed
"""

import argparse, glob, json, os, re, sys, tempfile

# ---------------------------------------------------------------------------
# GUT v9.3.0 signature table - addons/gut/test.gd
# name -> (min_args, max_args, index_of_text_param or None, parameter names)
# Entries whose text index is None have NO message parameter: anything passed
# there is consumed as real data and will corrupt the assertion.
# ---------------------------------------------------------------------------
SIG = {
 "assert_eq":(2,3,2,["got","expected","text"]),
 "assert_ne":(2,3,2,["got","not_expected","text"]),
 "assert_almost_eq":(3,4,3,["got","expected","error_interval","text"]),
 "assert_almost_ne":(3,4,3,["got","not_expected","error_interval","text"]),
 "assert_gt":(2,3,2,["got","expected","text"]),
 "assert_gte":(2,3,2,["got","expected","text"]),
 "assert_lt":(2,3,2,["got","expected","text"]),
 "assert_lte":(2,3,2,["got","expected","text"]),
 "assert_true":(1,2,1,["got","text"]),
 "assert_false":(1,2,1,["got","text"]),
 "assert_between":(3,4,3,["got","expect_low","expect_high","text"]),
 "assert_not_between":(3,4,3,["got","expect_low","expect_high","text"]),
 "assert_has":(2,3,2,["obj","element","text"]),
 "assert_does_not_have":(2,3,2,["obj","element","text"]),
 "assert_file_exists":(1,1,None,["file_path"]),
 "assert_file_does_not_exist":(1,1,None,["file_path"]),
 "assert_file_empty":(1,1,None,["file_path"]),
 "assert_file_not_empty":(1,1,None,["file_path"]),
 "assert_has_method":(2,3,2,["obj","method","text"]),
 "assert_accessors":(4,4,None,["obj","property","default","set_to"]),
 "assert_exports":(3,3,None,["obj","property_name","type"]),
 "assert_connected":(3,4,None,["signaler","connect_to","signal_name","method_name"]),
 "assert_not_connected":(3,4,None,["signaler","connect_to","signal_name","method_name"]),
 "assert_signal_emitted":(2,3,2,["object","signal_name","text"]),
 "assert_signal_not_emitted":(2,3,2,["object","signal_name","text"]),
 "assert_signal_emitted_with_parameters":(3,4,None,["object","signal_name","parameters","index"]),
 "assert_signal_emit_count":(3,4,3,["object","signal_name","times","text"]),
 "assert_has_signal":(2,3,2,["object","signal_name","text"]),
 "assert_is":(2,3,2,["object","a_class","text"]),
 "assert_typeof":(2,3,2,["object","type","text"]),
 "assert_not_typeof":(2,3,2,["object","type","text"]),
 "assert_string_contains":(2,3,None,["text","search","match_case"]),
 "assert_string_starts_with":(2,3,None,["text","search","match_case"]),
 "assert_string_ends_with":(2,3,None,["text","search","match_case"]),
 "assert_called":(2,3,None,["inst","method_name","parameters"]),
 "assert_not_called":(2,3,None,["inst","method_name","parameters"]),
 "assert_call_count":(3,4,None,["inst","method_name","expected_count","parameters"]),
 "assert_null":(1,2,1,["got","text"]),
 "assert_not_null":(1,2,1,["got","text"]),
 "assert_freed":(1,2,1,["obj","title"]),
 "assert_not_freed":(2,2,1,["obj","title"]),
 "assert_no_new_orphans":(0,1,0,["text"]),
 "assert_set_property":(4,4,None,["obj","property_name","new_value","expected_value"]),
 "assert_readonly_property":(4,4,None,["obj","property_name","new_value","expected_value"]),
 "assert_property_with_backing_variable":(4,5,None,["obj","prop","default","new","backed_by_name"]),
 "assert_property":(4,4,None,["obj","prop","default","new"]),
 "assert_eq_deep":(2,2,None,["v1","v2"]),
 "assert_ne_deep":(2,2,None,["v1","v2"]),
 "assert_eq_shallow":(2,2,None,["v1","v2"]),
 "assert_ne_shallow":(2,2,None,["v1","v2"]),
 "assert_same":(2,3,2,["v1","v2","text"]),
 "assert_not_same":(2,3,2,["v1","v2","text"]),
 "assert_setget":(2,6,None,["obj","name","..."]),
}

ANSI = re.compile(r"\x1b\[[0-9;]*m")
ASSERT_CALL = re.compile(r"\b(assert_[a-z_0-9]+)\s*\(")


def strip_comment(line):
    """Remove a trailing # comment without touching # inside string literals."""
    out = []; q = None; i = 0
    while i < len(line):
        c = line[i]
        if q:
            if c == "\\":
                out.append(c); i += 1
                if i < len(line): out.append(line[i])
            elif c == q:
                q = None; out.append(c)
            else:
                out.append(c)
        else:
            if c in "\"'": q = c; out.append(c)
            elif c == "#": break
            else: out.append(c)
        i += 1
    return "".join(out)


def split_args(s):
    """Split on top-level commas only (respects (), [], {} and quotes)."""
    args = []; depth = 0; q = None; cur = ""
    for c in s:
        if q:
            cur += c
            if c == q: q = None
            continue
        if c in "\"'": q = c; cur += c; continue
        if c in "([{": depth += 1; cur += c; continue
        if c in ")]}": depth -= 1; cur += c; continue
        if c == "," and depth == 0:
            args.append(cur.strip()); cur = ""; continue
        cur += c
    if cur.strip(): args.append(cur.strip())
    return args


def looks_like_message(arg):
    """True only for a PURE human-readable string literal.

    Critically this must reject expressions that merely BEGIN with a literal:
        "HUD_COLOR_ALARM_FILL" in whitelist     -> a boolean test, valid `got`
        "%d" % (stock - 1)                      -> a formatted value, valid `expected`
    Treating those as messages produced 10 false positives across this suite,
    which would have made the gate unusable and therefore ignored.
    """
    a = arg.strip()
    if not a or a[0] not in "\"'": return False
    q = a[0]; i = 1
    while i < len(a):                      # walk to the closing quote
        if a[i] == "\\": i += 2; continue
        if a[i] == q: break
        i += 1
    else:
        return False
    inner = a[1:i]
    if a[i+1:].strip():                    # anything after the literal => expression
        return False
    return len(inner) > 12 and " " in inner


def iter_assert_calls(text):
    """Yield (name, arg_string, line_no) for every assert_*() with balanced parens."""
    for m in ASSERT_CALL.finditer(text):
        start = m.end(); depth = 1; q = None; i = start
        while i < len(text) and depth > 0:
            c = text[i]
            if q:
                if c == "\\": i += 2; continue
                if c == q: q = None
            elif c in "\"'": q = c
            elif c == "(": depth += 1
            elif c == ")": depth -= 1
            i += 1
        yield m.group(1), text[start:i-1], text[:m.start()].count("\n") + 1


# Branch-head keywords that open a conditional block. A `return` nested inside
# one of these is a *conditional early-return*; the function's actual assert
# count is legitimately branch-dependent and must NOT be treated as a missing
# assertion (see B-class downgrade in scan_b_class).
_BRANCH_HEAD = re.compile(r"^\s*(if|elif|else|match|case)\b")
_RETURN = re.compile(r"\breturn\b")


def func_has_conditional_return(lines):
    """True iff the function body contains a `return` nested inside a branch.

    `lines` is the raw function body (one entry per source line, indentation
    preserved). Two branch forms are recognised:

      - block form : `if x:` ... then a deeper-indented `return`
      - inline form: `if x: return` (branch head + return on one line)

    A *top-level* `return` (indent equal to the function body itself, outside
    any branch) is NOT a conditional early-return and does not count.

    Algorithm: track the indentation of the most recent branch head
    (`branch_indent`). When a branch head is seen, record its indent and return
    True immediately if the same line also carries a `return` (inline form). A
    `return` line indented deeper than the active branch head is a conditional
    early-return (block form -> True). Any later line that dedents to/below the
    branch head (and is not itself a branch head) closes the branch block, so a
    subsequent top-level `return` is no longer counted. `elif`/`else`/`case`
    are themselves branch heads and simply re-arm `branch_indent`.

    Note: functions containing `for`/`while` are excluded from the B-class
    fatal decision by the `loops == 0` guard in scan_b_class, so a `return`
    living only inside a loop is never decisive either way.
    """
    branch_indent = None
    for raw in lines:
        stripped = raw.strip()
        if not stripped:
            continue
        indent = len(raw) - len(raw.lstrip())
        if _BRANCH_HEAD.match(raw):
            branch_indent = indent
            # inline form: branch head and return on the same line
            if _RETURN.search(stripped):
                return True
            continue
        if _RETURN.search(stripped):
            # block form: return deeper than the active branch head
            if branch_indent is not None and indent > branch_indent:
                return True
            continue
        # any other line that dedents to/below the branch head closes the block
        if branch_indent is not None and indent <= branch_indent:
            branch_indent = None
    return False


def scan_a_class(tests_dir):
    findings = []
    for f in sorted(glob.glob(os.path.join(tests_dir, "**", "*.gd"), recursive=True)):
        src = open(f, encoding="utf-8").read()
        joined = "\n".join(strip_comment(l) for l in src.split("\n"))
        for name, body, ln in iter_assert_calls(joined):
            if name not in SIG:
                findings.append((f, ln, name, "UNKNOWN_ASSERT",
                                 "not a GUT assertion - typo or removed API"))
                continue
            lo, hi, tidx, pn = SIG[name]
            args = split_args(body); n = len(args)
            if n > hi:
                findings.append((f, ln, name, "ARITY_OVERFLOW",
                                 f"{n} args but max is {hi} ({', '.join(pn)})"))
            elif n < lo:
                findings.append((f, ln, name, "ARITY_UNDERFLOW",
                                 f"{n} args but min is {lo} ({', '.join(pn)})"))
            else:
                for idx, a in enumerate(args):
                    if tidx is not None and idx == tidx: continue
                    if not looks_like_message(a): continue
                    # string-subject assertions legitimately take strings in 0/1
                    if name.startswith("assert_string") and idx in (0, 1): continue
                    findings.append((f, ln, name, "MESSAGE_IN_NON_TEXT_PARAM",
                                     f"arg #{idx} is `{pn[idx] if idx < len(pn) else '?'}`, "
                                     f"not a message: {a[:60]}"))
    return findings


def scan_b_class(tests_dir, gut_log):
    """Compare per-test static assertion count against the runtime count.

    Returns a (findings, info) tuple:
      - findings  fatal B-class defects (counts toward exit 1)
      - info      informational B-class notes (branch-divergent by design;
                  still printed, but never fails the build)
    """
    static = {}
    func_lines = {}
    for f in sorted(glob.glob(os.path.join(tests_dir, "**", "*.gd"), recursive=True)):
        res = "res://" + f.replace("\\", "/")
        cur = None
        buf = None
        for i, raw in enumerate(open(f, encoding="utf-8").read().split("\n")):
            l = strip_comment(raw)
            m = re.match(r"^func\s+([A-Za-z_0-9]+)\s*\(", l)
            if m:
                cur = m.group(1)
                static[(res, cur)] = {"line": i + 1, "asserts": 0, "loops": 0}
                buf = []
                func_lines[(res, cur)] = buf
                continue
            if cur is None: continue
            buf.append(l)
            static[(res, cur)]["asserts"] += len(ASSERT_CALL.findall(l))
            if re.match(r"^\s*(for|while)\b", l): static[(res, cur)]["loops"] += 1

    # Classify which test functions intentionally diverge via a conditional
    # early-return (so a lower runtime assert count is by design, not a defect).
    for key, buf in func_lines.items():
        static[key]["cond_return"] = func_has_conditional_return(buf)

    runtime = {}; script = None; func = None
    res_re = re.compile(r"^\s*\[(Passed|Failed|Pending|Risky)\]")
    for raw in open(gut_log, encoding="utf-8", errors="replace"):
        l = ANSI.sub("", raw).rstrip("\n")
        s = l.strip()
        if re.match(r"^res://.*\.gd$", s):
            script = s; func = None; continue
        m = re.match(r"^\* (test_[A-Za-z_0-9]+)", s)
        if m:
            func = m.group(1)
            runtime[(script, func)] = {"n": 0, "errors": 0}
            continue
        if func is None: continue
        if res_re.match(l): runtime[(script, func)]["n"] += 1
        if l.startswith("SCRIPT ERROR"): runtime[(script, func)]["errors"] += 1

    findings = []
    info = []
    for (script, fn), d in static.items():
        if not fn.startswith("test_"): continue
        r = runtime.get((script, fn))
        if r is None:
            continue  # test not in this log (filtered run) - not a finding
        if r["errors"]:
            findings.append((script, d["line"], fn, "SCRIPT_ERROR_INSIDE_TEST",
                             f"{r['errors']} SCRIPT ERROR(s); "
                             f"{r['n']} asserts ran vs {d['asserts']} in source"))
        elif r["n"] < d["asserts"] and d["loops"] == 0:
            if d.get("cond_return"):
                # Branch-divergent by design: a conditional early-return means
                # the assert count legitimately varies with the branch taken.
                # Surface it for visibility but never fail the build.
                info.append((script, d["line"], fn, "FEWER_ASSERTS_BRANCH_DIVERGENT",
                             f"{r['n']} ran vs {d['asserts']} in source - "
                             f"branch-divergent (conditional early-return) by design, "
                             f"not a no-op assertion"))
            else:
                findings.append((script, d["line"], fn, "FEWER_ASSERTS_THAN_SOURCE",
                                 f"{r['n']} ran vs {d['asserts']} in source "
                                 f"- an assertion did not execute"))
    return findings, info


SELFTEST_FIXTURE = '''extends GutTest
func test_planted():
\tassert_eq_deep(a, b, "this message has nowhere to go")
\tassert_signal_emitted_with_parameters(o, "sig", [1], "message not index")
\tassert_string_contains(hay, needle, "should contain the needle")
\tassert_called(dbl, "method_name", "a message instead of parameters")
\tassert_file_exists("res://x.txt", "extra message argument")
\tassert_connected(a, b, "sig", "a long human readable message")
\tassert_almost_eq(got, "the message landed in error_interval")
\tassert_property(o, "p", 1, 2)
\tassert_eq(got, expected, "this one is correct")
\tassert_true(flag, "so is this one")
'''
EXPECTED_KINDS = {
    "ARITY_OVERFLOW", "MESSAGE_IN_NON_TEXT_PARAM", "ARITY_UNDERFLOW",
}


def selftest():
    """A linter that cannot fail is exactly the bug we are hunting."""
    with tempfile.TemporaryDirectory() as td:
        sub = os.path.join(td, "unit"); os.makedirs(sub)
        open(os.path.join(sub, "test_planted.gd"), "w", encoding="utf-8").write(SELFTEST_FIXTURE)
        found = scan_a_class(td)
    by_line = {ln: kind for _, ln, _, kind, _ in found}
    planted = [3, 4, 5, 6, 7, 8, 9]        # lines that MUST be flagged
    clean   = [10, 11, 12]                 # lines that must NOT be flagged
    ok = True
    for ln in planted:
        if ln not in by_line:
            print(f"  SELFTEST FAIL: planted defect on line {ln} was NOT detected"); ok = False
    for ln in clean:
        if ln in by_line:
            print(f"  SELFTEST FAIL: false positive on clean line {ln} ({by_line[ln]})"); ok = False
    print(f"  selftest: {len(planted)} planted defects, "
          f"{sum(1 for l in planted if l in by_line)} detected; "
          f"{len(clean)} clean lines, "
          f"{sum(1 for l in clean if l in by_line)} false positives")

    # ── B-class: conditional early-return recognizer (func_has_conditional_return) ──
    # Must detect conditional early-returns (block + inline + match/case forms).
    cr_true = [
        "func test_a():\n\tif x:\n\t\treturn\n\tassert_eq(a,b)",          # block form
        "func test_b():\n\tif x: return\n\tassert_eq(a,b)",            # inline form
        "func test_c():\n\tmatch y:\n\t\t_:\n\t\t\treturn",            # match/case form
    ]
    # Must NOT flag a plain top-level return or a function with no return.
    cr_false = [
        "func test_d():\n\tassert_eq(a,b)\n\treturn",                  # top-level return
        "func test_e():\n\tassert_eq(a,b)\n\tassert_true(c)",          # no return at all
    ]
    for src in cr_true:
        if not func_has_conditional_return(src.split("\n")):
            print("  SELFTEST FAIL: conditional early-return NOT detected (expected True)")
            ok = False
    for src in cr_false:
        if func_has_conditional_return(src.split("\n")):
            print("  SELFTEST FAIL: false positive conditional-return (expected False)")
            ok = False
    print(f"  selftest: conditional-return recognizer "
          f"{sum(1 for s in cr_true if func_has_conditional_return(s.split(chr(10))))}/{len(cr_true)} true, "
          f"{sum(1 for s in cr_false if not func_has_conditional_return(s.split(chr(10))))}/{len(cr_false)} false")

    return ok


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tests-dir", default="tests")
    ap.add_argument("--gut-log", default=None)
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args()

    if a.selftest:
        print("[assert-lint] selftest")
        ok = selftest()
        print("[assert-lint] selftest " + ("PASSED" if ok else "FAILED"))
        return 0 if ok else 2

    findings = scan_a_class(a.tests_dir)
    print(f"[assert-lint][A] GUT signature misuse: {len(findings)} finding(s)")
    for f, ln, name, kind, detail in findings:
        print(f"  {kind}  {f}:{ln}  {name}\n      {detail}")

    b_fatal, b_info = [], []
    if a.gut_log and os.path.exists(a.gut_log):
        b_fatal, b_info = scan_b_class(a.tests_dir, a.gut_log)
        print(f"[assert-lint][B] assertions that never executed: "
              f"{len(b_fatal)} fatal, {len(b_info)} informational")
        for script, ln, fn, kind, detail in b_fatal:
            print(f"  {kind}  {script}:{ln}  {fn}\n      {detail}")
        for script, ln, fn, kind, detail in b_info:
            print(f"  {kind}  {script}:{ln}  {fn}\n      {detail} (informational)")
    else:
        print("[assert-lint][B] skipped (no --gut-log)")

    total = len(findings) + len(b_fatal)
    print(f"[assert-lint] total: {total} (informational not counted)")
    return 1 if total else 0


if __name__ == "__main__":
    sys.exit(main())
