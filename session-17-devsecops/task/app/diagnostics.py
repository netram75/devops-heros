"""SECURITY GATE DEMO - this module is deliberately insecure and gets reverted.

It exists only to prove that the Session 17 pipeline stops a bad change at the
security gate. It contains:
  * command injection (subprocess with shell=True on user input)  -> Bandit / Semgrep
  * a hard-coded AWS-style access key ID                         -> Gitleaks / Trivy secret
The key below is random text in the AWS key format. It was never issued by AWS.
"""
import subprocess

from flask import Blueprint, jsonify, request

AWS_ACCESS_KEY_ID = "AKIAMQV2GVDNXU2OVUEA"

bp = Blueprint("diagnostics", __name__)


@bp.get("/api/diagnostics/ping")
def ping():
    host = request.args.get("host", "127.0.0.1")
    out = subprocess.run(f"ping -c 1 {host}", shell=True, capture_output=True, text=True)
    return jsonify(host=host, returncode=out.returncode)
