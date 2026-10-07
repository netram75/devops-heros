# Session 11 - Task 2 - Kubernetes Object Comparison

- **Name:** Netram
- **Enrollment No:** 24BCS10329

> Written for Kubernetes v1.34 and later (my cluster for this session runs v1.37). I reuse the names from the course manifests (`yatri-backend`,
> `yatri-backend-service`, `web-stateful`, `node-logging-agent`) so the examples line up with the labs.

---

## Part 1: Deployment vs ReplicaSet

| Aspect | ReplicaSet | Deployment |
|---|---|---|
| **Purpose** | Keep N identical Pods running right now | Describe the version of the app I want and move to it safely |
| **Pod management** | Creates and deletes Pods directly, matched by label selector | Never touches Pods; creates and scales ReplicaSets, which manage the Pods |
| **Scaling** | `spec.replicas`, reconciled against a count of matching Pods | `spec.replicas`, passed down to the current ReplicaSet |
| **Rolling updates** | None: a template edit only affects Pods created later | Built in: `RollingUpdate` or `Recreate`, plus pause, resume, history and undo |
| **Relationship** | Usually owned by a Deployment | Owns one ReplicaSet per Pod template revision |

### Purpose

A ReplicaSet answers one question in a loop: "how many Pods match my selector, and is that the
number I was asked for?" Too few, it creates Pods; too many, it deletes some. That is the whole
job, and it has no idea which version of the app is running.

A Deployment sits one level up and manages change over time: which Pod template is current, how
to move from old to new without downtime, and how to go back. It does that by creating and scaling
ReplicaSets, never Pods. A hand-made ReplicaSet gives me self-healing but no update features.

### Pod management

The ReplicaSet controller is purely label based, and that has two consequences I did not expect:

- **It never updates existing Pods.** If I change the image in a bare ReplicaSet's template, the
  three running Pods keep the old image forever. Only Pods created later (after I delete one, or
  scale up) get the new template. The ReplicaSet is satisfied as long as the count is right.
- **It adopts orphans.** Any Pod that matches the selector and has no controller ownerReference
  gets adopted and counted. If I start a bare Pod labelled `app: yatri-backend` next to
  `yatri-backend-rs` (`replicas: 3`), the ReplicaSet now sees four Pods and deletes one, which
  may well be my hand-made Pod.

A Deployment only decides how many replicas each of its ReplicaSets should have; the ReplicaSet
controller does the actual Pod work above.

### Scaling

Both have `spec.replicas` and both work with `kubectl scale` and a HorizontalPodAutoscaler.
Scaling a Deployment does not create a new ReplicaSet, because the template has not changed; it
only changes `replicas` on the current one. Mid-rollout, the extra replicas are split across old
and new ReplicaSets in proportion to their size (proportional scaling).

### Rolling updates

A ReplicaSet cannot do one. A Deployment does it by running two ReplicaSets side by side:

1. I change anything inside `spec.template` (image, env, labels). Changing `replicas` does not count.
2. The Deployment hashes the new template and creates a new ReplicaSet `yatri-backend-<new-hash>`.
3. It scales the new ReplicaSet up and the old one down in steps, bounded by two numbers:
   - `maxSurge`: how many Pods above `replicas` may exist during the update (default 25%, rounded up).
   - `maxUnavailable`: how many Pods below `replicas` may be unavailable (default 25%, rounded down).
4. A new Pod only counts as available once it is Ready (and has stayed Ready for
   `minReadySeconds`), so a broken image stalls the rollout instead of replacing every healthy Pod.
   After `progressDeadlineSeconds` (default 600) the Deployment marks the `Progressing` condition
   `False` with reason `ProgressDeadlineExceeded`. It does not roll back on its own.

With the course's `deployment-v1.yaml` (3 replicas, `maxSurge: 1`, `maxUnavailable: 1`) that
means at most 4 Pods exist and at least 2 are available at every moment of the change.

```yaml
spec:
  replicas: 3
  revisionHistoryLimit: 10      # old ReplicaSets kept for rollback (10 is the default)
  strategy:
    type: RollingUpdate         # the alternative is Recreate: stop all old Pods, then start new ones
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 1
```

The old ReplicaSet is not deleted at the end; it is scaled to 0 and kept, and those zero-replica
ReplicaSets *are* the rollout history. `kubectl rollout undo` copies an old template back into the
Deployment, and since the hash matches, that same old ReplicaSet is scaled back up. Setting
`revisionHistoryLimit` to 0 makes undo impossible.

