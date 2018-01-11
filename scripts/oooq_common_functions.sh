function previous_release_from {
    # works even when $1 is empty string or not provided at all
    local RELEASE="$1"

    case "$RELEASE" in
        ''|master)
            # NOTE: we need to update this when we cut a stable branch
            echo "pike"
            ;;
        queens)
            echo "pike"
            ;;
        pike)
            echo "ocata"
            ;;
        ocata)
            echo "newton"
            ;;
        newton)
            echo "mitaka"
            ;;
        *)
            echo "UNKNOWN_RELEASE"
            return 1
            ;;
    esac
}

function is_featureset_mixed_upgrade {
    local FEATURESET_FILE="$1"

    [ $(shyaml get-value mixed_upgrade "False"< $FEATURESET_FILE) = "True" ]
}

function run_with_timeout {
    # First parameter is the START_JOB_TIME
    # Second is the command to be executed
    JOB_TIME=$1
    shift
    COMMAND=$@
    # Leave 10 minutes for quickstart logs collection for ovb only
    if [[ "$TOCI_JOBTYPE" =~ "ovb" ]]; then
        RESERVED_LOG_TIME=10
    else
        RESERVED_LOG_TIME=0
    fi
    # Use $REMAINING_TIME of infra to calculate maximum time for remaining part of job
    REMAINING_TIME=${REMAINING_TIME:-180}
    TIME_FOR_COMMAND=$(( REMAINING_TIME - ($(date +%s) - JOB_TIME)/60 - $RESERVED_LOG_TIME))

    if [[ $TIME_FOR_COMMAND -lt 1 ]]; then
        return 143
    fi
    /usr/bin/timeout --preserve-status ${TIME_FOR_COMMAND}m ${COMMAND}
}
