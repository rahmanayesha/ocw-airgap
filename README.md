# ocw-airgap
OCW - Enabling air-gapped container deployment in digital factories

## Required Tools
* Docker Desktop
* Kind
* Kubectl
* Flux
* (Optional) k9s (To debug)

## Architecture
![Architecture](assets/architecture.drawio.png)
## Installing 

1. Clone this repo

2. Create a new kind cluster
```
kind create cluster
```
3. Execute `deploy-local.sh <your-gitea-password>`

## Todo
- [ ] Add local registry for images