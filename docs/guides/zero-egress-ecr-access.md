# Zero Egress ECR Access

Enterprise pattern for application image pulls from Amazon ECR on zero-egress ROSA HCP clusters using **External Secrets Operator (ESO) with IRSA**.

## Background

Zero-egress clusters pull Red Hat platform images from the regional ECR mirror via VPC endpoints. The IAM module attaches `AmazonEC2ContainerRegistryReadOnly` to the worker role when `zero_egress = true` — required for platform images.

For **customer application images**, use ESO + IRSA instead of relying on the worker role (least privilege per [ROSA best practices](https://cloud.redhat.com/experts/rosa/best-practices-recommendations/)).

## Prerequisites

- Zero-egress cluster with `ecr.api` and `ecr.dkr` VPC endpoints
- `oc` access via Client VPN
- ECR repository in the same AWS account and region

## Step 1: Install External Secrets Operator

Operator images are pulled from the regional ECR mirror (no internet required):

```bash
cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: external-secrets-operator
  namespace: openshift-operators
spec:
  channel: stable
  name: external-secrets-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  installPlanApproval: Automatic
EOF
```

Wait for the operator, then create the operand:

```bash
cat <<EOF | oc apply -f -
apiVersion: operator.external-secrets.io/v1alpha1
kind: ExternalSecretsConfig
metadata:
  name: cluster
spec: {}
EOF
```

## Step 2: Create IAM policy and IRSA role

```bash
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export AWS_REGION="<region>"
export OIDC_ENDPOINT=$(oc get authentication cluster -o jsonpath='{.spec.serviceAccountIssuer}' | sed 's|https://||')
export ECR_REPOSITORY="my-app"
export APP_NAMESPACE="my-app-ns"
export ESO_SA_NAME="ecr-eso-sa"
export ECR_IAM_ROLE_NAME="<cluster-name>-ecr-eso-role"
```

Create a least-privilege ECR policy scoped to your repository, IAM role with IRSA trust policy for the service account, and attach the policy.

## Step 3: Configure ESO token generator

```bash
oc new-project "$APP_NAMESPACE"
oc create serviceaccount "$ESO_SA_NAME" -n "$APP_NAMESPACE"
oc annotate serviceaccount "$ESO_SA_NAME" -n "$APP_NAMESPACE" \
  eks.amazonaws.com/role-arn="$ECR_ROLE_ARN"
```

Apply `ECRAuthorizationToken` generator and `ExternalSecret` with `refreshInterval: 11h` (before 12-hour ECR token expiry).

## Step 4: Link pull secret and test

```bash
oc secrets link default ecr-docker-credentials --for=pull -n "$APP_NAMESPACE"
```

Deploy a test pod using your ECR image URL to confirm the pipeline works.

## VPC endpoints

The `ecr.api` and `ecr.dkr` endpoints in your VPC serve both Red Hat mirror and customer ECR repositories in the same region. No additional endpoints are required.

## Related

- [BYO Network Requirements](../prerequisites/byo/network.md)
- [Egress-Zero GitOps](egress-zero-gitops.md)
- [Red Hat: ESO + IRSA for ECR](https://cloud.redhat.com/experts/rosa/ecr-external-secrets-irsa)

## Reference

Adapted from Red Hat zero-egress ROSA HCP prerequisite guidance.
