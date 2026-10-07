# Session 14 - Kubernetes Troubleshooting - Task

- **Name:** Netram
- **Enrollment No:** 24BCS10329

> **Status:** completed
> Run on macOS (Apple Silicon) with Docker Desktop, minikube v1.39.0, Kubernetes v1.37.0.

Everything below was run for real on my single node minikube cluster (containerd runtime, kindnet CNI, metrics-server addon on). Every screenshot is a capture of the commands shown, and the text block under it is the same run.

## Summary table

| # | Issue | Symptom I saw | First command I ran | Typical root cause |
| :- | :--- | :--- | :--- | :--- |
| 1 | CrashLoopBackOff | `0/1 CrashLoopBackOff`, restart count going up | `kubectl logs <pod> --previous` | App exits (bad command, missing env, crash on start) |
| 2 | ErrImagePull / ImagePullBackOff | `ErrImagePull`, then `ImagePullBackOff` | `kubectl describe pod <pod>` (Events) | Typo in image name or tag, private registry without pull secret |
| 3 | Pending | `Pending`, NODE is `<none>` | `kubectl describe pod <pod>` (FailedScheduling) | nodeSelector/affinity that no node matches, requests bigger than any node, taints |
| 4 | ContainerCreating (FailedMount) | Stuck in `ContainerCreating`, no IP | `kubectl describe pod <pod>` (FailedMount) | Volume points at a ConfigMap/Secret/PVC that does not exist |
| 5 | Service selector mismatch | Service exists, `Endpoints: <none>`, curl refused | `kubectl get endpoints <svc>` | Service selector does not match the pod labels |
| 6 | Service wrong targetPort | Endpoints exist but curl to the Service is refused | `kubectl describe svc <svc>` (TargetPort) | targetPort is not the port the container listens on |
| 7 | DNS: wrong name / namespace | `NXDOMAIN`, `Could not resolve host` | `kubectl exec <pod> -- nslookup <name>` | Typo in the service name, or short name used from another namespace |
| 8 | DNS: bad nameserver | `connection timed out; no servers could be reached` | `kubectl exec <pod> -- cat /etc/resolv.conf` | `dnsPolicy: None` / custom dnsConfig pointing at a wrong server |
| 9 | Pod networking: app on 127.0.0.1 | Pod `Running`, endpoints fine, but curl from other pods refused | `kubectl exec <pod> -- netstat -tln` | App binds to loopback only (or to a different port) |
| 10 | CreateContainerConfigError | `CreateContainerConfigError` | `kubectl describe pod <pod>` (Events) | env `configMapKeyRef` / `secretKeyRef` to a missing ConfigMap, Secret or key |
| 11 | OOMKilled (mini project scenario 5) | `OOMKilled` / `CrashLoopBackOff`, Last State `OOMKilled`, exit 137 | `kubectl describe pod <pod>` (Last State) | Memory limit lower than what the app really uses |

## Setup

I copied the course YAMLs into this `task/` folder and added a namespace to each one, so nothing went into `default`:

| Namespace | Used for | Folder |
| :--- | :--- | :--- |
| `s14-basics` | Task 1 demo pods (get-demo, describe-demo, logs-demo, exec-demo, events-demo) | `task1-basics/` |
| `s14-t2`, `s14-t2-client` | Task 2 broken and fixed workloads, a test `client` pod, and DNS client pods | `task2-issues/` |
| `s14-mini` | Course mini project (Deployment, Service, broken pod) | `task3-mini-project/` |
| `s14-triage` | Course scenarios 1 to 5 (the "triage gauntlet") | `task3-mini-project/scenarios/` |

```bash
export KUBECONFIG=<my minikube kubeconfig>
kubectl create ns s14-basics && kubectl apply -f task1-basics/
kubectl create ns s14-t2 && kubectl create ns s14-t2-client
kubectl apply -f task2-issues/00-client.yaml -f task2-issues/01-crashloop-broken.yaml ...   # every *-broken.yaml
```

For curl and DNS tests I used `registry.k8s.io/e2e-test-images/agnhost:2.39` (it has `curl`, `nslookup`, `dig`, `netstat`). See "Problems I hit" for why I did not use the image from the course YAML.

---

## Task 1 - kubectl basics

### kubectl get and kubectl get -o wide

- `kubectl get`: first look at anything. I use it to see if a pod is Running/Ready and how many restarts it has.
- `kubectl get -o wide`: same list plus pod IP and node. I use it when I need the IP to curl a pod directly, or to see which node a pod landed on (or that it has no node at all, which means Pending).

![kubectl get](screenshots/s14-01-get.png)

```text
$ kubectl get pods -n s14-basics
NAME            READY   STATUS    RESTARTS   AGE
describe-demo   1/1     Running   0          91s
events-demo     1/1     Running   0          91s
exec-demo       1/1     Running   0          91s
get-demo        1/1     Running   0          91s
logs-demo       1/1     Running   0          91s

$ kubectl get pods -n s14-basics -o wide
NAME            READY   STATUS    RESTARTS   AGE   IP             NODE       NOMINATED NODE   READINESS GATES
describe-demo   1/1     Running   0          91s   10.244.0.128   minikube   <none>           <none>
events-demo     1/1     Running   0          91s   10.244.0.124   minikube   <none>           <none>
exec-demo       1/1     Running   0          91s   10.244.0.125   minikube   <none>           <none>
get-demo        1/1     Running   0          91s   10.244.0.126   minikube   <none>           <none>
logs-demo       1/1     Running   0          91s   10.244.0.127   minikube   <none>           <none>

$ kubectl get pod get-demo -n s14-basics --show-labels
NAME       READY   STATUS    RESTARTS   AGE   LABELS
get-demo   1/1     Running   0          91s   app=get-demo

$ kubectl get pod get-demo -n s14-basics -o jsonpath='{.status.phase} {.status.podIP} {.spec.nodeName}{"\n"}'
Running 10.244.0.126 minikube
```

### kubectl describe

When to use it: when `get` shows a bad status and I want the reason. It shows container state, last state, exit code, mounts, conditions and, most useful, the Events at the bottom.

![kubectl describe](screenshots/s14-02-describe.png)

```text
$ kubectl describe pod describe-demo -n s14-basics | grep -vE '^\s+(/var/run|kube-api-access|Type: +Projected|TokenExpiration|ConfigMapName|Optional|DownwardAPI|ConfigMapOptional)' | cut -c1-150
Name:             describe-demo
Namespace:        s14-basics
Priority:         0
Service Account:  default
Node:             minikube/192.168.49.2
Start Time:       Wed, 07 Oct 2026 22:22:39 +0530
Labels:           app=describe-demo
Annotations:      <none>
Status:           Running
IP:               10.244.0.128
IPs:
  IP:  10.244.0.128
Containers:
  nginx:
    Container ID:   containerd://c0c0bff9c3bc1a8f2527c9e7c50e40ab6a4b8dabf75160f4fff7a69a27a57713
    Image:          nginx:1.27
    Image ID:       docker.io/library/nginx@sha256:6784fb0834aa7dbbe12e3d7471e69c290df3e6ba810dc38b34ae33d3c1c05f7d
    Port:           80/TCP
    Host Port:      0/TCP
    State:          Running
      Started:      Wed, 07 Oct 2026 22:22:40 +0530
    Ready:          True
    Restart Count:  0
    Environment:    <none>
    Mounts:
Conditions:
  Type                        Status
  PodReadyToStartContainers   True 
  Initialized                 True 
  Ready                       True 
  ContainersReady             True 
  PodScheduled                True 
Volumes:
QoS Class:                   BestEffort
Node-Selectors:              <none>
Tolerations:                 node.kubernetes.io/not-ready:NoExecute op=Exists for 300s
                             node.kubernetes.io/unreachable:NoExecute op=Exists for 300s
Events:
  Type    Reason     Age   From               Message
  ----    ------     ----  ----               -------
  Normal  Scheduled  91s   default-scheduler  Successfully assigned s14-basics/describe-demo to minikube
  Normal  Pulled     90s   kubelet            spec.containers{nginx}: Container image "nginx:1.27" already present on machine and can be accessed by t
  Normal  Created    90s   kubelet            spec.containers{nginx}: Container created
  Normal  Started    90s   kubelet            spec.containers{nginx}: Container started
```

### kubectl logs

When to use it: when the container did start but the app is misbehaving or crashing. `--previous` shows the log of the last crashed run, `--tail` and `--since` keep it short, `--timestamps` helps line it up with events.

![kubectl logs](screenshots/s14-03-logs.png)

```text
$ kubectl logs logs-demo -n s14-basics | head -6
Application started
Connecting to database...
Database connection successful
Application is running
Application is healthy
Application is healthy

$ kubectl logs logs-demo -n s14-basics --tail=3 --timestamps
2026-10-07T16:54:00.144717882Z Application is healthy
2026-10-07T16:54:05.144775301Z Application is healthy
2026-10-07T16:54:10.145220595Z Application is healthy

$ kubectl logs logs-demo -n s14-basics --since=10s
Application is healthy
Application is healthy
```

### kubectl exec

When to use it: when the pod is Running and I want to test from inside it (is the app listening, what does `/etc/resolv.conf` say, can I curl localhost or another service).

![kubectl exec](screenshots/s14-04-exec.png)

```text
$ kubectl exec exec-demo -n s14-basics -- nginx -v
nginx version: nginx/1.27.5

$ kubectl exec exec-demo -n s14-basics -- sh -c 'hostname; cat /etc/resolv.conf'
exec-demo
search s14-basics.svc.cluster.local svc.cluster.local cluster.local
nameserver 10.96.0.10
options ndots:5

$ kubectl exec exec-demo -n s14-basics -- curl -s -o /dev/null -w 'HTTP %{http_code}\n' http://localhost:80
HTTP 200

$ kubectl exec exec-demo -n s14-basics -- ls /usr/share/nginx/html
50x.html
index.html
```

### Events (kubectl get events / kubectl events)

When to use it: to see what the scheduler and the kubelet did (scheduled, pulled, mount failed, back-off). `kubectl events --types=Warning` across a namespace is the fastest way to spot every broken thing at once. The third command shows the warnings from my Task 2 namespace.

![events](screenshots/s14-05-events.png)

