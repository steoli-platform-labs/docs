# Lab 14 - Network Policies

## Lab Information

| Property | Value |
|----------|-------|
| **Phase** | Platform Security |
| **Lab** | 14 |
| **Difficulty** | Intermediate |
| **Estimated Time** | 30-45 minutes |
| **Estimated Cost** | Free |
| **Primary Tools** | Helm, kubectl, Argo CD |

## Introduction

This lab introduces Kubernetes NetworkPolicies for controlling pod-to-pod and pod-to-platform traffic.

Network policies provide workload isolation inside the cluster and make application connectivity explicit instead of relying on default open namespace networking.

Concepts introduced in this lab include NetworkPolicies, pod selectors, namespace selectors, ingress rules, egress rules, DNS egress and CNI enforcement. See the [Concepts Reference](../concepts/README.md) for the security model behind Kubernetes network isolation.

## Outcome
Validate Kubernetes NetworkPolicies for the sample API in the complete platform reference implementation.

## Prerequisites

Before starting this lab:

- Lab 01 - Lab 13 completed
- AWS CLI, Terraform, kubectl and Helm installed
- Repository URLs configured

## Files to Review
Review these files before validation:

- `helm-charts/charts/sample-api/templates/networkpolicy.yaml`: rendered Kubernetes NetworkPolicy.
- `helm-charts/charts/sample-api/values.yaml`: chart values that control service ports, rollout mode and policy-related behavior.
- `platform-config/clusters/dev/sample-api-dev.yaml`: dev-specific values deployed by Argo CD.

## Step-by-Step Implementation

1. Review the NetworkPolicy template:

   ```bash
   cd "$WORKSPACE"
   sed -n '1,160p' helm-charts/charts/sample-api/templates/networkpolicy.yaml
   ```

   Confirm the policy selects only `sample-api` pods, includes both `Ingress` and `Egress` policy types and allows only the intended ingress and egress paths.

2. Confirm whether the cluster CNI enforces Kubernetes NetworkPolicy:

   ```bash
   printf '\n===== AWS VPC CNI pods =====\n'
   kubectl -n kube-system get pods -l k8s-app=aws-node
   printf '\n===== AWS VPC CNI containers =====\n'
   kubectl -n kube-system get daemonset aws-node \
     -o jsonpath='{range .spec.template.spec.containers[*]}{.name}{"\n"}{end}'
   printf '\n===== NetworkPolicy enforcement flag =====\n'
   kubectl -n kube-system describe daemonset aws-node | grep -- '--enable-network-policy=true' || true
   ```

   Expected result: the `aws-node` pods are `Running`, the DaemonSet includes the AWS VPC CNI containers and the output shows `--enable-network-policy=true` for the `aws-eks-nodeagent` container. That agent is what turns Kubernetes `NetworkPolicy` objects into enforced dataplane rules on the nodes.

   If the last command prints no `--enable-network-policy=true` line or shows `--enable-network-policy=false`, the cluster can still accept `NetworkPolicy` YAML, but the rules may not actually block traffic. Treat that as a failed validation for this lab, not as a successful deny test. In that case, stop and fix CNI network policy enforcement before relying on the positive and negative connectivity tests later in the lab.

3. Run `helm lint` and render the chart:

   ```bash
   printf '\n===== sample-api Helm lint =====\n'
   helm lint helm-charts/charts/sample-api
   printf '\n===== Render sample-api chart =====\n'
   helm template sample-api helm-charts/charts/sample-api \
     --values <(yq -r '.spec.source.helm.values' platform-config/clusters/dev/sample-api-dev.yaml) \
     > /tmp/sample-api-networkpolicy.yaml
   printf '\n===== Rendered NetworkPolicy =====\n'
   yq 'select(.kind == "NetworkPolicy")' /tmp/sample-api-networkpolicy.yaml
   ```

   Expected result: only the rendered `NetworkPolicy` is printed. It should select `sample-api` pods, include `policyTypes: [Ingress, Egress]`, allow ingress from the `ingress-nginx` namespace on port `8080`, allow DNS egress to `kube-system` on TCP and UDP port `53` and allow HTTPS egress on TCP port `443`.

   This file is a Helm template, not the final Kubernetes object. Helm fills in template values such as names and labels before Kubernetes sees the manifest.

   Rendering locally catches template mistakes before Argo CD deploys them. The rendered file contains every manifest from the chart, so use `yq` to extract only the `NetworkPolicy` document instead of showing a fixed number of lines after the match.

4. Refresh Argo CD and verify `sample-api-dev` is synced:

   ```bash
   printf '\n===== Refresh dev root =====\n'
   kubectl -n argocd annotate application platform-root-dev argocd.argoproj.io/refresh=hard --overwrite
   printf '\n===== sample-api-dev Application =====\n'
   kubectl -n argocd get application sample-api-dev -o wide
   ```

   Proceed when `sample-api-dev` is `Synced` and `Healthy`. If it is `OutOfSync`, refresh and wait briefly. If it is `Degraded` or `Missing`, describe the Application before running connectivity tests.

5. Confirm that the deployed NetworkPolicy and pods match the rendered intent:

   ```bash
   printf '\n===== Deployed NetworkPolicy =====\n'
   kubectl -n sample-api-dev get networkpolicy -o yaml
   printf '\n===== sample-api pods =====\n'
   kubectl -n sample-api-dev get pods -l app.kubernetes.io/name=sample-api -o wide
   ```

   Expected output includes one `NetworkPolicy` named `sample-api` and sample API pods in `Running` with `READY` as `1/1`. The policy selector should match the pod label `app.kubernetes.io/name=sample-api`; otherwise the policy may exist but not apply to the workload.

