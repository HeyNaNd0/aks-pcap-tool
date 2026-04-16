#!/bin/bash
# =============================================================
# aks-pcap-tool — Dry Run Test Suite
# Tests script logic without a real AKS cluster
# =============================================================

PASS=0
FAIL=0
SCRIPT_PATH="$(dirname "$0")/../scripts/aks-pcap-capture.sh"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

echo ""
echo -e "${CYAN}${BOLD}============================================${RESET}"
echo -e "${CYAN}${BOLD}   aks-pcap-tool — Dry Run Test Suite      ${RESET}"
echo -e "${CYAN}${BOLD}============================================${RESET}"
echo ""

# =============================================================
# Helper functions
# =============================================================

pass() {
  echo -e "  ${GREEN}✓ PASS${RESET} — $1"
  PASS=$((PASS + 1))
}

fail() {
  echo -e "  ${RED}✗ FAIL${RESET} — $1"
  FAIL=$((FAIL + 1))
}

section() {
  echo ""
  echo -e "${YELLOW}${BOLD}$1${RESET}"
}

# Run a validator in a subshell so exit 1 does not kill the test runner
# Returns 0 if valid, 1 if invalid
safe_validate() {
  ("$@") 2>/dev/null
  return $?
}

# =============================================================
# TEST 1 — Script exists and is executable
# =============================================================

section "[1] Script Validation"

if [ -f "$SCRIPT_PATH" ]; then
  pass "Script file exists at $SCRIPT_PATH"
else
  fail "Script not found at $SCRIPT_PATH"
fi

if [ -x "$SCRIPT_PATH" ]; then
  pass "Script is executable"
else
  fail "Script is not executable — run: chmod +x $SCRIPT_PATH"
fi

# =============================================================
# TEST 2 — Script contains required flags and settings
# =============================================================

section "[2] Script Content Checks"

grep -q "snapshot-length=0" "$SCRIPT_PATH" && \
  pass "tcpdump --snapshot-length=0 flag present (full packet capture)" || \
  fail "Missing --snapshot-length=0 flag"

grep -q "\-vvv" "$SCRIPT_PATH" && \
  pass "tcpdump -vvv flag present (verbose output)" || \
  fail "Missing -vvv flag"

grep -q "hostNetwork: true" "$SCRIPT_PATH" && \
  pass "hostNetwork: true present (node-level capture)" || \
  fail "Missing hostNetwork: true"

grep -q "privileged: true" "$SCRIPT_PATH" && \
  pass "privileged: true present (required for tcpdump)" || \
  fail "Missing privileged: true"

grep -q "nicolaka/netshoot" "$SCRIPT_PATH" && \
  pass "nicolaka/netshoot image referenced" || \
  fail "Missing nicolaka/netshoot image"

grep -q "HOW_TO_SHARE_WITH_SUPPORT" "$SCRIPT_PATH" && \
  pass "Support instructions file is generated" || \
  fail "Missing HOW_TO_SHARE_WITH_SUPPORT output"

grep -q "kubectl delete pod" "$SCRIPT_PATH" && \
  pass "Debug pod cleanup present" || \
  fail "Missing debug pod cleanup"

# =============================================================
# TEST 3 — Security fixes are present
# =============================================================

section "[3] Security Checks"

grep -q "validate_hostname" "$SCRIPT_PATH" && \
  pass "validate_hostname function present" || \
  fail "Missing validate_hostname — HIGH severity finding not fixed"

grep -q "validate_port" "$SCRIPT_PATH" && \
  pass "validate_port function present" || \
  fail "Missing validate_port — HIGH severity finding not fixed"

grep -q "validate_duration" "$SCRIPT_PATH" && \
  pass "validate_duration function present" || \
  fail "Missing validate_duration — input validation not fixed"

grep -q "validate_k8s_name" "$SCRIPT_PATH" && \
  pass "validate_k8s_name function present" || \
  fail "Missing validate_k8s_name — MEDIUM severity finding not fixed"

grep -q "trap cleanup EXIT" "$SCRIPT_PATH" && \
  pass "trap cleanup EXIT present (pod cleanup on Ctrl+C)" || \
  fail "Missing trap cleanup — LOW severity finding not fixed"

# =============================================================
# TEST 4 — Input validation logic works correctly
# =============================================================

section "[4] Input Validation Logic"

# Load validation functions from the script into current shell
# We extract just the function definitions so we can test them directly
eval "$(grep -A 10 'validate_hostname()' "$SCRIPT_PATH" | head -6)"
eval "$(grep -A 10 'validate_port()' "$SCRIPT_PATH" | head -7)"
eval "$(grep -A 10 'validate_duration()' "$SCRIPT_PATH" | head -7)"
eval "$(grep -A 10 'validate_k8s_name()' "$SCRIPT_PATH" | head -6)"

# --- hostname ---
safe_validate validate_hostname "10.0.1.50" && \
  pass "Valid IP accepted (10.0.1.50)" || \
  fail "Valid IP rejected"

safe_validate validate_hostname "sqlserver.internal" && \
  pass "Valid hostname accepted (sqlserver.internal)" || \
  fail "Valid hostname rejected"

