# Delivery Workflow

## Infrastructure Delivery

```text
Developer
  -> Pull Request
  -> Terraform Format and Validate
  -> Review
  -> Merge
  -> Terraform Plan or Apply under controlled workflow
  -> AWS
```

## Application Delivery

```text
Developer
  -> Git Push
  -> GitHub Actions
  -> Build, Test and Scan
  -> Container Image
  -> GitHub Container Registry
  -> Helm Values Update
  -> ArgoCD
  -> Argo Rollouts
  -> Amazon EKS
```

GitHub Actions is responsible for Continuous Integration. ArgoCD is responsible for Kubernetes deployment. CI workflows must not use `kubectl apply`, `helm install` or equivalent direct cluster mutation commands.
