Install and configure a tripleo testenv worker

Carves up this host into a number of test environments and registers each one with gearman.

Configuration
-------------

      gearman-worker:
        host: 127.0.0.1 # gearman broker host
        port:
        mem-per-env: 16   # Indicates each testenv should have 16G of Mem
        cpu-per-env: 4    # Indicates each testenv should have 4 cpu cores
        disk-per-env: 80  # Indicates each testenv should have 80G of disk space
        auth_user: admin
        auth_tenant: admin
        auth_url: http://127.0.0.1:5000
        auth_passwd: password
      neutron:
        ovs:
          physical_bridge:  # A bridge name for the public_interface and seed interfaces
          public_interface: # The interface that should be moved onto physical_bridge
                            # in order to communicate with seed VMs
