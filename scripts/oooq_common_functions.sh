function previous_release_from {
    local release="${1:-master}"
    local type="${2:-mixed_upgrade}"
    local previous_version=""
    case "${type}" in
        'mixed_upgrade')
            previous_version=$(previous_release_mixed_upgrade_case "${release}");;
        'ffu_upgrade')
            previous_version=$(previous_release_ffu_upgrade_case "${release}");;
        *)
            echo "UNKNOWN_TYPE"
            return 1
            ;;
    esac
    echo "${previous_version}"
}

function previous_release_mixed_upgrade_case {
    local release="${1:-master}"
    case "${release}" in
        ''|master)
            # NOTE: we need to update this when we cut a stable branch
            echo "queens"
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

function previous_release_ffu_upgrade_case {
    local release="${1:-master}"

    case "${release}" in
        ''|master)
            # NOTE: we need to update this when we cut a stable branch
            echo "newton"
            ;;
        queens)
            echo "newton"
            ;;
        *)
            echo "INVALID_RELEASE_FOR_FFU"
            return 1
            ;;
    esac
}

function is_featureset {
    local type="${1}"
    local featureset_file="${2}"

    [ $(shyaml get-value "${type}" "False"< "${featureset_file}") = "True" ]
}

function run_with_timeout {
    # First parameter is the START_JOB_TIME
    # Second is the command to be executed
    JOB_TIME=$1
    shift
    COMMAND=$@
    # Leave 20 minutes for quickstart logs collection for ovb only
    if [[ "$TOCI_JOBTYPE" =~ "ovb" ]]; then
        RESERVED_LOG_TIME=20
    else
        RESERVED_LOG_TIME=3
    fi
    # Use $REMAINING_TIME of infra to calculate maximum time for remaining part of job
    REMAINING_TIME=${REMAINING_TIME:-180}
    TIME_FOR_COMMAND=$(( REMAINING_TIME - ($(date +%s) - JOB_TIME)/60 - $RESERVED_LOG_TIME))

    if [[ $TIME_FOR_COMMAND -lt 1 ]]; then
        return 143
    fi
    /usr/bin/timeout --preserve-status ${TIME_FOR_COMMAND}m ${COMMAND}
}

function next_release_from {
    local release="${1:-master}"
    case "${release}" in
            # NOTE: we need to add a new release when we cut a stable branch
        ''|master)
            echo "master"
            ;;
        queens)
            echo "master"
            ;;
        pike)
            echo "queens"
            ;;
        ocata)
            echo "pike"
            ;;
        newton)
            echo "ocata"
            ;;
        *)
            echo "UNKNOWN_RELEASE"
            return 1
            ;;
    esac
}
