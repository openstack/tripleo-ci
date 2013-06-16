toci
====


Description
-----------

TripleO CI test framework.

By default it uses bm_poseur nodes. Options exist to deploy on real hardware as well.

Configuration
-------------

edit ~/.toci and add values for
```bash
TOCI_UPLOAD=0
TOCI_RESULTS_SERVER=1.2.3.4
TOCI_CLEANUP=1
TOCI_REMOVE=1
TOCI_GIT_CHECKOUT=1
export http_proxy=http://1.2.3.4:3128
export https_proxy=http://1.2.3.4:3128

# The following options can be used w/ real hardware
# Space delimited, aligned in order
#export TOCI_MACS="12:34:56:78:9A:E1 12:34:56:78:9A:E2"
#export TOCI_IPS="10.0.0.1 10.0.0.2"

#export TOCI_IPMI_USER="foo"
#export TOCI_IPMI_PASSWORD="bar"
```

Then run updated_launch.sh (this does a git update) or you can use toci.sh
directly to start the setup and tests.
