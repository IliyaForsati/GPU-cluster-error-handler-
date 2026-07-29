# Local simulation of the GPU cluster

This folder simulates the cluster from `../demo.md` on a laptop, so the
error-handling design (Kibana Alerting + LLM + StackStorm) can be built and
tested without access to the real 32-node cluster. It does NOT include the
error-handling part itself — see `../demo.md` section 4.2-4.4 for what is
still missing.

Scaled down from the real cluster: 8 fake worker nodes (instead of 32),
each simulating 8 fake H200 GPUs.

## 1. Bring up the local Kubernetes cluster

Requires [kind](https://kind.sigs.k8s.io/) and Docker.

```
kind create cluster --config kind-cluster.yaml --name gpu-sim
kubectl get nodes --show-labels   # confirms 8 nodes with node-role=gpu-worker
```

Tear down:

```
kind delete cluster --name gpu-sim
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

Get the auto-generated `elastic` user password and open Kibana:

```
kubectl -n gpu-sim get secret gpu-sim-es-es-elastic-user -o go-template='{{.data.elastic | base64decode}}'
kubectl -n gpu-sim port-forward service/gpu-sim-kibana-kb-http 5601
# then open https://localhost:5601 (user: elastic)
```

(Further steps — the fake-node fleet, KubeAI — are added below as they
are built.)