### Relationship between Deployment and ReplicaSet

```text
Deployment yatri-backend
  |  (ownerReferences on each child point up to the parent, controller: true)
  +-- ReplicaSet yatri-backend-<hash-2>   replicas: 3   <- current template
  |     +-- Pod yatri-backend-<hash-2>-<random>   (x3)
  +-- ReplicaSet yatri-backend-<hash-1>   replicas: 0   <- previous revision, kept for undo
```

Two pieces of metadata hold this together:

- **`ownerReferences`**: every ReplicaSet carries a reference to its Deployment, and every Pod one
  to its ReplicaSet, with `controller: true`. The garbage collector follows these links, so
  deleting the Deployment cascades to its ReplicaSets and then to their Pods.
- **The `pod-template-hash` label**: the Deployment controller adds this label (a hash of the Pod
  template) to each ReplicaSet's selector and Pod template, so every Pod carries it too. Without
  it, the old and new ReplicaSets would both match `app: yatri-backend` and fight over each
  other's Pods during a rollout. With it, each ReplicaSet only sees its own generation.

### How to see this myself

```bash
kubectl get deploy,rs,pods -l app=yatri-backend
kubectl get rs -l app=yatri-backend -o wide                       # SELECTOR column includes pod-template-hash
kubectl get pod <pod-name> -o jsonpath='{.metadata.ownerReferences}'   # points at the ReplicaSet
kubectl get rs <rs-name> -o jsonpath='{.metadata.ownerReferences}'     # points at the Deployment
kubectl set image deployment/yatri-backend backend=python:3.12-alpine
kubectl rollout status deployment/yatri-backend
kubectl rollout history deployment/yatri-backend
kubectl rollout undo deployment/yatri-backend --to-revision=1
```

---

## Part 2: Deployment vs DaemonSet vs StatefulSet

All three are `apps/v1` controllers that build Pods from a `template`. What differs is the promise
each one makes about its Pods: Deployment Pods are interchangeable, DaemonSet Pods are tied to
nodes, and StatefulSet Pods each have an identity of their own.

| | Deployment | DaemonSet | StatefulSet |
|---|---|---|---|
| **Use cases** | Stateless apps where any replica can serve any request | Node-level agents that must run on every node (or every matching node) | Clustered, stateful software where each member needs its own identity and data |
| **Pod creation** | Through a ReplicaSet, all at once, random names (`yatri-backend-<hash>-<random>`) | Directly, one Pod per eligible node, created as soon as a node joins | Directly, ordinal names (`web-stateful-0`, `-1`, `-2`), one at a time in order by default |
| **Scaling** | `replicas` field, `kubectl scale`, HPA | No `replicas` field; follows the node count, narrowed by `nodeSelector` or affinity | `replicas` field; scale-up adds the next ordinal, scale-down removes the highest first |
| **Networking** | Pods are anonymous, reached through a normal ClusterIP Service | Often `hostNetwork` or `hostPort` so the agent is reachable on the node IP; a Service is optional | A headless Service (named in `serviceName`) gives every Pod its own stable DNS name |
| **Storage** | Every replica mounts the same volumes; a single ReadWriteOnce PVC only works if all replicas land on one node | Usually `hostPath`, to read the node's own logs, metrics or sockets | `volumeClaimTemplates`: one PVC per Pod, re-attached to the same ordinal, kept after scale-down |
| **Updates** | `RollingUpdate` (surge/unavailable) or `Recreate` | `RollingUpdate` (`maxUnavailable` default 1, `maxSurge` default 0) or `OnDelete` | `RollingUpdate` in reverse ordinal order (optional `partition`) or `OnDelete` |
| **Examples** | nginx, the `yatri-backend` API, frontends, queue workers | kube-proxy, CNI agents (Calico, Cilium), Fluent Bit, Prometheus node-exporter | MySQL, PostgreSQL, MongoDB, Kafka, ZooKeeper, etcd, Elasticsearch |

### Pod creation, in more detail

