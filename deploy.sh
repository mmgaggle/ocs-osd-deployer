#!/bin/bash

function usage {
  echo "export PULL_SECRET=<base64 encoded pull secret>"
  echo "./deploy.sh <consumer | provider>"
  exit 0
}

if [ $1="provider" ];then
  ADDON_NAME='ocs-provider-qe'
  echo "- Detected type provider, using add-on: ${ADDON_NAME}"
elsif [ $1="consumer" ];then
  ADDON_NAME='ocs-consumer-qe'
  echo "- Detected type consumer, using add-on: ${ADDON_NAME}"
else
  &usage
fi

if [ -z "${PULL_SECRET}" ];then
  echo " - Found pull secret"
else
  &usage
fi

if ! command -v oc &> /dev/null
then
  echo "openshift cli `oc` not found, aborting"
fi

echo "- Create openshift-storage namespace"
oc create ns openshift-storage

echo "- Creating pull-secret in ns: openshift-storage"
cat << EOF | oc apply -f -
---
apiVersion: v1
kind: Secret
metadata:
  name: ocs-osd-deployer-ps
  namespace: openshift-storage
type: kubernetes.io/dockercfg
data:
  .dockercfg: |
        "${PULL_SECRET}"
EOF
oc secrets link default ocs-osd-deployer-ps --for=pull

echo "- Creating catalog source"
cat << EOF | oc apply -f -
---
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: ocs-osd-deployer-catalogsource
  namespace: openshift-marketplace
spec:
  displayName: Managed OpenShift Data Foundation
  icon:
    base64data: PHN2ZyBpZD0iTGF5ZXJfMSIgZGF0YS1uYW1lPSJMYXllciAxIiB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAxOTIgMTQ1Ij48ZGVmcz48c3R5bGU+LmNscy0xe2ZpbGw6I2UwMDt9PC9zdHlsZT48L2RlZnM+PHRpdGxlPlJlZEhhdC1Mb2dvLUhhdC1Db2xvcjwvdGl0bGU+PHBhdGggZD0iTTE1Ny43Nyw2Mi42MWExNCwxNCwwLDAsMSwuMzEsMy40MmMwLDE0Ljg4LTE4LjEsMTcuNDYtMzAuNjEsMTcuNDZDNzguODMsODMuNDksNDIuNTMsNTMuMjYsNDIuNTMsNDRhNi40Myw2LjQzLDAsMCwxLC4yMi0xLjk0bC0zLjY2LDkuMDZhMTguNDUsMTguNDUsMCwwLDAtMS41MSw3LjMzYzAsMTguMTEsNDEsNDUuNDgsODcuNzQsNDUuNDgsMjAuNjksMCwzNi40My03Ljc2LDM2LjQzLTIxLjc3LDAtMS4wOCwwLTEuOTQtMS43My0xMC4xM1oiLz48cGF0aCBjbGFzcz0iY2xzLTEiIGQ9Ik0xMjcuNDcsODMuNDljMTIuNTEsMCwzMC42MS0yLjU4LDMwLjYxLTE3LjQ2YTE0LDE0LDAsMCwwLS4zMS0zLjQybC03LjQ1LTMyLjM2Yy0xLjcyLTcuMTItMy4yMy0xMC4zNS0xNS43My0xNi42QzEyNC44OSw4LjY5LDEwMy43Ni41LDk3LjUxLjUsOTEuNjkuNSw5MCw4LDgzLjA2LDhjLTYuNjgsMC0xMS42NC01LjYtMTcuODktNS42LTYsMC05LjkxLDQuMDktMTIuOTMsMTIuNSwwLDAtOC40MSwyMy43Mi05LjQ5LDI3LjE2QTYuNDMsNi40MywwLDAsMCw0Mi41Myw0NGMwLDkuMjIsMzYuMywzOS40NSw4NC45NCwzOS40NU0xNjAsNzIuMDdjMS43Myw4LjE5LDEuNzMsOS4wNSwxLjczLDEwLjEzLDAsMTQtMTUuNzQsMjEuNzctMzYuNDMsMjEuNzdDNzguNTQsMTA0LDM3LjU4LDc2LjYsMzcuNTgsNTguNDlhMTguNDUsMTguNDUsMCwwLDEsMS41MS03LjMzQzIyLjI3LDUyLC41LDU1LC41LDc0LjIyYzAsMzEuNDgsNzQuNTksNzAuMjgsMTMzLjY1LDcwLjI4LDQ1LjI4LDAsNTYuNy0yMC40OCw1Ni43LTM2LjY1LDAtMTIuNzItMTEtMjcuMTYtMzAuODMtMzUuNzgiLz48L3N2Zz4=
    mediatype: image/svg+xml
  image: https://quay.io/repository/osd-addons/${ADDON_NAME}-index
  publisher: Red Hat
  sourceType: grpc
EOF

echo " - Creating add-on secrets"
oc create namespace openshift-storage --dry-run=client -o yaml | oc apply -f -
oc create secret generic addon-${ADDON_NAME}-parameters -n openshift-storage --from-literal size=1 --from-literal enable-mcg=false --dry-run=client -oyaml | oc apply -f -
oc create secret generic ${ADDON_NAME}-pagerduty -n openshift-storage --from-literal PAGERDUTY_KEY="test-key" --dry-run=client -oyaml | oc apply -f -
oc create secret generic ${ADDON_NAME}-deadmanssnitch -n openshift-storage --from-literal SNITCH_URL="https://test-url" --dry-run=client -oyaml | oc apply -f -
oc create secret generic ${ADDON_NAME}-smtp -n openshift-storage --from-literal host="smtp.sendgrid.net" --from-literal password="test-key" --from-literal port="587" \
--from-literal username="apikey" --dry-run=client -oyaml | oc apply -f -

echo "- Create rook config map"
oc create configmap rook-ceph-operator-config -n openshift-storage --dry-run=client -oyaml | oc apply -f -

echo "- Create OCS and MCG cluster service versions"
for csv in ocs-operator-0.1 mcg-operator-0.1; do \
  cat << EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: ClusterServiceVersion
metadata:
  name: ${CSV}
  namespace: openshift-storage
spec:
  displayName: ocs operator
  install:
    spec:
      deployments:
      - name: test
        spec:
          selector:
            matchLabels:
              app: test
          template:
            metadata:
              labels:
                app: test
            spec:
              containers:
              - name: test
    strategy: deployment
EOF

echo "- Creating subscription"
cat << EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: ocs-subscription
  namespace: openshift-storage
spec:
  channel: alpha
  name: ocs-osd-deployer
  source: ocs-osd-deployer-catalogsource
  sourceNamespace: openshift-marketplace
EOF

echo "FINSHED - 'watch -n5 oc get po -n openshfit-storage'"
