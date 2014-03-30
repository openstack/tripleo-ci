#!/usr/bin/env bash

set -eu

# cd to toci directory so relative paths work (below and in toci_devtest.sh)
cd $(dirname $0)

# XXX: 127.0.0.1 naturally won't work for real CI but for manual
# testing running a server on the same machine is convenient.
GEARDSERVER=${GEARDSERVER:-127.0.0.1}

TIMEOUT_SECS=$((DEVSTACK_GATE_TIMEOUT*60))
./testenv-client -b $GEARDSERVER:4730 -t $TIMEOUT_SECS -- ./toci_devtest.sh
