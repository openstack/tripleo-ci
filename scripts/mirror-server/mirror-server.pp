Exec { path => [ "/bin/", "/sbin/" ] }

package{"wget": }
package{"python34": }

# The git repositories are created in a unconfined context
# TODO: fix this
exec{"setenforce  0":}

vcsrepo {"/opt/stack/tripleo-ci":
    source => "https://opendev.org/openstack/tripleo-ci",
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
file {"/var/www/html/builds-pike":
    ensure => "directory",
    owner  => "apache",
}
file {"/var/www/html/builds-ocata":
    ensure => "directory",
    owner  => "apache",
}
file {"/var/www/html/builds-newton":
    ensure => "directory",
    owner  => "apache",
}
cron {"refresh-server":
    command => "timeout 20m puppet apply /opt/stack/tripleo-ci/scripts/mirror-server/mirror-server.pp",
    minute  => "*/30"
}
cron {"mirror-images-master":
    command => "timeout 60m /opt/stack/tripleo-ci/scripts/mirror-server/mirror-images.sh master | tee /var/log/images_update-master.log",
    hour  => "2",
    minute  => "0"
}
cron {"mirror-images-queens":
    command => "timeout 60m /opt/stack/tripleo-ci/scripts/mirror-server/mirror-images.sh queens | tee /var/log/images_update-queens.log",
    hour  => "2",
    minute  => "0"
}
cron {"mirror-images-pike":
    command => "timeout 60m /opt/stack/tripleo-ci/scripts/mirror-server/mirror-images.sh pike | tee /var/log/images_update-pike.log",
    hour  => "2",
    minute  => "0"
}
cron {"mirror-images-ocata":
    command => "timeout 60m /opt/stack/tripleo-ci/scripts/mirror-server/mirror-images.sh ocata | tee /var/log/images_update-ocata.log",
    hour  => "2",
    minute  => "0"
}
cron {"mirror-images-newton":
    command => "timeout 60m /opt/stack/tripleo-ci/scripts/mirror-server/mirror-images.sh newton | tee /var/log/images_update-newton.log",
    hour  => "2",
    minute  => "0"
}
