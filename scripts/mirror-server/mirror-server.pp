Exec { path => [ "/bin/", "/sbin/" ] }

package{"wget": }
package{"python34": }

# The git repositories are created in a unconfined context
# TODO: fix this
exec{"setenforce  0":}

vcsrepo {"/opt/stack/tripleo-ci":
    source => "https://git.openstack.org/openstack-infra/tripleo-ci",
    provider => git,
    ensure => latest,
}

file { "/etc/sysconfig/network-scripts/ifcfg-eth1":
  ensure    => "present",
  content   => "DEVICE=eth1\nBOOTPROTO=dhcp\nONBOOT=yes\nPERSISTENT_DHCLIENT=yes\nPEERDNS=no\nNM_CONTROLLED=no",
} ~> exec{"ifrestart":
  command => "ifdown eth1 ; ifup eth1",
}

class { "apache":
} ->
file {"/var/www/cgi-bin/upload.cgi":
    ensure => "link",
    target => "/opt/stack/tripleo-ci/scripts/mirror-server/upload.cgi",
} ->
file {"/var/www/html/builds":
    ensure => "directory",
    owner  => "apache",
}
file { '/var/www/html/builds-master':
    ensure => 'link',
    target => '/var/www/html/builds',
}
file {"/var/www/html/builds-ocata":
    ensure => "directory",
    owner  => "apache",
}
file {"/var/www/html/builds-newton":
    ensure => "directory",
    owner  => "apache",
}
file {"/var/www/html/builds-mitaka":
    ensure => "directory",
    owner  => "apache",
}

cron {"refresh-server":
    command => "timeout 20m puppet apply /opt/stack/tripleo-ci/scripts/mirror-server/mirror-server.pp",
    minute  => "*/30"
}

cron {"promote-master":
    command => "timeout 10m /opt/stack/tripleo-ci/scripts/mirror-server/promote.sh master current-tripleo tripleo-dlrn-promote periodic-tripleo-ci-centos-7-ovb-ha periodic-tripleo-ci-centos-7-ovb-nonha &>/var/log/last_master_promotion.log",
    minute  => "40"
}

cron {"promote-ocata":
    command => "timeout 10m /opt/stack/tripleo-ci/scripts/mirror-server/promote.sh ocata current-tripleo-ocata tripleo-dlrn-promote-ocata periodic-tripleo-ci-centos-7-ovb-ha-ocata &>/var/log/last_ocata_promotion.log",
    minute  => "40"
}

cron {"promote-newton":
    command => "timeout 10m /opt/stack/tripleo-ci/scripts/mirror-server/promote.sh newton current-tripleo-newton tripleo-dlrn-promote-newton periodic-tripleo-ci-centos-7-ovb-ha-newton &>/var/log/last_newton_promotion.log",
    minute  => "40"
}

cron {"promote-mitaka":
    command => "timeout 10m /opt/stack/tripleo-ci/scripts/mirror-server/promote.sh mitaka current-tripleo-mitaka tripleo-dlrn-promote-mitaka periodic-tripleo-ci-centos-7-ovb-ha-mitaka &>/var/log/last_mitaka_promotion.log",
    minute  => "40"
}
