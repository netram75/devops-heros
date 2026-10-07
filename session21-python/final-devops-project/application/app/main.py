"""Session 21 final project app: a tiny release-checklist API.

This is the same app I built for Session 17, reused on purpose: it is already
unit tested and security scanned, so the final project can focus on the
pipeline, the Helm chart and the deployment around it.

Two values come from the Helm chart at runtime:
  APP_ENV   - plain setting from the ConfigMap (dev, prod, ...)
  API_TOKEN - value from the Kubernetes Secret. It is never returned; the app
              only reports whether it was injected.
"""
import os
import threading

from flask import Flask, abort, jsonify, request

MAX_TITLE_LEN = 120


def create_app():
    app = Flask(__name__)

    # In-memory store. Fine for a demo: every pod keeps its own copy.
    lock = threading.Lock()
    items = {}
    counter = {"next_id": 1}

    @app.get("/")
    def index():
        return jsonify(
            service="release-checklist",
            version=os.environ.get("APP_VERSION", "dev"),
            commit=os.environ.get("GIT_SHA", "local"),
            pod=os.environ.get("POD_NAME", "n/a"),
            environment=os.environ.get("APP_ENV", "local"),
            secret_configured=bool(os.environ.get("API_TOKEN")),
        )

    @app.get("/healthz")
    def healthz():
        # Liveness: the process is up and can answer HTTP.
        return jsonify(status="ok")

    @app.get("/readyz")
    def readyz():
        # Readiness: nothing external to check yet, but kept separate from
        # liveness so a future dependency check only goes here.
        return jsonify(status="ready")

    @app.get("/api/items")
    def list_items():
        with lock:
            data = sorted(items.values(), key=lambda i: i["id"])
        return jsonify(items=data, count=len(data))

    @app.post("/api/items")
    def add_item():
        body = request.get_json(silent=True)
        if not isinstance(body, dict):
            return jsonify(error="expected a JSON object"), 400
        title = body.get("title")
        if not isinstance(title, str) or not title.strip():
            return jsonify(error="'title' must be a non-empty string"), 400
        title = title.strip()
        if len(title) > MAX_TITLE_LEN:
            return jsonify(error=f"'title' is longer than {MAX_TITLE_LEN} characters"), 400
        with lock:
            item_id = counter["next_id"]
            counter["next_id"] += 1
            item = {"id": item_id, "title": title, "done": False}
            items[item_id] = item
        return jsonify(item), 201

    @app.get("/api/items/<int:item_id>")
    def get_item(item_id):
        with lock:
            item = items.get(item_id)
        if item is None:
            abort(404)
        return jsonify(item)

    @app.post("/api/items/<int:item_id>/done")
    def mark_done(item_id):
        with lock:
            item = items.get(item_id)
            if item is None:
                abort(404)
            item["done"] = True
        return jsonify(item)

    @app.errorhandler(404)
    def not_found(_err):
        return jsonify(error="not found"), 404

    return app


app = create_app()
