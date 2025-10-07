# vLLM Inference Readiness Probes

## Overview

The llm-d inference images include a comprehensive readiness probe script to ensure proper container lifecycle management in Kubernetes. This addresses the three distinct stages of readiness for vLLM inference containers:

1. **Container Running** - Kubernetes native container lifecycle
2. **API Server Ready** - vLLM OpenAI API server is accepting connections
3. **Model Loaded** - Model-specific API routes are ready to serve inference requests

## Problem Statement

When deploying vLLM inference servers, there's a significant time gap between when the container starts and when the model is fully loaded and ready to serve requests. Using basic health checks (`/health` endpoint) can lead to:

- Premature traffic routing to pods that aren't ready
- Failed requests during model loading
- Need for arbitrary sleep times in deployment pipelines
- Unreliable E2E testing

The `/health` endpoint only indicates that the vLLM server process is running, not that the model is loaded and ready to serve.

## Solution

The `readiness_probe.sh` script provides a proper readiness check by:

1. Verifying the `/health` endpoint responds (server is up)
2. Checking the `/v1/models` endpoint (model is loaded)
3. Validating the response contains model data

### Script Location

The readiness probe script is available in all llm-d inference images at:
```
/usr/local/bin/readiness_probe.sh
```

### Usage

The script accepts two optional arguments:
```bash
readiness_probe.sh [PORT] [HOST]
```

**Arguments:**
- `PORT` - Port where vLLM server is listening (default: `8000`)
- `HOST` - Host to connect to (default: `localhost`)

**Environment Variables:**
- `READINESS_TIMEOUT` - Timeout in seconds for HTTP requests (default: `5`)

### Exit Codes

- `0` - Service is ready (model loaded and API responding)
- `1` - Service is not ready

## Kubernetes Configuration

### Recommended Probe Configuration

For production deployments, we recommend using all three probe types:

```yaml
containers:
  - name: vllm
    image: ghcr.io/llm-d/llm-d-cuda-dev:latest
    ports:
      - containerPort: 8000
        name: http
        protocol: TCP
    
    # Startup probe - gives the model time to load on initial startup
    # Disables liveness/readiness checks until this succeeds
    startupProbe:
      exec:
        command:
          - /usr/local/bin/readiness_probe.sh
          - "8000"
          - "localhost"
      initialDelaySeconds: 30
      periodSeconds: 10
      timeoutSeconds: 5
      failureThreshold: 60  # 10 minutes total (60 * 10s)
    
    # Liveness probe - detects if the container needs to be restarted
    # Uses basic health check since we only want to restart on critical failures
    livenessProbe:
      httpGet:
        path: /health
        port: 8000
      initialDelaySeconds: 10
      periodSeconds: 30
      timeoutSeconds: 5
      failureThreshold: 3
    
    # Readiness probe - determines if pod should receive traffic
    # Uses the comprehensive readiness check
    readinessProbe:
      exec:
        command:
          - /usr/local/bin/readiness_probe.sh
          - "8000"
          - "localhost"
      initialDelaySeconds: 5
      periodSeconds: 10
      timeoutSeconds: 5
      failureThreshold: 3
```

### Port Configuration

Adjust the port number in the probe configuration based on your deployment:

- **Prefill pods**: Typically use port `8000`
- **Decode pods**: May use port `8200` (depends on configuration)

Example for decode pods:
```yaml
readinessProbe:
  exec:
    command:
      - /usr/local/bin/readiness_probe.sh
      - "8200"  # Decode port
      - "localhost"
  initialDelaySeconds: 5
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 3
```

### Prefill/Decode Disaggregation

For P/D disaggregated deployments, configure probes for both pod types:

**Prefill Pods:**
```yaml
readinessProbe:
  exec:
    command:
      - /usr/local/bin/readiness_probe.sh
      - "8000"
```

**Decode Pods:**
```yaml
readinessProbe:
  exec:
    command:
      - /usr/local/bin/readiness_probe.sh
      - "8200"
```

## Helm Chart Integration

For the `llm-d-modelservice` Helm chart, you can configure probes in your `values.yaml`:

