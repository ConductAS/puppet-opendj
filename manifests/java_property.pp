# This will set java properties to OpenDJ.
#
# The input format is a hash with the key as the 'title' and the 'value'
# parameter gets its value from the 'value' key in the hash.
#
# java_property {
#   'default.java-home':
#     value => '/etc/alternatives/jre';
#
#   'start-ds.java-args':
#     value => '-server -Xms2G -Xmx2G -XX:+UseConcMarkSweepGC -XX:NewSize=512M';
#
#   'overwrite-env-java-home':
#     value => 'true';
# }
#
define opendj::java_property($value) {
  file_line { "java_property:${title}":
    path    => "${opendj::home}/config/java.properties",
    line    => "${title}=${value}",
    match   => "^(${title}=).*$",
    require => Exec['configure opendj'],
    notify  => Exec['apply java properties'],
  }
}
