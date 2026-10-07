# syntax=docker/dockerfile:1

# ---- stage 1: install dependencies into a separate prefix ----
FROM python:3.14-slim AS deps
WORKDIR /build
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# ---- stage 2: runtime image (no pip cache, no build files, non-root) ----
FROM python:3.14-slim
ARG APP_VERSION=dev
LABEL org.opencontainers.image.source="https://github.com/netram75/devops-heros" \
      org.opencontainers.image.title="session16-calculator" \
      org.opencontainers.image.description="Session 16 CI/CD demo app (Flask + gunicorn)"
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    APP_VERSION=${APP_VERSION}

# numeric UID so Kubernetes runAsNonRoot can verify it is not root
RUN useradd --uid 10001 --no-create-home --shell /usr/sbin/nologin app
COPY --from=deps /install /usr/local
WORKDIR /srv
COPY app/ app/

USER 10001
EXPOSE 8000
HEALTHCHECK --interval=15s --timeout=3s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=2)"
# --worker-tmp-dir /dev/shm and --no-control-socket let gunicorn run with a read-only
# root filesystem (gunicorn 26 otherwise creates a control socket under $HOME)
CMD ["gunicorn", "--bind", "0.0.0.0:8000", "--workers", "2", "--worker-tmp-dir", "/dev/shm", \
     "--no-control-socket", "--access-logfile", "-", "app.main:app"]