```text
$ kubectl get events -n s14-basics --field-selector involvedObject.name=events-demo | cut -c1-150
LAST SEEN   TYPE     REASON      OBJECT            MESSAGE
2m41s       Normal   Scheduled   pod/events-demo   Successfully assigned s14-basics/events-demo to minikube
2m41s       Normal   Pulled      pod/events-demo   Container image "nginx:1.27" already present on machine and can be accessed by the pod
2m41s       Normal   Created     pod/events-demo   Container created
2m41s       Normal   Started     pod/events-demo   Container started

$ kubectl events -n s14-basics --for pod/events-demo | cut -c1-150
LAST SEEN   TYPE     REASON      OBJECT            MESSAGE
2m41s       Normal   Scheduled   Pod/events-demo   Successfully assigned s14-basics/events-demo to minikube
2m41s       Normal   Pulled      Pod/events-demo   Container image "nginx:1.27" already present on machine and can be accessed by the pod
2m41s       Normal   Created     Pod/events-demo   Container created
2m41s       Normal   Started     Pod/events-demo   Container started

$ kubectl events -n s14-t2 --types=Warning | cut -c1-150 | head -14
LAST SEEN           TYPE      REASON             OBJECT             MESSAGE
82s                 Warning   FailedScheduling   Pod/pending-demo   0/1 nodes are available: 1 node(s) didn't match Pod's node affinity/selector. pree
46s (x3 over 81s)   Warning   BackOff            Pod/crash-demo     Back-off restarting failed container app in pod crash-demo_s14-t2(b3cd9235-37ad-46
20s (x3 over 81s)   Warning   Failed             Pod/image-demo     Failed to pull image "nginx:this-image-does-not-exist": rpc error: code = NotFound
20s (x3 over 81s)   Warning   Failed             Pod/image-demo     Error: ErrImagePull
19s (x8 over 82s)   Warning   FailedMount        Pod/mount-demo     MountVolume.SetUp failed for volume "site" : configmap "site-content" not found
10s (x7 over 82s)   Warning   Failed             Pod/config-demo    Error: configmap "app-settings" not found
8s (x3 over 81s)    Warning   Failed             Pod/image-demo     Error: ImagePullBackOff
```

### kubectl explain

When to use it: when I am writing or fixing YAML and I am not sure of a field name, its type, or its allowed values. It works offline against the cluster's own API schema.

![kubectl explain](screenshots/s14-06-explain.png)

```text
$ kubectl explain pod.spec.restartPolicy
KIND:       Pod
VERSION:    v1

FIELD: restartPolicy <string>
ENUM:
    Always
    Never
    OnFailure

DESCRIPTION:
    Restart policy for all containers within the pod. One of Always, OnFailure,
    Never. In some contexts, only a subset of those values may be permitted.
    Default to Always. More info:
    https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/#restart-policy
    
    Possible enum values:
     - `"Always"`
     - `"Never"`
     - `"OnFailure"`

$ kubectl explain pod.spec.containers.resources | sed -n '1,20p'
KIND:       Pod
VERSION:    v1

FIELD: resources <ResourceRequirements>


DESCRIPTION:
    Compute Resources required by this container. Cannot be updated. More info:
    https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/
    ResourceRequirements describes the compute resource requirements.
    
FIELDS:
  claims	<[]ResourceClaim>
    Claims lists the names of resources, defined in spec.resourceClaims, that
    are used by this container.
    
    This field depends on the DynamicResourceAllocation feature gate.
    
    This field is immutable. It can only be set for containers.
```

### kubectl top

When to use it: to check real CPU and memory usage (needs metrics-server). It is my first check when I suspect a pod is close to its memory limit or a node is full.

![kubectl top](screenshots/s14-07-top.png)

```text
$ kubectl top node
NAME       CPU(cores)   CPU(%)   MEMORY(bytes)   MEMORY(%)   
minikube   494m         3%       1442Mi          18%

$ kubectl top pods -n s14-basics
NAME            CPU(cores)   MEMORY(bytes)   
describe-demo   1m           11Mi            
events-demo     1m           11Mi            
exec-demo       1m           11Mi            
get-demo        1m           11Mi            
logs-demo       1m           0Mi

$ kubectl top pods -n s14-basics --containers --sort-by=memory
POD             NAME    CPU(cores)   MEMORY(bytes)   
get-demo        nginx   1m           11Mi            
exec-demo       nginx   1m           11Mi            
events-demo     nginx   1m           11Mi            
describe-demo   nginx   1m           11Mi            
logs-demo       app     1m           0Mi
```

---

## Task 2 - Troubleshooting common issues

All files are in `task2-issues/`. For every issue I first looked (get, describe, events, logs, exec) before changing any YAML.

### Issue 1 - CrashLoopBackOff

**Problem:** `crash-demo` (course file `06-crashloopbackoff/broken-pod.yaml`) keeps restarting and ends in `CrashLoopBackOff`.

**Investigation:** `get` shows the restart count rising. `describe` shows `Last State: Terminated, Reason: Error, Exit Code: 1`. `logs --previous` shows what the last run printed before it died.

![crashloop before](screenshots/s14-10-crashloop-before.png)

```text
$ kubectl get pod crash-demo -n s14-t2
NAME         READY   STATUS             RESTARTS      AGE
crash-demo   0/1     CrashLoopBackOff   4 (67s ago)   2m29s

$ kubectl describe pod crash-demo -n s14-t2 | sed -n '/State:/,/Restart Count/p'
    State:          Waiting
      Reason:       CrashLoopBackOff
    Last State:     Terminated
      Reason:       Error
      Exit Code:    1
      Started:      Wed, 07 Oct 2026 22:25:20 +0530
      Finished:     Wed, 07 Oct 2026 22:25:20 +0530
    Ready:          False
    Restart Count:  4

$ kubectl logs crash-demo -n s14-t2 --previous
Application starting...
Something went wrong!

$ kubectl events -n s14-t2 --for pod/crash-demo | grep -E 'BackOff|Started' | tail -2 | cut -c1-150
68s (x5 over 2m30s)   Normal    Started     Pod/crash-demo   Container started
1s (x5 over 2m29s)    Warning   BackOff     Pod/crash-demo   Back-off restarting failed container app in pod crash-demo_s14-t2(b3cd9235-37ad-4615-a239
```

**Root cause:** the container command itself ends with `exit 1`. The container starts fine, then exits with an error, and the kubelet keeps restarting it with a growing back-off delay.

**Fix:** use the fixed command (`01-crashloop-fixed.yaml`) that keeps the process running. A pod's command cannot be edited in place, so I used `kubectl replace --force` (delete and create).

**Verify:** Running, 0 restarts after 20+ seconds, and the logs show the healthy message.

![crashloop after](screenshots/s14-11-crashloop-after.png)

```text
$ diff 01-crashloop-broken.yaml 01-crashloop-fixed.yaml
17,18c17,18
<           echo "Something went wrong!"
<           exit 1
---
>           echo "Application is healthy"
>           sleep 3600

$ kubectl replace --force -f 01-crashloop-fixed.yaml
pod "crash-demo" deleted from s14-t2 namespace
pod/crash-demo replaced

$ kubectl wait --for=condition=Ready pod/crash-demo -n s14-t2 --timeout=60s
pod/crash-demo condition met

$ sleep 20; kubectl get pod crash-demo -n s14-t2
NAME         READY   STATUS    RESTARTS   AGE
crash-demo   1/1     Running   0          21s

$ kubectl logs crash-demo -n s14-t2
Application starting...
Application is healthy
```

### Issue 2 - ErrImagePull and ImagePullBackOff

**Problem:** `image-demo` never starts. Status flips between `ErrImagePull` and `ImagePullBackOff`.

**Investigation:** the waiting reason is `ErrImagePull`. The events show the whole story: `Pulling` -> `Failed ... NotFound` -> `Error: ErrImagePull` -> `Back-off pulling image` -> `Error: ImagePullBackOff`. I also pulled the same image by hand on the node with `crictl` to confirm the registry says "not found".

![imagepull before](screenshots/s14-12-imagepull-before.png)

```text
$ kubectl get pod image-demo -n s14-t2
NAME         READY   STATUS         RESTARTS   AGE
image-demo   0/1     ErrImagePull   0          82s

$ kubectl get pod image-demo -n s14-t2 -o jsonpath='{.status.containerStatuses[0].state.waiting.reason}{"\n"}'
ErrImagePull

$ kubectl events -n s14-t2 --for pod/image-demo | cut -c1-150
LAST SEEN           TYPE      REASON      OBJECT           MESSAGE
82s                 Normal    Scheduled   Pod/image-demo   Successfully assigned s14-t2/image-demo to minikube
41s (x3 over 82s)   Normal    Pulling     Pod/image-demo   Pulling image "nginx:this-image-does-not-exist"
20s (x3 over 81s)   Warning   Failed      Pod/image-demo   Failed to pull image "nginx:this-image-does-not-exist": rpc error: code = NotFound desc = f
20s (x3 over 81s)   Warning   Failed      Pod/image-demo   Error: ErrImagePull
8s (x3 over 81s)    Normal    BackOff     Pod/image-demo   Back-off pulling image "nginx:this-image-does-not-exist"
8s (x3 over 81s)    Warning   Failed      Pod/image-demo   Error: ImagePullBackOff

$ minikube ssh -- sudo crictl pull nginx:this-image-does-not-exist 2>&1 | grep -o 'not found.*' | head -1 | cut -c1-140
not found" image="nginx:this-image-does-not-exist"
```

**Root cause:** the tag `nginx:this-image-does-not-exist` does not exist on Docker Hub. `ErrImagePull` is the actual failed pull; `ImagePullBackOff` is Kubernetes waiting longer and longer before it tries again.

**Fix:** change the image to `nginx:1.27`. The image field of a pod is one of the few fields that can be changed in place, so a plain `kubectl apply` was enough.

**Verify:**

![imagepull after](screenshots/s14-13-imagepull-after.png)

```text
$ diff 02-imagepull-broken.yaml 02-imagepull-fixed.yaml
11c11
<       image: nginx:this-image-does-not-exist
---
>       image: nginx:1.27

$ kubectl apply -f 02-imagepull-fixed.yaml
pod/image-demo configured

$ kubectl wait --for=condition=Ready pod/image-demo -n s14-t2 --timeout=60s
pod/image-demo condition met

$ kubectl get pod image-demo -n s14-t2
NAME         READY   STATUS    RESTARTS   AGE
image-demo   1/1     Running   0          3m31s

$ kubectl events -n s14-t2 --for pod/image-demo | tail -3 | cut -c1-150
1s                     Normal    Pulled      Pod/image-demo   Container image "nginx:1.27" already present on machine and can be accessed by the pod
1s                     Normal    Created     Pod/image-demo   Container created
0s                     Normal    Started     Pod/image-demo   Container started
```

