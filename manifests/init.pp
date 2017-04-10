# == Class: opendj
#
# Module for deployment and configuration of ForgeRock OpenDJ.
#
# === Authors
#
# Eivind Mikkelsen <eivindm@conduct.no>
#
# === Copyright
#
# Copyright (c) 2013 Conduct AS
#

class opendj (
  $ldap_port       = hiera('ldap_port'),
  $ldaps_port      = undef,
  $admin_port      = hiera('opendj::admin_port'),
  $repl_port       = hiera('opendj::repl_port'),
  $jmx_port        = hiera('opendj::jmx_port'),
  $admin_user      = hiera('opendj::admin_user'),
  $admin_password  = hiera('admin_password'),
  $base_dn         = hiera('opendj::base_dn'),
  $base_dir        = hiera('opendj::base_dir'),
  $home            = hiera('opendj::home'),
  $user            = hiera('opendj::user'),
  $group           = hiera('opendj::group'),
  $host            = hiera('opendj::host'),
  $tmp             = hiera('opendj::tmpdir'),
  $master          = hiera('opendj::master'),
  $java_properties = hiera('opendj::java_properties'),
  $opendj_url      = hiera('opendj::opendj_url'),

) {
  $common_opts   = "-h localhost -D '${opendj::admin_user}' -w ${opendj::admin_password}"
  $ldapsearch    = "${opendj::home}/bin/ldapsearch ${common_opts} -p ${opendj::ldap_port}"
  $ldapmodify    = "${opendj::home}/bin/ldapmodify ${common_opts} -p ${opendj::ldap_port}"
  $dsconfig      = "${opendj::home}/bin/dsconfig   ${common_opts} -p ${opendj::admin_port} -X -n"
  $dsreplication = "${opendj::home}/bin/dsreplication --adminUID admin --adminPassword ${admin_password} -X -n"
# props_file Contains passwords, thus (temporarily) stored in /dev/shm
  $props_file    = '/dev/shm/opendj.properties'
  $base_dn_file  = "${tmp}/base_dn.ldif"

  exec{'retrieve_opendj_zip':
    command => "${opendj_url}",
    creates => "${base_dir}/opendj.zip",
    notify => Exec['unzip_opendj'],
  }

  file{'/opt/opendj.zip':
    mode => 0755,
    require => Exec["retrieve_opendj_zip"],
  }

  exec { 'unzip_opendj':
    command     => "/usr/bin/unzip ${base_dir}/opendj.zip -d ${base_dir}/",
    cwd         => '/home/vagrant/',
    user        => 'root',
    require     => File["${base_dir}/opendj.zip"],
    refreshonly => true,
  }

  if ! defined(Package['java-1.8.0-openjdk']) {
    package { 'java-1.8.0-openjdk':
        ensure => installed,
    }
  }

  group { $group:
    ensure => 'present',
  }

  user { $user:
    ensure     => 'present',
    groups     => $group,
    comment    => 'OpenDJ LDAP daemon',
    home       => $opendj::home,
    # If no login is specified the server cant start
    # shell      => '/sbin/nologin',
    managehome => true,
    require    => Group[$group],
  }

  file { $props_file:
    ensure  => file,
    content => template("${module_name}/setup.erb"),
    owner   => $user,
    group   => $group,
    mode    => '0600',
    require => [File[$home], File[$base_dn_file]],
  }

  file { $base_dn_file:
    ensure  => file,
    content => template("${module_name}/base_dn.ldif.erb"),
    owner   => $user,
    group   => $group,
    mode    => '0600',
    require => User[$user],
  }

  file { '/opt/opendj/esec-ldap.ldif':
    ensure  => file,
    content => template("${module_name}/base_dn.ldif.erb"),
    owner   => $user,
    group   => $group,
    mode    => '0600',
    require => User[$user],
  }

  file_line { 'file_limits_soft':
    path    => '/etc/security/limits.conf',
    line    => "${user} soft nofile 65536",
    require => User[$user],
  }

  file_line { 'file_limits_hard':
    path    => '/etc/security/limits.conf',
    line    => "${user} hard nofile 131072",
    require => User[$user],
  }

  exec { 'configure opendj2':
    require => File[$props_file],
    command => "${home}/setup --cli -v \
    --ldapPort '${ldap_port}' \
    --adminConnectorPort '${admin_port}' \
    --rootUserDN '${admin_user}' \
    --rootUserPassword '${admin_password}' \
    --no-prompt --noPropertiesFile \
    --doNotStart \
    --generateSelfSignedCertificate \
    --hostname esec-ldap \
    --acceptLicense \
    --enableStartTLS",
    creates => "${home}/config",
    user => "opendj",
  }

  file { $home:
    ensure  => directory,
    owner   => $user,
    group   => $group,
    recurse => true,
    require => [User[$user], Exec["unzip_opendj"]],
  }

  file { "${home}/locks":
    ensure  => directory,
    owner   => $user,
    group   => $group,
    recurse => true,
    require => [User[$user], Exec["unzip_opendj"]],
  }

  file { "${home}/logs":
    ensure  => directory,
    owner   => $user,
    group   => $group,
    recurse => true,
    require => [User[$user], Exec["unzip_opendj"]],
  }

  exec { 'create RC script':
    require => Exec["unzip_opendj"],
    command => "${home}/bin/create-rc-script --userName ${user} \
        --outputFile /etc/init.d/opendj",
    creates => '/etc/init.d/opendj',
    #notify  => Service['opendj'],
  }

  exec { 'create SD script':
    require => Exec["unzip_opendj"],
    command => "/usr/bin/systemctl -l enable opendj",
    #notify  => Service['opendj'],
  }

  exec { 'set single structural objectclass behavior':
    command => "${dsconfig} --advanced set-global-configuration-prop --set single-structural-objectclass-behavior:accept",
    unless  => "${dsconfig} --advanced get-global-configuration-prop | grep 'single-structural-objectclass-behavior' | grep accept",
    require => Service['opendj'],
  }

  if !empty($java_properties) {
    validate_hash($java_properties)
    create_resources('opendj::java_property', $java_properties)

  exec { 'apply java properties':
    command => "/bin/su ${user} -s /bin/bash -c \"${home}/bin/dsjavaproperties\"",
    notify  => Service['opendj'],
    }
  }

  exec { 'wait_for_file_lock' :
    command => "sleep 10",
    path => "/usr/bin:/bin",
  }

  service { 'opendj':
    ensure     => running,
    require    => Exec['create RC script'],
    enable     => true,
    hasstatus  => false,
  }

}