**DaemonSet.** The DaemonSet controller does not place Pods itself. For each eligible node it
creates a Pod with a required node affinity term pinned to that node's name
(`matchFields: metadata.name`) and the default scheduler binds it. That is why there is no
`replicas` field: the node list *is* the replica count. The controller also adds tolerations for
`node.kubernetes.io/not-ready`, `unreachable`, `disk-pressure`, `memory-pressure`, `pid-pressure`
and `unschedulable`, so an agent keeps running on a node that is struggling or cordoned, which is
exactly when I want my log collector. It does not tolerate the control-plane taint by default, so
to cover control-plane nodes too I would add:

```yaml
spec:
  template:
    spec:
      tolerations:
        - key: node-role.kubernetes.io/control-plane
          operator: Exists
          effect: NoSchedule
      nodeSelector:
        kubernetes.io/os: linux        # restrict the "every node" set to Linux nodes
```

**StatefulSet.** Pods are named `<statefulset>-<ordinal>`. With the default
`podManagementPolicy: OrderedReady`, `web-stateful-1` is not created until `web-stateful-0` is
Running and Ready, and scale-down goes from the highest ordinal down, waiting for each Pod to
terminate fully (`podManagementPolicy: Parallel` drops this for scaling). That ordering matters
when the first database member must be up before others join. A replacement StatefulSet Pod gets
the same name, DNS record and PVC; only the IP changes. A Deployment replacement shares nothing.

### Networking, in more detail