### Issue 3 - Pending

**Problem:** `pending-demo` stays `Pending` and has no node and no IP.

**Investigation:** `describe` shows `Node-Selectors: kubernetes.io/hostname=node-that-does-not-exist` and a `FailedScheduling` event: `0/1 nodes are available: 1 node(s) didn't match Pod's node affinity/selector`. The only node is called `minikube`.

![pending before](screenshots/s14-14-pending-before.png)

```text
$ kubectl get pod pending-demo -n s14-t2 -o wide
NAME           READY   STATUS    RESTARTS   AGE   IP       NODE     NOMINATED NODE   READINESS GATES
pending-demo   0/1     Pending   0          85s   <none>   <none>   <none>           <none>

$ kubectl describe pod pending-demo -n s14-t2 | sed -n '/Node-Selectors/p;/Events:/,$p' | cut -c1-150
Node-Selectors:              kubernetes.io/hostname=node-that-does-not-exist
Events:
  Type     Reason            Age   From               Message
  ----     ------            ----  ----               -------
  Warning  FailedScheduling  85s   default-scheduler  0/1 nodes are available: 1 node(s) didn't match Pod's node affinity/selector. preemption: 0/1 no

$ kubectl get nodes -L kubernetes.io/hostname
NAME       STATUS   ROLES           AGE   VERSION   HOSTNAME
minikube   Ready    control-plane   44m   v1.37.0   minikube
```

**Root cause:** the nodeSelector asks for a node that does not exist, so the scheduler has nowhere to put the pod. (Scenario 3 in the mini project shows the other common cause: requests bigger than the node.)

**Fix:** remove the nodeSelector (`03-pending-fixed.yaml`) and recreate the pod.

**Verify:**

![pending after](screenshots/s14-15-pending-after.png)

```text
$ diff 03-pending-broken.yaml 03-pending-fixed.yaml
9,11d8
<   nodeSelector:
<     kubernetes.io/hostname: node-that-does-not-exist
<

$ kubectl replace --force -f 03-pending-fixed.yaml
pod "pending-demo" deleted from s14-t2 namespace
pod/pending-demo replaced

$ kubectl wait --for=condition=Ready pod/pending-demo -n s14-t2 --timeout=60s
pod/pending-demo condition met

$ kubectl get pod pending-demo -n s14-t2 -o wide | cut -c1-110
NAME           READY   STATUS    RESTARTS   AGE   IP             NODE       NOMINATED NODE   READINESS GATES
pending-demo   1/1     Running   0          2s    10.244.0.211   minikube   <none>           <none>
```

### Issue 4 - ContainerCreating (missing ConfigMap volume)

**Problem:** `mount-demo` (`04-containercreating-broken.yaml`) sits in `ContainerCreating` forever.

**Investigation:** the pod was scheduled, but `describe` shows a repeating `FailedMount` warning: `MountVolume.SetUp failed for volume "site" : configmap "site-content" not found`. `kubectl get configmap` confirms it is not there.

![containercreating before](screenshots/s14-16-containercreating-before.png)

```text
$ kubectl get pod mount-demo -n s14-t2
NAME         READY   STATUS              RESTARTS   AGE
mount-demo   0/1     ContainerCreating   0          85s

$ kubectl describe pod mount-demo -n s14-t2 | sed -n '/^Volumes:/,/Optional/p;/Events:/,$p' | cut -c1-150
Volumes:
  site:
    Type:      ConfigMap (a volume populated by a ConfigMap)
    Name:      site-content
    Optional:  false
Events:
  Type     Reason       Age                From               Message
  ----     ------       ----               ----               -------
  Normal   Scheduled    85s                default-scheduler  Successfully assigned s14-t2/mount-demo to minikube
  Warning  FailedMount  22s (x8 over 85s)  kubelet            MountVolume.SetUp failed for volume "site" : configmap "site-content" not found

$ kubectl get configmap -n s14-t2
NAME               DATA   AGE
kube-root-ca.crt   1      86s
```

**Root cause:** the pod mounts a ConfigMap volume (not marked optional) that was never created, so the kubelet cannot prepare the volume and never starts the container.

**Fix:** create the missing ConfigMap (`04-containercreating-fix-configmap.yaml`). I did not touch the pod: the kubelet retries the mount by itself. It took 39 seconds for the next retry to pick it up.

**Verify:** the pod is Running and nginx serves the file that came from the ConfigMap.

![containercreating after](screenshots/s14-17-containercreating-after.png)

```text
$ kubectl apply -f 04-containercreating-fix-configmap.yaml
configmap/site-content created

$ time kubectl wait --for=condition=Ready pod/mount-demo -n s14-t2 --timeout=200s
pod/mount-demo condition met

real	0m39.007s
user	0m0.030s
sys	0m0.033s

$ kubectl get pod mount-demo -n s14-t2
NAME         READY   STATUS    RESTARTS   AGE
mount-demo   1/1     Running   0          4m12s

$ kubectl exec mount-demo -n s14-t2 -- curl -s http://localhost
hello from mount-demo (ConfigMap volume)
```

### Issue 5 - Service with a selector mismatch (no endpoints)

**Problem:** the course `web` Deployment (2 nginx pods) and `web-service` are both up, but curl to the Service from my `client` pod gets `Connection refused`.

**Investigation:** `kubectl get endpoints` shows `<none>`. `describe svc` shows `Selector: app=web-ahsgdf`, but the pods are labelled `app=web`. Asking for pods with the Service's selector returns nothing.

![selector before](screenshots/s14-18-svc-selector-before.png)

```text
$ kubectl get svc web-service -n s14-t2
NAME          TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE
web-service   ClusterIP   10.109.151.26   <none>        80/TCP    85s

$ kubectl get endpoints web-service -n s14-t2
Warning: v1 Endpoints is deprecated in v1.33+; use discovery.k8s.io/v1 EndpointSlice
NAME          ENDPOINTS   AGE
web-service   <none>      85s

$ kubectl exec client -n s14-t2 -- curl -sS -m 3 http://web-service.s14-t2; echo "exit=$?"
curl: (7) Failed to connect to web-service.s14-t2 port 80 after 0 ms: Connection refused
command terminated with exit code 7
exit=7

$ kubectl describe svc web-service -n s14-t2 | grep -E 'Selector|TargetPort|Endpoints'
Selector:                 app=web-ahsgdf
TargetPort:               80/TCP
Endpoints:

$ kubectl get pods -n s14-t2 -l app=web --show-labels
NAME                   READY   STATUS    RESTARTS   AGE   LABELS
web-557577df75-8554d   1/1     Running   0          85s   app=web,pod-template-hash=557577df75
web-557577df75-cjhvt   1/1     Running   0          85s   app=web,pod-template-hash=557577df75

$ kubectl get pods -n s14-t2 -l app=web-ahsgdf
No resources found in s14-t2 namespace.
```

**Root cause:** the Service selector does not match the pod labels, so the endpoints controller finds no pods and the Service has nowhere to send traffic.

**Fix:** set the selector to `app: web` (`05-web-service-fixed.yaml`).

**Verify:** the EndpointSlice now lists both pod IPs and curl returns the nginx page.

![selector after](screenshots/s14-19-svc-selector-after.png)

```text
$ diff 05-web-service-broken.yaml 05-web-service-fixed.yaml
10c10
<     app: web-ahsgdf
---
>     app: web

$ kubectl apply -f 05-web-service-fixed.yaml
service/web-service configured

$ sleep 2; kubectl get endpointslices -n s14-t2 -l kubernetes.io/service-name=web-service
NAME                ADDRESSTYPE   PORTS   ENDPOINTS                   AGE
web-service-phvld   IPv4          80      10.244.0.148,10.244.0.147   4m16s

$ kubectl exec client -n s14-t2 -- curl -sS -m 3 http://web-service.s14-t2 | grep -o '<title>.*</title>'
<title>Welcome to nginx!</title>
```

### Issue 6 - Service with the wrong targetPort

**Problem:** after the selector fix I applied a version of the Service with `targetPort: 8080` (`05-web-service-wrong-targetport.yaml`) to show the other classic mistake. The Service now has endpoints, but curl is refused again.

**Investigation:** `describe svc` shows `TargetPort: 8080/TCP` and endpoints like `10.244.0.147:8080`. The pod's `containerPort` is 80. Curling one pod IP directly proves it: port 80 returns 200, port 8080 fails.

![targetport before](screenshots/s14-20-targetport-before.png)

```text
$ kubectl apply -f 05-web-service-wrong-targetport.yaml
service/web-service configured

$ kubectl describe svc web-service -n s14-t2 | grep -E 'Selector|TargetPort|Endpoints'
Selector:                 app=web
TargetPort:               8080/TCP
Endpoints:                10.244.0.147:8080,10.244.0.148:8080

$ kubectl exec client -n s14-t2 -- curl -sS -m 3 http://web-service.s14-t2; echo "exit=$?"
curl: (7) Failed to connect to web-service.s14-t2 port 80 after 1 ms: Connection refused
command terminated with exit code 7
exit=7

$ kubectl get pods -n s14-t2 -l app=web -o jsonpath='{.items[0].spec.containers[0].ports[0].containerPort}{"\n"}'
80

$ POD_IP=$(kubectl get pods -n s14-t2 -l app=web -o jsonpath='{.items[0].status.podIP}'); for p in 80 8080; do kubectl exec client -n s14-t2 -- curl -s -m 3 -o /dev/null -w "$POD_IP:$p -> %{http_code}\n" http://$POD_IP:$p; done
10.244.0.147:80 -> 200
10.244.0.147:8080 -> 000
command terminated with exit code 7
```

**Root cause:** the Service forwards to port 8080 on the pods, but nginx only listens on 80. Having endpoints is not enough; the port must match too.

**Fix:** set `targetPort: 80`.

**Verify:**

![targetport after](screenshots/s14-21-targetport-after.png)

```text
$ diff 05-web-service-wrong-targetport.yaml 05-web-service-fixed.yaml
14c14
<       targetPort: 8080          # BUG: nginx listens on 80, not 8080
---
>       targetPort: 80

$ kubectl apply -f 05-web-service-fixed.yaml
service/web-service configured

$ sleep 2; kubectl describe svc web-service -n s14-t2 | grep -E 'TargetPort|Endpoints'
TargetPort:               80/TCP
Endpoints:                10.244.0.148:80,10.244.0.147:80

$ kubectl exec client -n s14-t2 -- curl -sS -m 3 -o /dev/null -w 'HTTP %{http_code}\n' http://web-service.s14-t2
HTTP 200
```

