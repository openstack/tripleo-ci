# tripleo-get-hash

## What is tripleo-get-hash

This utility is meant for use by TripleO deployments, particularly in zuul
continuous integration jobs. Given an RDO named tag, such as 'current-tripleo'
or 'tripleo-ci-testing' [1] it will return the hash information, including
the commit, distro and full hashes where available.

It includes a simple command line interface. If you clone the source you can
try it out of the box without installation invoking it as a module:
```
     python -m tripleo_get_hash # by default centos8, master, current-tripleo.
     python -m tripleo_get_hash --component tripleo --release victoria --os-version centos8
     python -m tripleo_get_hash --release master --os-version centos7
     python -m tripleo_get_hash --release train # by default centos8
     python -m tripleo_get_hash --os-version rhel8 --release osp16-2 --dlrn-url http://osp-trunk.hosted.upshift.rdu2.redhat.com
     python -m tripleo_get_hash --help
```

## Quick start

```
python setup.py install
```
The tripleo-get-hash utility uses a yaml configuration file named 'config.yaml'.
If you install this utility using setup.py as above, the configuration file
is placed in /etc:
```
     /etc/tripleo_get_hash/config.yaml
```
Alternatively if you are running from a checked out version of the repo and
invoking as a module (see examples above) the config.yaml in the repo checkout
is used instead.

After installation you can invoke tripleo-get-hash in /usr/local/bin/:
```
     tripleo-get-hash --help
```

By default this queries the delorean server at "https://trunk.rdoproject.org",
with this URL specified in config.yaml. To use a different delorean server you
can either update config.yaml or use the --dlrn-url parameter to the cli. If
instead you are instantiating TripleOHashInfo objects in code, you can create
the objects passing an existing 'config' dictionary. Note this has to contain
all of constants.CONFIG_KEYS to avoid explosions.


[1] https://docs.openstack.org/tripleo-docs/latest/ci/stages-overview.html#rdo-dlrn-promotion-criteria
