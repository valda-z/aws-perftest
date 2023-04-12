$rg = 'perftest-rg'
$acrName = 'jjazacrperf'

az network vnet create -n jjazvnetperf -g $rg -l SwedenCentral --address-prefixes 10.224.0.0/12
az network vnet subnet create -n aci-snet -g $rg --vnet-name jjazvnetperf --address-prefixes 10.224.0.0/16
az network vnet subnet create -n aks-snet -g $rg --vnet-name jjazvnetperf --address-prefixes 10.239.0.0/16
$snet=$(az network vnet subnet show --resource-group $rg --vnet-name jjazvnetperf --name aks-snet --query id -o tsv)

az aks create -n jjazaksperf -g $rg --node-count 3 -s Standard_D4ds_v5 --generate-ssh-keys --attach-acr $acrName -l SwedenCentral `
--kubernetes-version 1.26.0 --network-plugin azure --network-policy azure --enable-managed-identity `
--enable-addons virtual-node --aci-subnet-name aci-snet --vnet-subnet-id $snet

az aks get-credentials --resource-group $rg --name jjazaksperf

# save token to access ACR from ACI
az acr token create --name aci-access --registry $acrName --scope-map _repositories_pull --output json
docker login -u aci-access -p <password_from_json> jjazacrperf.azurecr.io
kubectl create namespace perftest
kubectl --namespace=perftest create secret generic regcred --from-file=.dockerconfigjson=/home/<your_profile>/.docker/config.json --type=kubernetes.io/dockerconfigjson

# deploy deployment and autoscale
# ! fix registry name and agentpool name
kubectl apply -f .\deploy-aks-deployment.yaml
kubectl autoscale deployment perftest --cpu-percent=25 --min=8 --max=32 -n perftest

# get pods and run test to external-ip
kubectl get hpa -n perftest
kubectl get pods -n perftest -o wide
kubectl get svc -n perftest -o wide

# run test
http://<external-ip>/test

# scaledown
kubectl delete hpa perftest -n perftest
kubectl scale deploy -n perftest --replicas=1 --all
