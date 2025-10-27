# CPU PD Disaggregation Deployment Guide
This document provides complete steps for deploying PD (Prefill-Decode) disaggregation service on Kubernetes cluster in pure CPU environment using meta-llama/Llama-3.2-3B-Instruct model. PD disaggregation separates the prefill and decode phases of inference, allowing for more efficient resource utilization and improved throughput.

## Prerequisites
### Hardware Requirements
* Pure CPU environment
* Sufficient disk space

### Software Requirements
* Kubernetes cluster (v1.28.0+)
* kubectl access with cluster-admin privileges

## Step 1: delete previous namespace, clusters
```shell
kubectl delete namespace llm-d
minikube delete --all
```

## Step 2: create minikube cluster with habana plugin supported
```shell
minikube start --container-runtime=containerd  --cpus=64 --memory=128g --disk-size=100g
kubectl describe nodes minikube
kubectl create namespace llm-d
```

## Step 3: git clone llm-d repo… and build CPU llm-d docker image. 
```shell
git clone https://github.com/llm-d/llm-d.git
```

### Build docker image for CPU llm-d
```shell
cd vllm
docker build --no-cache -f docker/Dockerfile.cpu --build-arg VLLM_CPU_AVX512BF16=false --build-arg VLLM_CPU_AVX512VNNI=false --build-arg VLLM_CPU_DISABLE_AVX512=false --tag vllm-cpu-base --target vllm-openai .
cd ..

#build vllm-cpu-env docker image with latest nixl and UCX …”
cd llm-d/docker
docker build --no-cache -f Dockerfile.cpu.nixl -t vllm-cpu-env .
cd ../..
```

### Load image into cluster
```shell
minikube image load vllm-cpu-env:latest
```
After loading the image you can verify by
```shell
minikube ssh
sudo crictl images
```
if cluster image has no external internet access you can add the commands as below then cluster will have external access -

```shell
minikube ssh
sudo mkdir -p /etc/systemd/system/containerd.service.d
sudo vi /etc/systemd/system/containerd.service.d/proxy.conf
# add below content
[Service]
Environment="HTTP_PROXY=http://proxy.ims.intel.com:911"
Environment="HTTPS_PROXY=http://proxy.ims.intel.com:911"
Environment="NO_PROXY=127.0.0.1,localhost,0.0.0.0,192.168.49.2"
# after saving above
sudo systemctl daemon-reexec
sudo systemctl restart containerd
```



## Step 4: Install Tool Dependencies
```shell

# Install necessary tools (helm, helmfile, kubectl, yq, git, kind, etc.)
./guides/prereq/client-setup/install-deps.sh
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64 && chmod +x ./kind && sudo mv ./kind /usr/local/bin/kind
```


## Step 5: Install Gateway API dependencies
```shell
cd guides/prereq/gateway-provider
./install-gateway-provider-dependencies.sh
cd ../../..
```


## Step 6: Deploy Kgateway Gateway control plane
```shell
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

## Step 9: Deploy CPU PD Disaggregation configuration

```shell
# Navigate to PD disaggregation guide directory
cd guides/pd-disaggregation

# Deploy Intel CPU PD disaggregation configuration
helmfile apply -e cpu -n ${NAMESPACE}
```

This will deploy three main components in the `llm-d` namespace:

1. **infra-pd**: Gateway infrastructure for PD disaggregation
2. **gaie-pd**: Gateway API inference extension with PD-specific routing
3. **ms-pd**: Model service with separate prefill and decode deployments


## Step 10: Verify Deployment
### Check Helm Releases
```shell
helm list -n llm-d

NAME            NAMESPACE       REVISION        UPDATED                                 STATUS          CHART                           APP VERSION
gaie-pd         llm-d           1               2025-10-26 17:13:28.037575686 -0700 PDT deployed        inferencepool-v1.0.1            v1.0.1
infra-pd        llm-d           1               2025-10-26 17:13:27.313144347 -0700 PDT deployed        llm-d-infra-v1.3.3              v0.3.0
ms-pd           llm-d           1               2025-10-26 17:13:29.982862829 -0700 PDT deployed        llm-d-modelservice-v0.2.11      v0.2.0

```

### Monitor Pod Status
```shell
$ kubectl get pods -n llm-d
NAME                                                READY   STATUS    RESTARTS   AGE
gaie-pd-epp-586bf7b8cc-t9l4d                        1/1     Running   0          3h18m
infra-pd-inference-gateway-56d75678f6-tqm7c         1/1     Running   0          3h18m
ms-pd-llm-d-modelservice-decode-6f94857565-8bxwq    2/2     Running   0          3h18m
ms-pd-llm-d-modelservice-prefill-79bbcb97c6-xt86h   1/1     Running   0          3h18m

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
```


## Step 12: Test PD Disaggregation Inference Service

### Perform Inference Requests
#### Method: Using Port Forwarding (Recommended)
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
