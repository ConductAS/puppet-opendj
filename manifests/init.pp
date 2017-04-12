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
  $ldap_port              = hiera('LDAP_PORT'),
  $ldaps_port             = hiera('ldaps_port'),
  $opendj_admin_port      = hiera('opendj_admin_port'),
  $opendj_repl_port       = hiera('opendj_repl_port'),
  $opendj_jmx_port        = hiera('opendj_jmx_port'),
  $opendj_admin_user      = hiera('opendj_admin_user'),
  $opendj_admin_password  = hiera('opendj_admin_password'),
  $opendj_base_dn         = hiera('opendj_base_dn'),
  $opendj_base_dir        = hiera('opendj_base_dir'),
  $opendj_home            = hiera('opendj_home'),
  $opendj_user            = hiera('opendj_user'),
  $opendj_group           = hiera('opendj_group'),
  $opendj_host            = hiera('opendj_host'),
  $opendj_tmp             = hiera('opendj_tmpdir'),
  $opendj_master          = hiera('opendj_master'),
  $opendj_url             = hiera('opendj_url'),

) {
  $common_opts   = "-h localhost -D '${opendj::opendj_admin_user}' -w ${opendj::opendj_admin_password}"
  $ldapsearch    = "${opendj::opendj_home}/bin/ldapsearch ${common_opts} -p ${opendj::ldap_port}"
  $ldapmodify    = "${opendj::opendj_home}/bin/ldapmodify ${common_opts} -p ${opendj::ldap_port}"
  $dsconfig      = "${opendj::opendj_home}/bin/dsconfig   ${common_opts} -p ${opendj::opendj_admin_port} -X -n"
  $dsreplication = "${opendj::opendj_home}/bin/dsreplication --adminUID admin --adminPassword ${opendj_admin_password} -X -n"
# props_file Contains passwords, thus (temporarily) stored in /dev/shm
  $props_file    = '/dev/shm/opendj.properties'
  $base_dn_file  = "${opendj_tmp}/base_dn.ldif"

  exec{'retrieve_opendj_zip':
    command => "${opendj_url}",
    creates => "${opendj_base_dir}/opendj.zip",
    notify => Exec['unzip_opendj'],
  }

  file{'/opt/opendj.zip':
    mode => 0755,
    require => Exec["retrieve_opendj_zip"],
  }

  exec { 'unzip_opendj':
    command     => "/usr/bin/unzip ${opendj_base_dir}/opendj.zip -d ${opendj_base_dir}/",
    user        => 'root',
    require     => File["${opendj_base_dir}/opendj.zip"],
    refreshonly => true,
  }

  if ! defined(Package['java-1.8.0-openjdk']) {
    package { 'java-1.8.0-openjdk':
        ensure => installed,
    }
  }

  group { $opendj_group:
    ensure => 'present',
  }

  user { $opendj_user:
    ensure     => 'present',
    groups     => $opendj_group,
    comment    => 'OpenDJ LDAP daemon',
    home       => $opendj::opendj_home,
    managehome => true,
    require    => Group[$opendj_group],
  }

  file { $props_file:
    ensure  => file,
    content => template("${module_name}/setup.erb"),
    owner   => $user,
    group   => $group,
    mode    => '0600',
    require => [File[$opendj_home]],
  }

  file { '/opt/opendj/esec-ldap.ldif':
    ensure  => file,
    content => template("${module_name}/esec-ldap.ldif.erb"),
    owner   => $opendj_user,
    group   => $opendj_group,
    mode    => '0600',
    require => User[$opendj_user],
  }

  file_line { 'file_limits_soft':
    path    => '/etc/security/limits.conf',
    line    => "${opendj_user} soft nofile 65536",
    require => User[$opendj_user],
  }

  file_line { 'file_limits_hard':
    path    => '/etc/security/limits.conf',
    line    => "${opendj_user} hard nofile 131072",
    require => User[$opendj_user],
  }

  exec { 'configure opendj2':
    require => File[$props_file],
    command => "${opendj_home}/setup --cli -v \
    --ldapPort '${ldap_port}' \
    --adminConnectorPort '${opendj_admin_port}' \
    --rootUserDN '${opendj_admin_user}' \
    --rootUserPassword '${opendj_admin_password}' \
    --no-prompt --noPropertiesFile \
    --doNotStart \
    --generateSelfSignedCertificate \
    --hostname esec-ldap \
    --acceptLicense \
    --enableStartTLS",
    creates => "${opendj_home}/config",
    user => "${opendj_user}",
  }

  file { $opendj_home:
    ensure  => directory,
    owner   => $opendj_user,
    group   => $opendj_group,
    recurse => true,
    require => [User[$opendj_user], Exec["unzip_opendj"]],
  }

  file { "${opendj_home}/locks":
    ensure  => directory,
    owner   => $opendj_user,
    group   => $opendj_group,
    recurse => true,
    require => [User[$opendj_user], Exec["unzip_opendj"]],
  }

  file { "${opendj_home}/logs":
    ensure  => directory,
    owner   => $opendj_user,
    group   => $opendj_group,
    recurse => true,
    require => [User[$opendj_user], Exec["unzip_opendj"]],
  }

  exec { 'create RC script':
    require => Exec["unzip_opendj"],
    command => "${opendj_home}/bin/create-rc-script --userName ${opendj_user} \
        --outputFile /etc/init.d/opendj",
    creates => '/etc/init.d/opendj',
    notify  => Service['opendj'],
  }

  exec { 'create SD script':
    require => Exec["unzip_opendj"],
    command => "/usr/bin/systemctl -l enable opendj",
    notify  => Service['opendj'],
  }

  exec { 'set single structural objectclass behavior':
    command => "${dsconfig} --advanced set-global-configuration-prop --set single-structural-objectclass-behavior:accept",
    unless  => "${dsconfig} --advanced get-global-configuration-prop | grep 'single-structural-objectclass-behavior' | grep accept",
    require => Service['opendj'],
  }

  service { 'opendj':
    ensure     => running,
    require    => Exec['create RC script'],
    enable     => true,
    hasstatus  => false,
  }

}