6. Run a positive connectivity test from the allowed namespace:

   ```bash
   printf '\n===== Ensure allowed-source namespace exists =====\n'
   kubectl create namespace ingress-nginx --dry-run=client -o yaml | kubectl apply -f -
   printf '\n===== Allowed client request =====\n'
   kubectl -n ingress-nginx run allowed-client --rm -it --restart=Never \
      --image=curlimages/curl -- curl -fsS http://sample-api.sample-api-dev.svc.cluster.local/
   ```

   Expected result: the command prints the sample API response and then deletes the temporary pod:

   ```json
   {"environment":"dev","service":"sample-api"}
   ```

   You may also see messages such as `couldn't attach to pod`, `falling back to streaming logs` or the JSON response printed twice. That is normal for short-lived `kubectl run --rm -it` pods: the curl container can finish before kubectl attaches, so kubectl falls back to reading the completed pod logs before deleting it.

   Treat the test as successful when the response contains `"service":"sample-api"` and the temporary `allowed-client` pod is deleted. If the curl command exits with an HTTP error, times out or cannot resolve `sample-api`, inspect the Service, endpoints and NetworkPolicy before running deny tests.

   This client runs in `ingress-nginx` because the policy explicitly allows ingress from that namespace. The namespace creation command is a no-op if an ingress namespace already exists; otherwise it creates the minimum namespace needed for this source-based test. A pod in a different namespace should not be able to reach the API once network policy enforcement is active.

7. Run a negative test from an unintended namespace:

   ```bash
   kubectl create namespace network-denied-test
   kubectl -n network-denied-test run denied-client --rm -it --restart=Never \
      --image=curlimages/curl -- curl --max-time=5 -fsS http://sample-api.sample-api-dev.svc.cluster.local/
   ```

   The `--` separator matters: everything before it is a `kubectl run` option, and everything after it is the command executed inside the temporary pod. `--max-time=5` must be after `--` so it is passed to `curl`.

   Expected result: this should fail or time out only if NetworkPolicy enforcement is enabled. A timeout, non-zero curl exit or `pod "denied-client" deleted` after a failed request is the intended deny behavior. If it prints the sample API JSON response, either the policy is too permissive or the CNI is not enforcing NetworkPolicy. Re-run step 2 and confirm the `aws-eks-nodeagent` container is configured with `--enable-network-policy=true`.

8. Validate DNS and required HTTPS egress from an application pod:

   ```bash
   SAMPLE_API_POD=$(kubectl -n sample-api-dev get pod -l app.kubernetes.io/name=sample-api -o jsonpath='{.items[0].metadata.name}')
   kubectl -n sample-api-dev exec "$SAMPLE_API_POD" -- python -c 'import socket; print(socket.gethostbyname("kubernetes.default.svc.cluster.local"))'
   ```

   Expected result: the command prints a cluster IP address, such as `172.20.0.1`. The sample API image does not include debugging tools such as `nslookup`, so this uses Python from the application runtime to perform the same DNS lookup.

   DNS must keep working after egress policy is applied. If the application needs outbound HTTPS, validate that path with a non-sensitive endpoint used by the lab.

9. Delete the temporary namespace after validation:

   ```bash
   kubectl delete namespace network-denied-test
   ```

   Proceed when namespace deletion completes or `kubectl get namespace network-denied-test` returns `NotFound`. If the namespace stays `Terminating`, inspect namespace events and finalizers before continuing.

## Expected Results
The `sample-api` chart renders a NetworkPolicy and the deployed application still passes health checks while unintended traffic is denied.

## Validation
- The intended ingress source can reach the API.
- An unintended namespace cannot reach the API.
- DNS resolution still works.
- Only documented outbound destinations/ports work.
- Existing probes and monitoring traffic continue to function.
- Denials are reproducible and disappear when the policy is removed in a controlled test.
- If the installed AWS VPC CNI configuration does not have NetworkPolicy enforcement enabled, the manifest may exist while traffic remains unrestricted; that is a failed validation.

## Troubleshooting
Start with the rendered policy and namespace events:

```bash
printf '\n===== sample-api NetworkPolicy details =====\n'
kubectl -n sample-api-dev describe networkpolicy sample-api
printf '\n===== sample-api pods, services and endpoints =====\n'
kubectl -n sample-api-dev get pods,svc,endpoints -o wide
printf '\n===== sample-api events =====\n'
kubectl -n sample-api-dev get events --sort-by=.lastTimestamp
```

If the deny test succeeds unexpectedly:

- Confirm the CNI enforces Kubernetes NetworkPolicy.
- Confirm the policy selects the sample-api pods.
- Confirm the source namespace does not match an allowed namespace selector.
- Confirm there is no additional policy allowing the traffic.

If the allowed test fails:

- Confirm the Service has endpoints.
- Confirm the allowed source matches the policy selectors.
- Confirm the policy port matches the pod container port, not only the Service port.

## Final Repository State
The implementation remains GitOps-driven and mergeable to `main`.

## Cleanup
Delete only temporary test pods and namespaces created during validation. Keep the Git-managed NetworkPolicy in place.

## Next Steps
Continue with [Lab 15 - Multi-Environment Platform](./lab15-multi-environment-platform.md).
