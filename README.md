# aks-pcap-tool

![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20WSL-blue)
![Shell](https://img.shields.io/badge/shell-bash-green)
![License](https://img.shields.io/badge/license-MIT-orange)

On-demand packet capture tool for AKS Linux nodes. Built for Azure Support
Engineers and AKS administrators to quickly collect network traces during
live troubleshooting sessions — no Helm, no persistent storage, no setup.

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

| Requirement | Why |
|---|---|
| `kubectl` installed and configured | Script uses kubectl to find nodes, deploy pods, and copy files |
| AKS cluster access | Must be able to reach the cluster from your terminal |
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
| Target port | `5432` | `1433` |
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

## Analyzing the Capture (Optional)

Open the `.pcap` file in [Wireshark](https://www.wireshark.org/download.html)
and use these filters depending on your issue:

| Issue | Wireshark Filter |
|---|---|
| All SQL Server traffic | `tcp.port == 1433` |
| TLS handshake frames | `tls.handshake` |
| TLS failures (Error 35) | `tls.alert_message` |
| Connection resets | `tcp.flags.reset == 1` |
| DNS resolution failures | `dns` |
| All traffic to target IP | `ip.addr == <target-ip>` |

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

- [Microsoft Docs — Capture a TCP dump from a Linux node in AKS](https://learn.microsoft.com/en-us/troubleshoot/azure/azure-kubernetes/logs/capture-tcp-dump-linux-node-aks)
- [nicolaka/netshoot — Container Network Troubleshooting](https://github.com/nicolaka/netshoot)
- [amjadaljunaidi/tcpdump — Helm chart alternative for multi-node captures](https://github.com/amjadaljunaidi/tcpdump)

---

## Contributing

Issues and pull requests are welcome.
See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

---

## License

MIT — see [LICENSE](LICENSE) for details.