### Issue 7 - DNS: wrong service name and wrong namespace

To test DNS I first needed the course `dns-test` pod, and that pod itself was broken (wrong image, see "Problems I hit"). I fixed its image first:

![dns image before](screenshots/s14-22-dns-image-before.png)

```text
$ kubectl get pod dns-test -n s14-t2-client
NAME       READY   STATUS         RESTARTS   AGE
dns-test   0/1     ErrImagePull   0          85s

$ kubectl events -n s14-t2-client --for pod/dns-test | grep -m2 -E 'Failed' | cut -c1-150
24s (x3 over 83s)   Warning   Failed      Pod/dns-test   Failed to pull image "registry.k8s.io/e2e-test-images/dnsutils:1.3": rpc error: code = NotFou
24s (x3 over 83s)   Warning   Failed      Pod/dns-test   Error: ErrImagePull
```

![dns image after](screenshots/s14-23-dns-image-after.png)

```text
$ diff 06-dns-test-pod-course-original.yaml 06-dns-test-pod-fixed.yaml
11c11
<       image: registry.k8s.io/e2e-test-images/dnsutils:1.3
---
>       image: registry.k8s.io/e2e-test-images/agnhost:2.39

$ kubectl apply -f 06-dns-test-pod-fixed.yaml
pod/dns-test configured

$ kubectl wait --for=condition=Ready pod/dns-test -n s14-t2-client --timeout=90s
pod/dns-test condition met

$ kubectl get pod dns-test -n s14-t2-client
NAME       READY   STATUS    RESTARTS   AGE
dns-test   1/1     Running   0          4m23s
```

**Problem:** `dns-test` lives in `s14-t2-client`. From there, `curl http://web-service` fails with `Could not resolve host`, and `web-svc.s14-t2` (a typo I made on purpose) also fails.

**Investigation:** `/etc/resolv.conf` shows the search list starts with `s14-t2-client.svc.cluster.local`, so the short name `web-service` becomes `web-service.s14-t2-client.svc.cluster.local`, which does not exist (NXDOMAIN). `kubectl get svc -A --field-selector metadata.name=web-service` shows which namespace the Service really lives in. It also shows there is another `web-service` in a different namespace on this cluster, which is a good reminder that a short name only means "the one in my own namespace".

![dns name before](screenshots/s14-24-dns-name-before.png)

```text
$ kubectl exec dns-test -n s14-t2-client -- cat /etc/resolv.conf
search s14-t2-client.svc.cluster.local svc.cluster.local cluster.local
nameserver 10.96.0.10
options ndots:5

$ kubectl exec dns-test -n s14-t2-client -- nslookup web-service | tail -3
command terminated with exit code 1

** server can't find web-service: NXDOMAIN

$ kubectl exec dns-test -n s14-t2-client -- nslookup web-svc.s14-t2 | tail -3
command terminated with exit code 1

** server can't find web-svc.s14-t2: NXDOMAIN

$ kubectl exec dns-test -n s14-t2-client -- curl -sS -m 3 http://web-service; echo "exit=$?"
curl: (6) Could not resolve host: web-service
command terminated with exit code 6
exit=6

$ kubectl get svc -A --field-selector metadata.name=web-service
NAMESPACE               NAME          TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE
s13-production-webapp   web-service   ClusterIP   10.111.171.18   <none>        80/TCP    2m36s
s14-t2                  web-service   ClusterIP   10.109.151.26   <none>        80/TCP    4m28s
```

**Root cause:** wrong name (typo) and a short name used from a different namespace. CoreDNS itself was fine (it answered NXDOMAIN quickly, not a timeout).

**Fix:** use `<service>.<namespace>` or the full `<service>.<namespace>.svc.cluster.local`.

**Verify:**

![dns name after](screenshots/s14-25-dns-name-after.png)

```text
$ kubectl exec dns-test -n s14-t2-client -- nslookup web-service.s14-t2 | tail -3
Name:	web-service.s14-t2.svc.cluster.local
Address: 10.109.151.26

$ kubectl exec dns-test -n s14-t2-client -- dig +short web-service.s14-t2.svc.cluster.local
10.109.151.26

$ kubectl exec dns-test -n s14-t2-client -- curl -sS -m 3 http://web-service.s14-t2.svc.cluster.local | grep -o '<title>.*</title>'
<title>Welcome to nginx!</title>
```

### Issue 8 - DNS: pod pointed at a nameserver that does not exist

I was told not to touch CoreDNS (another person documents it on this shared cluster), so I broke DNS only inside my own pod.

**Problem:** `dns-bad` (`06-dns-bad-nameserver-broken.yaml`) is Running, but every lookup times out, even `kubernetes.default`, and curl says `Resolving timed out`.

**Investigation:** `/etc/resolv.conf` inside the pod says `nameserver 10.96.0.99`. The pod spec has `dnsPolicy: None` with a custom `dnsConfig`. The real cluster DNS Service (`kube-dns`) is `10.96.0.10`. A timeout (instead of NXDOMAIN) means no DNS server answered at all.

![dns nameserver before](screenshots/s14-26-dns-nameserver-before.png)

```text
$ kubectl get pod dns-bad -n s14-t2-client
NAME      READY   STATUS    RESTARTS   AGE
dns-bad   1/1     Running   0          85s

$ kubectl exec dns-bad -n s14-t2-client -- cat /etc/resolv.conf
search s14-t2-client.svc.cluster.local
nameserver 10.96.0.99

$ kubectl exec dns-bad -n s14-t2-client -- nslookup -timeout=2 -retry=1 kubernetes.default; echo "exit=$?"
;; connection timed out; no servers could be reached


command terminated with exit code 1
exit=1

$ kubectl exec dns-bad -n s14-t2-client -- curl -sS -m 5 http://web-service.s14-t2; echo "exit=$?"
curl: (28) Resolving timed out after 5000 milliseconds
command terminated with exit code 28
exit=28

$ kubectl get pod dns-bad -n s14-t2-client -o jsonpath='{.spec.dnsPolicy} {.spec.dnsConfig.nameservers}{"\n"}'
None ["10.96.0.99"]

$ kubectl get svc kube-dns -n kube-system
NAME       TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)                  AGE
kube-dns   ClusterIP   10.96.0.10   <none>        53/UDP,53/TCP,9153/TCP   44m
```

**Root cause:** `dnsPolicy: None` tells the kubelet to ignore cluster DNS and use only my `dnsConfig`, which points at an IP where nothing listens.

**Fix:** go back to `dnsPolicy: ClusterFirst` and drop the custom `dnsConfig`. DNS settings of a running pod cannot be changed, so I recreated it.

**Verify:** resolv.conf now points at `10.96.0.10` with the normal search list, lookups work, and cross-namespace curl works.

![dns nameserver after](screenshots/s14-27-dns-nameserver-after.png)

```text
$ diff 06-dns-bad-nameserver-broken.yaml 06-dns-bad-nameserver-fixed.yaml
1c1
< # Pod overrides DNS with dnsPolicy None and points at a nameserver that does not exist
---
> # Same pod with the default ClusterFirst policy -> uses CoreDNS from the kubelet
8,13c8
<   dnsPolicy: "None"
<   dnsConfig:
<     nameservers:
<       - 10.96.0.99              # BUG: nothing listens here (CoreDNS is 10.96.0.10)
<     searches:
<       - s14-t2-client.svc.cluster.local
---
>   dnsPolicy: ClusterFirst

$ kubectl replace --force -f 06-dns-bad-nameserver-fixed.yaml
pod "dns-bad" deleted from s14-t2-client namespace
pod/dns-bad replaced

$ kubectl wait --for=condition=Ready pod/dns-bad -n s14-t2-client --timeout=60s
pod/dns-bad condition met

$ kubectl exec dns-bad -n s14-t2-client -- cat /etc/resolv.conf
search s14-t2-client.svc.cluster.local svc.cluster.local cluster.local
nameserver 10.96.0.10
options ndots:5

$ kubectl exec dns-bad -n s14-t2-client -- nslookup kubernetes.default | tail -3
Name:	kubernetes.default.svc.cluster.local
Address: 10.96.0.1

$ kubectl exec dns-bad -n s14-t2-client -- curl -sS -m 3 http://web-service.s14-t2 | grep -o '<title>.*</title>'
<title>Welcome to nginx!</title>
```

### Issue 9 - Pod networking: app listening on 127.0.0.1 only

**Problem:** `localhost-app` (`07-localhost-app-broken.yaml`, busybox httpd) is `Running 1/1`, the Service has an endpoint, but curl from another pod gets `Connection refused`.

**Investigation:** inside the pod, `wget http://127.0.0.1:8080` works, so the app is fine. `netstat -tln` shows why other pods cannot reach it: it listens on `127.0.0.1:8080`, not on the pod IP.

![localhost before](screenshots/s14-28-localhost-before.png)

```text
$ kubectl get pods -n s14-t2 -l app=localhost-app -o wide | cut -c1-96
NAME                             READY   STATUS    RESTARTS   AGE     IP             NODE       
localhost-app-8577d58bb5-pm6zt   1/1     Running   0          2m30s   10.244.0.150   minikube

$ kubectl get endpointslices -n s14-t2 -l kubernetes.io/service-name=localhost-app
NAME                  ADDRESSTYPE   PORTS   ENDPOINTS      AGE
localhost-app-kw8fq   IPv4          8080    10.244.0.150   2m30s

$ kubectl exec client -n s14-t2 -- curl -sS -m 3 http://localhost-app.s14-t2; echo "exit=$?"
curl: (7) Failed to connect to localhost-app.s14-t2 port 80 after 1 ms: Connection refused
command terminated with exit code 7
exit=7

$ kubectl exec deploy/localhost-app -n s14-t2 -- wget -qO- http://127.0.0.1:8080
hello from localhost-app

$ kubectl exec deploy/localhost-app -n s14-t2 -- netstat -tln
Active Internet connections (only servers)
Proto Recv-Q Send-Q Local Address           Foreign Address         State       
tcp        0      0 127.0.0.1:8080          0.0.0.0:*               LISTEN
```

**Root cause:** the server was started with `-p 127.0.0.1:8080`. Loopback is only reachable from inside the pod's own network namespace, so traffic that comes in on the pod IP (from the Service or another pod) is refused.

