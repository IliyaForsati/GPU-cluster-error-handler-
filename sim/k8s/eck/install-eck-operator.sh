#!/usr/bin/env bash
# Installs the official ECK operator + CRDs. Vendored as a script instead
# of a local copy, since Elastic publishes and maintains these manifests
# themselves - copying them in would just go stale.
set -euo pipefail

ECK_VERSION="2.14.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# On a server with no outbound internet at all, drop the same two files
# Elastic publishes into vendor/ (untracked - see .gitignore) and this
# picks them up instead of trying to fetch them. Still fetches straight
# from Elastic by default everywhere else, so nothing here can go stale.
CRDS_FILE="$SCRIPT_DIR/vendor/crds.yaml"
OPERATOR_FILE="$SCRIPT_DIR/vendor/operator.yaml"

if [ -f "$CRDS_FILE" ] && [ -f "$OPERATOR_FILE" ]; then
  kubectl create -f "$CRDS_FILE"
  kubectl apply -f "$OPERATOR_FILE"
else
  # Bounded so a machine with no internet route to Elastic's CDN fails
  # fast and loud instead of kubectl hanging on the URL fetch - drop the
  # two files into vendor/ (see above) to avoid this fetch entirely.
  timeout 30 kubectl create -f "https://download.elastic.co/downloads/eck/${ECK_VERSION}/crds.yaml"
  timeout 30 kubectl apply -f "https://download.elastic.co/downloads/eck/${ECK_VERSION}/operator.yaml"
fi

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
