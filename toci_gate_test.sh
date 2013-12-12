#!/usr/bin/env bash

set -e

# XXX: 127.0.0.1 naturally won't work for real CI but for manual
# testing running a server on the same machine is convenient.
GEARDSERVER=${GEARDSERVER:-127.0.0.1}

./testenv-client -b $GEARDSERVER:4730 -- ./toci_devtest.sh
