#!/usr/bin/env python3
"""Build the monthly security review from docs/SECURITY-CLAIMS.md.

    security-review-report.py [--today YYYY-MM-DD] [REGISTER]

Prints the issue body (markdown) on stdout. Exit status: number of overdue
decisions and engineering items (capped at 100), so the workflow can
escalate. Claims not "verified" are listed every month, overdue or not.
"""
import argparse
import datetime
import re
import sys


def tables(text):
    """{section title: [row dicts]} for every markdown table under a ## heading."""
    out, section, header = {}, None, None
    for line in text.splitlines():
        if line.startswith("## "):
            section, header = line[3:].strip(), None
            continue
        if not line.startswith("|"):
            header = None if not line.strip() else header
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if header is None:
            header = cells
        elif set(line.replace("|", "").strip()) <= set("-: "):
            continue
        else:
            out.setdefault(section, []).append(dict(zip(header, cells)))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("register", nargs="?", default="docs/SECURITY-CLAIMS.md")
    ap.add_argument("--today", default=datetime.date.today().isoformat())
    a = ap.parse_args()
    today = datetime.date.fromisoformat(a.today)
    t = tables(open(a.register).read())

    lines = [f"Monthly security review, {today.isoformat()}. Source: `{a.register}`.", ""]
    overdue = []

    def due_of(row):
        m = re.match(r"\d{4}-\d{2}-\d{2}", row.get("Due", ""))
        return datetime.date.fromisoformat(m.group(0)) if m else None

    claims = [r for r in t.get("Claims", []) if not r.get("Status", "").lower().startswith("verified")]
    lines.append(f"## Claims not fully verified ({len(claims)})\n")
    lines += [f"- [ ] **{r['ID']}** {r['Promise']}: *{r['Status']}*" for r in claims] or ["- none"]
    lines.append("")

    for title, key in (("Decisions pending", "Question"), ("Engineering items", "Item")):
        rows = [r for r in t.get(title, []) if r.get("Status", "open").lower() != "done"]
        lines.append(f"## {title} ({len(rows)})\n")
        for r in rows:
            d = due_of(r)
            late = d is not None and d < today
            if late:
                overdue.append(r["ID"])
            flag = f" **OVERDUE since {d.isoformat()}**" if late else (f" (due {d.isoformat()})" if d else " (no due date)")
            lines.append(f"- [ ] **{r['ID']}** {r[key]}{flag}")
        if not rows:
            lines.append("- none")
        lines.append("")

    lines += [
        "## Every month",
        "",
        "- [ ] Open \"Security baseline drift\" issues reviewed, baseline updated or the change reverted",
        "- [ ] Last smoke-boot runs: security probe PASS, no new WARN lines (validator, SELinux denials)",
        "- [ ] Scorecard and Renovate security updates looked at",
        "- [ ] Upstream security news for what Margine ships: shim/GRUB/dbx, kernel (CachyOS), bootc/rpm-ostree, containers/image, cosign",
        "- [ ] Register updated: statuses, new claims, due dates; close this issue when done",
        "",
    ]
    if overdue:
        lines.insert(1, f"**{len(overdue)} item(s) overdue: {', '.join(overdue)}.** Decide, do, or move the date with a reason in the register.\n")
    print("\n".join(lines))
    return min(len(overdue), 100)


if __name__ == "__main__":
    sys.exit(main())
