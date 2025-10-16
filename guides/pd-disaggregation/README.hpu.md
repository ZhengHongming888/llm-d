# Intel HPU PD Disaggregation Deployment Guide
This document provides complete steps for deploying Intel HPU PD (Prefill-Decode) disaggregation service on Kubernetes cluster using meta-llama/Llama-3.2-3B-Instruct model. PD disaggregation separates the prefill and decode phases of inference, allowing for more efficient resource utilization and improved throughput.

## Prerequisites
### Hardware Requirements
* Intel Gaudi2 machine with HPU cards
* Sufficient disk space (recommended at least 50GB available)

### Software Requirements
* Kubernetes cluster (v1.28.0+)
* Intel Gaudi Plugin deployed - https://vault.habana.ai/artifactory/docker-k8s-device-plugin/habana-k8s-device-plugin.yaml
* kubectl access with cluster-admin privileges

## Step 1: delete previous namespace, clusters
```shell
kubectl config get-contexts
kubectl delete namespace llm-d
kubectl config get-contexts
minikube delete --all
minikube profile list
kind delete clusters $(kind get clusters)
```

## Step 2: create minikube cluster with habana plugin supported
```shell
minikube start --container-runtime=containerd
kubectl create -f https://vault.habana.ai/artifactory/docker-k8s-device-plugin/habana-k8s-device-plugin.yaml
kubectl label node minikube habana.ai/hpu-present=true
kubectl config get-contexts
kubectl describe nodes minikube
kubectl create namespace llm-d
```


## Step 3: git clone llm-d repo… and build HPU llm-d docker image. 

```shell
### Clone Repository
git clone https://github.com/llm-d/llm-d.git
```

### Build docker image for HPU llm-d
```shell
cd llm-d/docker
docker build --no-cache -f Dockerfile.hpu -t vllm-gaudi-for-llmd  .
cd ..
```

### Load image into cluster
```shell
minikube image load vllm-gaudi-for-llmd:latest
```
After loading the image you can verify by
```shell
minikube ssh
sudo crictl images
```
You will see the image list in minikube as below including your build image -
```shell
IMAGE                                                               TAG                  IMAGE ID            SIZE
cr.kgateway.dev/kgateway-dev/envoy-wrapper                          v2.0.4               3f6eec4b9b4b3       98.1MB
cr.kgateway.dev/kgateway-dev/kgateway                               v2.0.4               e59ae13ef5d7e       133MB
docker.io/grafana/grafana                                           12.2.0               1849e21404219       204MB
docker.io/kindest/kindnetd                                          v20250512-df8de77b   409467f978b4a       44.4MB
docker.io/library/vllm-gaudi-for-llmd                               latest               afc30d1246d82       2.94GB
```

## Step 4: Install Tool Dependencies
```shell

# Install necessary tools (helm, helmfile, kubectl, yq, git, kind, etc.)
./guides/prereq/client-setup/install-deps.sh
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64 && chmod +x ./kind && sudo mv ./kind /usr/local/bin/kind

# Optional: Install development tools (including chart-testing)
./guides/prereq/client-setup/install-deps.sh --dev
```

**Installed tools include:**

* helm (v3.12.0+)
* helmfile (v1.1.0+)
* kubectl (v1.28.0+)
* yq (v4+)
* git (v2.30.0+)


## Step 5: Install Gateway API dependencies
```shell
# Install Gateway API dependencies
cd guides/prereq/gateway-provider
./install-gateway-provider-dependencies.sh
cd ../../..
```


## Step 6: Deploy Kgateway Gateway control plane
```shell
# Deploy Kgateway Gateway control plane
cd guides/prereq/gateway-provider
helmfile apply -f kgateway.helmfile.yaml
cd ../../..
```

## Step 7: Install prometheus-grafana CRDs
```shell
./docs/monitoring/scripts/install-prometheus-grafana.sh
```


## Step 8: Create hugging token secret
```shell
# Set environment variables
export NAMESPACE=llm-d
export HF_TOKEN= $your_HF_token 
export HF_TOKEN_NAME=${HF_TOKEN_NAME:-llm-d-hf-token}

# Create HuggingFace token secret (empty token for public models)
kubectl create secret generic $HF_TOKEN_NAME --from-literal="HF_TOKEN=${HF_TOKEN}" --namespace ${NAMESPACE}
```

## Step 9: Deploy Intel HPU PD Disaggregation configuration

⚠️ **Important - For Intel XPU Users**: Before running `helmfile apply`, you must update the GPU resource type in `ms-pd/values_hpu.yaml`:

```yaml
# Edit ms-pd/values_hpu.yaml

# Configure accelerator type for Intel HPU
accelerator:
  type: intel-gaudi

# Also update decode and prefill resource specifications:
decode:
  containers:
  - name: "vllm"
    resources:
      limits:
	habana.ai/gaudi: 1
      requests:
	habana.ai/gaudi: 1

prefill:
  containers:
  - name: "vllm"
    resources:
      limits:
	habana.ai/gaudi: 1
      requests:
	habana.ai/gaudi: 1
```


```shell
# Navigate to PD disaggregation guide directory
cd guides/pd-disaggregation

# Deploy Intel HPU PD disaggregation configuration
helmfile apply -e hpu -n ${NAMESPACE}
```

This will deploy three main components in the `llm-d-pd` namespace:

1. **infra-pd**: Gateway infrastructure for PD disaggregation
2. **gaie-pd**: Gateway API inference extension with PD-specific routing
3. **ms-pd**: Model service with separate prefill and decode deployments