**Fix:** bind to all interfaces: `-p 0.0.0.0:8080` (`07-localhost-app-fixed.yaml`), applied as a normal Deployment rollout.

**Verify:** netstat shows `0.0.0.0:8080`. My first curl right after `rollout status` was still refused (see "Problems I hit"), so I checked again once the old pod was gone, and it worked.

![localhost after](screenshots/s14-29-localhost-after.png)

```text
$ diff 07-localhost-app-broken.yaml 07-localhost-app-fixed.yaml
21c21
<               exec httpd -f -v -p 127.0.0.1:8080 -h /www     # BUG: loopback only
---
>               exec httpd -f -v -p 0.0.0.0:8080 -h /www       # FIX: listen on all interfaces

$ kubectl apply -f 07-localhost-app-fixed.yaml
deployment.apps/localhost-app configured
service/localhost-app unchanged

$ kubectl rollout status deploy/localhost-app -n s14-t2 --timeout=60s
Waiting for deployment spec update to be observed...
Waiting for deployment "localhost-app" rollout to finish: 0 out of 1 new replicas have been updated...
Waiting for deployment "localhost-app" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "localhost-app" rollout to finish: 1 old replicas are pending termination...
deployment "localhost-app" successfully rolled out

$ kubectl exec deploy/localhost-app -n s14-t2 -- netstat -tln
Active Internet connections (only servers)
Proto Recv-Q Send-Q Local Address           Foreign Address         State       
tcp        0      0 0.0.0.0:8080            0.0.0.0:*               LISTEN

$ kubectl exec client -n s14-t2 -- curl -sS -m 3 http://localhost-app.s14-t2
curl: (7) Failed to connect to localhost-app.s14-t2 port 80 after 6 ms: Connection refused
command terminated with exit code 7
```

![localhost verify](screenshots/s14-29b-localhost-verify.png)

```text
$ kubectl get pods -n s14-t2 -l app=localhost-app -o wide | cut -c1-96
NAME                             READY   STATUS    RESTARTS   AGE     IP             NODE       
localhost-app-5d7d75c964-sqh42   1/1     Running   0          40s     10.244.0.224   minikube   
localhost-app-8577d58bb5-pm6zt   0/1     Error     0          5m48s   10.244.0.150   minikube

$ kubectl get endpointslices -n s14-t2 -l kubernetes.io/service-name=localhost-app
NAME                  ADDRESSTYPE   PORTS   ENDPOINTS      AGE
localhost-app-kw8fq   IPv4          8080    10.244.0.224   5m48s

$ kubectl exec client -n s14-t2 -- curl -sS -m 3 http://localhost-app.s14-t2
hello from localhost-app

$ kubectl get events -n s14-t2 --field-selector involvedObject.name=localhost-app-8577d58bb5-pm6zt | tail -2 | cut -c1-150
5m52s       Normal   Started     pod/localhost-app-8577d58bb5-pm6zt   Container started
42s         Normal   Killing     pod/localhost-app-8577d58bb5-pm6zt   Stopping container httpd
```

### Issue 10 - CreateContainerConfigError (missing ConfigMap key in env)

**Problem:** `config-demo` (`08-config-broken.yaml`) shows `CreateContainerConfigError`.

**Investigation:** `describe` shows `APP_MODE: <set to the key 'mode' of config map 'app-settings'>  Optional: false`, and the event says `Error: configmap "app-settings" not found`.

![config before](screenshots/s14-30-config-before.png)

```text
$ kubectl get pod config-demo -n s14-t2
NAME          READY   STATUS                       RESTARTS   AGE
config-demo   0/1     CreateContainerConfigError   0          93s

$ kubectl describe pod config-demo -n s14-t2 | sed -n '/State:/,/Reason/p;/Environment:/,/Mounts/p' | head -8
    State:          Waiting
      Reason:       CreateContainerConfigError
    Environment:
      APP_MODE:  <set to the key 'mode' of config map 'app-settings'>  Optional: false
    Mounts:

$ kubectl events -n s14-t2 --for pod/config-demo | grep -E 'Failed' | tail -2 | cut -c1-150
6s (x8 over 93s)   Warning   Failed      Pod/config-demo   Error: configmap "app-settings" not found

$ kubectl get configmap app-settings -n s14-t2
Error from server (NotFound): configmaps "app-settings" not found
```

**Root cause:** an environment variable is filled from a ConfigMap that does not exist. The image is pulled and the pod is scheduled, but the kubelet cannot build the container config, so the container is never created.

**Fix:** create the ConfigMap `app-settings` with key `mode` (`08-config-fix-configmap.yaml`). No change to the pod; the kubelet picked it up on its next retry (about 2 seconds).

**Verify:**

![config after](screenshots/s14-31-config-after.png)

```text
$ kubectl apply -f 08-config-fix-configmap.yaml
configmap/app-settings created

$ time kubectl wait --for=condition=Ready pod/config-demo -n s14-t2 --timeout=200s
pod/config-demo condition met

real	0m1.982s
user	0m0.027s
sys	0m0.015s

$ kubectl get pod config-demo -n s14-t2
NAME          READY   STATUS    RESTARTS   AGE
config-demo   1/1     Running   0          5m14s

$ kubectl logs config-demo -n s14-t2
APP_MODE=production
```

### Task 2 final state

![all fixed](screenshots/s14-32-all-fixed.png)

```text
$ kubectl get pods -n s14-t2 -o wide | cut -c1-100
NAME                             READY   STATUS    RESTARTS   AGE     IP             NODE       NOMI
client                           1/1     Running   0          5m52s   10.244.0.144   minikube   <non
config-demo                      1/1     Running   0          5m52s   10.244.0.152   minikube   <non
crash-demo                       1/1     Running   0          2m43s   10.244.0.206   minikube   <non
image-demo                       1/1     Running   0          5m52s   10.244.0.146   minikube   <non
localhost-app-5d7d75c964-sqh42   1/1     Running   0          44s     10.244.0.224   minikube   <non
mount-demo                       1/1     Running   0          5m52s   10.244.0.216   minikube   <non
pending-demo                     1/1     Running   0          2m21s   10.244.0.211   minikube   <non
web-557577df75-8554d             1/1     Running   0          5m52s   10.244.0.147   minikube   <non
web-557577df75-cjhvt             1/1     Running   0          5m52s   10.244.0.148   minikube   <non

$ kubectl get pods -n s14-t2-client
NAME       READY   STATUS    RESTARTS   AGE
dns-bad    1/1     Running   0          48s
dns-test   1/1     Running   0          5m53s

$ kubectl get svc,endpointslices -n s14-t2
NAME                    TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE
service/localhost-app   ClusterIP   10.96.129.231   <none>        80/TCP    5m53s
service/web-service     ClusterIP   10.109.151.26   <none>        80/TCP    5m53s

NAME                                                 ADDRESSTYPE   PORTS   ENDPOINTS                   AGE
endpointslice.discovery.k8s.io/localhost-app-kw8fq   IPv4          8080    10.244.0.224                5m53s
endpointslice.discovery.k8s.io/web-service-phvld     IPv4          80      10.244.0.148,10.244.0.147   5m53s
```

---

## Task 3 - Mini project

Files are in `task3-mini-project/` (course files plus a namespace, and my fixed versions).

### 1-4. Deploy, check the app, check the Service and endpoints

![mini deploy](screenshots/s14-40-mini-deploy.png)

```text
$ kubectl create namespace s14-mini
namespace/s14-mini created

$ kubectl apply -f deployment.yaml -f service.yaml
deployment.apps/troubleshooting-app created
service/troubleshooting-service created

$ kubectl rollout status deploy/troubleshooting-app -n s14-mini --timeout=90s
Waiting for deployment spec update to be observed...
Waiting for deployment "troubleshooting-app" rollout to finish: 0 out of 2 new replicas have been updated...
Waiting for deployment "troubleshooting-app" rollout to finish: 0 of 2 updated replicas are available...
Waiting for deployment "troubleshooting-app" rollout to finish: 1 of 2 updated replicas are available...
deployment "troubleshooting-app" successfully rolled out

$ kubectl get pods -n s14-mini -o wide | cut -c1-110
NAME                                   READY   STATUS    RESTARTS   AGE   IP             NODE       NOMINATED 
troubleshooting-app-59d4957864-7nwl7   1/1     Running   0          5s    10.244.0.220   minikube   <none>    
troubleshooting-app-59d4957864-hvmxb   1/1     Running   0          6s    10.244.0.221   minikube   <none>

$ kubectl get service -n s14-mini
NAME                      TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE
troubleshooting-service   ClusterIP   10.97.193.125   <none>        80/TCP    6s
```

`curl localhost` inside the container returns the nginx page, the Service selector is `app=troubleshooting-app`, the target port is 80 and both pod IPs are in the endpoints.

![mini check](screenshots/s14-41-mini-check.png)

```text
$ POD=$(kubectl get pods -n s14-mini -l app=troubleshooting-app -o name | head -1); echo $POD; kubectl describe -n s14-mini $POD | grep -E '^Status|Image:|Ready:|Restart Count'
pod/troubleshooting-app-59d4957864-7nwl7
Status:           Running
    Image:          nginx:1.27
    Ready:          True
    Restart Count:  0

$ kubectl logs -n s14-mini deploy/troubleshooting-app | tail -3 | cut -c1-140
Found 2 pods, using pod/troubleshooting-app-59d4957864-hvmxb
2026/10/07 16:59:02 [notice] 1#1: start worker process 41
2026/10/07 16:59:02 [notice] 1#1: start worker process 42
2026/10/07 16:59:02 [notice] 1#1: start worker process 43

$ kubectl exec -n s14-mini deploy/troubleshooting-app -- curl -s localhost | grep -o '<title>.*</title>'
<title>Welcome to nginx!</title>

$ kubectl describe service troubleshooting-service -n s14-mini | grep -E 'Selector|TargetPort|Endpoints'
Selector:                 app=troubleshooting-app
TargetPort:               80/TCP
Endpoints:                10.244.0.221:80,10.244.0.220:80

$ kubectl get endpoints troubleshooting-service -n s14-mini
Warning: v1 Endpoints is deprecated in v1.33+; use discovery.k8s.io/v1 EndpointSlice
NAME                      ENDPOINTS                         AGE
troubleshooting-service   10.244.0.220:80,10.244.0.221:80   8s
```

### 5-6. Broken pod: troubleshoot before touching the YAML

![mini broken pod](screenshots/s14-42-mini-broken-pod.png)

