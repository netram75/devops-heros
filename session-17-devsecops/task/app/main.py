"""Session 17 task app: a tiny release-checklist API.

It is deliberately small. The point of the task is the pipeline around it, so the
app only needs enough real behaviour to be worth unit testing and smoke testing
after it is deployed to Kubernetes.
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

    # SECURITY GATE DEMO: registers the deliberately insecure blueprint.
    from app.diagnostics import bp as diagnostics_bp
    app.register_blueprint(diagnostics_bp)

    @app.errorhandler(404)
    def not_found(_err):
        return jsonify(error="not found"), 404

    return app


app = create_app()
