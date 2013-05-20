toci
====

TripleO CI tests


edit ~/.toci and add values for
```bash
TOCI_UPLOAD=0
TOCI_RESULTS_SERVER=1.2.3.4
TOCI_CLEANUP=1
TOCI_REMOVE=1
export http_proxy=http://1.2.3.4:3128
export https_proxy=http://1.2.3.4:3128
```


then run updated_launch.sh (this does a git update) or toci.sh
