#!/usr/bin/env bash
set -euxo pipefail

ISTIO_REQUIRED="yes"
DEPLOY_NAMESPACE="nifi-demo"

require() {
    hash kubectl 2>/dev/null || { echo >&2 "kubectl is not installed.  Aborting."; exit 1; }
    hash istioctl 2>/dev/null || { echo >&2 "istioctl is not installed.  Aborting."; exit 1; }
    hash helm 2>/dev/null || { echo >&2 "helm is not installed.  Aborting."; exit 1; }
}

create_istio_gw() {
    openssl req -x509 -sha256 -nodes -days 365 -newkey rsa:4096 -subj '/O=trustbasevn Inc./CN=trustbase.vn' -keyout trustbase.vn.key -out trustbase.vn.crt
    openssl req -out gw.aks-npe.trustbase.vn.csr -newkey rsa:4096 -nodes -keyout gw.aks-npe.trustbase.vn.key -subj "/CN=*.aks-npe.trustbase.vn/O=trustbasevn Inc."
    openssl x509 -req -days 365 -CA trustbase.vn.crt -CAkey trustbase.vn.key -set_serial 0 -in gw.aks-npe.trustbase.vn.csr -out gw.aks-npe.trustbase.vn.crt
    kubectl create -n istio-system secret generic gw-credential --from-file=tls.key=gw.aks-npe.trustbase.vn.key \
        --from-file=tls.crt=gw.aks-npe.trustbase.vn.crt --from-file=ca.crt=trustbase.vn.crt
    kubectl apply -n istio-system -f istio-gw.yml
}

installed_istio_version() {
    local installed_version=$(istioctl version | grep "control plane" | cut -d':' -f2 | xargs)
    echo "$installed_version"
}

install_istio() {
    bash istio.sh
}

install_cert_manager() {
    helm repo add jetstack https://charts.jetstack.io
    # Update your local Helm chart repository cache
    helm repo update

    # Install the cert-manager Helm chart
    helm install \
    cert-manager jetstack/cert-manager \
    --namespace cert-manager \
    --create-namespace \
    --version v1.14.3 \
    --set installCRDs=true
}

install_nifi() {
    local name="${1:?name is required}"
    local chartPath="${2:?chartPath is required}"
    local valueFilePath="${3:?valueFilePath is required}"
    pushd .
    cd $chartPath
    helm repo add bitnami https://charts.bitnami.com/bitnami
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo add dysnix https://dysnix.github.io/charts/
    helm repo add helm-repo https://charts.helm.sh/stable
    helm repo update
    helm dep up
    popd

    if kubectl get namespace "$DEPLOY_NAMESPACE" > /dev/null 2>&1; then
        echo "Namespace $DEPLOY_NAMESPACE exists."
    else
        echo "Namespace $DEPLOY_NAMESPACE does not exist. Creating ..."
        kubectl create ns $DEPLOY_NAMESPACE
        kubectl label namespace $DEPLOY_NAMESPACE istio-injection=enabled
    fi


    helm upgrade --install -f $valueFilePath $name $chartPath -n $DEPLOY_NAMESPACE
    kubectl apply -f nifi-vs.yml -n $DEPLOY_NAMESPACE

}

require
istio_version=$(installed_istio_version)
if [ "x$istio_version" = "x" -a "$ISTIO_REQUIRED" = "yes" ]; then
    install_istio
    create_istio_gw
fi

if kubectl get namespace cert-manager > /dev/null 2>&1; then
    echo "Namespace cert-manager exists."
else
    echo "Installing cert-manager ..."
    install_cert_manager
fi


# install "$@"
install_nifi nifi-release ./helm-nifi values-oidc.yml