#!/bin/bash

set -eu
set -o pipefail

TMPFILE=$(mktemp)
TMP2FILE=$(mktemp)

function heat_resource_metadata() {
  # Build os-collect-config command line arguments for the given heat
  # resource, which when run, allow us to collect the heat completion
  # signals.
  heat resource-metadata overcloud $1 | jq '.["os-collect-config"]["cfn"]' | grep \" | tr -d '\n' | sed -e 's/"//g' -e 's/_/-/g' -e 's/: / /g' -e 's/,  / --cfn-/g' -e 's/^  /--cfn-/' -e 's/$/ --print/'
  echo
}

>$TMPFILE
heat_resource_metadata controller0 >>$TMPFILE
for i in $(seq 0 34) ; do
    heat_resource_metadata NovaCompute$i >>$TMPFILE
done

sed -e 's/^/os-collect-config /' -e 's/$/ \&/' < $TMPFILE > $TMP2FILE
echo "#!/bin/sh\nset -e\n" > $TMPFILE
cat $TMPFILE $TMP2FILE > "kill-heat"
chmod +x "kill-heat"