```text
$ kubectl replace --force -f broken-pod.yaml
pod "project-broken-pod" deleted from s14-mini namespace
pod/project-broken-pod replaced

$ until kubectl get pod project-broken-pod -n s14-mini | grep -qE 'ErrImagePull|ImagePullBackOff'; do sleep 2; done; kubectl get pod project-broken-pod -n s14-mini
NAME                 READY   STATUS         RESTARTS   AGE
project-broken-pod   0/1     ErrImagePull   0          4s

$ kubectl describe pod project-broken-pod -n s14-mini | sed -n '/^    Image:/p;/State:/,/Reason/p;/Events:/,$p' | cut -c1-150
    Image:          nginx:this-tag-does-not-exist
    State:          Waiting
      Reason:       ErrImagePull
Events:
  Type     Reason     Age   From               Message
  ----     ------     ----  ----               -------
  Normal   Scheduled  5s    default-scheduler  Successfully assigned s14-mini/project-broken-pod to minikube
  Normal   Pulling    4s    kubelet            spec.containers{app}: Pulling image "nginx:this-tag-does-not-exist"
  Warning  Failed     3s    kubelet            spec.containers{app}: Failed to pull image "nginx:this-tag-does-not-exist": rpc error: code = NotFound 
  Warning  Failed     3s    kubelet            spec.containers{app}: Error: ErrImagePull
  Normal   BackOff    2s    kubelet            spec.containers{app}: Back-off pulling image "nginx:this-tag-does-not-exist"
  Warning  Failed     2s    kubelet            spec.containers{app}: Error: ImagePullBackOff

$ minikube ssh -- sudo crictl pull nginx:this-tag-does-not-exist 2>&1 | grep -o 'not found.*' | head -1 | cut -c1-140
not found" image="nginx:this-tag-does-not-exist"
```

### 7. Answers for the broken pod

**Question 1:** What is the Pod status?
*Answer:* `0/1 ErrImagePull` right after creation, and then `ImagePullBackOff` while Kubernetes waits to retry. It never reaches Running.

**Question 2:** What is the actual error?
*Answer:* `Failed to pull image "nginx:this-tag-does-not-exist": rpc error: code = NotFound`. The registry says that tag does not exist.

**Question 3:** Which command helped you find the reason?
*Answer:* `kubectl describe pod project-broken-pod -n s14-mini`, the Events section. `kubectl get` only gave me the status name.

**Question 4:** What is wrong with the image?
*Answer:* the repository `nginx` is fine, but the tag `this-tag-does-not-exist` is not a real tag, so there is nothing to pull. Pulling it by hand on the node with `crictl pull` gives the same "not found".

**Question 5:** How would you fix it?
*Answer:* use a tag that exists, here `nginx:1.27` (the same one the Deployment uses). The image field can be changed on a live pod, so `kubectl apply -f fixed-pod.yaml` was enough:

![mini broken pod fixed](screenshots/s14-43-mini-broken-pod-fixed.png)

```text
$ diff broken-pod.yaml fixed-pod.yaml
11c11
<       image: nginx:this-tag-does-not-exist
---
>       image: nginx:1.27

$ kubectl apply -f fixed-pod.yaml
Warning: resource pods/project-broken-pod is missing the kubectl.kubernetes.io/last-applied-configuration annotation which is required by kubectl apply. kubectl apply should only be used on resources created declaratively by either kubectl create --save-config or kubectl apply. The missing annotation will be patched automatically.
pod/project-broken-pod configured

$ kubectl wait --for=condition=Ready pod/project-broken-pod -n s14-mini --timeout=60s
pod/project-broken-pod condition met

$ kubectl get pod project-broken-pod -n s14-mini
NAME                 READY   STATUS    RESTARTS   AGE
project-broken-pod   1/1     Running   0          13s
```

### 8-9. Service selector challenge

I changed the selector to `app: wrong-app`. The Service still exists and still has a ClusterIP, but the endpoints are `<none>` and curl fails. `--show-labels` shows the pods have `app=troubleshooting-app`, which does not match `app=wrong-app`.

![mini selector before](screenshots/s14-44-mini-selector-before.png)

```text
$ diff service.yaml service-wrong-selector.yaml
10c10
<     app: troubleshooting-app
---
>     app: wrong-app

$ kubectl apply -f service-wrong-selector.yaml
service/troubleshooting-service configured

$ kubectl get service -n s14-mini
NAME                      TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE
troubleshooting-service   ClusterIP   10.97.193.125   <none>        80/TCP    20s

$ sleep 2; kubectl get endpoints troubleshooting-service -n s14-mini
Warning: v1 Endpoints is deprecated in v1.33+; use discovery.k8s.io/v1 EndpointSlice
NAME                      ENDPOINTS   AGE
troubleshooting-service   <none>      22s

$ kubectl get pods -n s14-mini --show-labels | cut -c1-120
NAME                                   READY   STATUS    RESTARTS   AGE   LABELS
project-broken-pod                     1/1     Running   0          14s   <none>
troubleshooting-app-59d4957864-7nwl7   1/1     Running   0          21s   app=troubleshooting-app,pod-template-hash=59d4
troubleshooting-app-59d4957864-hvmxb   1/1     Running   0          22s   app=troubleshooting-app,pod-template-hash=59d4

$ kubectl describe service troubleshooting-service -n s14-mini | grep -E 'Selector|Endpoints'
Selector:                 app=wrong-app
Endpoints:

$ kubectl exec -n s14-mini project-broken-pod -- curl -sS -m 3 http://troubleshooting-service; echo "exit=$?"
curl: (7) Failed to connect to troubleshooting-service port 80 after 6 ms: Couldn't connect to server
command terminated with exit code 7
exit=7
```

Fix: put the selector back to `app: troubleshooting-app`. Endpoints come back, the name resolves through cluster DNS, and curl works:

![mini selector after](screenshots/s14-45-mini-selector-after.png)

```text
$ kubectl apply -f service.yaml
service/troubleshooting-service configured

$ sleep 2; kubectl get endpoints troubleshooting-service -n s14-mini
Warning: v1 Endpoints is deprecated in v1.33+; use discovery.k8s.io/v1 EndpointSlice
NAME                      ENDPOINTS                         AGE
troubleshooting-service   10.244.0.220:80,10.244.0.221:80   27s

$ kubectl exec -n s14-mini project-broken-pod -- getent hosts troubleshooting-service
10.97.193.125   troubleshooting-service.s14-mini.svc.cluster.local

$ kubectl exec -n s14-mini project-broken-pod -- curl -sS -m 3 http://troubleshooting-service | grep -o '<title>.*</title>'
<title>Welcome to nginx!</title>
```

### 11. Troubleshooting table

| Problem | What I Saw | Command I Used | Root Cause | Fix |
| :--- | :--- | :--- | :--- | :--- |
| **Broken Pod** | `project-broken-pod` stuck at `0/1 ErrImagePull` / `ImagePullBackOff` | `kubectl describe pod project-broken-pod` (Events) | Image `nginx:this-tag-does-not-exist` cannot be pulled | Change image to `nginx:1.27` and apply |
| **Service Problem** | Service has a ClusterIP but `Endpoints: <none>`; curl fails | `kubectl get endpoints`, `kubectl get pods --show-labels`, `kubectl describe service` | Selector `app=wrong-app` does not match pod label `app=troubleshooting-app` | Selector back to `app: troubleshooting-app` |
| **Image Problem** | Events: `Failed to pull image ... NotFound`, then `Back-off pulling image` | `kubectl describe pod`, `crictl pull` on the node | The tag does not exist in the registry | Use a real tag (`nginx:1.27`); pin real versions instead of guessing |

### 12. README questions

1. **What does `kubectl get` tell us?** A one line summary per object: name, ready count, status, restarts, age. With `-o wide` also IP and node. It tells me *that* something is wrong, not *why*.
2. **Difference between `get` and `describe`?** `get` is the short list; `describe` is the full detail of one object: container states, exit codes, mounts, selectors, endpoints and the Events. `describe` usually tells me why.
3. **Why do we use `kubectl logs`?** To read what the application itself printed (stdout/stderr). It is how I found `DATABASE_URL environment variable is MISSING!` in scenario 1. `--previous` gives the log of the crashed run.
4. **When would you use `kubectl exec`?** When the pod is Running but something still does not work: to curl localhost, check which port the app listens on (`netstat -tln`), read `/etc/resolv.conf`, or run `nslookup` from inside the cluster.
5. **What does `CrashLoopBackOff` mean?** The container started, exited, and was restarted again and again; Kubernetes now waits longer (back-off) between restarts. The container does run, so `logs --previous` usually shows the reason.
6. **What does `ImagePullBackOff` mean?** The kubelet failed to pull the image (`ErrImagePull`) and is now waiting before trying again. The container never ran, so there are no logs; the reason is in the Events.
7. **Why can a Pod remain `Pending`?** The scheduler cannot find a node for it: a nodeSelector/affinity no node matches, requests larger than any node's free CPU/memory, taints without tolerations, or an unbound PVC.
8. **Why can a Service have no endpoints?** Its selector matches no pods (typo, wrong label), the matching pods are not Ready, or they are in a different namespace than the Service.
9. **Relationship between a Service selector and Pod labels?** The selector is a label query. Every Ready pod in the same namespace whose labels contain all the selector's key=value pairs becomes an endpoint. Nothing else links them; a one character difference means no traffic.
10. **What is Kubernetes DNS?** CoreDNS running in `kube-system` behind the `kube-dns` Service (`10.96.0.10` here). Every pod gets it as its nameserver, and every Service gets a name `<service>.<namespace>.svc.cluster.local`. The search list in the pod's resolv.conf lets me use the short name inside the same namespace.

### Course scenarios (triage gauntlet)

The course `scenarios/` folder deploys 5 broken pods at once. I added `namespace: s14-triage` to each file and `-n s14-triage` to the final `kubectl get` in `triage_all.sh`, then ran it.

![triage deploy](screenshots/s14-46-triage-deploy.png)

