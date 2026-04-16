#!/bin/bash
# =============================================================
# AKS Network Packet Capture Tool
# For use by Azure Support / AKS Escalation Engineers
# =============================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
OUTPUT_DIR="./aks-pcap-${TIMESTAMP}"
PCAP_FILE="capture_${TIMESTAMP}.pcap"
INSTRUCTIONS_FILE="${OUTPUT_DIR}/HOW_TO_SHARE_WITH_SUPPORT.txt"

echo ""
echo -e "${CYAN}${BOLD}============================================${RESET}"
echo -e "${CYAN}${BOLD}   AKS Packet Capture Tool - Azure Support  ${RESET}"
echo -e "${CYAN}${BOLD}============================================${RESET}"
echo ""

# =============================================================
# STEP 1 — Collect inputs
# =============================================================

echo -e "${BOLD}Please answer the following questions:${RESET}"
echo ""

read -p "1. Pod name (the pod having the issue): " POD_NAME
read -p "2. Namespace (press Enter for 'default'): " NAMESPACE
NAMESPACE=${NAMESPACE:-default}
read -p "3. Target IP or hostname (e.g. SQL Server IP): " TARGET_HOST
read -p "4. Target port (press Enter for 1433): " TARGET_PORT
TARGET_PORT=${TARGET_PORT:-1433}
read -p "5. Capture duration in seconds (press Enter for 60): " DURATION
DURATION=${DURATION:-60}

echo ""
echo -e "${YELLOW}${BOLD}--- Summary of inputs ---${RESET}"
echo "  Pod:        $POD_NAME"
echo "  Namespace:  $NAMESPACE"
echo "  Target:     $TARGET_HOST:$TARGET_PORT"
echo "  Duration:   ${DURATION}s"
echo ""
read -p "Looks good? Press Enter to start or Ctrl+C to cancel..."

# =============================================================
# STEP 2 — Validate kubectl context
# =============================================================

echo ""
echo -e "${CYAN}[1/6] Checking kubectl context...${RESET}"

CURRENT_CONTEXT=$(kubectl config current-context 2>/dev/null)
if [ -z "$CURRENT_CONTEXT" ]; then
  echo -e "${RED}ERROR: No kubectl context found. Run 'az aks get-credentials' first.${RESET}"
  exit 1
fi
echo -e "${GREEN}  Context: $CURRENT_CONTEXT${RESET}"

# =============================================================
# STEP 3 — Find the node the pod is running on
# =============================================================

echo ""
echo -e "${CYAN}[2/6] Finding node for pod '${POD_NAME}'...${RESET}"

NODE=$(kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.nodeName}' 2>/dev/null)

if [ -z "$NODE" ]; then
  echo -e "${RED}ERROR: Pod '$POD_NAME' not found in namespace '$NAMESPACE'.${RESET}"
  echo "  Run: kubectl get pods -n $NAMESPACE"
  exit 1
fi

echo -e "${GREEN}  Pod is on node: $NODE${RESET}"

# =============================================================
# STEP 4 — Launch debug pod and run tcpdump
# =============================================================

echo ""
echo -e "${CYAN}[3/6] Launching privileged debug pod on node...${RESET}"
echo -e "${YELLOW}  This may take 20-30 seconds...${RESET}"

DEBUG_POD_NAME="pcap-debug-${TIMESTAMP}"

# Create a pod manifest that runs tcpdump on the node network namespace
cat <<EOF | kubectl apply -f - > /dev/null
apiVersion: v1
kind: Pod
metadata:
  name: ${DEBUG_POD_NAME}
  namespace: ${NAMESPACE}
  labels:
    app: pcap-debug
spec:
  hostNetwork: true
  hostPID: true
  nodeName: ${NODE}
  tolerations:
  - operator: "Exists"
  containers:
  - name: capture
    image: nicolaka/netshoot
    command: ["/bin/sh", "-c"]
    args:
    - >
      echo "Checking tcpdump..." &&
      tcpdump --version &&
      echo "Starting capture..." &&
      tcpdump --snapshot-length=0 -vvv
      host ${TARGET_HOST} and port ${TARGET_PORT}
      -w /host/tmp/${PCAP_FILE} &&
      echo "Capture complete."
    securityContext:
      privileged: true
    volumeMounts:
    - name: host-tmp
      mountPath: /host/tmp
  volumes:
  - name: host-tmp
    hostPath:
      path: /tmp
  restartPolicy: Never
EOF

echo -e "${GREEN}  Debug pod '${DEBUG_POD_NAME}' created.${RESET}"

# =============================================================
# STEP 5 — Wait for capture to complete
# =============================================================

echo ""
echo -e "${CYAN}[4/6] Capturing traffic for ${DURATION} seconds...${RESET}"
echo -e "${YELLOW}  --> REPRODUCE THE ISSUE NOW (trigger the failing connection) <--${RESET}"
echo ""

# Wait for pod to complete with a progress bar
for i in $(seq 1 $DURATION); do
  PERCENT=$((i * 100 / DURATION))
  BAR=$(printf '#%.0s' $(seq 1 $((i * 30 / DURATION))))
  printf "\r  [%-30s] %d%% (%ds/%ds)" "$BAR" "$PERCENT" "$i" "$DURATION"
  sleep 1
