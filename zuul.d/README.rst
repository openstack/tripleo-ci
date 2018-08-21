Override config
===============

featureset override
-------------------

Take advantage of zuul job config to override featureset settings like
tempest tests that should run. The following settings from the featureset
config can be overriden:

 - `run_tempest`: To run tempest or not (true|false).
 - `tempest_whitelist`: List of tests you want to be executed.
 - `test_black_regex`: Set of tempest tests to skip.

Example::

    - job:
        name: tripleo-ci-centos-7-scenario001-multinode-oooq-container
        parent: tripleo-ci-multinode
        ...
        vars:
        featureset_override:
          run_tempest: true
          tempest_whitelist:
            - 'tempest.scenario.test_volume_boot_pattern.TestVolumeBootPattern.test_volume_boot_pattern'
