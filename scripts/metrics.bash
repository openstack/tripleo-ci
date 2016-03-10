export METRICS_START_TIMES=/tmp/metric-start-times
export METRICS_DATA_FILE=/tmp/metrics-data

# Record a metric. If no DTS is provided the current date is used.
function record_metric {
    local METRIC_NAME=$1
    local METRIC_VALUE=$2
    local DTS=${3:-$(date +%s)}
    if [ -z "$METRIC_NAME" -o -z "$METRIC_VALUE" ]; then
        echo "Please specify METRIC_NAME and METRIC_VALUE" >&2
        exit 1
    fi
    echo "$METRIC_NAME:$METRIC_VALUE:$DTS" >> $METRICS_DATA_FILE
}

# Start a time metric by keeping track of a timestamp until stop_metric is
# called. NOTE: time metrics names must be unique.
function start_metric {
    local NAME=$1
    local START_TIME=$(date +%s)
    # we use : as our delimiter so convert to _. Also convert spaces and /'s.
    local METRIC_NAME=$(echo "$1" | sed -e 's|[\ \///:]|_|g')

    if grep -c "^$METRIC_NAME:" $METRICS_START_TIMES &>/dev/null; then
        echo "start_metric has already been called for $NAME" >&2
        exit 1
    fi
    echo "$METRIC_NAME:$START_TIME" >> $METRICS_START_TIMES

}

# Stop a time metric previously started by the start_metric function.
# The total time (in seconds) is calculated and logged to the metrics
# data file. NOTE: the end time is used as the DTS.
function stop_metric {
    local NAME=$1
    local METRIC_NAME=$(echo "$1" | sed -e 's|[\ \///:]|_|g')
    local END_TIME=$(date +%s)
    if ! grep -c "^$METRIC_NAME" $METRICS_START_TIMES &>/dev/null; then
        echo "Please call start_metric before calling stop_metric for $NAME" >&2
        exit 1
    fi
    local LINE=$(grep "^$METRIC_NAME:" $METRICS_START_TIMES)
    local START_TIME=$(grep "^$METRIC_NAME:" $METRICS_START_TIMES | cut -d ':' -f '2')
    local TOTAL_TIME="$(($END_TIME - $START_TIME))"
    record_metric "$METRIC_NAME" "$TOTAL_TIME" "$END_TIME"

}

function metrics_to_graphite {
    local SERVER=$1
    local PORT=${2:-2003} # default port for graphite data

    local METRIC_NAME
    local METRIC_VAL
    local DTS

    for X in $(cat $METRICS_DATA_FILE); do
        METRIC_NAME=$(echo $X | cut -d ":" -f 1)
        METRIC_VAL=$(echo $X | cut -d ":" -f 2)
        DTS=$(echo $X | cut -d ":" -f 3)
        echo "$METRIC_NAME $METRIC_VAL $DTS" | nc ${SERVER} ${PORT}
    done
    # reset the existing data file and start times
    echo "" > METRICS_START_TIMES
    echo "" > METRICS_DATA_FILE
}