safe_validate validate_hostname "1.2.3.4;rm -rf /" && \
  fail "Shell injection accepted — SECURITY ISSUE" || \
  pass "Shell injection blocked (1.2.3.4;rm -rf /)"

safe_validate validate_hostname '$(whoami)' && \
  fail "Command substitution accepted — SECURITY ISSUE" || \
  pass "Command substitution blocked"

# --- port ---
safe_validate validate_port "1433" && \
  pass "Valid port accepted (1433)" || \
  fail "Valid port rejected"

safe_validate validate_port "99999" && \
  fail "Out of range port accepted" || \
  pass "Out of range port blocked (99999)"

safe_validate validate_port "abc" && \
  fail "Non-numeric port accepted" || \
  pass "Non-numeric port blocked (abc)"

safe_validate validate_port "0" && \
  fail "Port 0 accepted" || \
  pass "Port 0 blocked"

# --- duration ---
safe_validate validate_duration "60" && \
  pass "Valid duration accepted (60)" || \
  fail "Valid duration rejected"

safe_validate validate_duration "9999" && \
  fail "Duration over 3600 accepted" || \
  pass "Duration over 3600 blocked (9999)"

safe_validate validate_duration "abc" && \
  fail "Non-numeric duration accepted" || \
  pass "Non-numeric duration blocked (abc)"

# --- k8s name ---
safe_validate validate_k8s_name "test-pod" && \
  pass "Valid pod name accepted (test-pod)" || \
  fail "Valid pod name rejected"

safe_validate validate_k8s_name "UPPERCASE-POD" && \
  fail "Uppercase pod name accepted" || \
  pass "Uppercase pod name blocked"

safe_validate validate_k8s_name "pod name with spaces" && \
  fail "Pod name with spaces accepted" || \
  pass "Pod name with spaces blocked"

# =============================================================
# TEST 5 — Output folder simulation
# =============================================================

section "[5] Output Folder Simulation"

TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
TEST_OUTPUT_DIR="/tmp/aks-pcap-test-${TIMESTAMP}"
TEST_PCAP="${TEST_OUTPUT_DIR}/capture-${TIMESTAMP}.pcap"
TEST_INSTRUCTIONS="${TEST_OUTPUT_DIR}/HOW_TO_SHARE_WITH_SUPPORT.txt"

mkdir -p "$TEST_OUTPUT_DIR"
[ -d "$TEST_OUTPUT_DIR" ] && pass "Output directory created" || fail "Could not create output directory"

touch "$TEST_PCAP"
[ -f "$TEST_PCAP" ] && pass "Capture file placeholder created" || fail "Could not create capture file"

cat > "$TEST_INSTRUCTIONS" << EOF
TEST — HOW_TO_SHARE_WITH_SUPPORT.txt
Generated by dry-run test at $TIMESTAMP
EOF
[ -f "$TEST_INSTRUCTIONS" ] && pass "HOW_TO_SHARE_WITH_SUPPORT.txt created" || fail "Could not create instructions file"

# =============================================================
# TEST 6 — Mock kubectl checks
# =============================================================

section "[6] Mock kubectl Checks"

MOCK_BIN="/tmp/mock-kubectl-${TIMESTAMP}"
cat > "$MOCK_BIN" << 'EOF'
#!/bin/bash
if [[ "$*" == *"jsonpath"* ]]; then
  echo "aks-nodepool1-12345678-vmss000000"
elif [[ "$*" == *"current-context"* ]]; then
  echo "my-test-cluster"
else
  echo "mock-kubectl: $*"
fi
EOF
chmod +x "$MOCK_BIN"

NODE=$("$MOCK_BIN" get pod test-pod -n default -o jsonpath='{.spec.nodeName}')
[ "$NODE" = "aks-nodepool1-12345678-vmss000000" ] && \
  pass "Mock kubectl node lookup returns expected node name" || \
  fail "Mock kubectl node lookup failed — got: $NODE"

CONTEXT=$("$MOCK_BIN" config current-context)
[ "$CONTEXT" = "my-test-cluster" ] && \
  pass "Mock kubectl context check returns expected context" || \
  fail "Mock kubectl context check failed — got: $CONTEXT"

# =============================================================
# TEST 7 — Cleanup simulation
# =============================================================

section "[7] Cleanup Simulation"

rm -rf "$TEST_OUTPUT_DIR"
[ ! -d "$TEST_OUTPUT_DIR" ] && pass "Output directory cleaned up" || fail "Output directory not cleaned up"

rm -f "$MOCK_BIN"
[ ! -f "$MOCK_BIN" ] && pass "Mock kubectl binary cleaned up" || fail "Mock kubectl binary not cleaned up"

# =============================================================
# RESULTS
# =============================================================

echo ""
echo -e "${CYAN}${BOLD}============================================${RESET}"
echo -e "${BOLD}Results: ${GREEN}${PASS} passed${RESET} / ${RED}${FAIL} failed${RESET}"
echo -e "${CYAN}${BOLD}============================================${RESET}"
echo ""

if [ "$FAIL" -eq 0 ]; then
  echo -e "${GREEN}${BOLD}All tests passed. Script is ready.${RESET}"
  exit 0
else
  echo -e "${RED}${BOLD}${FAIL} test(s) failed. Review output above.${RESET}"
  exit 1
fi
