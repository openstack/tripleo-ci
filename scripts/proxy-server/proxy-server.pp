Exec { path => [ "/bin/", "/sbin/" ] }

vcsrepo {"/opt/stack/tripleo-ci":
    source => "https://opendev.org/openstack/tripleo-ci",
    provider => git,
    ensure => latest,
}

cron {"refresh-server":
    command => "timeout 20m puppet apply /opt/stack/tripleo-ci/scripts/proxy-server/proxy-server.pp",
    minute  => "*/30"
}

package{"squid": } ->
file {"/etc/squid/squid.conf":
    source => "/opt/stack/tripleo-ci/scripts/proxy-server/squid.conf",
} ~>
service {"squid":
    ensure => "running",
    enable => true,
}
