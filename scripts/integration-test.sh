#!/bin/bash
set -euo pipefail

# =====================================================
# Integration test: submit a job via frontend, verify
# it reaches "completed" status within the timeout.
# =====================================================

FRONTEND_URL="http://localhost:3000"
MAX_ATTEMPTS=30
SLEEP_SECONDS=2

echo "=========================================="
echo "Integration test starting"
echo "=========================================="

# Step 1: Submit a job
echo ""
echo "[1/3] Submitting a job via POST ${FRONTEND_URL}/submit..."
RESPONSE=$(curl -sf -X POST "${FRONTEND_URL}/submit")
echo "Response: ${RESPONSE}"

JOB_ID=$(echo "${RESPONSE}" | python3 -c "import sys, json; print(json.load(sys.stdin)['job_id'])")

if [ -z "${JOB_ID}" ]; then
  echo "ERROR: Failed to extract job_id from response"
  exit 1
fi

echo "Created job: ${JOB_ID}"

# Step 2: Poll for completion
echo ""
echo "[2/3] Polling ${FRONTEND_URL}/status/${JOB_ID} for completion..."

for i in $(seq 1 ${MAX_ATTEMPTS}); do
  STATUS_RESPONSE=$(curl -sf "${FRONTEND_URL}/status/${JOB_ID}")
  STATUS=$(echo "${STATUS_RESPONSE}" | python3 -c "import sys, json; print(json.load(sys.stdin)['status'])")
  echo "  Attempt ${i}/${MAX_ATTEMPTS}: status=${STATUS}"

  if [ "${STATUS}" = "completed" ]; then
    echo ""
    echo "[3/3] ✅ Job completed successfully."
    echo "=========================================="
    echo "Integration test PASSED"
    echo "=========================================="
    exit 0
  fi

  if [ "${STATUS}" = "failed" ]; then
    echo ""
    echo "ERROR: Job status is 'failed' — worker reported an error"
    echo "=========================================="
    echo "Integration test FAILED"
    echo "=========================================="
    exit 1
  fi

  sleep ${SLEEP_SECONDS}
done

echo ""
echo "ERROR: Job did not reach 'completed' status within $((MAX_ATTEMPTS * SLEEP_SECONDS)) seconds"
echo "=========================================="
echo "Integration test FAILED (timeout)"
echo "=========================================="
exit 1
