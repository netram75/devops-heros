# Final project: CI/CD, DevSecOps and Helm

Student: Netram, Enrollment No 24BCS10329
Branch: `session21-final`
Workflow GitHub runs: [`.github/workflows/session21-final.yml`](../../../.github/workflows/session21-final.yml)
(an identical copy sits in [`../.github/workflows/session21-final.yml`](../.github/workflows/session21-final.yml) because the course asks for that folder layout; GitHub only runs workflows from the repository root, so that copy is documentation only).

This part of the final project takes one small Flask app from a commit to a running Helm release, and refuses to ship it if any security scanner finds something that crosses my gate policy. I reused the release-checklist app from Session 17 on purpose. It already had 100 percent test coverage and a hardened Dockerfile, so I could spend the final project time on the pipeline, the Helm chart and the deployment instead of on app code.

## Folder layout

| Path | What is in it |
|---|---|
| `application/` | Flask app (`app/main.py`), unit tests, pinned `requirements.txt`, `requirements-dev.txt`, `pytest.ini` |
| `docker/` | `Dockerfile` (multi-stage, pinned base by digest, non-root UID 10001, HEALTHCHECK) and `Dockerfile.dockerignore` |
| `security/` | Bandit, Semgrep, Trivy and Gitleaks configs, `gate-policy.json`, `security_gate.py` |
| `helm/final-app/` | Helm chart: Deployment, Service, ConfigMap, Secret, Ingress, HPA, PVC, ServiceAccount, `values.yaml`, `values-prod.yaml` |
| `docs/` | this file |
| `screenshots/cicd-*.png` | evidence referenced below |

## Pipeline

```
 push to session21-final / main (only when application/, docker/, security/, helm/ or the workflow change)
 or workflow_dispatch
        |
        v
 [1 Build + unit test] -> [2 SAST] -> [3 SCA] -> [4 Secret scan] -> [5 Docker build] -> [6 Image scan]
   compileall, pytest      Bandit     pip-audit    Gitleaks over       buildx, image       Trivy image
   coverage >= 90%         Semgrep    Trivy fs     history of HEAD     saved as tarball    (OS + Python pkgs)
        |                     |           |             |                 + smoke run            |
        |                     +-----------+------+------+------------------------------------------+
        |                                        |
        v                                        v
   test-results artifact                 [7 Security gate]  reads every report-* artifact,
                                                 |          applies gate-policy.json, fails closed
                                                 v
                                     [8 Push to GHCR]  the exact tarball that was scanned,
                                                 |     tagged :<git sha> and :latest
                                                 v
                                     [9 Helm deploy to kind]  helm lint, helm upgrade --install --wait,
                                                              verify pods, smoke test via port-forward
```

Every job lists the previous one in `needs`, so a failure anywhere stops everything after it. The gate also lists all four scan jobs in `needs` so it cannot run on a partial set of reports.

Why the jobs are split instead of one big script: each stage gets its own green or red tick on the run page, its own log, and its own artifact. When something fails I can see at a glance whether it was a test, a scanner or the deploy.

Other choices in the YAML and why:

- `paths:` filter. The repo holds every session of the course. Without the filter, a typo fix in Session 3 notes would rebuild and redeploy this app.
- `concurrency` with `cancel-in-progress: true`. If I push twice in a row, the first run is already stale, so there is no point in finishing it and pushing an older image.
- `permissions: contents: read` at the top, and only `push-image` gets `packages: write`. The deploy job only gets `packages: read` for pulling. Least privilege for the `GITHUB_TOKEN`.
- Action versions: `actions/*` use the same major tags as my Session 16 and 17 workflows (`checkout@v7`, `setup-python@v7`, `upload-artifact@v7`, `download-artifact@v8`). Third-party actions (`docker/setup-buildx-action`, `docker/build-push-action`, `docker/login-action`, `helm/kind-action`) are pinned to the same full commit SHAs I used in Session 17, so a moved tag upstream cannot change what runs.
- Scanner versions are pinned in `env:` (Trivy 0.75.0, Semgrep 1.179.0, Gitleaks 8.30.1 with checksum check, Bandit 1.9.4, pip-audit 2.10.1). A scanner that silently upgrades can change the result of the gate without any change in my code.

## Stage by stage

