# cluster access

```bash
aws eks update-kubeconfig --region eu-west-1 --name perftest-cluster --kubeconfig ~/.kube/tvnova
export KUBECONFIG=~/.kube/tvnova
```

# install monitoring

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

kubectl create namespace prometheus
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm upgrade -i prometheus prometheus-community/prometheus \
    --namespace prometheus \
    --set alertmanager.persistentVolume.storageClass="gp2",server.persistentVolume.storageClass="gp2"      

# test
export POD_NAME=$(kubectl get pods --namespace prometheus -l "app.kubernetes.io/component=server" -o jsonpath="{.items[0].metadata.name}")
kubectl --namespace prometheus port-forward $POD_NAME 9090

```  

# cluster autoscaler

```bash
# update role ARN in eks-fargate/deploy-autoscaler.yaml

kubectl apply -f eks-fargate/deploy-autoscaler.yaml
```

# install alb supprt

```bash
helm repo add eks https://aws.github.io/eks-charts
helm repo update

helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=perftest-cluster
`

# deploy app

```bash
kubectl create namespace perftest
kubectl apply -f deployment.yaml
```