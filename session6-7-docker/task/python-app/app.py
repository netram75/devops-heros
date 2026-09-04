import os

from flask import Flask

app = Flask(__name__)
PORT = int(os.environ.get("PORT", 5000))

PAGE = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Hello World from Python</title>
<style>
  body { margin:0; font-family: system-ui, -apple-system, "Segoe UI", sans-serif;
         display:flex; align-items:center; justify-content:center; min-height:100vh;
         background:#172554; color:#dbeafe; }
  .card { text-align:center; padding:1rem; }
  h1 { font-size:1.9rem; margin:0 0 .6rem; }
  p  { margin:.2rem 0; color:#93c5fd; font-size:.95rem; }
  code { background:#1e3a8a; padding:2px 8px; border-radius:6px; color:#bfdbfe; }
</style>
</head>
<body>
  <div class="card">
    <h1>Hello World from Python + Flask!</h1>
    <p>Served from a Docker container</p>
    <p>Image <code>python:3.12-slim</code>, container port %d</p>
    <p>Netram, 24BCS10329</p>
  </div>
</body>
</html>""" % PORT


@app.get("/")
def index():
    return PAGE


@app.get("/healthz")
def healthz():
    return {"status": "ok", "runtime": "python", "port": PORT}


if __name__ == "__main__":
    # 0.0.0.0, not 127.0.0.1: bound to loopback the server would only be
    # reachable from inside the container and the port mapping would appear dead.
    app.run(host="0.0.0.0", port=PORT)
