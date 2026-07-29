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

(Further steps — Elasticsearch, the fake-node fleet, KubeAI — are added
below as they are built.)
