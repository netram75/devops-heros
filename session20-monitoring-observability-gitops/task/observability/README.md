# Session 20 - Task 2 - Observability

- **Name:** Netram
- **Enrollment No:** 24BCS10329

> **Status:** completed

> Documentation task. The hands-on part (kube-prometheus-stack on a local kind cluster) is the
> monitoring demo in [../README.md](../README.md). This file covers the concepts behind it.

---

## What the task asked

Understand the three major pillars of observability (metrics, logs, traces) and document what each
pillar means, why observability is required, the common tools, and Kubernetes observability.
Sections 1 to 4 below cover those four items, with "why" first because the pillars only make sense
once the problem is clear. Kubernetes metric names are the real ones; `http_*` names stand in for
whatever an application exposes.

## 1. Why observability is required

### Monitoring vs observability

The course notes frame it as two questions: monitoring asks "is the system healthy?", observability
asks "why is it behaving this way?".

| | Monitoring | Observability |
|---|---|---|
| Covers | **Known unknowns**: failures I predicted (CPU spike, error rate climbing) | **Unknown unknowns**: failures nobody predicted (one tenant, one pod version, only on retries) |
| Question | Is something wrong? | Why is it wrong, and where? |
| Output | Dashboards and threshold alerts written in advance | Ad-hoc queries across metrics, logs and traces, after the fact |
| Data needed | A few aggregated numbers | High-context data: labels, request IDs, per-request timings |

They are not competitors: the alert tells me to look, observability tells me where.

### Why it matters for microservices and Kubernetes

- **Pods are ephemeral.** A crashed pod is replaced with a new name and IP, and its logs go with it.
- **One request crosses many hops.** A latency alert on the gateway does not say which service is slow.
- **Nothing stays put.** With autoscaling and rescheduling, data must be labelled by namespace,
  deployment and pod, because "server 3" is no longer a stable thing to investigate.
- **Nodes are shared.** A noisy neighbour throttling my pod looks exactly like my code being slow.

### MTTD, MTTR, SLIs, SLOs and error budgets

Observability is judged by **MTTD** (mean time to detect) and **MTTR** (mean time to recover): good
alerts cut the first, jumping straight from alert to the guilty trace and log line cuts the second.
An **SLI** is a measured indicator ("share of checkout requests served OK in under 300 ms"), an
**SLO** is its target ("99.9% over 30 days"), and the **error budget** is what the SLO allows to fail:
0.1% of 30 days is about 43 minutes. While budget remains the team ships features; once it is spent,
reliability comes first. Alerting on budget burn rate beats raw CPU alerts: it measures what users feel.

## 2. What each pillar means

The course summary is "metrics = numbers, logs = events, traces = journey". Expanded:

| Pillar | Question it answers | Shape of the data | Cost profile |
|---|---|---|---|
| Metrics | How much? How often? Getting worse? | Numeric time series with labels | Cheap per sample, but each new label value is a new series |
| Logs | What exactly happened? | Timestamped event records (text or JSON) | Grows with traffic, expensive to index |
| Traces | Where did this request spend its time? | Tree of timed spans sharing one trace ID | Usually sampled, since every request makes many spans |

### 2.1 Metrics

A metric is a number sampled over time, identified by a name plus labels, for example
`http_requests_total{service="checkout", status="500"}`. Prometheus has four types:

| Type | Behaviour | Example | How to query it |
|---|---|---|---|
| Counter | Only goes up, resets to 0 on restart | `http_requests_total` | Always via `rate()` or `increase()`, which also handle resets |
| Gauge | Goes up and down | `container_memory_working_set_bytes` | Directly, or `avg_over_time()` |
| Histogram | Counts observations into buckets (`_bucket{le=...}`, `_sum`, `_count`) | `http_request_duration_seconds` | `histogram_quantile()`; buckets can be summed across pods |
| Summary | Quantiles computed inside the app | `go_gc_duration_seconds` | Cannot be combined across pods, because percentiles do not average |

**Labels and cardinality.** Every unique combination of label values is a separate time series:
`method` (5) x `status` (10) x `pod` (20) is 1,000 series, fine; add `user_id` for a million users
and it is a billion, and Prometheus runs out of memory. Labels are for bounded things, IDs are not.

**Pull vs push.** Prometheus pulls: it scrapes each target's `/metrics` endpoint on an interval, and
`up` drops to 0 when a scrape fails, a free health signal. Push is for things too short-lived to
scrape: batch jobs use the Pushgateway, and Prometheus 3 can accept OTLP metrics from OpenTelemetry
when its OTLP receiver is enabled. **What to measure:** RED for request-driven services (**R**ate,
**E**rrors, **D**uration) and USE for resources (**U**tilization, **S**aturation, **E**rrors).

