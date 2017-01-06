Exec { path => [ "/bin/", "/sbin/" ] }

vcsrepo {"/opt/stack/openstack-virtual-baremetal":
    source => "https://github.com/cybertron/openstack-virtual-baremetal.git",
    provider => git,
    ensure => latest,
}

vcsrepo {"/opt/stack/tripleo-ci":
    source => "https://git.openstack.org/openstack-infra/tripleo-ci",
    provider => git,
    ensure => latest,
}

cron {"refresh-server":
    command => "timeout 20m puppet apply /opt/stack/tripleo-ci/scripts/te-broker/te-broker.pp",
    minute  => "*/30"
}

service{"te_workers":
    ensure => "running",
    enable => true,
}
service{"geard":
    ensure => "running",
    enable => true,
}

