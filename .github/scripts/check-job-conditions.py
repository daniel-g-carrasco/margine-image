#!/usr/bin/env python3
"""Fail when a workflow job can be skipped by accident.

GitHub skips a job whose condition is the implicit success() as soon as
ANY job it depends on, directly or through others, was skipped. On
2026-10-06 build_push gained a dependency on a job that only runs on
Renovate PRs; the sign job, two steps down the chain, kept the implicit
condition and silently stopped running on main: two unsigned images were
published and promoted. actionlint does not flag this.

Rule: if any ancestor of a job has an `if:` (so it can be skipped), the
job's own `if:` must name a status function: always(), !cancelled(),
failure(), cancelled(), or success(). Writing success() explicitly is
allowed and means "stop when anything upstream was skipped" on purpose
(an ISO install test with no ISO to test, for example); leaving the
status implicit is what nobody notices, so that is what fails.

Usage: check-job-conditions.py WORKFLOW.yml...
"""
import re
import sys

import yaml

STATUS_OK = re.compile(r"always\(\)|!\s*cancelled\(\)|failure\(\)|cancelled\(\)|success\(\)")


def needs_of(job):
    n = job.get("needs") or []
    return [n] if isinstance(n, str) else list(n)


def check(path):
    jobs = (yaml.safe_load(open(path)) or {}).get("jobs") or {}
    problems = []

    def ancestors(name, seen=None):
        seen = set() if seen is None else seen
        for parent in needs_of(jobs.get(name, {})):
            if parent not in seen:
                seen.add(parent)
                ancestors(parent, seen)
        return seen

    for name, job in jobs.items():
        skippable = sorted(a for a in ancestors(name) if "if" in jobs.get(a, {}))
        if not skippable:
            continue
        cond = str(job.get("if", ""))
        if not STATUS_OK.search(cond):
            problems.append(
                f"{path}: job '{name}' depends on {', '.join(skippable)}, which can be skipped, "
                f"but its condition ({cond or 'implicit success()'}) skips it too. "
                "Use `!cancelled() && needs.<job>.result == 'success'` to run anyway, "
                "or write `success() && ...` if stopping is intended."
            )
    return problems


def main(paths):
    problems = [p for path in paths for p in check(path)]
    for p in problems:
        print(f"::error::{p}")
    if not problems:
        print(f"job conditions OK in {len(paths)} workflow(s)")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
