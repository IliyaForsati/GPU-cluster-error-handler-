#!/usr/bin/env bash
# Installs the official ECK operator + CRDs. Vendored as a script instead
# of a local copy, since Elastic publishes and maintains these manifests
# themselves - copying them in would just go stale.
set -euo pipefail

ECK_VERSION="2.14.0"

kubectl create -f "https://download.elastic.co/downloads/eck/${ECK_VERSION}/crds.yaml"
kubectl apply -f "https://download.elastic.co/downloads/eck/${ECK_VERSION}/operator.yaml"

echo "Waiting for the ECK operator pod to be created..."
# `kubectl wait` errors immediately with "no matching resources found" if
# no pod exists yet for the selector - it does not wait for the resource
# to appear, only for a condition on ones that already exist. There's a
# real gap between the StatefulSet being applied and its pod object
# existing, so this has to be polled first.
until kubectl -n elastic-system get pod --selector=control-plane=elastic-operator 2>/dev/null | grep -q elastic-operator; do
  sleep 2
done

echo "Waiting for the ECK operator pod to be ready..."
kubectl -n elastic-system wait --for=condition=Ready pod --selector=control-plane=elastic-operator --timeout=180s
