#!/usr/bin/env python3
"""Security gate for the Session 21 final project pipeline (reused from Session 17).

Every scanner in the pipeline runs in report mode and uploads a JSON report as an
artifact. This script is the single place that turns those reports into a
pass/fail decision, using the thresholds in gate-policy.json.

usage: security_gate.py --reports DIR [--policy gate-policy.json] [--out gate-result.json]

Exit code 0 = release allowed, 1 = release blocked. A report that is missing or
cannot be parsed counts as a blocking failure (fail closed), so a scanner that
silently crashed can never turn the gate green.
"""
import argparse
import json
import os
import sys

CONF_ORDER = {"LOW": 1, "MEDIUM": 2, "HIGH": 3}


def load(path):
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


def check_bandit(data, rule):
    results = data.get("results", [])
    min_conf = CONF_ORDER[rule.get("min_confidence", "LOW")]
    blocking = [
        f"{r['test_id']} {r['issue_severity']}/{r['issue_confidence']} "
        f"{r['filename']}:{r['line_number']} {r['issue_text']}"
        for r in results
        if r["issue_severity"] in rule["block_severities"]
        and CONF_ORDER.get(r["issue_confidence"], 0) >= min_conf
    ]
    return len(results), blocking


def check_semgrep(data, rule):
    results = data.get("results", [])
    if data.get("errors"):
        # A rule that failed to run is not a finding, but it should be visible.
        print(f"  note: semgrep reported {len(data['errors'])} non-fatal error(s)")
    blocking = [
        f"{r['check_id'].split('.')[-1]} {r['extra']['severity']} "
        f"{r['path']}:{r['start']['line']}"
        for r in results
        if r["extra"]["severity"] in rule["block_severities"]
    ]
    return len(results), blocking


def check_pip_audit(data, rule):
    total, blocking = 0, []
    for dep in data.get("dependencies", []):
        for v in dep.get("vulns", []):
            total += 1
            if v.get("fix_versions") or not rule.get("block_if_fix_available", True):
                aliases = ",".join(v.get("aliases", [])[:2])
                blocking.append(
                    f"{dep['name']}=={dep['version']} {v['id']} ({aliases}) "
                    f"fix: {','.join(v.get('fix_versions', [])) or 'none'}"
                )
    return total, blocking


def check_trivy(data, rule):
    total, blocking = 0, []
    for res in data.get("Results") or []:
        target = res.get("Target", "?")
        for v in res.get("Vulnerabilities") or []:
            total += 1
            if v["Severity"] not in rule.get("block_vuln_severities", []):
                continue
            if rule.get("ignore_unfixed") and not v.get("FixedVersion"):
                continue
            blocking.append(
                f"{v['VulnerabilityID']} {v['Severity']} {v['PkgName']} "
                f"{v['InstalledVersion']} -> {v.get('FixedVersion') or 'no fix'} [{target}]"
            )
        for m in res.get("Misconfigurations") or []:
            if m.get("Status") != "FAIL":
                continue
            total += 1
            if m["Severity"] in rule.get("block_misconfig_severities", []):
                blocking.append(f"{m['ID']} {m['Severity']} {target}: {m['Title']}")
        for s in res.get("Secrets") or []:
            total += 1
            if rule.get("block_any_secret"):
                blocking.append(f"secret {s['RuleID']} {s['Severity']} {target}:{s.get('StartLine')}")
    return total, blocking


def check_gitleaks(data, rule):
    findings = data if isinstance(data, list) else []
    blocking = [
        f"{f['RuleID']} {f['File']}:{f['StartLine']} commit {f.get('Commit', '')[:7]}"
        for f in findings
    ]
    if len(findings) <= rule.get("max_findings", 0):
        blocking = []
    return len(findings), blocking


CHECKS = [
    ("SAST", "bandit", check_bandit),
    ("SAST", "semgrep", check_semgrep),
    ("SCA", "pip_audit", check_pip_audit),
    ("SCA", "trivy_fs", check_trivy),
    ("Secrets", "gitleaks", check_gitleaks),
    ("Image", "trivy_image", check_trivy),
]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--reports", required=True)
    ap.add_argument("--policy", default=os.path.join(os.path.dirname(__file__), "gate-policy.json"))
    ap.add_argument("--out", default=None)
    args = ap.parse_args()
    policy = load(args.policy)

    rows, details, failed = [], {}, False
    for stage, name, fn in CHECKS:
        rule = policy[name]
        path = os.path.join(args.reports, rule["report"])
        try:
            total, blocking = fn(load(path), rule)
            status = "BLOCK" if blocking else "pass"
        except (OSError, ValueError, KeyError, TypeError) as exc:
            total, blocking, status = "-", [f"report unusable: {exc}"], "BLOCK"
        failed |= status == "BLOCK"
        rows.append((stage, name, rule["report"], total, len(blocking), status))
        details[name] = blocking

    header = ("stage", "check", "report", "findings", "blocking", "result")
    widths = [max(len(str(r[i])) for r in rows + [header]) for i in range(len(header))]
    line = lambda r: "  ".join(str(c).ljust(w) for c, w in zip(r, widths))
    print("SECURITY GATE")
    print(line(header))
    print("  ".join("-" * w for w in widths))
    for r in rows:
        print(line(r))
    for name, items in details.items():
        if items:
            print(f"\n[{name}] blocking findings ({len(items)}):")
            for item in items[:15]:
                print(f"  - {item}")
            if len(items) > 15:
                print(f"  ... and {len(items) - 15} more")
    verdict = "FAILED - release blocked" if failed else "PASSED - release allowed"
    print(f"\nGATE {verdict}")

    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as fh:
            fh.write(f"## Security gate: {verdict}\n\n")
            fh.write("| stage | check | findings | blocking | result |\n|---|---|---|---|---|\n")
            for r in rows:
                fh.write(f"| {r[0]} | {r[1]} | {r[3]} | {r[4]} | {r[5]} |\n")
            for name, items in details.items():
                if items:
                    fh.write(f"\n**{name}**\n\n")
                    fh.write("".join(f"- `{i}`\n" for i in items[:15]))

    if args.out:
        with open(args.out, "w", encoding="utf-8") as fh:
            json.dump({"passed": not failed, "checks": [dict(zip(header, r)) for r in rows],
                       "blocking": details}, fh, indent=2)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
