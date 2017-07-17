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
  $ldap_port              = hiera('llc_ldap_port'),
  $ldaps_port             = hiera('llc_ldaps_port'),
  $opendj_admin_port      = hiera('llc_opendj_admin_port'),
  $opendj_repl_port       = hiera('llc_opendj_repl_port'),
  $opendj_jmx_port        = hiera('llc_opendj_jmx_port'),
  $opendj_admin_user      = hiera('llc_opendj_admin_user'),
  $opendj_admin_password  = hiera('llc_opendj_admin_password'),
  $opendj_base_dn         = hiera('llc_opendj_base_dn'),
  $opendj_base_dir        = hiera('llc_opendj_base_dir'),
  $opendj_home            = hiera('llc_opendj_home'),
  $opendj_user            = hiera('llc_opendj_user'),
  $opendj_group           = hiera('llc_opendj_group'),
  $opendj_host            = hiera('llc_opendj_host'),
  $opendj_tmp             = hiera('llc_opendj_tmpdir'),
  $opendj_master          = hiera('llc_opendj_master'),
  $opendj_url             = hiera('llc_opendj_url'),
  $ldap_base_dn           = hiera('llc_ldap_base_dn'),
  $ldap_auth_org01        = hiera('llc_ldap_auth_org01'),
  $ldap_auth_org02        = hiera('llc_ldap_auth_org02'),
  $ldap_roles_dn          = hiera('llc_ldap_roles_dn'),
  $ldap_group_clients     = hiera('llc_ldap_group_clients'),
  $ldap_group_laadmins    = hiera('llc_ldap_group_laadmins'),
  $ldap_group_lausers     = hiera('llc_ldap_group_lausers'),
  $ldap_group_lradmins    = hiera('llc_ldap_group_lradmins'),
  $ldap_group_lrusers     = hiera('llc_ldap_group_lrusers'),
  $ldap_people_dn         = hiera('llc_ldap_people_dn'),
  $opendj_ldap_content    = hiera('llc_opendj_ldap_content')
) {
  $common_opts   = "-h localhost -D '${opendj::opendj_admin_user}' -w ${opendj::opendj_admin_password}"
  $ldapsearch    = "${opendj::opendj_home}/bin/ldapsearch ${common_opts} -p ${opendj::ldap_port}"
  $ldapmodify    = "${opendj::opendj_home}/bin/ldapmodify ${common_opts} -p ${opendj::ldap_port}"
  $dsconfig      = "${opendj::opendj_home}/bin/dsconfig \
    --noPropertiesFile --no-prompt --port '${opendj_admin_port}' --trustAll  --bindDN '${opendj_admin_user}' \
    --bindPassword '${opendj_admin_password}'"
  $dsreplication = "${opendj::opendj_home}/bin/dsreplication --adminUID admin --adminPassword ${opendj_admin_password} -X -n"
# props_file Contains passwords, thus (temporarily) stored in /dev/shm
  $props_file    = '/dev/shm/opendj.properties'
  $opendj_dirs = [ "${opendj_home}","${opendj_home}/locks","${opendj_home}/logs"]

  if ! defined(Package['java-1.8.0-openjdk']) {
    package { 'java-1.8.0-openjdk':
        ensure => installed,
    }
  }

  exec{'retrieve_opendj_zip':
    command => "${opendj_url}",
    creates => "${opendj_base_dir}/opendj.zip",
    notify => Exec["unzip_opendj"],
  }

  exec { 'unzip_opendj':
    require     => Exec["retrieve_opendj_zip"],
    command     => "/usr/bin/unzip ${opendj_base_dir}/opendj.zip -d ${opendj_base_dir}/",
    user        => 'root',
    creates     => "${opendj_home}/setup",
    refreshonly => true,
  }
  
  group { $opendj_group:
    ensure => 'present',
  }
  ->
  user { $opendj_user:
    ensure     => 'present',
    groups     => $opendj_group,
    comment    => 'OpenDJ LDAP daemon',
    home       => $opendj::opendj_home,
    managehome => true,
  }
  ->
  file { $opendj_dirs:
    ensure  => 'directory',
    owner   => $opendj_user,
    group   => $opendj_group,
    recurse => true,
  }
  ->
  file { $props_file:
    ensure  => file,
    content => template("${module_name}/setup.erb"),
    owner   => $opendj_user,
    group   => $opendj_group,
    mode    => '0600',
  }
  ->
  file { "${opendj_home}/opendj-ldap.ldif":
    ensure  => file,
    content => $opendj_ldap_content,
    owner   => $opendj_user,
    group   => $opendj_group,
    mode    => '0600',
    notify  => [Exec['configure opendj5'], Service['opendj']],
  }
  ->
  file_line { 'file_limits_soft':
    path    => '/etc/security/limits.conf',
    line    => "${opendj_user} soft nofile 65536",
  }
  ->
  file_line { 'file_limits_hard':
    path    => '/etc/security/limits.conf',
    line    => "${opendj_user} hard nofile 131072",
  }
  ->
  exec { 'configure opendj1':
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
  }
  ->
  exec { 'configure opendj2':
    command => "/opt/opendj/bin/start-ds",
    creates => "${opendj_home}/config_done",
  }
  ->
  exec { 'configure opendj3':
    command => "${dsconfig} \
    --hostname localhost create-backend \
    --backend-name userRoot --type=je \
    --set base-dn:'${ldap_base_dn}' --set enabled:true",
    creates => "${opendj_home}/config_done",
  }
  ->
  exec { 'configure opendj4':
    command => "${dsconfig} create-password-policy \
    --set default-password-storage-scheme:PBKDF2 \
    --set password-attribute:userpassword \
    --type password-policy --policy-name password-policy",
    creates => "${opendj_home}/config_done",
  }
  ->
  exec { 'configure opendj5':
    command => "/opt/opendj/bin/import-ldif --includeBranch '${ldap_base_dn}' \
    --backendID userRoot  --start 0 --port '${opendj_admin_port}' --trustAll \
    --bindPassword '${opendj_admin_password}' --hostname localhost \
    --ldifFile /opt/opendj/opendj-ldap.ldif",
    creates => "${opendj_home}/config_done",
  }
  ->
  exec { 'configure opendj6':
    command => '/opt/opendj/bin/stop-ds',
    creates => "${opendj_home}/config_done",
  }
  ->
  exec { 'what dependency cycle':
    command => "chown -R ${opendj_user}:${opendj_group} ${opendj_home}",
  }
  ->
  exec { 'create RC script':
    command => "${opendj_home}/bin/create-rc-script --userName ${opendj_user} \
        --outputFile /etc/init.d/opendj",
    creates => '/etc/init.d/opendj',
  }
  ->
  exec { '/bin/systemctl daemon-reload':
   unless  => '/bin/pgrep -fla /opt/opendj/config/config.ldif',
   notify  => Service['opendj'],
  }
  ->
  service { 'opendj':
    ensure    => running,
    enable    => true,
    hasstatus => false,
  }
  ->
  file { "${opendj_home}/config_done":
    ensure  => file,
    content => "config_done",
    owner   => $opendj_user,
    group   => $opendj_group,
  }
  ->
  exec { 'set single structural objectclass behavior':
    command => "${dsconfig} --advanced set-global-configuration-prop --set single-structural-objectclass-behavior:accept",
    unless  => "${dsconfig} --advanced get-global-configuration-prop | grep 'single-structural-objectclass-behavior' | grep accept",
  }
}