```promql
# RED Rate: requests per second per service
sum by (service) (rate(http_requests_total[5m]))
# RED Errors: share of requests that returned 5xx
sum(rate(http_requests_total{status=~"5.."}[5m])) / sum(rate(http_requests_total[5m]))
# RED Duration: p95 latency, summing buckets across pods first, then taking the quantile
histogram_quantile(0.95, sum by (le) (rate(http_request_duration_seconds_bucket[5m])))
# USE Utilization: CPU cores used per pod (cAdvisor, built into the kubelet)
sum by (namespace, pod) (rate(container_cpu_usage_seconds_total{container!=""}[5m]))
# USE Utilization: memory working set per pod
sum by (namespace, pod) (container_memory_working_set_bytes{container!=""})
```

`container!=""` drops the pod-level cgroup series cAdvisor also exports, which would double count.
Working set beats `container_memory_usage_bytes` because the latter includes reclaimable page cache;
working set is what the kubelet uses for eviction and what `kubectl top` shows.

### 2.2 Logs

Logs are timestamped records of individual events, the detail a metric averages away. The same event,
unstructured and then structured:

```text
2026-10-07 09:14:03 ERROR payment call failed for order A-1042 after 3012ms
{"ts":"2026-10-07T09:14:03.512Z","level":"error","service":"checkout","msg":"payment call failed","order_id":"A-1042","duration_ms":3012,"trace_id":"4bf92f3577b34da6a3ce929d0e0e4736"}
```

Finding slow payments in the first needs a regex that breaks when someone rewords the message. The
second is already fields, so a query can say `duration_ms > 2000`, and `trace_id` links the line to
its trace. Anything running in a cluster should log JSON.

**Container logs in Kubernetes.** The app writes to stdout and stderr, not to files in the container.
The runtime (containerd, via CRI) captures both streams into files the kubelet manages:

- `/var/log/pods/<namespace>_<pod>_<uid>/<container>/<restart>.log`: the actual files.
- `/var/log/containers/<pod>_<namespace>_<container>-<id>.log`: symlinks with metadata in the name.

The kubelet rotates them (10 MiB x 5 files by default) and `kubectl logs` reads them through the
kubelet, so it works only while the pod exists and `--previous` reaches back one restart. Once the
pod is deleted or the node dies the logs are gone, which is the whole reason to ship them elsewhere.

