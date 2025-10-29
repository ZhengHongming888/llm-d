# llm-d Accelerators

llm-d supports multiple accelerator vendors and we are expanding our coverage.

## Support

Maintainers for each accelerator type are listed below. See our well-lit path guides for details of deploying on each hardware type.

| Vendor | Models | Maintainers | Supported Well-lit Paths |
| --- | --- | --- | --- |
| AMD | ROCm | Kenny Roche (Kenny.Roche@amd.com) | Coming soon |
| Google | [TPU](../infra-providers/gke/README.md#llm-d-on-google-kubernetes-engine-gke) | Edwin Hernandez (@Edwinhr716), Cong Liu (@liu-cong, congliu.thu@gmail.com) | [Inference Scheduling](../../guides/inference-scheduling/README.md) |
| Intel | XPU | Yuan Wu (@yuanwu2017, yuan.wu@intel.com) | [Inference Scheduling](../../guides/inference-scheduling/README.md) |
| Intel | HPU | Yuan Wu (@yuanwu2017, yuan.wu@intel.com) | Coming soon |
| NVIDIA | GPU | Will Eaton (weaton@redhat.com), Greg (grpereir@redhat.com) | All |

## Requirements

We welcome contributions from accelerator vendors. To be referenced as a supported hardware vendor we require at minimum a publicly available container image that launches vLLM in the [recommended configuration](../../guides/prereq/infrastructure#optional-vllm-container-image).

For integration into the well-lit paths our standard for contribution is higher, **requiring**:

- A named maintainer responsible for keeping guide contents up to date
- Manual or automated verification of the guide deployment for each release

> [!NOTE]
> We aim to increase our requirements to have active CI coverage for all hardware guide variants in a future release.

> [!NOTE] 
> The community can assist but is not responsible for keeping hardware guide variants updated. We reserve the right to remove stale examples and documentation with regard to hardware support.

## Hardware-Specific Setup

### Intel XPU

Intel XPU deployments require the Intel GPU Device Plugin to be installed in your Kubernetes cluster:

```bash
# Deploy Intel GPU Device Plugin v0.32.1
kubectl apply -k 'https://github.com/intel/intel-device-plugins-for-kubernetes/deployments/gpu_plugin?ref=v0.32.1'
```

This plugin enables Kubernetes to discover and schedule workloads on Intel GPUs. Make sure to install this before deploying any XPU-based inference workloads.

### Intel HPU

Intel HPU deployments require the Intel Gaudi Plugin to be installed in your Kubernetes cluster:

```bash
# Deploy Intel Gaudi Plugin
kubectl create -f https://vault.habana.ai/artifactory/docker-k8s-device-plugin/habana-k8s-device-plugin.yaml
```

This plugin enables Kubernetes to discover and schedule workloads on Intel Gaudi. Make sure to install this before deploying any HPU-based inference workloads.
~

