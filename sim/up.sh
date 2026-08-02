#!/usr/bin/env bash
# One command for the whole simulation: cluster, proxy fix, Elasticsearch +
# Kibana, the fake-node fleet, and KubeAI managing the fake-vLLM model.
# Before this script existed, bringing the stack up meant running every
# command in README.md by hand, in order, waiting on each one - easy to
# get wrong or forget a step. Safe to re-run: every step below is either
# idempotent or only runs once the previous one succeeded.
set -euo pipefail

SIM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLUSTER_NAME="${1:-gpu-sim}"

# Without this, kubectl (and anything else hitting 127.0.0.1) can get
# routed through an HTTP/SOCKS proxy that can't reach localhost, and just
# hangs - see sim/scripts/fix-node-proxy.sh for the node-side half of
# this same class of bug.
export NO_PROXY="${NO_PROXY:-127.0.0.1,localhost}"
export no_proxy="${no_proxy:-127.0.0.1,localhost}"

echo "=== 1/5: kind cluster + proxy relay ==="
bash "$SIM_DIR/scripts/up.sh" "$CLUSTER_NAME"

# The API server is still stabilizing right after node join - RBAC and
# the OpenAPI schema aren't always ready yet, so even `kubectl wait`
# itself can fail with transient errors (EOF, "unknown", Forbidden).
# A single wait isn't enough; retry until a real kubectl call succeeds.
echo "Waiting for the API server to settle..."
for i in $(seq 1 30); do
  kubectl get nodes >/dev/null 2>&1 && break
  sleep 3
done
kubectl wait --for=condition=Ready nodes --all --timeout=120s >/dev/null

echo "=== 2/5: Elasticsearch + Kibana ==="
kubectl apply -f "$SIM_DIR/k8s/namespace.yaml"
bash "$SIM_DIR/k8s/eck/install-eck-operator.sh"
kubectl apply -f "$SIM_DIR/k8s/eck/elasticsearch.yaml"
kubectl apply -f "$SIM_DIR/k8s/eck/kibana.yaml"

echo "Waiting for Elasticsearch to go green (first pull is ~1.2GB, can take a few minutes)..."
until [ "$(kubectl -n gpu-sim get elasticsearch gpu-sim-es -o jsonpath='{.status.health}' 2>/dev/null)" = "green" ]; do
  sleep 10
done
echo "Waiting for Kibana..."
until [ "$(kubectl -n gpu-sim get kibana gpu-sim-kibana -o jsonpath='{.status.health}' 2>/dev/null)" = "green" ]; do
  sleep 10
done

echo "=== 3/5: fake-node fleet ==="
docker build -t fake-node-generator:local "$SIM_DIR/fake-node/"
kind load docker-image fake-node-generator:local --name "$CLUSTER_NAME"
kubectl apply -f "$SIM_DIR/k8s/fleet/fluent-bit-configmap.yaml"
kubectl apply -f "$SIM_DIR/k8s/fleet/fake-node-daemonset.yaml"

echo "=== 4/5: fake-vLLM image ==="
docker build -t fake-vllm:local "$SIM_DIR/fake-vllm/"
kind load docker-image fake-vllm:local --name "$CLUSTER_NAME"

echo "=== 5/5: KubeAI ==="
helm repo add kubeai https://www.kubeai.org >/dev/null 2>&1 || true
helm repo update >/dev/null
helm install kubeai kubeai/kubeai -n gpu-sim -f "$SIM_DIR/k8s/kubeai/kubeai-helm-values.yaml" --wait
kubectl apply -f "$SIM_DIR/k8s/kubeai/fake-model.yaml"

echo
echo "Done. Everything is up:"
kubectl get nodes
kubectl -n gpu-sim get elasticsearch,kibana,pods -l app=fake-node
kubectl -n gpu-sim get model fake-vllm

# The elastic user's password is auto-generated fresh by ECK on every
# Elasticsearch create, so it's different every time up.sh is run -
# printing it here saves having to know/remember the get-secret command.
ELASTIC_PASSWORD="$(kubectl -n gpu-sim get secret gpu-sim-es-es-elastic-user -o go-template='{{.data.elastic | base64decode}}')"
echo
echo "Elasticsearch: https://localhost:9200  (user: elastic, password: ${ELASTIC_PASSWORD})"
echo "Kibana:        https://localhost:5601  (user: elastic, password: ${ELASTIC_PASSWORD})"