```text
$ kubectl create namespace s14-triage
namespace/s14-triage created

$ ./triage_all.sh
==================================================
      KUBERNETES INCIDENT TRIAGE GAUNTLET         
==================================================
Deploying 5 intentionally broken production workloads...

pod/fail-1-crashloop-pod created
pod/fail-2-imagepull-pod created
pod/fail-3-pending-pod created
pod/fail-4-dns-failure-pod created
pod/fail-5-oomkilled-pod created

Workloads deployed! Sleeping 5s to allow states to settle...

=== CURRENT CLUSTER CARNAGE ===
NAME                     READY   STATUS              RESTARTS   AGE
fail-1-crashloop-pod     1/1     Running             0          7s
fail-2-imagepull-pod     0/1     ContainerCreating   0          6s
fail-3-pending-pod       0/1     Pending             0          6s
fail-4-dns-failure-pod   1/1     Running             0          6s
fail-5-oomkilled-pod     1/1     Running             0          6s

==================================================
Your mission: Diagnose and fix each of the 5 pods!
Follow the diagnostic guide in README.md!
==================================================

$ sleep 20; kubectl get pods -n s14-triage -l tier=triage-gauntlet
NAME                     READY   STATUS              RESTARTS      AGE
fail-1-crashloop-pod     0/1     CrashLoopBackOff    1 (17s ago)   27s
fail-2-imagepull-pod     0/1     ContainerCreating   0             26s
fail-3-pending-pod       0/1     Pending             0             26s
fail-4-dns-failure-pod   1/1     Running             0             26s
fail-5-oomkilled-pod     0/1     CrashLoopBackOff    1 (17s ago)   26s
```

After 20 seconds: scenario 1 and 5 are in `CrashLoopBackOff`, 2 is still trying to pull, 3 is `Pending`, and 4 looks healthy (`Running`), which turned out to be the trap.

#### Scenario 1 - CrashLoopBackOff (missing env var)

**Problem / Investigation:** `CrashLoopBackOff`. `logs --previous` says it straight away: `[FATAL ERROR]: DATABASE_URL environment variable is MISSING!`.

**Root cause:** the app needs `DATABASE_URL` and exits with code 1 when it is not set. The pod spec has no env at all.

**Fix attempt 1** (`fix-attempt-1-env-only.yaml`): I only added the env var. The error went away, but the pod still did not stay up: it printed "Application started successfully!" and exited with code 0, so the status became `Completed` with the restart count still going up.

![scenario 1 investigate and first attempt](screenshots/s14-47-sc1-crashloop.png)

```text
$ kubectl get pod fail-1-crashloop-pod -n s14-triage
NAME                   READY   STATUS             RESTARTS      AGE
fail-1-crashloop-pod   0/1     CrashLoopBackOff   1 (17s ago)   27s

$ kubectl logs fail-1-crashloop-pod -n s14-triage --previous
[FATAL ERROR]: DATABASE_URL environment variable is MISSING!

$ kubectl replace --force -f scenario-1-crashloop/fix-attempt-1-env-only.yaml
pod "fail-1-crashloop-pod" deleted from s14-triage namespace
pod/fail-1-crashloop-pod replaced

$ sleep 25; kubectl get pod fail-1-crashloop-pod -n s14-triage
NAME                   READY   STATUS      RESTARTS      AGE
fail-1-crashloop-pod   0/1     Completed   2 (17s ago)   26s

$ kubectl logs fail-1-crashloop-pod -n s14-triage; kubectl get pod fail-1-crashloop-pod -n s14-triage -o jsonpath='{.status.containerStatuses[0].lastState.terminated.reason} exit={.status.containerStatuses[0].lastState.terminated.exitCode}{"\n"}'
Application started successfully!
Completed exit=0
```

**Real fix** (`fixed.yaml`): add `DATABASE_URL` and keep the process running after start-up (a long-running service must not exit; with `restartPolicy: Always` any exit counts as a crash). I also added small requests/limits.

**Verify:** Running, 0 restarts after 20+ seconds.

![scenario 1 fixed](screenshots/s14-48-sc1-fixed.png)

```text
$ diff scenario-1-crashloop/broken.yaml scenario-1-crashloop/fixed.yaml
12a13,15
>       env:
>         - name: DATABASE_URL            # FIX 1: provide the variable the app needs
>           value: "postgres://app:app@postgres-db.s14-triage.svc.cluster.local:5432/app"
17c20
<           import os, sys
---
>           import os, sys, time
22c25,30
<           print("Application started successfully!")
---
>           print("Application started successfully!", flush=True)
>           while True:                   # FIX 2: a long-running app must not exit
>               time.sleep(3600)
>       resources:
>         requests: {cpu: 10m, memory: 16Mi}
>         limits: {memory: 64Mi}

$ kubectl replace --force -f scenario-1-crashloop/fixed.yaml
pod "fail-1-crashloop-pod" deleted from s14-triage namespace
pod/fail-1-crashloop-pod replaced

$ kubectl wait --for=condition=Ready pod/fail-1-crashloop-pod -n s14-triage --timeout=60s; sleep 20
pod/fail-1-crashloop-pod condition met

$ kubectl get pod fail-1-crashloop-pod -n s14-triage; kubectl logs fail-1-crashloop-pod -n s14-triage
NAME                   READY   STATUS    RESTARTS   AGE
fail-1-crashloop-pod   1/1     Running   0          31s
Application started successfully!
```

#### Scenario 2 - ImagePullBackOff (image does not exist)

**Investigation:** `ImagePullBackOff`. The event and a manual `crictl pull` on the node both say `pull access denied, repository does not exist or may require authorization`. This is different from the course 07 example: there the repository (`nginx`) existed and only the tag was wrong (`not found`); here the whole repository `docker.io/library/yatri-api-service` does not exist (or would be private).

**Root cause:** wrong image name and tag. **Fix:** I could not find a real `yatri-api-service` image anywhere, so I used `nginx:1.27` as a stand-in for the real app image. In a real team I would ask for the correct registry path and tag, and add an `imagePullSecret` if it is a private registry.

![scenario 2](screenshots/s14-49-sc2-imagepull.png)

```text
$ kubectl get pod fail-2-imagepull-pod -n s14-triage
NAME                   READY   STATUS             RESTARTS   AGE
fail-2-imagepull-pod   0/1     ImagePullBackOff   0          96s

$ kubectl events -n s14-triage --for pod/fail-2-imagepull-pod | grep -m1 'Failed to pull' | cut -c1-150
56s (x2 over 70s)   Warning   Failed      Pod/fail-2-imagepull-pod   Failed to pull image "yatri-api-service:v999-invalid-tag-does-not-exist": failed

$ minikube ssh -- sudo crictl pull yatri-api-service:v999-invalid-tag-does-not-exist 2>&1 | grep -o 'pull access denied.*\|not found.*\|insufficient_scope.*' | head -1 | cut -c1-140
pull access denied, repository does not exist or may require authorization: server message: insufficient_scope: authorization failed" image=

$ kubectl replace --force -f scenario-2-imagepull/fixed.yaml
pod "fail-2-imagepull-pod" deleted from s14-triage namespace
pod/fail-2-imagepull-pod replaced

$ kubectl wait --for=condition=Ready pod/fail-2-imagepull-pod -n s14-triage --timeout=60s
pod/fail-2-imagepull-pod condition met

$ kubectl get pod fail-2-imagepull-pod -n s14-triage
NAME                   READY   STATUS    RESTARTS   AGE
fail-2-imagepull-pod   1/1     Running   0          1s
```

#### Scenario 3 - Pending (impossible resource requests)

**Investigation:** `Pending` with `FailedScheduling: 0/1 nodes are available: 1 Insufficient cpu, 1 Insufficient memory`. The node has 15 CPUs and about 7.7 GiB allocatable; the pod asked for `cpu: "500"` and `memory: "1000Gi"`.

**Root cause:** requests larger than any node can ever offer. **Fix:** realistic requests (`50m` CPU, `32Mi` memory, `64Mi` limit). Requests are immutable on a pod, so I recreated it.

![scenario 3](screenshots/s14-50-sc3-pending.png)

```text
$ kubectl get pod fail-3-pending-pod -n s14-triage
NAME                 READY   STATUS    RESTARTS   AGE
fail-3-pending-pod   0/1     Pending   0          117s

$ kubectl describe pod fail-3-pending-pod -n s14-triage | sed -n '/Events:/,$p' | cut -c1-150
Events:
  Type     Reason            Age                 From               Message
  ----     ------            ----                ----               -------
  Warning  FailedScheduling  2s (x17 over 118s)  default-scheduler  0/1 nodes are available: 1 Insufficient cpu, 1 Insufficient memory. preemption: 0/

$ kubectl get node minikube -o jsonpath='allocatable cpu={.status.allocatable.cpu} memory={.status.allocatable.memory}{"\n"}'
allocatable cpu=15 memory=8125796Ki

$ kubectl replace --force -f scenario-3-pending/fixed.yaml
pod "fail-3-pending-pod" deleted from s14-triage namespace
pod/fail-3-pending-pod replaced

$ kubectl wait --for=condition=Ready pod/fail-3-pending-pod -n s14-triage --timeout=120s
pod/fail-3-pending-pod condition met

$ kubectl get pod fail-3-pending-pod -n s14-triage -o wide | cut -c1-100
NAME                 READY   STATUS    RESTARTS   AGE   IP             NODE       NOMINATED NODE   R
fail-3-pending-pod   1/1     Running   0          10s   10.244.0.248   minikube   <none>           <
```

#### Scenario 4 - DNS failure hidden behind "Running"

**Investigation:** the pod is `Running 1/1`, and the logs only say "Attempting connection..." then "Process sleeping...". The error was hidden because the script uses `curl -s ... || true`. Running the lookup myself with `kubectl exec` gives `NXDOMAIN` for `postgres-db-wrong-name.production.svc.cluster.local`, curl gives `Could not resolve host`, and there is not even a `production` namespace on this cluster.

![scenario 4 investigate](screenshots/s14-51-sc4-dns-before.png)

```text
$ kubectl get pod fail-4-dns-failure-pod -n s14-triage
NAME                     READY   STATUS    RESTARTS   AGE
fail-4-dns-failure-pod   1/1     Running   0          2m8s

$ kubectl logs fail-4-dns-failure-pod -n s14-triage
Attempting connection to internal database...
Process sleeping...

$ kubectl exec fail-4-dns-failure-pod -n s14-triage -- nslookup postgres-db-wrong-name.production.svc.cluster.local 2>&1 | tail -3
** server can't find postgres-db-wrong-name.production.svc.cluster.local: NXDOMAIN

command terminated with exit code 1

$ kubectl exec fail-4-dns-failure-pod -n s14-triage -- curl -sS --connect-timeout 3 http://postgres-db-wrong-name.production.svc.cluster.local:5432; echo "exit=$?"
curl: (6) Could not resolve host: postgres-db-wrong-name.production.svc.cluster.local
command terminated with exit code 6
exit=6

$ kubectl get namespace production
Error from server (NotFound): namespaces "production" not found
```

