const express = require("express");

const app = express();
const PORT = process.env.PORT || 3000;

const page = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Hello World from Node.js</title>
<style>
  body { margin:0; font-family: system-ui, -apple-system, "Segoe UI", sans-serif;
         display:flex; align-items:center; justify-content:center; min-height:100vh;
         background:#052e16; color:#dcfce7; }
  .card { text-align:center; padding:1rem; }
  h1 { font-size:1.9rem; margin:0 0 .6rem; }
  p  { margin:.2rem 0; color:#86efac; font-size:.95rem; }
  code { background:#14532d; padding:2px 8px; border-radius:6px; color:#bbf7d0; }
</style>
</head>
<body>
  <div class="card">
    <h1>Hello World from Node.js + Express!</h1>
    <p>Served from a Docker container</p>
    <p>Image <code>node:22-alpine</code>, container port ${PORT}</p>
    <p>Netram, 24BCS10329</p>
  </div>
</body>
</html>`;

app.get("/", (req, res) => res.type("html").send(page));

// Health endpoint, used to prove the container is up without parsing HTML.
app.get("/healthz", (req, res) => res.json({ status: "ok", runtime: "node", port: PORT }));

app.listen(PORT, "0.0.0.0", () => {
  console.log(`hello-nodejs listening on port ${PORT}`);
});