Green run: [https://github.com/netram75/devops-heros/actions/runs/37661957163](https://github.com/netram75/devops-heros/actions/runs/37661957163) on commit `8ecf8c5` of `session21-final`. All 9 jobs succeeded, total duration 5m 35s, 9 artifacts (screenshots `cicd-10-run-green-overview.png` and `cicd-11-run-artifacts.png`).

The log excerpts below are copied from the real job logs of that run (fetched with the GitHub API after the run finished, timestamps and pip download noise removed).

### 1. Build and unit test ([job](https://github.com/netram75/devops-heros/actions/runs/37661957163/job/112931453977), YAML job `build-test`)

`python -m compileall` fails fast on a syntax error before any test runs. pytest then runs with `--cov-fail-under=90`, so falling coverage breaks the build too. JUnit XML and coverage XML go into the `test-results` artifact.

```
collected 17 items
tests/test_app.py .................                                      [100%]
TOTAL                60      0   100%
Required test coverage of 90% reached. Total coverage: 100.00%
============================== 17 passed in 0.38s ==============================
```

### 2. SAST ([job](https://github.com/netram75/devops-heros/actions/runs/37661957163/job/112931627245), YAML job `sast`)

Bandit is the Python-specific checker; Semgrep adds the public `p/python` and `p/flask` rule packs plus my own three rules in `security/semgrep-rules.yml` (Flask debug mode, `shell=True`, hard-coded credentials). Two tools because they catch different things: Bandit knows Python APIs, Semgrep matches patterns I can write myself.

```
Test results:
	No issues identified.
Code scanned:
	Total lines of code: 76
...
Ran 154 rules on 2 files: 0 findings.
```

### 3. SCA ([job](https://github.com/netram75/devops-heros/actions/runs/37661957163/job/112931983560), YAML job `sca`)

pip-audit checks every pinned package in `application/requirements.txt` against the PyPI advisory database. Every transitive dependency is pinned in that file, because pip-audit `-r` only sees what is listed. Trivy fs scans the same folder for vulnerable packages, Dockerfile and Helm misconfiguration (Trivy renders the chart itself) and secrets.

```
No known vulnerabilities found
helm/final-app/templates/deployment.yaml (helm)
Failures: 3 (UNKNOWN: 0, LOW: 1, MEDIUM: 2, HIGH: 0, CRITICAL: 0)
KSV-0013 (MEDIUM): Container 'final-app' of Deployment 'final-app' should specify an image tag
KSV-0110 (LOW): deployment final-app in default namespace should set metadata.namespace to a non-default namespace
KSV-0125 (MEDIUM): Container final-app in deployment final-app (namespace: default) uses an image from an untrusted registry.
```

These 3 do not block (policy blocks HIGH and CRITICAL only) and I agree with that: the scanner renders the chart with default values, so it sees `tag: latest` and the `default` namespace. In the pipeline the chart is always installed with `--set image.tag=<git sha>` into the `final-app` namespace, so the first two do not apply to what actually runs. KSV-0125 is about an allowlist of registries, which I do not have for GHCR.

### 4. Secret scan ([job](https://github.com/netram75/devops-heros/actions/runs/37661957163/job/112932383858), YAML job `secret-scan`)

`fetch-depth: 0` gives the whole history. Gitleaks scans `--full-history HEAD`, so a secret that was committed and later "deleted" is still caught, but other branches are not mixed in. The binary is checksum-verified before it runs.

```
INF 41 commits scanned.
INF scanned ~2037564 bytes (2.04 MB) in 584ms
INF no leaks found
findings: 0
```

### 5. Docker build ([job](https://github.com/netram75/devops-heros/actions/runs/37661957163/job/112932474330), YAML job `docker-build`)

Buildx builds `docker/Dockerfile` with the project folder as context and writes the image to a tarball instead of pushing it. The same tarball is scanned in job 6 and pushed in job 8, so what reaches GHCR is byte for byte what was scanned. Before uploading it, the job runs the container with `--read-only` and waits for the HEALTHCHECK to report healthy.

```
Loaded image: ghcr.io/netram75/devops-heros-final:8ecf8c5cc10d97173f4a273d37a1475049711247
user=10001:10001 healthcheck=["CMD","python","-c","import urllib.request,sys; ..."]
container health: healthy
{"commit":"8ecf8c5cc10d97173f4a273d37a1475049711247","environment":"local","pod":"n/a","secret_configured":false,"service":"release-checklist","version":"1.0.1"}
uid=10001(app) gid=10001(app) groups=10001(app)
```

### 6. Image scan ([job](https://github.com/netram75/devops-heros/actions/runs/37661957163/job/112932812910), YAML job `image-scan`)

Trivy scans the OS packages and the Python packages inside the image tarball, plus secrets in every layer. It found 165 vulnerabilities in total; the 44 HIGH ones are all in Debian 13.7 base packages (util-linux, libacl1 and others) with status `affected` and an empty Fixed Version column, meaning Debian has not released a fix yet. My policy reports those but does not block them, because no rebuild can remove them today. The moment Debian ships a fix, the same CVE turns into a blocking finding.

### 7. Security gate ([job](https://github.com/netram75/devops-heros/actions/runs/37661957163/job/112933070947), YAML job `security-gate`)

```
SECURITY GATE
stage    check        report            findings  blocking  result
-------  -----------  ----------------  --------  --------  ------
SAST     bandit       bandit.json       0         0         pass
SAST     semgrep      semgrep.json      0         0         pass
SCA      pip_audit    pip-audit.json    0         0         pass
SCA      trivy_fs     trivy-fs.json     3         0         pass
Secrets  gitleaks     gitleaks.json     0         0         pass
Image    trivy_image  trivy-image.json  165       0         pass
GATE PASSED - release allowed
```

### 8. Push to GHCR ([job](https://github.com/netram75/devops-heros/actions/runs/37661957163/job/112933140103), YAML job `push-image`)

Only this job has `packages: write`. It loads the scanned tarball, tags it `:<sha>` and `:latest`, and pushes both. The `:sha` tag is what gets deployed (immutable and traceable to a commit); `:latest` is only a convenience pointer.

```
8ecf8c5cc10d97173f4a273d37a1475049711247: digest: sha256:e340e943da97219ffe7534c0e4ea1e8a723a09a707c9822029772f057bea6ad2 size: 1992
latest: digest: sha256:e340e943da97219ffe7534c0e4ea1e8a723a09a707c9822029772f057bea6ad2 size: 1992
```

Both tags point to the same digest, which shows `:latest` is the very image that passed the gate.

### 9. Helm deploy to kind + smoke test ([job](https://github.com/netram75/devops-heros/actions/runs/37661957163/job/112933326334), YAML job `deploy`)

kind gives me a real Kubernetes API inside the runner, so the chart is installed for real on every run instead of only being templated. GHCR packages are private by default, so the job creates a `docker-registry` Secret from the short-lived `GITHUB_TOKEN` and passes it to the chart as `imagePullSecrets`. `helm upgrade --install --wait` only returns once every pod is Ready, so a failing readiness probe fails the job.

```
Release "final-app" does not exist. Installing it now.
STATUS: deployed
REVISION: 1
deployment.apps/final-app   2/2     2            2           11s   final-app    ghcr.io/netram75/devops-heros-final:8ecf8c5cc10d97173f4a273d37a1475049711247
horizontalpodautoscaler.autoscaling/final-app   Deployment/final-app   cpu: <unknown>/70%   2         5
uid=10001(app) gid=10001(app) groups=10001(app)
touch: cannot touch '/should-fail': Read-only file system
+ curl -sf localhost:8080/healthz
{"status":"ok"}
+ curl -sf localhost:8080/readyz
{"status":"ready"}
{"commit":"8ecf8c5cc10d97173f4a273d37a1475049711247","environment":"dev","pod":"final-app-8684bcf85b-8rzjt","secret_configured":true,"service":"release-checklist",...}
+ grep -q '"commit":"8ecf8c5cc10d97173f4a273d37a1475049711247"'
+ grep -q '"environment":"dev"'
+ grep -q '"secret_configured":true'
{"done":false,"id":1,"title":"deployed by helm"}
+ test 404 = 404
```

The smoke test does not just check for HTTP 200. It checks that the running pod reports the exact commit that was built, that `APP_ENV=dev` arrived from the ConfigMap and that the Secret was injected. The HPA shows `cpu: <unknown>` because kind has no metrics-server; the object itself is created and targets the Deployment.

Artifacts of the run: `test-results`, `report-sast`, `report-sca`, `report-secrets`, `report-image`, `gate-result`, `image-tar` (3 day retention), `deploy-evidence` (rendered manifest, `helm status`, `kubectl get all`, describe, events, pod logs), plus the buildx build record.

## Security gate policy

Scanners run in report mode (`--exit-zero`, `exit-code: 0`, `|| true` on pip-audit). They never fail the build themselves. The single decision point is [`security/security_gate.py`](../security/security_gate.py) with [`security/gate-policy.json`](../security/gate-policy.json). I like this split because the policy lives in one JSON file that I can review in a pull request, instead of being spread over ten `--exit-code` flags.

| Check | Report | Blocks the release when |
|---|---|---|
| Bandit | `bandit.json` | any HIGH severity finding with MEDIUM or higher confidence |
| Semgrep | `semgrep.json` | any ERROR severity finding (my project rules for debug mode, `shell=True`, hard-coded credentials are ERROR) |
| pip-audit | `pip-audit.json` | any known vulnerability that already has a fixed version |
| Trivy fs | `trivy-fs.json` | HIGH or CRITICAL vulnerability, HIGH or CRITICAL misconfiguration in the Dockerfile or Helm chart, or any secret |
| Gitleaks | `gitleaks.json` | more than 0 findings |
| Trivy image | `trivy-image.json` | HIGH or CRITICAL vulnerability that has a fix, or any secret in an image layer |

Fail closed: if a report is missing or cannot be parsed (for example a scanner crashed), that row counts as BLOCK. A broken scanner can never make the gate green.

Unfixed base image CVEs in the image scan are reported but do not block, because rebuilding cannot remove them until Debian ships a fix. Everything that has a fix blocks.

The Gitleaks allowlist ([`security/gitleaks.toml`](../security/gitleaks.toml)) is the same narrow one I built in Session 17: course material with demo Kubernetes Secrets (path + rule), and the one fake AWS-format key I committed on purpose to prove the gate works (commit + path + rule, all three must match). I scan `--full-history HEAD`, not `--all`, so only the history of the commit being built counts, not unrelated branches.

## Helm chart: `helm/final-app`

The chart turns the plain manifests from earlier sessions into one versioned, values-driven package.

| Template | What it does and why |
|---|---|
| `deployment.yaml` | Liveness probe on `/healthz`, readiness probe on `/readyz` (separate so a future dependency check only affects readiness). Requests and limits from values. Pod `securityContext`: `runAsNonRoot`, UID/GID 10001, `seccompProfile: RuntimeDefault`. Container: read-only root filesystem, no privilege escalation, all capabilities dropped. `/tmp` is an `emptyDir` because gunicorn needs one writable folder. `checksum/config` and `checksum/secret` annotations so a changed ConfigMap or Secret rolls the pods. `maxUnavailable: 0` so a rollout never drops below the current capacity. |
| `service.yaml` | ClusterIP on port 80 to the named container port `http` (8080). |
| `configmap.yaml` | Every key under `config:` (APP_ENV, LOG_LEVEL), loaded into the pod with `envFrom`. |
| `secret.yaml` | `API_TOKEN` from `secret.apiToken`, base64 encoded by Helm, wrapped in `required` so an empty value fails at render time instead of starting a pod with no token. The default in `values.yaml` is a clearly fake demo value; the app only reports `secret_configured: true`, it never prints the token. |
| `ingress.yaml` | Disabled by default (kind has no ingress controller). `ingressClassName: nginx`, hosts and TLS from values. Enabled in `values-prod.yaml`. |
| `hpa.yaml` | `autoscaling/v2` HPA on CPU. When it is enabled the Deployment leaves out `replicas`, so Helm and the HPA do not fight over the replica count. |
| `pvc.yaml` | Optional PVC mounted at `/data`. Off by default because the app keeps its data in memory; on in prod values. |
| `serviceaccount.yaml` | Own ServiceAccount with `automountServiceAccountToken: false`; the app never talks to the Kubernetes API. |

`values.yaml` is the dev / CI default (2 replicas, HPA 2 to 5, APP_ENV=dev, ingress off, PVC off). `values-prod.yaml` only overrides what changes in production: 3 replicas, HPA 3 to 10 at 60 percent CPU, bigger requests and limits, `pullPolicy: Always`, APP_ENV=prod, ingress on with TLS, a 5Gi PVC, and a placeholder token that must be replaced at install time.

### Real `helm lint` and `helm template` output

Run locally with Helm v3.22.0 from `session21-python/final-devops-project/helm`:

```
$ helm version --short
v3.22.0+g144ca65

$ helm lint final-app
==> Linting final-app
[INFO] Chart.yaml: icon is recommended

1 chart(s) linted, 0 chart(s) failed

$ helm lint final-app -f final-app/values-prod.yaml
==> Linting final-app
[INFO] Chart.yaml: icon is recommended

1 chart(s) linted, 0 chart(s) failed

$ helm lint final-app --strict
==> Linting final-app
[INFO] Chart.yaml: icon is recommended

1 chart(s) linted, 0 chart(s) failed

$ helm template final-app final-app -f final-app/values-prod.yaml --set image.tag=demo | grep -E '^(kind|  name):|image:|ingressClassName|claimName|APP_ENV|minReplicas|maxReplicas|storage:'
kind: ServiceAccount
  name: final-app
kind: Secret
  name: final-app-secret
kind: ConfigMap
  name: final-app-config
  APP_ENV: "prod"
kind: PersistentVolumeClaim
  name: final-app-data
      storage: 5Gi
kind: Service
  name: final-app
kind: Deployment
  name: final-app
          image: "ghcr.io/netram75/devops-heros-final:demo"
            claimName: final-app-data
kind: HorizontalPodAutoscaler
  name: final-app
  minReplicas: 3
  maxReplicas: 10
kind: Ingress
  name: final-app
  ingressClassName: nginx

$ helm template final-app final-app -f final-app/values-prod.yaml --set secret.apiToken= 2>&1 | head -1
Error: execution error at (final-app/templates/secret.yaml:9:16): secret.apiToken is required
```

The last command shows the `required` guard: an empty token stops the render instead of producing a Secret with no value. Screenshots: `cicd-01-helm-lint.png`, `cicd-02-helm-template-dev.png`, `cicd-03-helm-template-prod.png`.

The pipeline runs the same `helm lint` (both value files) and `helm template` in job 9 before installing, so a chart error stops the deploy before it touches the cluster.

## Screenshots

- [`cicd-01-helm-lint.png`](../screenshots/cicd-01-helm-lint.png): local `helm lint` with default and prod values, and `--strict`
- [`cicd-02-helm-template-dev.png`](../screenshots/cicd-02-helm-template-dev.png): local `helm template` with default values (6 objects, no Ingress, no PVC)
- [`cicd-03-helm-template-prod.png`](../screenshots/cicd-03-helm-template-prod.png): local `helm template` with `values-prod.yaml` (Ingress class nginx, PVC, HPA 3 to 10) and the `required` guard
- [`cicd-10-run-green-overview.png`](../screenshots/cicd-10-run-green-overview.png): run 37661957163 overview, all 9 jobs green
- [`cicd-11-run-artifacts.png`](../screenshots/cicd-11-run-artifacts.png): artifacts of that run
- [`cicd-20-job1-build-test.png`](../screenshots/cicd-20-job1-build-test.png): job 1 log: compile + 17 tests, 100% coverage
- [`cicd-21-job2-sast.png`](../screenshots/cicd-21-job2-sast.png): job 2 log: Bandit and Semgrep, 0 findings
- [`cicd-22-job3-sca.png`](../screenshots/cicd-22-job3-sca.png): job 3 log: pip-audit clean, Trivy fs 3 non-blocking chart findings
- [`cicd-23-job4-gitleaks.png`](../screenshots/cicd-23-job4-gitleaks.png): job 4 log: Gitleaks over 41 commits, no leaks
- [`cicd-24-job5-docker-build.png`](../screenshots/cicd-24-job5-docker-build.png): job 5 log: image loaded, non-root user, healthy container
- [`cicd-25-job6-image-scan.png`](../screenshots/cicd-25-job6-image-scan.png): job 6 log: Trivy image table (HIGH findings are unfixed base-image CVEs)
- [`cicd-26-job7-gate.png`](../screenshots/cicd-26-job7-gate.png): job 7 log: security gate PASSED
- [`cicd-27-job8-push-ghcr.png`](../screenshots/cicd-27-job8-push-ghcr.png): job 8 log: push of :sha and :latest with the same digest
- [`cicd-28-job9-helm-install.png`](../screenshots/cicd-28-job9-helm-install.png): job 9 log: helm lint, helm upgrade --install, release history
- [`cicd-29-job9-verify-smoke.png`](../screenshots/cicd-29-job9-verify-smoke.png): job 9 log: pods, non-root, read-only rootfs, smoke test through the Service

## How to run it yourself

```bash
cd session21-python/final-devops-project
# tests
cd application && pip install -r requirements-dev.txt && python -m pytest --cov=app && cd ..
# image (build context is the project folder)
docker build -f docker/Dockerfile -t final-app:local .
# chart
helm lint helm/final-app && helm template final-app helm/final-app -f helm/final-app/values-prod.yaml
helm upgrade --install final-app helm/final-app -n final-app --create-namespace \
  --set image.tag=<git sha from the pipeline> --set 'imagePullSecrets[0].name=ghcr-pull' --wait
```
