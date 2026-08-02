#!/usr/bin/env bash
# Tears down everything up.sh brings up: the kind cluster (which takes
# Elasticsearch, Kibana, the fake-node fleet, and KubeAI down with it,
# since they're all just pods on that cluster) and the proxy relay
# container, which lives outside the cluster so it survives cluster
# deletes on its own otherwise.
set -euo pipefail

CLUSTER_NAME="${1:-gpu-sim}"

kind delete cluster --name "$CLUSTER_NAME"
docker rm -f kind-proxy-relay >/dev/null 2>&1 || true

echo "Cluster '$CLUSTER_NAME' and the proxy relay are gone."