**Root cause:** wrong service name and wrong namespace in the hostname (and a script that swallows the error).

**Fix:** there is no real database in this course, so I created a stand-in `postgres-db` Service on port 5432 in `s14-triage` (`postgres-db-standin.yaml`, nginx behind port 5432; it proves DNS and TCP work, it is not a real PostgreSQL). Then I pointed the client at `postgres-db.s14-triage.svc.cluster.local:5432` and removed `-s` / `|| true` so errors show up in the logs next time.

**Verify:** the log now says it connected, and the name resolves to the Service IP.

![scenario 4 fixed](screenshots/s14-52-sc4-dns-after.png)

```text
$ kubectl apply -f scenario-4-dns-failure/postgres-db-standin.yaml
pod/postgres-db-standin created
service/postgres-db created

$ kubectl wait --for=condition=Ready pod/postgres-db-standin -n s14-triage --timeout=60s
pod/postgres-db-standin condition met

$ kubectl replace --force -f scenario-4-dns-failure/fixed.yaml
pod "fail-4-dns-failure-pod" deleted from s14-triage namespace
pod/fail-4-dns-failure-pod replaced

$ kubectl wait --for=condition=Ready pod/fail-4-dns-failure-pod -n s14-triage --timeout=60s; sleep 3
pod/fail-4-dns-failure-pod condition met

$ kubectl logs fail-4-dns-failure-pod -n s14-triage
Attempting connection to internal database...
connected, HTTP 200
Process sleeping...

$ kubectl exec fail-4-dns-failure-pod -n s14-triage -- nslookup postgres-db.s14-triage.svc.cluster.local 2>&1 | tail -3
Name:	postgres-db.s14-triage.svc.cluster.local
Address: 10.109.16.203
```

#### Scenario 5 - OOMKilled

**Investigation:** `CrashLoopBackOff`, and `describe` shows `Last State: Terminated, Reason: OOMKilled, Exit Code: 137` with `Limits: memory: 20Mi`. `logs --previous` returned `unable to retrieve container logs` at this point (after 5 OOM kills the previous container's log was not available any more), so `describe` was the evidence here, not the logs.

![scenario 5 investigate](screenshots/s14-53-sc5-oom-before.png)

```text
$ kubectl get pod fail-5-oomkilled-pod -n s14-triage
NAME                   READY   STATUS      RESTARTS        AGE
fail-5-oomkilled-pod   0/1     OOMKilled   5 (2m13s ago)   4m5s

$ kubectl describe pod fail-5-oomkilled-pod -n s14-triage | sed -n '/Last State/,/Restart Count/p;/Limits:/,/memory/p'
    Last State:     Terminated
      Reason:       OOMKilled
      Exit Code:    137
      Started:      Wed, 07 Oct 2026 22:31:20 +0530
      Finished:     Wed, 07 Oct 2026 22:31:21 +0530
    Ready:          False
    Restart Count:  5
    Limits:
      memory:  20Mi

$ kubectl logs fail-5-oomkilled-pod -n s14-triage --previous
unable to retrieve container logs for containerd://dc7ea400b917a4c2a90b2ee5f0cb08885a8395c881912fbd2662bbf67a6a04e2
```

**Root cause:** the script tries to hold 100 x 10 MB = 1000 MB while the container limit is 20 Mi, so the kernel's OOM killer kills it (exit 137 = 128 + SIGKILL).

**Fix:** bounded allocation (3 x 10 MB) and a limit above the real usage (`64Mi`, request `48Mi`). I kept the numbers small because the cluster is shared.

**Verify:** Running, 0 restarts. My first `kubectl top` failed with `Metrics API not available` because metrics-server had just restarted in `kube-system` (not something I touched), so I ran it again a minute later: 33Mi used, under the 64Mi limit.

![scenario 5 fixed](screenshots/s14-54-sc5-oom-after.png)

```text
$ kubectl replace --force -f scenario-5-oomkilled/fixed.yaml
pod "fail-5-oomkilled-pod" deleted from s14-triage namespace
pod/fail-5-oomkilled-pod replaced

$ kubectl wait --for=condition=Ready pod/fail-5-oomkilled-pod -n s14-triage --timeout=60s; sleep 45
pod/fail-5-oomkilled-pod condition met

$ kubectl get pod fail-5-oomkilled-pod -n s14-triage; kubectl logs fail-5-oomkilled-pod -n s14-triage
NAME                   READY   STATUS    RESTARTS   AGE
fail-5-oomkilled-pod   1/1     Running   0          66s
Allocating a bounded amount of memory...
Allocated 30 MB, staying up

$ kubectl top pod fail-5-oomkilled-pod -n s14-triage
error: Metrics API not available
```

![scenario 5 top](screenshots/s14-54b-sc5-top.png)

```text
$ kubectl get pod fail-5-oomkilled-pod -n s14-triage
NAME                   READY   STATUS    RESTARTS   AGE
fail-5-oomkilled-pod   1/1     Running   0          112s

$ kubectl top pod fail-5-oomkilled-pod -n s14-triage
NAME                   CPU(cores)   MEMORY(bytes)   
fail-5-oomkilled-pod   2m           33Mi

$ kubectl get pod fail-5-oomkilled-pod -n s14-triage -o jsonpath='requests={.spec.containers[0].resources.requests.memory} limits={.spec.containers[0].resources.limits.memory}{"\n"}'
requests=48Mi limits=64Mi
```

#### All five scenarios fixed

![triage final](screenshots/s14-55-triage-final.png)

```text
$ kubectl get pods -n s14-triage -o wide | cut -c1-110
NAME                     READY   STATUS    RESTARTS   AGE     IP             NODE       NOMINATED NODE   READI
fail-1-crashloop-pod     1/1     Running   0          4m17s   10.244.0.245   minikube   <none>           <none
fail-2-imagepull-pod     1/1     Running   0          3m25s   10.244.0.247   minikube   <none>           <none
fail-3-pending-pod       1/1     Running   0          3m23s   10.244.0.248   minikube   <none>           <none
fail-4-dns-failure-pod   1/1     Running   0          99s     10.244.0.252   minikube   <none>           <none
fail-5-oomkilled-pod     1/1     Running   0          67s     10.244.0.253   minikube   <none>           <none
postgres-db-standin      1/1     Running   0          3m12s   10.244.0.249   minikube   <none>           <none
```

---

## What I learned

- Follow the order get -> describe (Events) -> logs -> exec -> test. The status name tells me which tool to use next: image and scheduling problems live in Events, app problems live in logs, network problems need exec and curl.
- `Running` does not mean working. Scenario 4, Issue 8 and Issue 9 were all `Running 1/1` while the app could not do its job.
- `ErrImagePull` and `ImagePullBackOff` are the same problem at two moments: the failed pull, and the wait before the next try.
- `ContainerCreating` and `CreateContainerConfigError` both come from missing ConfigMaps/Secrets, and both heal on their own once the object exists. The kubelet keeps retrying, so no pod restart is needed.
- For Services I check three things in order: endpoints exist (selector matches labels), targetPort matches the port the app listens on, and the app listens on `0.0.0.0` and not on `127.0.0.1`.
- NXDOMAIN means DNS works but the name is wrong; a timeout means no DNS server answered. That one difference tells me whether to look at the name or at the pod's DNS config.
- Many pod fields cannot be edited in place (command, nodeSelector, resources, dnsPolicy). The image can. For the rest I used `kubectl replace --force`, which in real life I would avoid by using a Deployment.
- With `restartPolicy: Always`, even a clean `exit 0` is treated as a crash if the process should be long running.

## Problems I hit

- **The course DNS test image does not exist.** `09-service-dns-troubleshooting/dns-test-pod.yaml` uses `registry.k8s.io/e2e-test-images/dnsutils:1.3`. Pulling it on the node gave `registry.k8s.io/e2e-test-images/dnsutils:1.3: not found`, and the pod went to `ErrImagePull` (screenshot `s14-22`). I switched to `registry.k8s.io/e2e-test-images/agnhost:2.39`, the image the Kubernetes DNS debugging docs use, which has nslookup, dig and curl.
- **Scenario 1: my first fix was not enough.** Adding `DATABASE_URL` stopped the error, but the script then prints "started successfully" and exits with code 0. With the default `restartPolicy: Always` the pod went to `Completed` with the restart count still rising (screenshot `s14-47`). I had to also keep the process running.
- **Issue 9: curl still failed right after `rollout status` said "successfully rolled out".** At that moment the old pod (still bound to 127.0.0.1) was still Terminating; my best guess is that the request still went to it, or kube-proxy had not picked up the new endpoint yet. The old busybox httpd runs as PID 1 and does not react to SIGTERM, so it stayed around for the 30 second grace period and ended as `Error` (killed). When I checked again about 30 seconds later, curl worked.
- **The first mini project capture caught the broken pod too early.** After 6 seconds it was still `ContainerCreating` (pulling), with no failure in Events yet. I recreated it and waited until the status really was `ErrImagePull` before answering the questions.
- **`kubectl apply` warning after `kubectl replace --force`.** The replaced pod had no `last-applied-configuration` annotation, so the next `apply` printed a warning and patched it in. Harmless, but a sign that mixing `replace` and `apply` is messy.
- **Scenario 5: no previous logs and no metrics at first.** `kubectl logs --previous` on the OOMKilled pod returned `unable to retrieve container logs`, and my first `kubectl top` after the fix failed with `Metrics API not available` because metrics-server had restarted. I used `describe` (Last State OOMKilled, exit 137) as the evidence and re-ran `top` once metrics-server was Ready again.
- `kubectl get endpoints` prints `v1 Endpoints is deprecated in v1.33+`. I used it where the course asks for it, and EndpointSlices elsewhere.
- I did not use NetworkPolicy for the networking issue because kindnet (minikube's default CNI here) does not enforce it; the localhost binding problem is a real failure that does not depend on the CNI.

## Cleanup

I deleted only the namespaces I created. Nothing in `kube-system` or other namespaces was changed.

![cleanup](screenshots/s14-60-cleanup.png)

```text
$ kubectl delete namespace s14-basics s14-t2 s14-t2-client s14-mini s14-triage --wait=true --timeout=180s
namespace "s14-basics" deleted
namespace "s14-t2" deleted
namespace "s14-t2-client" deleted
namespace "s14-mini" deleted
namespace "s14-triage" deleted

$ kubectl get namespaces | grep -E '^s14-' || echo 'no s14-* namespaces left'
no s14-* namespaces left
```
