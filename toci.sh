#!/usr/bin/bash

export STARTTIME=$(date)
export TOCI_WORKING_DIR=$(mktemp -d)
export TOCI_LOG_DIR=$(mktemp -d)

echo $TOCI_LOG_DIR

STATUS=0

./toci_setup.sh > $TOCI_LOG_DIR/setup.out 2>&1 || STATUS=1
if [ $STATUS == 0 ] ; then
    ./toci_test.sh > $TOCI_LOG_DIR/test.out 2>&1 || STATUS=1
fi
./toci_cleanup.sh > $TOCI_LOG_DIR/cleanup.out 2>&1 || STATUS=1

cd $(dirname $TOCI_LOG_DIR)
tar -czf - $(basename $TOCI_LOG_DIR) | ssh ec2-user@toci_results tar -C /var/www/html/toci -xzf -

if [ $STATUS == 0 ] ; then
    ssh ec2-user@toci_results "echo \<a href=\"$(basename $TOCI_LOG_DIR)\"\>$STARTTIME : OK\</a\>\<br/\> >> /var/www/html/toci/index.html ; chmod -R 775 /var/www/html/toci/*"
else
    ssh ec2-user@toci_results "echo \<a style=\\\"COLOR: \#FF0000\\\" href=\"$(basename $TOCI_LOG_DIR)\"\>$STARTTIME : ERR\</a\>\<br/\> >> /var/www/html/toci/index.html ; chmod -R 775 /var/www/html/toci/*"
fi