**Node-level agent pattern.** One log agent per node as a DaemonSet mounts the host's `/var/log`,
tails every container file, adds pod labels from the API server and forwards: cheaper than a sidecar
per pod, and no app changes. **Grafana Alloy** (Grafana's OpenTelemetry Collector distribution) is the
recommended Loki shipper; **Fluent Bit** is a small C agent with outputs for Loki, Elasticsearch,
OpenSearch and CloudWatch. **Promtail**, the original Loki agent, reached **end of life in March 2026**.

**Loki vs Elasticsearch.** Elasticsearch (and its fork OpenSearch) builds a full-text index of every
field: any word is instantly searchable, but the index costs a lot of RAM and disk. Loki indexes only
a few labels (namespace, app, container), keeps compressed chunks in object storage and greps the
selected streams at query time: much cheaper. The cardinality rule applies to Loki labels too, so
`trace_id` stays in the line, never in a label.

```logql
# Select streams by label (all Loki indexes), then filter and parse the lines
{namespace="shop", app="checkout"} |= "payment" | json | level="error" | duration_ms > 2000
# Turn logs into a metric: error lines per second per app
sum by (app) (rate({namespace="shop"} | json | level="error" [5m]))
# Every line of one request, by trace ID
{namespace="shop"} |= "4bf92f3577b34da6a3ce929d0e0e4736"
```

### 2.3 Traces

A **trace** is the journey of one request, built from **spans**: one per unit of work (an HTTP
handler, a DB query, a call to another service), each with a start time, duration, status,
attributes and its parent's span ID. The parent links form a tree. The course example as spans:

```text
trace_id 4bf92f35...   (one checkout request, 820 ms end to end)
+-- GET /checkout          api-gateway       820 ms   root span
    +-- POST /orders       order-service     780 ms
        +-- POST /charge   payment-service   700 ms
            +-- INSERT txn postgres          600 ms   <- where the time went
```

A metric says "p95 is 820 ms". Only the trace says 600 ms of it is one INSERT behind payment-service.

**Context propagation.** Spans from different services join one trace because every outgoing call
carries the context, normally in the W3C Trace Context `traceparent` header:

```text
traceparent: 00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01
             version | trace ID (same for the whole request) | parent span ID | flags (01 = sampled)
```

Each service makes its span a child of the incoming span ID and passes a new header downstream. If
one service drops the header, the trace splits into unrelated halves. (Zipkin's older B3 headers do
the same job.)

**Sampling.** Keeping every span is expensive. **Head sampling** decides at the first service (e.g.
keep 10% of trace IDs) and the decision travels in the `traceparent` flag: cheap, but it randomly
throws away most rare errors. **Tail sampling** decides in the Collector after the trace completes,
keeping every trace that errored or was slow: better traces, but the Collector must buffer whole
traces and all spans of one trace must reach the same Collector instance.

**OpenTelemetry.** OTel is the vendor-neutral standard for producing telemetry: an SDK per language
(with auto-instrumentation for common HTTP and database libraries), the OTLP protocol (gRPC 4317, HTTP
4318), and the **Collector**, a pipeline of receivers, processors (Kubernetes metadata, tail sampling)
and exporters. Apps send to a Collector, not a backend, so switching backends is a config change, not
a code change. Backends: **Jaeger** (CNCF graduated; v2 is built on the OTel Collector and takes OTLP
natively, v1 reached end of life at the end of 2025), **Grafana Tempo** (cheap object storage,
TraceQL) and **Zipkin** (the original open-source tracer).

### 2.4 Correlating the pillars

Each pillar alone is weak; the value is in jumping between them. An alert fires on checkout p95
latency (**metric**). A histogram sample can carry an **exemplar**, the `trace_id` of one real request
in that bucket, which Grafana draws as a dot on the latency panel and opens as a **trace** on click
(Prometheus stores exemplars only with `--enable-feature=exemplar-storage`). The trace points at the
slow INSERT, and because every log line carries `trace_id`, Grafana's "logs for this span" link
finds the exact error in the **logs**. The glue is shared metadata: the same namespace, pod and
service labels on all three signals.

## 3. Common tools

| Pillar / role | Tool | What it does |
|---|---|---|
| Metrics | **Prometheus** (+ **node-exporter**, **kube-state-metrics**) | Scrapes targets, stores time series locally (15 days by default), PromQL, alert rules; the two exporters cover node OS stats and Kubernetes object state |
| Alerting | **Alertmanager** | Groups, deduplicates, inhibits and silences alerts, routes them to Slack, email, PagerDuty |
| Metrics, long term | **Thanos**, **Grafana Mimir** | Long retention in object storage, HA, one query view over many Prometheus servers |
| Logs | **Loki** | Label-indexed log store, LogQL |
| Logs | **ELK / OpenSearch** | Elasticsearch + Logstash + Kibana, or the OpenSearch fork with OpenSearch Dashboards; full-text search |
| Logs, shipping | **Fluent Bit** | Lightweight node agent, many outputs |
| All signals | **OpenTelemetry**, **Grafana Alloy** | Vendor-neutral SDKs, OTLP and Collector; Alloy is Grafana's Collector distribution |
| Traces | **Jaeger**, **Grafana Tempo**, **Zipkin** | Trace storage, search and waterfall views |
| Visualisation | **Grafana** | Dashboards and Explore over all of the above, links between signals |
| SaaS | **Datadog**, **New Relic**, **AWS CloudWatch**, **Grafana Cloud** | Managed backends: nothing to run, cost grows with data volume |

### How the tools fit together

```text
 SOURCE                       COLLECT                               STORE                SEE / ACT
 app /metrics endpoint  <---  Prometheus scrape (pull), targets --> Prometheus TSDB --+
 node-exporter, kube-state-   from ServiceMonitor / PodMonitor      (Thanos / Mimir   |
 metrics, kubelet/cAdvisor                                           for long term)   |
                                                                                      +--> Grafana
 app stdout / stderr  ----->  kubelet writes /var/log/pods,                           |    dashboards,
                              Alloy or Fluent Bit (DaemonSet) ----> Loki -------------+    Explore,
                                                                                      |    jumps between
 app OTel SDK spans --OTLP->  OpenTelemetry Collector ------------> Tempo / Jaeger ---+    pillars
                              (k8s metadata, tail sampling)

 Prometheus alert rules --firing--> Alertmanager (group, dedupe, silence) --> Slack / email / PagerDuty
```

Metrics are pulled, logs are tailed from files, traces are pushed. The monitoring demo in
[../README.md](../README.md) covers the metrics row and Alertmanager; Loki and Tempo would plug in beside it.

## 4. Kubernetes observability

### Where cluster metrics come from

| Source | Runs as | Measures | Example metrics |
|---|---|---|---|
| cAdvisor | Built into the kubelet (`/metrics/cadvisor`) | Real CPU, memory, network, disk per container | `container_cpu_usage_seconds_total`, `container_memory_working_set_bytes` |
| kubelet | Node agent (`/metrics`, `/metrics/probes`) | The kubelet itself, probe results | `kubelet_running_pods`, `prober_probe_total` |
| node-exporter | DaemonSet | The node's OS and hardware | `node_cpu_seconds_total`, `node_filesystem_avail_bytes` |
| kube-state-metrics | Deployment, watches the API server | Desired vs actual state of objects, not usage | `kube_deployment_status_replicas_available`, `kube_pod_container_status_restarts_total` |
| Control plane | Static pods on control-plane nodes (or run by the cloud provider) | API server, etcd, scheduler and controller-manager health | `apiserver_request_duration_seconds`, `etcd_server_has_leader`, `scheduler_pending_pods` |
| metrics-server | Deployment | Latest CPU and memory only | Served via the Metrics API, not to Prometheus |

The split that clicked for me: cAdvisor says how much a pod **uses**, kube-state-metrics says what
Kubernetes **thinks** of it (3 of 5 replicas available, 7 restarts), node-exporter says how the
**machine** is doing. On kubeadm-style clusters, kind included, the scheduler, controller-manager
and etcd bind their metrics ports to `127.0.0.1` by default, so an in-cluster Prometheus cannot
reach them until that is changed. Managed clusters (EKS, GKE, AKS) expose only part of the control plane.

### metrics-server vs Prometheus

**metrics-server** scrapes the kubelet's `/metrics/resource` endpoint (every 15 s by default), keeps
only the latest CPU and memory per pod and node in memory, and serves them through the Metrics API
(`metrics.k8s.io`), which is what `kubectl top` and the HorizontalPodAutoscaler read. No history, no
PromQL, and its own README says not to use it for monitoring. They are separate pipelines:
kube-prometheus-stack does not install metrics-server and kind does not ship it, so full Grafana
dashboards and a failing `kubectl top` can coexist on the same cluster.

### Events

Events are the cluster's own record of what it did to objects (`Scheduled`, `FailedScheduling`,
`BackOff`, `Unhealthy`, `FailedMount`), read with `kubectl get events --sort-by=.lastTimestamp`,
`kubectl events --types=Warning` or at the bottom of `kubectl describe pod`. They are often the
fastest answer to "why is this pod not running?". The catch is retention: they live in etcd with a
TTL set by the API server's `--event-ttl` flag, **1 hour by default**, so a 3 a.m. crash has no
events left by morning. To keep them, ship them as logs, e.g. with Alloy's
`loki.source.kubernetes_events` component or kubernetes-event-exporter.

