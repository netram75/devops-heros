# Session 21 - Final DevOps Project

- **Name:** Netram
- **Enrollment No:** 24BCS10329

> **Status:** in progress - the sections below are being filled in from the runs

> Built on macOS (Apple Silicon) with Docker Desktop. The CI/CD pipeline runs on GitHub-hosted
> Ubuntu runners; the Kubernetes, monitoring and GitOps parts ran on minikube v1.39.0
> (Kubernetes v1.37.0); Terraform ran against LocalStack (no real AWS account).

---

## Project overview

One small Python web app taken all the way from source code to a monitored, GitOps-managed
Kubernetes deployment, using what each session of the course taught. The application itself
is deliberately simple (it is the Flask app I built and secured in Session 17) so that the
project is about the delivery path, not the app.

Everything in this folder follows the layout the task asked for:

```text
final-devops-project/
├── application/        Flask app + unit tests
├── docker/             Dockerfile (non-root, pinned base image, healthcheck)
├── kubernetes/         Deployment, Service, ConfigMap, Secret, Ingress, HPA, probes, PVC
├── helm/               Helm chart for the same app (used by the CI deploy job)
├── terraform/          AWS infrastructure (VPC, subnets, security groups, EC2, IAM, S3)
├── .github/workflows/  the CI/CD + DevSecOps pipeline (copy; GitHub runs the one at repo root)
├── security/           SAST / SCA / secret-scan / image-scan configs and the security gate
├── monitoring/         Prometheus + Grafana + alert rules for the app
├── gitops/             Argo CD Application + kustomize overlay
├── troubleshooting/    broken and fixed manifests for the final troubleshooting challenge
├── docs/               the detailed write-up for each area, with real output
└── screenshots/
```

## Architecture

```text
 Developer ──git push──> GitHub (netram75/devops-heros)
                              │
                              ▼
                 GitHub Actions: session21-final.yml
   build + unit test ─> SAST ─> SCA ─> secret scan ─> docker build ─> image scan
                                                                          │
                                                                   security gate
                                                                          │
                                       push image ─> ghcr.io/netram75/devops-heros-final
                                                                          │
                                         helm upgrade --install into a kind cluster (CI)

 Git (gitops/ overlay) ──watched by──> Argo CD ──sync / self-heal / prune──> Kubernetes
                                                                              │
     ┌───────────────────────── namespace final-app ─────────────────────────┤
     │ Ingress (nginx) ─> Service ─> Deployment (probes, limits) <─ HPA       │
     │                               ConfigMap, Secret, PVC                   │
     └────────────────────────────────────────────────────────────────────────┘
                                                                              │
             Prometheus (scrapes kubelet/cAdvisor + kube-state-metrics) ─> Grafana
                          └─> alert rules ─> Alertmanager

 Terraform ──> AWS: VPC, public + private subnets, IGW, route tables, security groups,
               EC2 node (k3s), IAM role, S3 artifacts bucket   (applied on LocalStack)
```

## Technologies used

| Area | Tools |
|---|---|
| Application | Python, Flask, pytest |
| Containers | Docker, GitHub Container Registry (GHCR) |
| Orchestration | Kubernetes (minikube locally, kind inside CI), kustomize |
| Packaging | Helm |
| CI/CD | GitHub Actions |
| DevSecOps | Bandit and Semgrep (SAST), pip-audit (SCA), Gitleaks (secrets), Trivy (image), a policy-driven security gate |
| Infrastructure as Code | Terraform, AWS provider, LocalStack |
| Monitoring | Prometheus, Grafana, Alertmanager (kube-prometheus-stack) |
| GitOps | Argo CD |

## Sections

The detailed write-ups (application and Docker setup, Kubernetes, Helm, Terraform, CI/CD, DevSecOps, monitoring, GitOps, troubleshooting) are being added under [docs/](docs/) with real output and screenshots.


## Lessons learned

To be written once all parts have run.

