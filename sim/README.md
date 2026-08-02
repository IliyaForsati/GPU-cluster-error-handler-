# Local simulation of the GPU cluster

This folder simulates the cluster from `../demo.md` on a laptop, so the
error-handling design (Kibana Alerting + LLM + StackStorm) can be built and
tested without access to the real 32-node cluster. It does NOT include the
error-handling part itself — see `../demo.md` section 4.2-4.4 for what is
still missing.

Scaled down from the real cluster: 4 fake worker nodes + 1 control-plane
node (instead of 32 workers), each worker simulating 8 fake H200 GPUs.
This is a smaller footprint than the original 8-node simulation, to fit
on machines with less CPU/RAM free.

## Quick start

```
bash up.sh    # brings up everything: cluster, ES/Kibana, fake nodes, KubeAI
bash down.sh  # tears it all back down
```

Both are safe to re-run. The sections below explain what each step does
and how to run them one at a time, e.g. to iterate on a single piece
without rebuilding everything.

## 1. Bring up the local Kubernetes cluster

Requires [kind](https://kind.sigs.k8s.io/) and Docker.

If your host uses an HTTP/SOCKS proxy (e.g. v2ray), use the wrapper script -
kind copies your host's proxy address into every node, but that address
(usually `127.0.0.1:PORT`) is wrong inside a container, and normally has to
be fixed by hand after every single recreate. `scripts/up.sh` fixes this
automatically by pointing every node at a small relay container
(`kind-proxy-relay`) that forwards to your host proxy - see
`scripts/setup-proxy-relay.sh` and `scripts/fix-node-proxy.sh` for how:

```
bash scripts/up.sh
kubectl get nodes --show-labels   # confirms 4 nodes with node-role=gpu-worker
```

If you don't use a proxy, plain `kind create cluster --config
kind-cluster.yaml --name gpu-sim` works the same way.

Tear down:

```
kind delete cluster --name gpu-sim
docker rm -f kind-proxy-relay   # only if you used scripts/up.sh
```

## 2. Elasticsearch (3 nodes) + Kibana, via ECK

Requires the [ECK operator](https://www.elastic.co/guide/en/cloud-on-k8s/current/index.html)
(installed once per cluster) and Helm is not needed for this part.

```
kubectl apply -f k8s/namespace.yaml
bash k8s/eck/install-eck-operator.sh          # one-time: installs ECK CRDs + operator
kubectl apply -f k8s/eck/elasticsearch.yaml    # 3-node Elasticsearch
kubectl apply -f k8s/eck/kibana.yaml           # Kibana UI (no alert rules yet)

kubectl -n gpu-sim get elasticsearch,kibana    # wait for phase: Ready
```

Both are already reachable directly on localhost - no port-forward needed -
because `kind-cluster.yaml` maps host ports 9200/5601 straight to the
NodePort Services set in elasticsearch.yaml/kibana.yaml. Get the
auto-generated `elastic` user password and open Kibana:

```
kubectl -n gpu-sim get secret gpu-sim-es-es-elastic-user -o go-template='{{.data.elastic | base64decode}}'
# then open https://localhost:5601 (user: elastic) or curl https://localhost:9200
```

(`up.sh` prints this password automatically at the end of the run.)

## 3. The fake-node fleet (4 nodes, 8 fake GPUs each)

Build the generator image and load it into the kind cluster (kind
nodes don't see your local Docker registry by default):

```
docker build -t fake-node-generator:local fake-node/
kind load docker-image fake-node-generator:local --name gpu-sim
```

Then deploy the DaemonSet (1 pod per gpu-worker node, so 4 pods total)
and its Fluent Bit sidecar config:

```
kubectl apply -f k8s/fleet/fluent-bit-configmap.yaml
kubectl apply -f k8s/fleet/fake-node-daemonset.yaml

kubectl -n gpu-sim get pods -l app=fake-node   # expect 4 Running pods
```

Check data is landing in Elasticsearch (after port-forwarding Kibana,
see step 2): open Discover and look for the `fake-node-logs` and
`fake-node-metrics` indices. You should see normal request logs plus
occasional CUDA OOM / NCCL timeout / XID lines, and gauge/counter
metrics for 8 GPUs per node.

## 4. Dummy fake-vLLM workload

```
docker build -t fake-vllm:local fake-vllm/
kind load docker-image fake-vllm:local --name gpu-sim

kubectl apply -f k8s/fleet/fake-vllm-deployment.yaml
kubectl -n gpu-sim get pods -l app=fake-vllm   # expect 1 Running pod
```

## 5. KubeAI

```
helm repo add kubeai https://www.kubeai.org
helm repo update
helm install kubeai kubeai/kubeai -n gpu-sim -f k8s/kubeai/kubeai-helm-values.yaml --wait

kubectl -n gpu-sim get pods -l app.kubernetes.io/name=kubeai
```

Then let KubeAI manage the fake workload instead of the plain
Deployment from step 4:

```
kubectl delete -f k8s/fleet/fake-vllm-deployment.yaml
kubectl apply -f k8s/kubeai/fake-model.yaml
kubectl -n gpu-sim get model fake-vllm
```

Verified against a live KubeAI install: `kubectl -n gpu-sim get pods
-l model.kubeai.org/name=fake-vllm` should show one `Running` pod once
the Model is reconciled (a few seconds after apply).

## What this simulation does NOT include

Kibana Alerting rules, the advisory LLM, and StackStorm - see
`../demo.md` sections 4.2-4.4. Those are the next stage, once this
simulation is proven to produce realistic-enough logs and metrics.
