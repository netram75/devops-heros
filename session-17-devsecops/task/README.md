# Session 17 - Complete CI/CD & DevSecOps - Task

- **Name:** Netram
- **Enrollment No:** 24BCS10329

> **Status:** completed

> The pipeline runs on GitHub Actions (`ubuntu-latest`, Ubuntu 24.04 runners) in
> [netram75/devops-heros](https://github.com/netram75/devops-heros) on the branch
> `session17-devsecops`, deploys into a kind cluster (kind v0.33.0, Kubernetes v1.37.0)
> created inside the runner, and pushes to GHCR. I also ran every scanner locally on
> macOS (Apple Silicon) with Docker Desktop 29.6.2 and a throwaway kind cluster
> (`netram-s17`, Kubernetes v1.34.0) that I deleted afterwards.

---

## What the task asked

Build a complete CI/CD pipeline with security built in:

- CI/CD: application build, unit testing, Docker image build, container registry,
  Kubernetes deployment.
- Security: SAST, SCA, secret scanning, container image scanning, security gates.
- Flow: Code -> Build -> Unit Test -> SAST -> SCA -> Secret Scan -> Docker Build ->
  Container Image Scan -> Security Gate -> Push Image -> Deploy to Kubernetes.
- Deliverables: application, Dockerfile, GitHub Actions workflow, security tool
  configuration, Kubernetes manifests, successful pipeline output, screenshots, README.

## My approach

The course demo (`../demo`) uses CodeQL, pip-audit, Trivy, Docker Hub and kind. I kept
pip-audit, Trivy and kind, and changed three things on purpose:

1. **Scanners report, one gate decides.** In the demo every scanner fails its own job
   with `--exit-code 1`. Then the "gate" is spread over five places and a scanner that
   crashes looks the same as one that found something. In my pipeline every scanner runs
   in report mode and uploads a JSON report as an artifact. One job,
   `7. Security gate`, downloads all six reports and applies one policy file
   ([`security/gate-policy.json`](security/gate-policy.json)). If a report is missing or
   unreadable the gate fails (fail closed).
2. **Push exactly what was scanned.** The demo rebuilds the image in the scan job and
   again in the push job, so the image that reaches the registry is not the one that was
   scanned. I build once, save the image as a tarball artifact, scan that tarball, push
   that tarball, and deploy it to Kubernetes by its `@sha256` digest.
3. **GHCR instead of Docker Hub**, with the built-in `GITHUB_TOKEN`
   (`permissions: packages: write`), so there is no long-lived registry password.

For SAST I used Bandit (Python specific) and Semgrep (`p/python`, `p/flask` and three
project rules) instead of CodeQL, because both give me a JSON report the gate can read
and a SARIF file for the Security tab. For secrets I used Gitleaks over the full git
history.

The app is a small Flask "release checklist" API (`app/main.py`): `GET /`, `/healthz`,
`/readyz`, and `GET/POST /api/items`. It is small on purpose; the work is the pipeline.

### Files

| Path | What it is |
|---|---|
| [`app/main.py`](app/main.py), [`tests/test_app.py`](tests/test_app.py) | Flask app (app factory) and 15 pytest tests, 100% coverage |
| [`requirements.txt`](requirements.txt) | Runtime deps, **every** package pinned including transitive ones |
| [`Dockerfile`](Dockerfile) | Multi-stage, base pinned by tag and digest, non-root UID 10001, no pip at runtime, `HEALTHCHECK`, gunicorn |
| [`k8s/`](k8s) | Namespace (Pod Security `restricted`), Deployment (probes, limits, securityContext), ClusterIP Service |
| [`security/bandit.yaml`](security/bandit.yaml) | Bandit config |
| [`security/semgrep-rules.yml`](security/semgrep-rules.yml) | 3 project Semgrep rules (Flask debug, `shell=True`/`os.system`, hard-coded credential) |
| [`security/gitleaks.toml`](security/gitleaks.toml) | Default Gitleaks rules plus three narrow allowlists (explained below) |
| [`security/trivy.yaml`](security/trivy.yaml) | Shared Trivy settings: report every severity, exit 0 |
| [`security/gate-policy.json`](security/gate-policy.json), [`security/security_gate.py`](security/security_gate.py) | The gate policy and the script that enforces it (stdlib Python only) |
| [`../../.github/workflows/session17-devsecops.yml`](../../.github/workflows/session17-devsecops.yml) | The pipeline |
| [`screenshots/`](screenshots) | Local terminal captures and CI evidence |

## Pipeline diagram

```
 git push (session17-devsecops or main, paths: session-17-devsecops/task/** + the workflow)
   |
   v
 [1] Build + unit test ---- compileall, pytest, coverage >= 90%        (fails fast)
   |
   v
 [2] SAST ----------------- Bandit + Semgrep  -> bandit.json, semgrep.json (+ SARIF to Security tab)
   |
   v
 [3] SCA ------------------ pip-audit + Trivy fs -> pip-audit.json, trivy-fs.json
   |
   v
 [4] Secret scan ---------- Gitleaks, full history of HEAD -> gitleaks.json
   |
   v
 [5] Docker build --------- buildx -> image.tar artifact, run it read-only, wait for "healthy"
   |
   v
 [6] Image scan ----------- Trivy on image.tar (OS + Python packages + secrets) -> trivy-image.json
   |
   v
 [7] SECURITY GATE -------- downloads report-* artifacts, applies gate-policy.json
   |        \
   |         `--> any blocking finding or missing report: exit 1, STOP (8 and 9 are skipped)
   v
 [8] Push to GHCR --------- push the SAME image.tar, record the registry digest
   |
   v
 [9] Deploy to kind ------- pull secret from GITHUB_TOKEN, deploy image@sha256, rollout, smoke test
```

Every job lists the previous one in `needs`, so the order is exactly the order the task
asked for. The gate also lists `sast`, `sca`, `secret-scan` and `image-scan` directly,
because it needs their artifacts.

## The runs

| Run | Commit | What it shows | Result |
|---|---|---|---|
| [37655587947](https://github.com/netram75/devops-heros/actions/runs/37655587947) | `d67c9dd` | First run of the pipeline, all 9 jobs | **green** |
| [37656959433](https://github.com/netram75/devops-heros/actions/runs/37656959433) | `7d46976` | Gate demo: deliberately bad commit | **gate failed**, push and deploy skipped |
| [37657715475](https://github.com/netram75/devops-heros/actions/runs/37657715475) | `b7aa6ce` | Bad code reverted, fake key still in history | **gate failed** on Gitleaks only |
| [37658989975](https://github.com/netram75/devops-heros/actions/runs/37658989975) | `6e7cb80` | Demo commit allowlisted after review | **green** again, pushed and deployed |

![Run 1 overview](screenshots/s17-10-ci-run1-green-overview.png)

The GitHub web UI only shows job logs to signed-in users, so the job log screenshots
below are the real logs fetched with `gh api repos/netram75/devops-heros/actions/jobs/<id>/logs`
and rendered by a small filter script that strips timestamps and echoed script lines.
The command is shown at the top of each one.

## Stage by stage

### 1. Build and unit test

```yaml
- name: Build (byte-compile every module, fails on syntax errors)
  run: python -m compileall -q app
- name: Unit tests with coverage
  run: |
    python -m pytest --cov=app --cov-report=term-missing \
      --cov-report=xml:reports/coverage.xml --cov-fail-under=90 \
      --junitxml=reports/junit.xml
```

Python has no compile step, so "build" here is `compileall` (a syntax error fails the
job) plus installing the pinned dependencies. Real output from run 37655587947:

```
collected 15 items
tests/test_app.py ...............                                        [100%]
Name              Stmts   Miss  Cover   Missing
-----------------------------------------------
app/__init__.py       0      0   100%
app/main.py          60      0   100%
-----------------------------------------------
TOTAL                60      0   100%
Required test coverage of 90% reached. Total coverage: 100.00%
============================== 15 passed in 0.40s ==============================
```

Unit tests are the one stage that fails immediately instead of going through the gate:
a broken app is not a security policy question.

![job 1](screenshots/s17-13-ci-job1-build-test.png)

### 2. SAST: Bandit + Semgrep

```yaml
bandit -c security/bandit.yaml -r app -f json -o reports/bandit.json --exit-zero
bandit -c security/bandit.yaml -r app -f sarif -o reports/bandit.sarif --exit-zero
docker run --rm -v "$PWD:/src" -w /src "$SEMGREP_IMAGE" semgrep scan --metrics=off \
  --config p/python --config p/flask --config security/semgrep-rules.yml \
  --json-output=reports/semgrep.json --sarif-output=reports/semgrep.sarif --text app
```

Both SARIF files go to the Security tab with `github/codeql-action/upload-sarif@v4`
(`permissions: security-events: write`). The CI log says
`Successfully uploaded results` / `Analysis upload status is complete.` twice, and the
code scanning API lists both analyses for `refs/heads/session17-devsecops`
(`Bandit ... results=0`, `Semgrep OSS ... results=0`). On the clean code: Bandit
`No issues identified.`, Semgrep `Ran 154 rules on 2 files: 0 findings.`

I added three project rules because the public rulesets do not know my policy, for
example "a variable named like a key must not hold a literal string". The gate demo
below shows them firing (`s17-hardcoded-credential`, `s17-subprocess-with-shell`).

![job 2](screenshots/s17-14-ci-job2-sast.png)

### 3. SCA: pip-audit + Trivy fs

```yaml
pip-audit -r requirements.txt -f json -o reports/pip-audit.json || echo "pip-audit reported findings (exit $?)"
docker run --rm -v "$PWD:/src" -w /src "$TRIVY_IMAGE" fs --quiet \
  --config security/trivy.yaml --scanners vuln,misconfig,secret \
  --format json -o reports/trivy-fs.json .
```

pip-audit is the course tool, but it has no severity field, so I also run Trivy fs,
which has severities and also checks the Dockerfile and the Kubernetes manifests
(misconfiguration) and looks for secrets. On the clean code pip-audit says
`No known vulnerabilities found`; Trivy fs finds one MEDIUM misconfiguration:

```
k8s/deployment.yaml (kubernetes)
Failures: 1 (UNKNOWN: 0, LOW: 0, MEDIUM: 1, HIGH: 0, CRITICAL: 0)
KSV-0125 (MEDIUM): Container app in deployment release-checklist (namespace: session17) uses an image from an untrusted registry.
```

That one is expected: Trivy's default trusted list does not include `ghcr.io`. It is
MEDIUM, so it is reported but does not block. Before my manifests were final it also
reported KSV-0013 ("should specify an image tag") because I used a bare placeholder;
I changed the placeholder to `...:set-by-pipeline` and the deploy job swaps in the digest.

Why every transitive dependency is pinned in `requirements.txt`: both `pip-audit -r` and
`trivy fs` only judge what the file lists. If `Jinja2` were unpinned, a vulnerable Jinja2
in the image would be invisible to SCA and only caught later by the image scan.

![job 3](screenshots/s17-15-ci-job3-sca.png)

### 4. Secret scan: Gitleaks

```yaml
- uses: actions/checkout@v7
  with:
    fetch-depth: 0
- name: Install Gitleaks (checksum verified)
  run: |
    curl -sSfLO "$base/$tarball"
    curl -sSfL "$base/gitleaks_${GITLEAKS_VERSION}_checksums.txt" | grep " $tarball\$" | sha256sum -c -
- name: Gitleaks over the whole repository history
  run: |
    gitleaks git . --config "$APP_DIR/security/gitleaks.toml" \
      --log-opts="--full-history HEAD" \
      --redact --no-banner --verbose --exit-code 0 \
      --report-format json --report-path "$APP_DIR/reports/gitleaks.json"
```

It scans every commit (`fetch-depth: 0`), not just the latest diff, because a secret
that was committed and then deleted is still readable in history.

The first time I ran Gitleaks on the whole repository locally, with default rules, it
found **9** "secrets", all in the Session 12 course material (base64 of demo passwords
like `secretpassword` in Kubernetes Secret examples). That is why
`security/gitleaks.toml` has allowlists. I kept them narrow: they name exact paths and
only silence the two rules that fired (`generic-api-key`, `kubernetes-secret-yaml`), so a
real AWS key or private key in those same files would still be caught. With the config:
`no leaks found` (screenshot `s17-04`).

![job 4](screenshots/s17-16-ci-job4-gitleaks.png)

### 5. Docker build

```yaml
- uses: docker/build-push-action@c3c9e263c25d99ce0380d002d59b67737d91b0dc # v7.4.0
  with:
    context: ${{ env.APP_DIR }}
    tags: ${{ env.IMAGE_NAME }}:${{ github.sha }}
    outputs: type=docker,dest=${{ runner.temp }}/image.tar
```

The Dockerfile pins `python:3.13.16-slim@sha256:bf44cdfc...`, installs dependencies in a
build stage, copies only the venv and `app/` into the runtime stage, runs as UID 10001,
and has a `HEALTHCHECK` written in Python (the slim image has no curl). The job then
runs the image the way Kubernetes will (read-only root, `/tmp` tmpfs) and waits for
Docker to report it healthy:

```
user=10001:10001 healthcheck=["CMD","python","-c","import urllib.request,sys; ..."]
container health: healthy
{"commit":"d67c9ddcf9e053c268e5ed36f71dee2e0ab34381","pod":"n/a","service":"release-checklist","version":"1.0.1"}
uid=10001(app) gid=10001(app) groups=10001(app)
```

![job 5](screenshots/s17-17-ci-job5-docker-build.png)

### 6. Container image scan: Trivy

```yaml
docker run --rm -v "$PWD:/src" -v "$RUNNER_TEMP:/img" -w /src "$TRIVY_IMAGE" image --quiet \
  --config security/trivy.yaml --scanners vuln,secret \
  --format json -o reports/trivy-image.json --input /img/image.tar
```

The image scan finds things the source scans cannot: Debian packages from the base
image, and secrets baked into layers. On the clean image Trivy reports 165
vulnerabilities, **all with no fixed version published yet** (local count, same image):

```
HIGH      no fix yet     44
LOW       no fix yet     61
MEDIUM    no fix yet     58
UNKNOWN   no fix yet     2
```

The policy for the image is "block HIGH/CRITICAL that have a fix". I cannot fix a
Debian CVE that Debian has not fixed by rebuilding, and blocking on it would block every
release until upstream ships a patch. They stay visible in the report and in the job
log (`Total: 44 (HIGH: 44, CRITICAL: 0)`, all `affected`). Everything with a fix blocks.

![job 6](screenshots/s17-18-ci-job6-image-scan.png)

### 7. Security gate

```yaml
- name: Download every scan report
  uses: actions/download-artifact@v8
  with:
    pattern: report-*
    merge-multiple: true
    path: ${{ env.APP_DIR }}/gate-input
- name: Evaluate reports against gate-policy.json
  run: python3 security/security_gate.py --reports gate-input --policy security/gate-policy.json --out gate-input/gate-result.json
```

| Check | Blocks when |
|---|---|
| Bandit | severity HIGH with confidence MEDIUM or HIGH |
| Semgrep | severity ERROR |
| pip-audit | any known vulnerability that already has a fixed version |
| Trivy fs | vuln HIGH/CRITICAL, misconfig HIGH/CRITICAL, any secret |
| Gitleaks | any finding |
| Trivy image | vuln HIGH/CRITICAL with a fix available, any secret |
| any report | missing or unparseable |

Real output from run 37655587947:

```
SECURITY GATE
stage    check        report            findings  blocking  result
-------  -----------  ----------------  --------  --------  ------
SAST     bandit       bandit.json       0         0         pass
SAST     semgrep      semgrep.json      0         0         pass
SCA      pip_audit    pip-audit.json    0         0         pass
SCA      trivy_fs     trivy-fs.json     1         0         pass
Secrets  gitleaks     gitleaks.json     0         0         pass
Image    trivy_image  trivy-image.json  165       0         pass

GATE PASSED - release allowed
```

"findings" vs "blocking" is the whole point: 166 things were found, none of them is
blocking under the written policy, and the policy says why.

![job 7](screenshots/s17-19-ci-job7-gate-pass.png)

### 8. Push to GHCR

```yaml
permissions:
  contents: read
  packages: write
...
docker load -i "$RUNNER_TEMP/image.tar"
docker push "$IMAGE_NAME:$GITHUB_SHA" | tee push.log
digest=$(grep -o 'digest: sha256:[0-9a-f]*' push.log | head -1 | cut -d' ' -f2)
```

```
Login Succeeded!
Loaded image: ghcr.io/netram75/devops-heros-session17:d67c9ddcf9e053c268e5ed36f71dee2e0ab34381
d67c9ddcf9e053c268e5ed36f71dee2e0ab34381: digest: sha256:6602983d2c596e2304f1cc201ae8772a0c9e8d6e351033dbe13bbf2df3860369 size: 1992
session17-devsecops: digest: sha256:6602983d2c596e2304f1cc201ae8772a0c9e8d6e351033dbe13bbf2df3860369 size: 1992
```

The package is at
[github.com/netram75/devops-heros/pkgs/container/devops-heros-session17](https://github.com/netram75/devops-heros/pkgs/container/devops-heros-session17).
It is linked to the public repo; an anonymous token request and manifest fetch for
`:session17-devsecops` returned HTTP 200.

![job 8](screenshots/s17-30-ci-job8-push-ghcr.png)

### 9. Deploy to Kubernetes (kind in the runner) + smoke test

```yaml
- uses: helm/kind-action@1544676c07bb3570fcb70166beaa07c4528fd4aa # v1.15.1
- run: |
    kubectl -n session17 create secret docker-registry ghcr-pull \
      --docker-server=ghcr.io --docker-username="${{ github.actor }}" \
      --docker-password="${{ secrets.GITHUB_TOKEN }}"
- run: |
    sed -i "s|image: ghcr.io/netram75/devops-heros-session17:.*|image: $IMAGE_NAME@$DIGEST|" k8s/deployment.yaml
    kubectl apply -f k8s/deployment.yaml -f k8s/service.yaml
    kubectl -n session17 rollout status deployment/release-checklist --timeout=180s
```

The cluster really pulls from GHCR (it is not `kind load`), and it pulls by digest, so
the pods run the exact bytes that passed the gate. Output from run 37655587947:

```
41:          image: ghcr.io/netram75/devops-heros-session17@sha256:6602983d2c596e2304f1cc201ae8772a0c9e8d6e351033dbe13bbf2df3860369
deployment "release-checklist" successfully rolled out
release-checklist-6ff6c94cdf-9rv4z  image=ghcr.io/netram75/devops-heros-session17@sha256:6602983d...  ready=true
release-checklist-6ff6c94cdf-fhdz8  image=ghcr.io/netram75/devops-heros-session17@sha256:6602983d...  ready=true
uid=10001(app) gid=10001(app) groups=10001(app)
touch: cannot touch '/should-fail': Read-only file system
+ curl -sf localhost:8080/healthz
{"status":"ok"}
+ curl -sf localhost:8080/
{"commit":"d67c9ddcf9e053c268e5ed36f71dee2e0ab34381","pod":"release-checklist-6ff6c94cdf-9rv4z","service":"release-checklist","version":"1.0.1"}
+ curl -sf -X POST -H 'content-type: application/json' -d '{"title":"deployed by the pipeline"}' localhost:8080/api/items
{"done":false,"id":1,"title":"deployed by the pipeline"}
+ test 404 = 404
```

![job 9](screenshots/s17-31-ci-job9-deploy-kind.png)

Every scan report, the image tarball, the test results, the gate result and the
deployment evidence (`kubectl get all`, `describe`, events, logs) are uploaded as
artifacts:

![artifacts](screenshots/s17-12-ci-run1-artifacts.png)

## Security gate demo: fail, then pass

To prove the gate is not decoration I pushed commit `7d46976`, which was bad on
purpose in three ways:

- `app/diagnostics.py`: a `/api/diagnostics/ping?host=` endpoint that runs
  `subprocess.run(f"ping -c 1 {host}", shell=True)` (command injection);
- the same file: `AWS_ACCESS_KEY_ID = "AKIA..."`, a **random** string in AWS key
  format that AWS never issued (I generated it with Python's `secrets` module);
- `requirements.txt`: `urllib3==1.26.5`, an old version with known HIGH CVEs.

I first tried AWS's own documentation key `AKIAIOSFODNN7EXAMPLE`. Gitleaks did **not**
flag it: its AWS rule ignores keys ending in `EXAMPLE`. A random key in the same format
was flagged, so I used that. The unit tests still passed, the image still built and
became healthy, so the only thing that could stop this commit was the gate.

**Run [37656959433](https://github.com/netram75/devops-heros/actions/runs/37656959433):
jobs 1 to 6 green, job 7 red, jobs 8 and 9 skipped.**

![gate fail overview](screenshots/s17-20-ci-run2-gate-fail-overview.png)

```
SECURITY GATE
stage    check        report            findings  blocking  result
-------  -----------  ----------------  --------  --------  ------
SAST     bandit       bandit.json       2         1         BLOCK
SAST     semgrep      semgrep.json      5         5         BLOCK
SCA      pip_audit    pip-audit.json    18        18        BLOCK
SCA      trivy_fs     trivy-fs.json     12        8         BLOCK
Secrets  gitleaks     gitleaks.json     14        14        BLOCK
Image    trivy_image  trivy-image.json  176       8         BLOCK

[bandit] blocking findings (1):
  - B602 HIGH/HIGH app/diagnostics.py:21 subprocess call with shell=True identified, security issue.

[semgrep] blocking findings (5):
  - s17-hardcoded-credential ERROR app/diagnostics.py:13
  - subprocess-injection ERROR app/diagnostics.py:21
  - s17-subprocess-with-shell ERROR app/diagnostics.py:21
  - dangerous-subprocess-use ERROR app/diagnostics.py:21
  - subprocess-shell-true ERROR app/diagnostics.py:21

[trivy_fs] blocking findings (8):
  - CVE-2023-43804 HIGH urllib3 1.26.5 -> 2.0.6, 1.26.17 [requirements.txt]
  ...
  - secret aws-access-key-id CRITICAL app/diagnostics.py:13

[gitleaks] blocking findings (14):
  - aws-access-token session-17-devsecops/task/app/diagnostics.py:13 commit 7d46976
  - kubernetes-secret-yaml session-12-ingress-configmaps-secrets/task/task2-secret/secret.yaml:7 commit e4d6b4d
  ...

[trivy_image] blocking findings (8):
  - CVE-2023-43804 HIGH urllib3 1.26.5 -> 2.0.6, 1.26.17 [Python]
  ...
  - secret aws-access-key-id CRITICAL /srv/app/diagnostics.py:13

GATE FAILED - release blocked
```

Every category caught something, and the fake key was caught three times: in the
source (Gitleaks, Trivy fs) and inside the image layer (Trivy image).

![gate fail log](screenshots/s17-21-ci-run2-gate-fail-log.png)

Two surprises in that output, both real lessons:

1. **13 of the 14 Gitleaks findings were not from my commit.** They came from commit
   `e4d6b4d` (the Session 12 task), which is on `main`, not on my branch. Gitleaks runs
   `git log --all` by default and `fetch-depth: 0` fetches every branch, so my pipeline
   was judging other branches. I fixed it with `--log-opts="--full-history HEAD"`
   (commit `624a3e6`): scan the full history of the commit being built, nothing else.
   I checked locally: all refs gave `leaks found: 14`, HEAD only gave `leaks found: 1`.
2. **Reverting is not enough.** I reverted the bad commit (`b7aa6ce`, pushed together
   with the scope fix). The code went back to exactly what it was before
   (`git diff 7d46976~1 HEAD -- session-17-devsecops/task` is empty), but run
   [37657715475](https://github.com/netram75/devops-heros/actions/runs/37657715475)
   still failed, on Gitleaks alone:

```
SAST     bandit       bandit.json       0         0         pass
SAST     semgrep      semgrep.json      0         0         pass
SCA      pip_audit    pip-audit.json    0         0         pass
SCA      trivy_fs     trivy-fs.json     1         0         pass
Secrets  gitleaks     gitleaks.json     1         1         BLOCK
Image    trivy_image  trivy-image.json  165       0         pass

[gitleaks] blocking findings (1):
  - aws-access-token session-17-devsecops/task/app/diagnostics.py:13 commit 7d46976

GATE FAILED - release blocked
```

![revert run overview](screenshots/s17-23-ci-run3-revert-still-blocked-overview.png)

![revert still blocked](screenshots/s17-24-ci-run3-gate-history-fail-log.png)

That is the course's "If a Real Secret Is Leaked: deleting the line is not enough" in
practice. For a real key the steps would be: revoke and rotate it, check for misuse,
then remove it from history. Mine was random text, so there was nothing to revoke. I
reviewed it and recorded that decision in `security/gitleaks.toml` as an allowlist that
needs **all three** of: commit `7d469760...`, path `app/diagnostics.py`, rule
`aws-access-token` (`condition = "AND"`). I tested that a new random key in the same
file in a new commit is still flagged (`leaks found: 1`). In the same commit I added a
narrow allowlist for the Session 12 task's demo Secrets (the files say every value is
FAKE), so this workflow will not trip on them when it runs on `main`.

**Run [37658989975](https://github.com/netram75/devops-heros/actions/runs/37658989975)
(commit `6e7cb80`): green again, all 9 jobs, image pushed and deployed.** The gate table
is identical to run 1 (Gitleaks back to `0 / 0 / pass`), the push job logged
`ghcr.io/netram75/devops-heros-session17@sha256:531cec9b2bd66f200d1dd8c5b797f986a925a0e95ad2f0627a2821e60b4d2bc3`,
both pods ran that digest, and `GET /` answered with `"commit":"6e7cb80e100a9eeaeab226978fce5bff7e054e08"`.

![green again](screenshots/s17-40-ci-run4-green-overview.png)

![green again gate](screenshots/s17-41-ci-run4-gate-pass.png)

## Kubernetes deployment

`k8s/namespace.yaml` labels the namespace `pod-security.kubernetes.io/enforce: restricted`,
so the API server itself rejects a pod that runs as root, keeps capabilities or allows
privilege escalation. `k8s/deployment.yaml`:

- 2 replicas, `RollingUpdate` with `maxUnavailable: 0`;
- `startupProbe` and `livenessProbe` on `/healthz`, `readinessProbe` on `/readyz`
  (separate so a future dependency check only removes the pod from the Service instead
  of restarting it);
- requests 50m CPU / 64Mi, limits 250m / 192Mi;
- pod: `runAsNonRoot`, UID/GID 10001, `seccompProfile: RuntimeDefault`,
  `automountServiceAccountToken: false`;
- container: `readOnlyRootFilesystem: true`, `allowPrivilegeEscalation: false`,
  `capabilities.drop: ["ALL"]`; the only writable path is an in-memory `emptyDir` on `/tmp`.

`k8s/service.yaml` is a ClusterIP Service (port 80 -> named port `http`/8080). The
smoke test reaches it with `kubectl port-forward`, because nothing outside the runner
needs to reach it.

Locally I applied the same manifests to a throwaway kind cluster (`kind load` of a
locally built image, since my local `gh` token has no `read:packages` scope). The
`restricted` namespace accepted the pods, both became Ready, `id` showed UID 10001 and
`touch /x` failed with `Read-only file system` (screenshot `s17-07`). I deleted that
cluster afterwards.

## Local runs (screenshots)

| Screenshot | What |
|---|---|
| `s17-01-local-build-unit-tests.png` | compileall + pytest, 15 passed, 100% coverage |
| `s17-02-local-sast.png` | Bandit 1.9.4 and Semgrep 1.179.0, 0 findings |
| `s17-03-local-sca.png` | pip-audit and Trivy fs summary, 1 MEDIUM misconfig |
| `s17-04-local-gitleaks.png` | Gitleaks: 9 course-material findings without config, 0 with it |
| `s17-05-local-image-build-scan.png` | build, non-root, no pip, healthy, Trivy image summary |
| `s17-06-local-security-gate.png` | the gate run against fresh local reports, PASSED |
| `s17-07-local-kind-deploy.png` | kind deploy, securityContext, read-only rootfs, curl |

## What I learned

- **A pipeline that runs scanners is not a security gate.** The gate is the written
  policy plus the one job that enforces it. Having it in one file meant that when I
  decided "unfixed Debian CVEs are reported but do not block", that decision is visible
  and reviewable instead of hidden in a `--ignore-unfixed` flag somewhere.
- **Fail closed.** If Trivy's database download had failed, a "scanner exits 1 on
  findings" pipeline would have shown red for the wrong reason, and a "continue on
  error" pipeline would have shown green. My gate treats a missing report as a block.
- **Scan what you ship and ship what you scanned.** Building once and passing the
  tarball between jobs, then deploying by digest, closes the gap where the pushed image
  differs from the scanned one.
- **Secret scanning has to look at history,** and history includes mistakes you have
  already "fixed". The revert run proved it.
- **Different tools see different layers.** urllib3 1.26.5 was caught by pip-audit,
  Trivy fs and Trivy image; the fake key by Gitleaks, Trivy fs and Trivy image; the
  `shell=True` only by Bandit and Semgrep; the Debian CVEs only by the image scan.
- **Pin things that can change under you:** base image by digest, all Python packages,
  scanner versions, and third-party actions by commit SHA (`docker/*`, `helm/kind-action`).
  GitHub-owned actions use their major tag.

## Problems I hit

1. **gunicorn 26 on a read-only filesystem.** My first container run logged
   `Control server error: [Errno 30] Read-only file system: '/home/app'`. gunicorn 26
   creates a control socket under `$HOME/.gunicorn/` by default. I do not use it, so I
   added `--no-control-socket` (found with `gunicorn --help | grep control`) instead of
   making another path writable.
2. **Trivy flagged pip's vendored libraries.** The first image scan had 4 fixable HIGH
   findings in `msgpack 1.1.2`, `setuptools 70.3.0` and `urllib3 2.7.0`, none of which I
   install. They were pip's own vendored copies (pip is in the base image and in every
   venv). pip is not needed at runtime, so the Dockerfile uninstalls it from both
   places; the next scan had 0 fixable HIGH/CRITICAL.
3. **Local Python was 3.9.** macOS's `python3` is 3.9.6, which could not install the
   pinned versions. I created the venv with `uv venv --python 3.13` instead.
4. **GitHub returned `Internal Server Error` on push** three times in a row (even for a
   push with no new objects, and githubstatus.com said all systems operational). I
   retried every 30 seconds and the fourth attempt went through.
5. **Gitleaks scanned other branches** (`git log --all`), see the gate demo section.
6. **`AKIAIOSFODNN7EXAMPLE` is not detected** by Gitleaks (its AWS rule allowlists the
   `EXAMPLE` suffix), so the obvious demo key would have shown a false "pass".
7. **Job logs need sign-in.** Logged-out Playwright only gets "Sign in to view logs" on
   job pages, so the run overview and artifact screenshots are real logged-out page
   captures, and the job log screenshots are rendered from the real logs fetched with
   `gh api`.
8. **`trivy convert --format table` prints `No enabled scanners found. Summary table
   will not be displayed.`** in CI, because a converted report does not remember which
   scanners ran. The detailed tables still print, and the JSON (which the gate reads)
   is complete, so I left it.
