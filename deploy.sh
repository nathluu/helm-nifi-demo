#!/usr/bin/env bash

ISTIO_REQUIRED="yes"

require() {
    hash kubectl 2>/dev/null || { echo >&2 "kubectl is not installed.  Aborting."; exit 1; }
    hash istioctl 2>/dev/null || { echo >&2 "istioctl is not installed.  Aborting."; exit 1; }
    hash helm 2>/dev/null || { echo >&2 "helm is not installed.  Aborting."; exit 1; }
}

installed_istio_version() {
    local installed_version=$(istioctl version | grep "control plane" | cut -d':' -f2 | xargs)
    echo "$installed_version"
}

install_istio() {
    ./istio.sh
}

install() {
    local name="${1:?name is required}"
    local chartPath="${2:?chartPath is required}"
    local valueFilePath="${3:?valueFilePath is required}"

    helm repo add bitnami https://charts.bitnami.com/bitnami
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo update
    helm dep up
    result=$(kubectl get ns | grep "nifi-ns")
    if [ "x$result" = "x" ]; then
        kubectl create ns nifi-ns
        kubectl label namespace nifi-ns istio-injection=enabled
    fi
    helm install -f $valueFilePath $name $chartPath
}

require
istio_version=$(installed_istio_version)
if [ "x$istio_version" = "x" -a "$ISTIO_REQUIRED" = "yes" ]; then
    install_istio
fi
# install "$@"
# install values-zk.yml