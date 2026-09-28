#!/usr/bin/env bash

set -u

NODE="clab-frr-bgp-R1"

TARGET="198.51.100.1"
PRIMARY_NEIGHBOR="10.0.12.2"

HEALTHY_MAP="ISP-A-IN"
DEGRADED_MAP="ISP-A-DEGRADED-IN"

FAIL_THRESHOLD=3
RECOVER_THRESHOLD=3
INTERVAL=1

STATE="healthy"

FAIL_COUNT=0
SUCCESS_COUNT=0


apply_policy() {

    local ROUTE_MAP="$1"

    docker exec "$NODE" vtysh \
        -c "configure terminal" \
        -c "router bgp 65010" \
        -c "address-family ipv4 unicast" \
        -c "neighbor ${PRIMARY_NEIGHBOR} route-map ${ROUTE_MAP} in" \
        -c "end" \
        >/dev/null 2>&1

    docker exec "$NODE" vtysh \
        -c "clear bgp ipv4 unicast ${PRIMARY_NEIGHBOR} soft in" \
        >/dev/null 2>&1
}


echo "=========================================="
echo "R2 End-to-End Health Tracker"
echo "=========================================="
echo "Target: $TARGET"
echo "Primary neighbor: $PRIMARY_NEIGHBOR"
echo "Failure threshold: $FAIL_THRESHOLD"
echo "Recovery threshold: $RECOVER_THRESHOLD"
echo
echo "Press Ctrl+C to stop."
echo


while true; do

    TIMESTAMP=$(date '+%H:%M:%S')

    if docker exec "$NODE" \
        ping -c 1 -W 1 "$TARGET" >/dev/null 2>&1
    then

        FAIL_COUNT=0

        if [[ "$STATE" == "degraded" ]]; then

            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))

            echo "[$TIMESTAMP] probe=UP state=degraded success=$SUCCESS_COUNT"

            if [[ "$SUCCESS_COUNT" -ge "$RECOVER_THRESHOLD" ]]; then

                echo "[$TIMESTAMP] HEALTH RECOVERED"
                echo "[$TIMESTAMP] Restoring primary policy..."

                apply_policy "$HEALTHY_MAP"

                STATE="healthy"
                SUCCESS_COUNT=0

                echo "[$TIMESTAMP] R2 Local Preference restored to 200"
            fi

        else

            SUCCESS_COUNT=0
            echo "[$TIMESTAMP] probe=UP state=healthy"

        fi

    else

        SUCCESS_COUNT=0

        if [[ "$STATE" == "healthy" ]]; then

            FAIL_COUNT=$((FAIL_COUNT + 1))

            echo "[$TIMESTAMP] probe=DOWN state=healthy failure=$FAIL_COUNT"

            if [[ "$FAIL_COUNT" -ge "$FAIL_THRESHOLD" ]]; then

                echo "[$TIMESTAMP] HEALTH FAILURE DETECTED"
                echo "[$TIMESTAMP] Degrading primary path..."

                apply_policy "$DEGRADED_MAP"

                STATE="degraded"
                FAIL_COUNT=0

                echo "[$TIMESTAMP] R2 Local Preference changed to 50"
            fi

        else

            FAIL_COUNT=0
            echo "[$TIMESTAMP] probe=DOWN state=degraded"

        fi

    fi

    sleep "$INTERVAL"

done