done
echo ""

# Wait for pod to reach Completed state
echo -e "${YELLOW}  Waiting for capture pod to finish writing...${RESET}"
kubectl wait pod "$DEBUG_POD_NAME" -n "$NAMESPACE" \
  --for=condition=Ready=false \
  --timeout=30s 2>/dev/null || true

sleep 3

# =============================================================
# STEP 6 — Copy pcap file locally
# =============================================================

echo ""
echo -e "${CYAN}[5/6] Copying capture file to local machine...${RESET}"

mkdir -p "$OUTPUT_DIR"

kubectl cp "${NAMESPACE}/${DEBUG_POD_NAME}:/tmp/${PCAP_FILE}" \
  "${OUTPUT_DIR}/${PCAP_FILE}" 2>/dev/null

if [ ! -f "${OUTPUT_DIR}/${PCAP_FILE}" ]; then
  echo -e "${RED}ERROR: Could not copy pcap file. The capture may have been empty.${RESET}"
  echo "  Check debug pod logs: kubectl logs $DEBUG_POD_NAME -n $NAMESPACE"
  kubectl delete pod "$DEBUG_POD_NAME" -n "$NAMESPACE" --ignore-not-found > /dev/null
  exit 1
fi

FILE_SIZE=$(du -h "${OUTPUT_DIR}/${PCAP_FILE}" | cut -f1)
echo -e "${GREEN}  File saved: ${OUTPUT_DIR}/${PCAP_FILE} (${FILE_SIZE})${RESET}"

# Clean up debug pod
kubectl delete pod "$DEBUG_POD_NAME" -n "$NAMESPACE" --ignore-not-found > /dev/null
echo -e "${GREEN}  Debug pod cleaned up.${RESET}"

# =============================================================
# STEP 7 — Write instructions file
# =============================================================

echo ""
echo -e "${CYAN}[6/6] Writing sharing instructions...${RESET}"

cat > "$INSTRUCTIONS_FILE" <<EOF
=============================================================
  AKS PACKET CAPTURE — INSTRUCTIONS FOR SHARING WITH SUPPORT
=============================================================

Capture Details
---------------
Date/Time      : $(date)
Cluster Context: $CURRENT_CONTEXT
Pod Name       : $POD_NAME
Namespace      : $NAMESPACE
Node           : $NODE
Target         : $TARGET_HOST:$TARGET_PORT
Duration       : ${DURATION} seconds
File           : $PCAP_FILE
File Size      : $FILE_SIZE


HOW TO SHARE THIS FILE WITH AZURE SUPPORT
------------------------------------------

Option 1 — Upload via Azure Support Portal (Recommended)
  1. Go to https://portal.azure.com
  2. Search for "Help + Support" in the top search bar
  3. Open your existing support case
  4. Click "File upload" or "Add attachment"
  5. Upload the file: $PCAP_FILE

Option 2 — Upload via Azure Storage (Large Files)
  1. Create a Storage Account in the Azure Portal
  2. Create a Blob container and set access to "Blob (anonymous read)"
  3. Upload $PCAP_FILE to the container
  4. Copy the blob URL and paste it into the support case notes

Option 3 — Share via Secure File Transfer (if requested by engineer)
  Your support engineer may provide a secure upload link.
  Use that link to upload: $PCAP_FILE


WHAT TO TELL YOUR SUPPORT ENGINEER
-------------------------------------
"I have captured a packet trace from AKS node '$NODE'
filtering traffic to $TARGET_HOST on port $TARGET_PORT.
Duration was ${DURATION} seconds. I reproduced the connection
failure during the capture window."


HOW TO OPEN THIS FILE (OPTIONAL — FOR YOUR OWN REVIEW)
---------------------------------------------------------
1. Download Wireshark from https://www.wireshark.org/download.html
2. Open Wireshark → File → Open → select $PCAP_FILE
3. Useful filters to try:
   - tcp.port == $TARGET_PORT        (all SQL traffic)
   - tls.handshake                   (TLS negotiation frames)
   - tls.alert_message               (TLS failures — look here first)
   - tcp.flags.reset == 1            (connection resets)


FILES IN THIS FOLDER
---------------------
  $PCAP_FILE              <- Upload this to support
  HOW_TO_SHARE_WITH_SUPPORT.txt   <- This file


=============================================================
Generated by aks-pcap-capture.sh
=============================================================
EOF

echo -e "${GREEN}  Instructions written.${RESET}"

# =============================================================
# DONE
# =============================================================

echo ""
echo -e "${GREEN}${BOLD}============================================${RESET}"
echo -e "${GREEN}${BOLD}   Capture Complete!${RESET}"
echo -e "${GREEN}${BOLD}============================================${RESET}"
echo ""
echo -e "  ${BOLD}Output folder:${RESET}  $OUTPUT_DIR"
echo -e "  ${BOLD}Capture file:${RESET}   ${OUTPUT_DIR}/${PCAP_FILE} (${FILE_SIZE})"
echo -e "  ${BOLD}Instructions:${RESET}   $INSTRUCTIONS_FILE"
echo ""
echo -e "${YELLOW}  Next step: Open '$INSTRUCTIONS_FILE' and follow the steps to share with Azure Support.${RESET}"
echo ""
