#!/usr/bin/env bash
# Installs the official ECK operator + CRDs. Vendored as a script instead
# of a local copy, since Elastic publishes and maintains these manifests
# themselves - copying them in would just go stale.
set -euo pipefail

ECK_VERSION="2.14.0"

kubectl create -f "https://download.elastic.co/downloads/eck/${ECK_VERSION}/crds.yaml"
kubectl apply -f "https://download.elastic.co/downloads/eck/${ECK_VERSION}/operator.yaml"

echo "Waiting for the ECK operator pod to be ready..."
kubectl -n elastic-system wait --for=condition=Ready pod --selector=control-plane=elastic-operator --timeout=180s
