"""Small HTTP API around the calculator.

APP_VERSION is baked into the image at build time (the git commit SHA in CI), so a
curl against the running pod proves which commit is actually deployed.
API_TOKEN comes from a Kubernetes Secret in the CD job; the app only reports
whether it is set, never its value.
"""

import os
import socket

from flask import Flask, jsonify, request

from app.calculator import OPERATIONS


def create_app() -> Flask:
    app = Flask(__name__)

    @app.get("/")
    def index():
        return jsonify(
            service="session16-calculator",
            version=os.environ.get("APP_VERSION", "dev"),
            host=socket.gethostname(),
            api_token_configured=bool(os.environ.get("API_TOKEN")),
            operations=sorted(OPERATIONS),
        )

    @app.get("/health")
    def health():
        return jsonify(status="ok")

    @app.get("/api/<op>")
    def calculate(op: str):
        func = OPERATIONS.get(op)
        if func is None:
            return jsonify(error=f"unknown operation '{op}'"), 404
        a = request.args.get("a", type=float)
        b = request.args.get("b", type=float)
        if a is None or b is None:
            return jsonify(error="query parameters a and b must be numbers"), 400
        try:
            result = func(a, b)
        except ValueError as exc:
            return jsonify(error=str(exc)), 400
        return jsonify(operation=op, a=a, b=b, result=result)

    return app


app = create_app()
