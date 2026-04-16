> ⚠️ **Disclaimer:** This is a personal project and is not affiliated with,
> endorsed by, or supported by Microsoft in any way. Use at your own risk.
> For official guidance, refer to the
> [Microsoft AKS documentation](https://learn.microsoft.com/en-us/azure/aks/).


# aks-pcap-tool

![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20WSL-blue)
![Shell](https://img.shields.io/badge/shell-bash-green)
![License](https://img.shields.io/badge/license-MIT-orange)

A lightweight bash script that automates packet captures on AKS Linux nodes.
No Helm, no persistent storage, no node SSH required — just kubectl access
and five prompts.

---

## The Problem It Solves

When troubleshooting AKS connectivity issues (e.g. pods cannot reach a
SQL Server, external API, or internal service), the standard workflow is:

1. SSH into the node
2. Install tcpdump
3. Find the right interface
4. Run the capture
5. Copy the file out manually
6. Clean up

This tool does all of that in a single script with five prompts.

---

## How It Works

```
You answer 5 questions
        ↓
Script finds which node your pod is on
        ↓
Deploys a privileged netshoot debug pod on that node
        ↓
Runs tcpdump (full packet, verbose, filtered to your target)
        ↓
You reproduce the issue during the capture window
        ↓
Script copies the .pcap to your local machine
        ↓
Debug pod is deleted automatically
        ↓
Output folder created with the capture file + sharing instructions
```

---

## Prerequisites

> **No SSH access to the AKS node is required.** This script runs entirely
> from your local machine or jumpbox using `kubectl`. It deploys a temporary
> debug pod on the node automatically, captures the traffic, copies the file
> back to your machine, and cleans up — all without ever logging into the node.

| Requirement | Why |
|---|---|
| `kubectl` installed and configured | Script uses kubectl to find nodes, deploy pods, and copy files |
| AKS cluster access | Run `az aks get-credentials --resource-group <rg> --name <cluster>` to connect |
| Permission to create privileged pods | Debug pod runs with `hostNetwork: true` and `privileged: true` |
| `nicolaka/netshoot` pullable from nodes | Used as the debug pod image — includes tcpdump |

> If your cluster uses a private container registry or restricts image pulls,
> see [Using a Custom Image](#using-a-custom-image) below.

---

## Installation

```bash
# Clone the repo
git clone https://github.com/HeyNaNd0/aks-pcap-tool.git
cd aks-pcap-tool

# Make the script executable
chmod +x scripts/aks-pcap-capture.sh
```

---

## Usage

```bash
./scripts/aks-pcap-capture.sh
```

The script will prompt you for:

| Prompt | Example | Default |
|---|---|---|
| Pod name | `my-app-pod-7d6f8b-xkq2p` | none |
| Namespace | `production` | `default` |
| Target IP or hostname | `10.0.1.50` or `sqlserver.internal` | none |
| Target port | `1433` | none |
| Capture duration (seconds) | `120` | `60` |

After confirming the inputs, the script runs automatically.
**Reproduce your issue during the capture window when prompted.**

---

## Output

A timestamped folder is created in your current directory:

```
aks-pcap-20250415_143022/
├── capture_20250415_143022.pcap       ← Upload this to Azure Support
└── HOW_TO_SHARE_WITH_SUPPORT.txt      ← Step-by-step sharing instructions
```

### HOW_TO_SHARE_WITH_SUPPORT.txt includes:
- Capture metadata (cluster, node, pod, target, duration)
- Azure Support Portal upload steps
- Azure Blob Storage upload steps (for large files)
- Wireshark filter tips for common AKS issues

---

## Using a Custom Image

If your cluster cannot pull `nicolaka/netshoot` from Docker Hub, build and
push your own image that includes `tcpdump`, then edit this line in the script:

```bash
image: nicolaka/netshoot
```

Replace it with your internal registry image.

---

## Common Errors

| Error | Cause | Fix |
|---|---|---|
| `Pod not found` | Wrong pod name or namespace | Run `kubectl get pods -n <namespace>` |
| `Permission denied` writing pcap | Debug pod not privileged | Ensure your account can create privileged pods |
| `tcpdump: command not found` | Wrong image | Use `nicolaka/netshoot` or an image with tcpdump |
| Empty pcap file | Issue not reproduced during window | Re-run with longer duration |
| `kubectl cp` fails | Debug pod exited too fast | Increase duration or check pod logs |
| Cannot create debug pod | RBAC restriction | Ask cluster admin for node debug permissions |

---

## References

This script automates all 5 steps described in the official Microsoft documentation:

- [Microsoft Docs — Capture a TCP dump from a Linux node in AKS](https://learn.microsoft.com/en-us/troubleshoot/azure/azure-kubernetes/logs/capture-tcp-dump-linux-node-aks)
  - Step 1: Find the node → automated via `kubectl get pod -o jsonpath`
  - Step 2: Connect to the node → automated via privileged debug pod
  - Step 3: Verify tcpdump is installed → automated via `nicolaka/netshoot` image
  - Step 4: Run tcpdump → automated with all recommended flags and filters
  - Step 5: Transfer the file locally → automated via reader pod and `kubectl cp`
- [nicolaka/netshoot — Container Network Troubleshooting](https://github.com/nicolaka/netshoot)
- [amjadaljunaidi/tcpdump — Helm chart alternative for multi-node captures](https://github.com/amjadaljunaidi/tcpdump)

---

## Contributing

Issues and pull requests are welcome.
See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

---

## License

MIT — see [LICENSE](LICENSE) for details.