### Deployment Architecture
* **Decode Service**: 1 replica with 1 Intel HPUs
* **Prefill Service**: 1 replicas with 1 Intel HPU each
* **Total HPU Usage**: 2 Intel HPUs (1 for decode + 1 for prefill)

## Step 10: Verify Deployment
### Check Helm Releases
```shell
helm list -n llm-d
```

Expected output:

```
NAME            NAMESPACE       REVISION        UPDATED                                 STATUS          CHART                           APP VERSION
gaie-pd         llm-d           1               2025-10-15 22:32:30.443666157 +0000 UTC deployed        inferencepool-v1.0.1            v1.0.1
infra-pd        llm-d           1               2025-10-15 22:32:30.197138884 +0000 UTC deployed        llm-d-infra-v1.3.3              v0.3.0
ms-pd           llm-d           1               2025-10-15 22:32:31.008176848 +0000 UTC deployed        llm-d-modelservice-v0.2.13      v0.2.0

```

### Check All Resources
```shell
kubectl get all -n llm-d
```

### Monitor Pod Startup Status
```shell
# Check all PD pods status
kubectl get pods -n llm-d

# Monitor decode pod startup (real-time)
kubectl get pods -n llm-d -l llm-d.ai/role=decode -w

# Monitor prefill pods startup (real-time)
kubectl get pods -n llm-d -l llm-d.ai/role=prefill -w
```
Expected output for all PD pods status -
```shell
$ kubectl get pods -n llm-d
NAME                                               READY   STATUS    RESTARTS   AGE
gaie-pd-epp-586bf7b8cc-ptkff                       1/1     Running   0          6h55m
infra-pd-inference-gateway-56d75678f6-x2ndr        1/1     Running   0          6h55m
ms-pd-llm-d-modelservice-decode-7cc78779cc-5hx7l   2/2     Running   0          6h55m
ms-pd-llm-d-modelservice-prefill-8fbf5c655-rlm9l   1/1     Running   0          6h55m
```

### View vLLM Startup Logs
#### Decode Pod Logs
```shell
# Get decode pod name
DECODE_POD=$(kubectl get pods -n llm-d -l llm-d.ai/role=decode -o jsonpath='{.items[0].metadata.name}')

# View vLLM container logs
kubectl logs -n llm-d ${DECODE_POD} -c vllm -f

# View recent logs
kubectl logs -n llm-d ${DECODE_POD} -c vllm --tail=50
```

#### Prefill Pod Logs
```shell
# Get prefill pod names if prefill pod number bigger than 1
PREFILL_PODS=($(kubectl get pods -n llm-d -l llm-d.ai/role=prefill -o jsonpath='{.items[*].metadata.name}'))

# View first prefill pod logs
kubectl logs -n llm-d ${PREFILL_PODS[0]} -f

# View all prefill pod logs
for pod in "${PREFILL_PODS[@]}"; do
  echo "=== Logs for $pod ==="
  kubectl logs -n llm-d $pod --tail=20
  echo ""
done
```

## Step 11: Create HTTPRoute for Gateway Access

```shell
# Apply the HTTPRoute configuration from the PD disaggregation guide
kubectl apply -f httproute.yaml -n llm-d
```

### Verify HTTPRoute Configuration
Verify the HTTPRoute is properly configured:

```shell
# Check HTTPRoute status
kubectl get httproute -n llm-d

# View HTTPRoute details
kubectl describe httproute -n llm-d
```


## Step 12: Test PD Disaggregation Inference Service
### Get Gateway Service Information
```shell
kubectl get service -n llm-d infra-pd-inference-gateway
```

### Perform Inference Requests
#### Method 1: Using Port Forwarding (Recommended)
```shell
# Port forward to local
kubectl port-forward -n llm-d service/infra-pd-inference-gateway 8086:80 &

# Test health check
curl -X GET "http://localhost:8086/health" -v

# Perform inference test
curl -X POST http://localhost:8086/v1/chat/completions   -H "Content-Type: application/json"   -d '{
    "model": "meta-llama/Llama-3.2-3B-Instruct",
    "messages": [
      {
        "role": "user",
        "content": "Explain the benefits of prefill-decode disaggregation in LLM inference"
      }
    ],
    "max_tokens": 150,
    "temperature": 0.7
  }'

```
Expected output -

```shell
{"id":"chatcmpl-5471a768-14e5-4de7-b2f3-38fe9aa62298","object":"chat.completion","created":1760594331,"model":"meta-llama/Llama-3.2-3B-Instruct","choices":[{"index":0,"message":{"role":"assistant","content":"Prefill-decode disaggregation is a technique used in Large Language Models (LLMs) to improve inference performance, particularly in scenarios where the input data is noisy, ambiguous, or has varying levels of relevance. Here are the benefits of prefill-decode disaggregation in LLM inference:\n\n1. **Improved accuracy**: Prefill-decode disaggregation helps to identify and filter out irrelevant or noisy input data, which can improve the overall accuracy of the LLM's predictions.\n2. **Reduced bias**: By disaggregating the input data, the model is less likely to be biased towards certain types of input, which can lead to more accurate and generalizable results.\n3. **Increased robustness**: Prefill-decode disaggregation makes the","refusal":null,"annotations":null,"audio":null,"function_call":null,"tool_calls":[],"reasoning_content":null},"logprobs":null,"finish_reason":"length","stop_reason":null,"token_ids":null}],"service_tier":null,"system_fingerprint":null,"usage":{"prompt_tokens":50,"total_tokens":200,"completion_tokens":150,"prompt_tokens_details":null},"prompt_logprobs":null,"prompt_token_ids":null,"kv_transfer_params":null}
```
