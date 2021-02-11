Override config
===============

featureset override
-------------------

Take advantage of zuul job config to override featureset settings like
tempest tests that should run. The following settings from the featureset
config can be overriden:

 - `run_tempest`: To run tempest or not (true|false).
 - `tempest_whitelist`: List of tests you want to be executed.
 - `test_exclude_regex`: Set of tempest tests to skip.
 - `tempest_format`: Installing tempest from venv, packages or containers
 - `tempest_extra_config`: A dict values in order to override the tempest.conf
 - `tempest_plugins`: List of tempest plugins needs to be installed
 - `standalone_environment_files`: List of environment files to be overriden
   by the featureset configuration on standalone deployment. The environment
   file should exist in tripleo-heat-templates repo.
 - `test_white_regex`: Regex to be used by tempest
 - `tempest_workers`: Numbers of parallel workers to run

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
            tempest_exclude_regex: 'tempest.api.network|tempest.api.compute'
            tempest_format: 'containers'
            tempest_extra_config: {'telemetry.alarm_granularity': '60'}
            tempest_workers: 1
            tempest_plugins:
              - 'python-keystone-tests-tempest'
              - 'python-cinder-tests-tempest'
            standalone_environment_files:
              - 'environments/low-memory-usage.yaml'
              - 'ci/environments/scenario003-standalone.yaml'
