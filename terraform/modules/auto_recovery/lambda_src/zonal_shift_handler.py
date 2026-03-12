"""
zonal_shift_handler.py
======================
Closed-Loop Auto-Recovery via ARC Zonal Shift.

Triggered directly by a CloudWatch Alarm (direct invocation feature —
no SNS/EventBridge hop required).

Flow:
  1. CloudWatch Alarm fires (5XX threshold breached for a specific AZ).
  2. CW invokes this Lambda directly with an alarm-state-change event.
  3. Lambda reads the AvailabilityZone dimension from the alarm payload.
  4. Lambda calls arc-zonal-shift.StartZonalShift for that AZ on the ALB.
  5. ARC shifts traffic away from the impaired AZ for VAR_EXPIRY_MINUTES minutes.

Environment variables (set by Terraform):
  ALB_ARN          - Full ARN of the target ALB.
  EXPIRY_MINUTES   - Zonal shift expiry window in minutes (default: 30).

For idempotency: if a zonal shift already exists for this AZ+resource,
StartZonalShift returns the existing record, so repeated alarm firings
are safe.
"""

import json
import logging
import os
from datetime import datetime, timedelta, timezone

import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# ---------------------------------------------------------------------------
# Configuration (injected via Terraform environment variables)
# ---------------------------------------------------------------------------
ALB_ARN = os.environ["ALB_ARN"]
EXPIRY_MINUTES = int(os.environ.get("EXPIRY_MINUTES", "30"))


def _extract_failing_az(event: dict) -> str | None:
    """
    Parse the CloudWatch Alarm invocation payload and return the value of the
    AvailabilityZone dimension, or None if it cannot be found.

    CloudWatch direct-invocation payload structure (simplified):
    {
      "alarmData": {
        "alarmName": "...",
        "state": { "value": "ALARM", ... },
        "configuration": {
          "metrics": [
            {
              "metricStat": {
                "metric": {
                  "dimensions": {
                    "AvailabilityZone": "eu-central-1a",
                    "LoadBalancer": "app/my-alb/..."
                  }
                }
              }
            }
          ]
        }
      }
    }
    """
    try:
        alarm_data = event.get("alarmData", {})
        metrics = (
            alarm_data
            .get("configuration", {})
            .get("metrics", [])
        )
        for metric_item in metrics:
            dims = (
                metric_item
                .get("metricStat", {})
                .get("metric", {})
                .get("dimensions", {})
            )
            az = dims.get("AvailabilityZone")
            if az:
                logger.info("Extracted AvailabilityZone from alarm payload: %s", az)
                return az
    except Exception as exc:  # pylint: disable=broad-except
        logger.error("Unexpected error parsing alarm payload: %s", exc)

    logger.error(
        "Could not extract AvailabilityZone from event payload. Full event: %s",
        json.dumps(event),
    )
    return None


def _validate_alarm_state(event: dict) -> bool:
    """
    Only act when the alarm transitions INTO the ALARM state.
    Ignore OK / INSUFFICIENT_DATA transitions to avoid cancelling
    an active zonal shift prematurely (the shift will auto-expire).
    """
    state = (
        event
        .get("alarmData", {})
        .get("state", {})
        .get("value", "")
    )
    if state != "ALARM":
        logger.info(
            "Alarm state is '%s' — not ALARM, skipping zonal shift action.", state
        )
        return False
    return True


def _start_zonal_shift(az: str) -> dict:
    """
    Call ARC Zonal Shift to divert ALB traffic away from the impaired AZ.

    The expiry time is computed as UTC now + EXPIRY_MINUTES. ARC requires
    an ISO-8601 datetime string ending in 'Z'.
    """
    client = boto3.client("arc-zonal-shift")

    expiry_dt = datetime.now(tz=timezone.utc) + timedelta(minutes=EXPIRY_MINUTES)
    # ARC API expects an ISO-8601 string; datetime.isoformat() produces the correct format.
    expiry_str = expiry_dt.strftime("%Y-%m-%dT%H:%M:%SZ")

    comment = f"Auto-recovery: 5XX alarm in {az}. Expires: {expiry_str} UTC."

    logger.info(
        "Starting zonal shift: resource=%s, awayFrom=%s, expiresAt=%s",
        ALB_ARN,
        az,
        expiry_str,
    )

    response = client.start_zonal_shift(
        resourceIdentifier=ALB_ARN,
        awayFrom=az,
        expiresIn=f"{EXPIRY_MINUTES}m",  # ARC accepts "<N>m" or "<N>h" duration strings
        comment=comment,
    )

    logger.info(
        "Zonal shift started successfully. zonalShiftId=%s, status=%s",
        response.get("zonalShiftId"),
        response.get("status"),
    )
    return response


def lambda_handler(event: dict, context) -> dict:  # noqa: ANN001
    """
    Entry point invoked by CloudWatch Alarm direct integration.

    Returns a dict with {"statusCode": 200/400/500, "body": "..."} for
    observability in CloudWatch Logs; CW ignores the return value.
    """
    logger.info("Received event: %s", json.dumps(event))

    # --- Guard: only proceed on actual ALARM state transitions ---
    if not _validate_alarm_state(event):
        return {"statusCode": 200, "body": "No action — alarm not in ALARM state."}

    # --- Extract the impaired AZ from the alarm dimensions ---
    az = _extract_failing_az(event)
    if az is None:
        return {
            "statusCode": 400,
            "body": "Could not determine impaired AZ from alarm payload.",
        }

    # --- Trigger ARC Zonal Shift ---
    try:
        response = _start_zonal_shift(az)
        return {
            "statusCode": 200,
            "body": (
                f"Zonal shift initiated for AZ={az}. "
                f"zonalShiftId={response.get('zonalShiftId')}"
            ),
        }
    except ClientError as exc:
        error_code = exc.response["Error"]["Code"]
        error_msg = exc.response["Error"]["Message"]
        logger.error(
            "AWS ClientError starting zonal shift: [%s] %s", error_code, error_msg
        )
        # Re-raise so Lambda marks the invocation as failed and CW retries
        raise
