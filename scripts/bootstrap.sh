#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/brunnojob/gitops-platform.git"
CHART_VERSION="10.19.1"
NAMESPACE="argocd"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

for name in kubectl helm git; do
  if ! command -v "${name}" >/dev/null 2>&1; then
    printf 'Ferramenta ausente: %s\n' "${name}" >&2
    exit 1
  fi
done
if ! git ls-remote --exit-code "${REPO_URL}" refs/heads/main >/dev/null 2>&1; then
  printf 'Repositório ou branch main indisponível: %s\n' "${REPO_URL}" >&2
  exit 1
fi
kubectl cluster-info >/dev/null
helm repo add argo https://argoproj.github.io/argo-helm --force-update
helm repo update argo
kubectl apply -k "${PROJECT_DIR}/bootstrap"
helm upgrade --install argocd argo/argo-cd \
  --namespace "${NAMESPACE}" \
  --version "${CHART_VERSION}" \
  --values "${PROJECT_DIR}/bootstrap/values-argocd.yaml" \
  --wait --timeout 15m
kubectl rollout status statefulset/argocd-application-controller -n "${NAMESPACE}" --timeout 10m
for component in server repo-server applicationset-controller; do
  kubectl rollout status "deployment/argocd-${component}" -n "${NAMESPACE}" --timeout 10m
done
kubectl apply -n "${NAMESPACE}" --server-side -f "${PROJECT_DIR}/bootstrap/root-app.yaml"
printf '\nAplicação raiz aplicada. Aguarde: argocd app wait gitops-platform --sync --timeout 600\n'
if kubectl get secret argocd-initial-admin-secret -n "${NAMESPACE}" >/dev/null 2>&1; then
  password="$(kubectl get secret argocd-initial-admin-secret -n "${NAMESPACE}" -o jsonpath='{.data.password}' | base64 --decode)"
  printf 'Senha inicial admin: %s\n' "${password}"
else
  printf 'Senha inicial indisponível; use a credencial admin existente.\n'
fi
printf 'Acesso local: kubectl -n argocd port-forward svc/argocd-server 8080:443\n'
printf 'CLI: argocd login localhost:8080 --username admin --insecure\n'
printf 'Repositório público: não é necessário cadastrar credenciais.\n'