### Probes as health signals

| Probe | On failure | Where it shows up |
|---|---|---|
| Liveness | kubelet restarts the container | RESTARTS column, `kube_pod_container_status_restarts_total`, `Unhealthy` events |
| Readiness | Pod removed from the Service's endpoints, no restart | READY `0/1`, `kube_pod_status_ready{condition="false"}` |
| Startup | Holds off the other probes until the app is up, restarts it if it never passes | Restarts during startup only |

Probes are self-healing and a signal at once. A climbing restart counter is CrashLoopBackOff in
metric form, and `prober_probe_total` exposes a readiness probe that flaps without restarting anything.

### ServiceMonitor and PodMonitor

With the Prometheus Operator (which kube-prometheus-stack installs), scrape targets are Kubernetes
objects instead of lines in `prometheus.yml`. A **ServiceMonitor** selects Services by label and
scrapes their endpoints; a **PodMonitor** selects pods directly when there is no Service. The
operator turns them into Prometheus config (`PrometheusRule` does the same for alert rules).

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: checkout
  namespace: shop
  labels:
    release: monitoring              # must match the kube-prometheus-stack Helm release name
spec:
  selector:
    matchLabels: { app: checkout }   # Services with this label are scraped
  endpoints:
    - port: http-metrics             # the NAME of the Service port, not the number
      interval: 30s
```

### Logs and traces in Kubernetes

Logs follow the DaemonSet agent pattern from 2.2. For traces, the OpenTelemetry Operator runs
Collectors (per-node DaemonSet, gateway Deployment, or both) and injects auto-instrumentation through
an `Instrumentation` resource plus a pod annotation such as `instrumentation.opentelemetry.io/inject-java: "true"`,
so a service gets traces with no code change. Kubernetes traces itself too: API server and kubelet
tracing are stable since v1.34 and export OTLP.

## What I learned

- My test for monitoring vs observability: could I have written the alert in advance?
- Cardinality is the cost model for Prometheus and Loki alike. IDs go in log lines and traces, never in labels.
- `kubectl top` and Prometheus are different pipelines: one feeds autoscaling, the other monitors.
- Kubernetes forgets fast (pod logs vanish with the pod, events after an hour), so anything needed
  for a post-mortem has to be shipped off the cluster.
- The pillars pay off when linked: `trace_id` in every log line plus exemplars on latency histograms
  turn three tools into one investigation.
