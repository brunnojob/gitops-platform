#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/brunnojob/gitops-platform.git"
ARGOCD_HOST="argocd.platform.example.org"
CHART_VERSION="10.19.1"
NAMESPACE="argocd"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

for name in kubectl helm git argocd; do
  if ! command -v "${name}" >/dev/null 2>&1; then
    printf 'Ferramenta ausente: %s\n' "${name}" >&2
    exit 1
  fi
done
if [[ "${ARGOCD_HOST}" == *.example.org ]]; then
  printf 'Substitua o domínio de exemplo nos manifestos e neste script antes da instalação.\n' >&2
  exit 1
fi
if ! git ls-remote --exit-code "${REPO_URL}" refs/heads/main >/dev/null 2>&1; then
  printf 'Repositório ou branch main indisponível: %s\n' "${REPO_URL}" >&2
  exit 1
fi
kubectl cluster-info >/dev/null
kubectl get ingressclass nginx >/dev/null
kubectl get clusterissuer letsencrypt-production >/dev/null
kubectl get crd servicemonitors.monitoring.coreos.com >/dev/null
helm repo add argo https://argoproj.github.io/argo-helm --force-update
helm repo update argo
kubectl apply -k "${PROJECT_DIR}/bootstrap"
helm upgrade --install argocd argo/argo-cd \
  --namespace "${NAMESPACE}" \
  --version "${CHART_VERSION}" \
  --values "${PROJECT_DIR}/bootstrap/values-argocd.yaml" \
  --wait --timeout 15m
kubectl rollout status statefulset/argocd-application-controller -n "${NAMESPACE}" --timeout 10m
for component in server repo-server applicationset-controller notifications-controller; do
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
printf 'Login: argocd login %s --username admin\n' "${ARGOCD_HOST}"
printf 'Repositório privado: argocd repo add %s --username SEU_USUARIO --password SEU_TOKEN\n' "${REPO_URL}"
printf 'Repositório público: não é necessário cadastrar credenciais.\n'
