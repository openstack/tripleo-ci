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


cron {"refresh-server":
    command => "timeout 20m puppet apply /opt/stack/tripleo-ci/scripts/mirror-server/mirror-server.pp",
    minute  => "*/30"
}

cron {"centos-cloud-images":
    command => "cd /var/www/html && timeout 30m wget -m --no-parent --accept-regex qcow2.xz --progress=dot http://cloud.centos.org/centos/7/images/",
    minute  => "11"
}

cron {"promote":
    command => "timeout 10m /opt/stack/tripleo-ci/scripts/mirror-server/promote.sh current-tripleo periodic-tripleo-ci-centos-7-ovb-ha periodic-tripleo-ci-centos-7-ovb-nonha &>/var/log/last_promotion.log",
    minute  => "40"
}
