#!/bin/bash
set -e 

if [ $# -ne 1 ]; then
  echo "Error: Add password as argument"
  exit 1
fi 

password=$1
username="flux_robot"
repositoryName="flux-repo"

helm repo add gitea-charts https://dl.gitea.io/charts/

# TODO: Add gitea default url "localhost:3000"
echo "Start creating gitea in cluster, can take some time"
helm install \
--set gitea.admin.password=$password \
--set gitea.admin.username=$username gitea gitea-charts/gitea \
--wait

flux install 

### SETUP ###

# Port-forward
localport=3000
giteaHttpIp=localhost:$localport
kubectl port-forward svc/gitea-http $localport  > /dev/null 2>&1 &
pid=$!
# kill the port-forward regardless of how this script exits
trap '{
    # echo killing $pid
    kill $pid
}' EXIT

# wait for $localport to become available
while ! nc -vz localhost $localport > /dev/null 2>&1 ; do
    # echo sleeping
    sleep 0.1
done

# Get Gitea API Token 
giteaApiToken=$(curl -XPOST -H "Content-Type: application/json" -s -k -d '{"name":"setup-process"}' \
-u $username:$password ${giteaHttpIp}/api/v1/users/${username}/tokens | jq .sha1 | xargs)

echo "Api Token: "$giteaApiToken

# Create Gitea Repository
curl -X 'POST' \
  "${giteaHttpIp}/api/v1/user/repos?token=${giteaApiToken}" \
  -H 'accept: application/json' \
  -H 'Content-Type: application/json' \
  -d '{
  "auto_init": true,
  "default_branch": "main",
  "description": "Flux Source Repository",
  "name": "'${repositoryName}'",
  "private": false,
  "template": false,
  "trust_model": "default"
}'

# Create a Kubernetes secret for Git authentication
# https://fluxcd.io/docs/cmd/flux_create_secret_git/
# comment: I don't like the hack below to get the deployKey :(
kubectl apply -f flux-pod.yaml --wait=true
sleep 10
#deployKey=$(kubectl exec $(kubectl get po -l app=flux-pod -o name) -- flux create secret git flux-repo-auth --url=ssh://git@gitea-ssh.default.svc.cluster.local/${username}/${repositoryName} 2>&1 | grep 'deploy key' | cut -c 17-)
kubectl exec $(kubectl get po -l app=flux-pod -o name) -- flux create secret git flux-repo-auth --url=ssh://git@gitea-ssh.default.svc.cluster.local/${username}/${repositoryName} --export | kubectl apply -f -

deployKey=$(kubectl get secret flux-repo-auth -n flux-system -o=jsonpath="{.data['identity\.pub']}" | base64 --decode)

### This doesn't work yet, need to import key into gitea
# Upload Deploy Key to Gitea
curl -X 'POST' \
  "${giteaHttpIp}/api/v1/repos/${username}/${repositoryName}/keys?token=${giteaApiToken}" \
  -H 'accept: application/json' \
  -H 'Content-Type: application/json' \
  -d '{
  "key": "'"${deployKey}"'",
  "read_only": true,
  "title": "flux-source-repository"
}'

# Create a GitRepository source
# https://fluxcd.io/docs/cmd/flux_create_source_git/
#kubectl exec $(kubectl get po -l app=flux-pod -o name) -- flux create source git flux-repo --secret-ref=flux-repo-auth --url=ssh://git@gitea-ssh.default.svc.cluster.local/${username}/${repositoryName} --branch=main --interval=1m
kubectl apply -f flux-gitrepository.yaml

# Create a Kustomization resource.
kubectl apply -f flux-kustomize.yaml