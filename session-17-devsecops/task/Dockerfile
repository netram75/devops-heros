# syntax=docker/dockerfile:1
# Base image pinned by tag AND digest (multi-arch index), so a rebuild next week
# uses exactly the same OS layer that the image scan approved.
ARG PYTHON_IMAGE=python:3.13.16-slim@sha256:bf44cdfcb76cd3b41e879bc058fc37ec5872002ccfde7fcb765e218cde0cd79c

# ---- build stage: install dependencies into an isolated virtualenv ----------
FROM ${PYTHON_IMAGE} AS build
ENV PIP_NO_CACHE_DIR=1 PIP_DISABLE_PIP_VERSION_CHECK=1
RUN python -m venv /opt/venv
COPY requirements.txt /tmp/requirements.txt
RUN /opt/venv/bin/pip install --require-virtualenv -r /tmp/requirements.txt \
 && /opt/venv/bin/pip uninstall --yes pip

# ---- runtime stage: only the venv and the app code --------------------------
FROM ${PYTHON_IMAGE}
ARG APP_VERSION=dev
ARG GIT_SHA=local
LABEL org.opencontainers.image.source="https://github.com/netram75/devops-heros" \
      org.opencontainers.image.description="Session 17 DevSecOps task app" \
      org.opencontainers.image.revision="${GIT_SHA}"

ENV PATH="/opt/venv/bin:${PATH}" \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    APP_VERSION=${APP_VERSION} \
    GIT_SHA=${GIT_SHA}

# pip is not needed at runtime. Removing it (from the venv above and from the base
# image here) also removes its vendored urllib3/msgpack/pkg_resources copies,
# which Trivy reported as fixable HIGH findings on my first scan.
# Fixed numeric UID/GID so Kubernetes runAsNonRoot can verify it without a passwd lookup.
RUN python -m pip uninstall --yes pip \
 && groupadd --system --gid 10001 app \
 && useradd --system --uid 10001 --gid app --no-create-home --shell /usr/sbin/nologin app

WORKDIR /srv
COPY --from=build /opt/venv /opt/venv
COPY --chown=root:root app ./app

USER 10001:10001
EXPOSE 8080

# No curl in the slim image, so the healthcheck uses Python's stdlib.
HEALTHCHECK --interval=15s --timeout=3s --start-period=10s --retries=3 \
  CMD ["python", "-c", "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8080/healthz', timeout=2).status == 200 else 1)"]

# gunicorn instead of the Flask dev server. Worker heartbeat files go to /tmp
# (an emptyDir in Kubernetes, because the root filesystem is read-only), and the
# gunicorn 26 control socket is switched off: by default it tries to create
# $HOME/.gunicorn/gunicorn.ctl, which fails on a read-only filesystem.
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", "--worker-tmp-dir", "/tmp", "--no-control-socket", "--access-logfile", "-", "app.main:app"]
