function previous_release_from {
    # works even when $1 is empty string or not provided at all
    local RELEASE="$1"

    case "$RELEASE" in
        ''|master)
            # NOTE: we need to update this when we cut a stable branch
            echo "ocata"
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