```yaml
decode:
  containers:
    - name: vllm
      startupProbe:
        exec:
          command:
            - /usr/local/bin/readiness_probe.sh
            - "8200"
        initialDelaySeconds: 30
        periodSeconds: 10
        timeoutSeconds: 5
        failureThreshold: 60
      livenessProbe:
        httpGet:
          path: /health
          port: 8200
        periodSeconds: 30
        timeoutSeconds: 5
        failureThreshold: 3
      readinessProbe:
        exec:
          command:
            - /usr/local/bin/readiness_probe.sh
            - "8200"
        periodSeconds: 10
        timeoutSeconds: 5
        failureThreshold: 3

prefill:
  containers:
    - name: vllm
      startupProbe:
        exec:
          command:
            - /usr/local/bin/readiness_probe.sh
            - "8000"
        initialDelaySeconds: 30
        periodSeconds: 10
        timeoutSeconds: 5
        failureThreshold: 60
      livenessProbe:
        httpGet:
          path: /health
          port: 8000
        periodSeconds: 30
        timeoutSeconds: 5
        failureThreshold: 3
      readinessProbe:
        exec:
          command:
            - /usr/local/bin/readiness_probe.sh
            - "8000"
        periodSeconds: 10
        timeoutSeconds: 5
        failureThreshold: 3
```

## Tuning Guidelines

### Startup Probe

The startup probe is critical for model loading. Tune based on:
- Model size (larger models take longer to load)
- Storage backend (local SSD vs network storage)
- Available GPU memory

**Small models (< 7B parameters):**
```yaml
initialDelaySeconds: 30
periodSeconds: 10
failureThreshold: 30  # 5 minutes
```

**Medium models (7B - 70B parameters):**
```yaml
initialDelaySeconds: 60
periodSeconds: 15
failureThreshold: 40  # 10 minutes
```

**Large models (> 70B parameters):**
```yaml
initialDelaySeconds: 120
periodSeconds: 20
failureThreshold: 60  # 20 minutes
```

### Readiness Probe

Keep readiness checks frequent to quickly detect issues:
```yaml
periodSeconds: 10        # Check every 10 seconds
timeoutSeconds: 5        # 5 second timeout
failureThreshold: 3      # Mark unready after 3 failures (30s)
```

### Liveness Probe

Be conservative with liveness probes to avoid unnecessary restarts:
```yaml
periodSeconds: 30        # Check every 30 seconds
timeoutSeconds: 5        # 5 second timeout  
failureThreshold: 3      # Restart after 3 failures (90s)
```

## Testing

### Manual Testing

Test the readiness probe manually:

```bash
# Get a shell in the container
kubectl exec -it <pod-name> -n <namespace> -- bash

# Run the probe
/usr/local/bin/readiness_probe.sh 8000 localhost
echo $?  # Should return 0 when ready
```

### Verification

Verify probes are working:

```bash
# Check pod events
kubectl describe pod <pod-name> -n <namespace>

# Watch pod status during startup
kubectl get pods -n <namespace> -w

# Check probe logs
kubectl logs <pod-name> -n <namespace> | grep readiness_probe
```

## E2E Testing

With proper readiness probes, E2E tests can eliminate arbitrary sleep times:

**Before:**
```yaml
- name: Wait for all pods to be ready
  run: |
    kubectl wait pod --for=condition=Ready --all -n ${NAMESPACE} --timeout=15m
    sleep 480  # Wait for model loading
```

**After:**
```yaml
- name: Wait for all pods to be ready
  run: |
    kubectl wait pod --for=condition=Ready --all -n ${NAMESPACE} --timeout=15m
    # No sleep needed - readiness probe ensures model is loaded
```

## Troubleshooting

### Pod Stuck in Not Ready

If pods are stuck in not ready state:

1. Check the probe logs:
   ```bash
   kubectl logs <pod-name> -n <namespace> | grep readiness_probe
   ```

2. Verify the vLLM server is starting:
   ```bash
   kubectl logs <pod-name> -n <namespace> | grep -i "uvicorn\|vllm"
   ```

3. Check for model loading errors:
   ```bash
   kubectl logs <pod-name> -n <namespace> | grep -i "error\|failed"
   ```

4. Manually test the endpoints:
   ```bash
   kubectl exec -it <pod-name> -n <namespace> -- curl -s http://localhost:8000/health
   kubectl exec -it <pod-name> -n <namespace> -- curl -s http://localhost:8000/v1/models
   ```

### Probe Timeouts

If probes are timing out:

1. Increase the timeout:
   ```yaml
   timeoutSeconds: 10  # Increase from 5
   ```

2. Increase the period for startup:
   ```yaml
   periodSeconds: 20  # Check less frequently
   ```

3. Check network connectivity within the pod

### False Negatives

If the probe reports not ready when the model is loaded:

1. Verify the port matches your vLLM configuration
2. Check if there are firewall or network policy restrictions
3. Ensure the probe script is executable: `ls -la /usr/local/bin/readiness_probe.sh`

## Related Issues

- Issue #300: Original feature request for readiness probe implementation
- See E2E workflow files for integration examples

## Additional Resources

- [Kubernetes Probes Documentation](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/)
- [vLLM OpenAI API Documentation](https://docs.vllm.ai/en/latest/serving/openai_compatible_server.html)
- [llm-d Getting Started Guide](./getting-started-inferencing.md)

