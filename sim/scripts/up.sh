#!/usr/bin/env bash
# One command to bring the cluster up in a working state: create it, then
# wire every node's proxy through the stable kind-proxy-relay container
# instead of the host's raw proxy address (which kind gets wrong and
# which used to need a manual fix after every single recreate).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SIM_DIR="$(dirname "$SCRIPT_DIR")"
CLUSTER_NAME="${1:-gpu-sim}"

kind create cluster --config "$SIM_DIR/kind-cluster.yaml" --name "$CLUSTER_NAME"
bash "$SCRIPT_DIR/setup-proxy-relay.sh"
bash "$SCRIPT_DIR/fix-node-proxy.sh" "$CLUSTER_NAME"

echo "Cluster '$CLUSTER_NAME' is up and its nodes can reach the internet through your proxy."