A headless Service is a Service with `clusterIP: None` (the course's `05-headless/service.yaml`).
It gets no virtual IP; its DNS name returns the IPs of the ready Pods directly. The StatefulSet
sets each Pod's `hostname` to its own name and `subdomain` to `serviceName`, and that gives every
Pod a DNS record of its own:

```text
<pod-name>.<serviceName>.<namespace>.svc.cluster.local  ->  web-stateful-0.web-service-headless.default.svc.cluster.local
```

This is how a Kafka broker or MySQL replica reaches one specific peer ("member 0") instead of
whichever Pod a load balancer picks. The StatefulSet does not create this Service; I have to.

### Storage, in more detail

```yaml
spec:
  serviceName: web-service-headless
  replicas: 3
  template:
    spec:
      containers:
        - name: nginx-stateful
          image: nginx:1.25-alpine
          volumeMounts:
            - name: data
              mountPath: /usr/share/nginx/html
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 1Gi
```

This produces PVCs named `<template>-<statefulset>-<ordinal>`: `data-web-stateful-0`,
`data-web-stateful-1`, `data-web-stateful-2`. If I scale down to 1, Pods 1 and 2 go away but their
PVCs stay; scaling back to 3 re-attaches the same data to the same ordinals. A database wants
exactly that. `persistentVolumeClaimRetentionPolicy` (GA since v1.32) can switch `whenScaled` or
`whenDeleted` to `Delete`; both default to `Retain`, so deleting a StatefulSet never silently
deletes data.

### How to see this myself

```bash
kubectl get daemonsets -n kube-system                     # kube-proxy and the CNI agent usually live here
kubectl get pods -l app=node-logging-agent -o wide        # one Pod per node, check the NODE column
kubectl get pod <ds-pod> -o jsonpath='{.spec.affinity.nodeAffinity}'
kubectl get pods -l app=web-headless -w                   # watch -0, -1, -2 appear in order
kubectl get pvc                                           # data-web-stateful-N once volumeClaimTemplates is added
kubectl run dns-check --rm -it --image=busybox:1.36 --restart=Never -- \
  nslookup web-stateful-0.web-service-headless
```

---

## Part 3: ReplicaSet vs Service

Both use a label selector, often the same one (`app: yatri-backend`), but they do opposite jobs:
a ReplicaSet makes Pods exist, a Service makes them reachable.

| | ReplicaSet | Service |
|---|---|---|
| Question it answers | "Are there N Pods?" | "Where should this request go?" |
| Uses its selector to | Count Pods, then create or delete them | Build the list of backend IPs |
| Creates Pods | Yes | Never |
| Stable address | No | Yes: a ClusterIP and a DNS name |
| Load balancing | No | Yes, across ready endpoints |
| Readiness | Counts every matching Pod, ready or not | Sends normal traffic only to Pods that are Ready |

### ReplicaSet responsibility

Keep `replicas` Pods matching its selector alive. When a node dies or a Pod is deleted, it
creates a replacement with a new name and a new IP, possibly on a different node. It has no
networking role at all: it neither knows nor cares whether anything can reach those Pods.

### Service responsibility

Put one stable front door in front of a changing set of Pods:

- a **virtual IP** (ClusterIP) from the cluster's service range, fixed for the Service's lifetime;
- a **DNS name** served by CoreDNS: `yatri-backend-service.default.svc.cluster.local`, or just
  `yatri-backend-service` from inside the same namespace;
- a **port mapping**: `port: 80` on the Service to `targetPort: 5000` on the Pods (`service/clusterip.yaml`);
- a **live backend list**: the EndpointSlice controller watches Pods matching the selector and
  writes their IPs, ports and readiness into EndpointSlice objects labelled
  `kubernetes.io/service-name=yatri-backend-service`. The older `Endpoints` API is still filled in
  for compatibility but has been deprecated since v1.33; kube-proxy reads EndpointSlices.

### Why a Service is required

Pod IPs are ephemeral. The CNI plugin assigns an IP when the Pod's sandbox is created and frees
it when the Pod is gone, and every ReplicaSet replacement, rolling update or reschedule after a
node failure produces a new one. If the frontend hard-coded a backend Pod IP:

- it would break the first time that Pod is replaced;
- all traffic would go to one replica, so scaling to 6 would add no capacity;
- it would keep sending requests to a Pod that is failing its readiness probe.

A Service fixes all three: one name that never changes, backed by a list that is kept current
and only includes Ready Pods. It also selects by label, not by owner, so during a rolling update
it spans the Pods of both the old and the new ReplicaSet (both carry `app: yatri-backend`). That
is what makes the update zero-downtime for callers. A ReplicaSet guarantees Pods exist; the
Service is what lets anyone find them.

### How traffic reaches Pods

```text
 frontend Pod: curl http://yatri-backend-service/
        |
        | 1. DNS: CoreDNS resolves the name to the ClusterIP
        v
 10.96.145.82:80  (ClusterIP, example address; no process listens on it)
        |
        | 2. packet leaves the Pod and hits the node's kernel rules
        v
 +-----------------------------------------+        +------------------------------+
 | node kernel: iptables / IPVS / nftables |<-------| kube-proxy (on every node)   |
 | match 10.96.145.82:80                   | writes | watches Services and         |
 | pick one ready endpoint                 | rules  | EndpointSlices               |
 | DNAT -> PodIP:5000                      |        +------------------------------+
 +-----------------------------------------+                      ^
        |                                                         | reads
        | 3. normal Pod-network routing (CNI), same or other node |
        v                                          +------------------------------+
 +------------------+ +------------------+         | EndpointSlice for            |
 | Pod 10.244.1.7   | | Pod 10.244.2.4   | ...     | yatri-backend-service:       |
 | :5000 (Ready)    | | :5000 (Ready)    |         | ready Pod IPs + port 5000    |
 +------------------+ +------------------+         +------------------------------+
```

1. The frontend Pod's `/etc/resolv.conf` points at the cluster DNS, and its search domains expand
   `yatri-backend-service` to the full `.default.svc.cluster.local` name, which resolves to the ClusterIP.
2. The frontend connects to `ClusterIP:80`. No process listens on that address. Before the packet
   is routed anywhere, it hits the netfilter (or IPVS) rules kube-proxy programmed on that node.
3. The rules match the ClusterIP and port, pick one ready endpoint (random in iptables and
   nftables mode, round robin by default in IPVS mode) and rewrite the destination (DNAT) to
   `PodIP:5000`. The CNI then delivers it like any Pod-to-Pod packet. Conntrack remembers the
   translation, so replies come back looking like they are from the ClusterIP, and every packet
   of that connection reaches the same Pod.

Two consequences worth remembering. kube-proxy is not in the data path: it only writes kernel
rules, so if it crashes, existing traffic keeps flowing but Pod changes stop being reflected. And
balancing is per connection, not per request, so one keep-alive HTTP or gRPC connection talks to
one Pod the whole time. NodePort and LoadBalancer only add entry points in front of this.

### How to see this myself

```bash
kubectl get svc yatri-backend-service
kubectl get endpointslices -l kubernetes.io/service-name=yatri-backend-service
kubectl get pods -l app=yatri-backend -o wide                # compare these Pod IPs with the slice
kubectl delete pod <one-backend-pod>                         # RS replaces it; the new IP shows up in the slice
kubectl exec curl-test-pod -- curl -s http://yatri-backend-service/healthz
sudo iptables -t nat -L KUBE-SERVICES -n | grep yatri        # on a node, in iptables mode
```
