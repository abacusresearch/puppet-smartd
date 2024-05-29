# == Class: smartd
#
# Manages the smartmontools package including the smartd daemon
#
#
# === Parameters
#
# All parameters are optional.
#
# [*ensure*]
#  `String`
#
#   Standard Puppet ensure semantics (and supports `purged` state if your
#   package provider does). Valid values are:
#   `present`,`latest`,`absent`,`purged`
#
#   defaults to: `present`
#
# [*package_name*]
#   `String`
#
#   Name of the smartmontools package.
#
#   defaults to: `smartmontools`
#
# [*service_name*]
#  `String`
#
#   Name of the smartmontools monitoring daemon.
#
#   defaults to: `smartd`
#
# [*service_ensure*]
#  `String`
#
#   State of the smartmontools monitoring daemon. Valid values are:
#   `running`,`stopped`
#
#   defaults to: `running`
#
# [*manage_service*]
#  `Bool`
#
#   State whether or not this puppet module should manage the service.
#   This parameter is disregarded when $ensure = absent|purge.
#
#   defaults to: `true`
#
# [*config_file*]
#   `String`
#
#   Path to the configuration file for the monitoring daemon.
#
#   defaults to: (OS-specific)
#
# [*devicescan*]
#   `Bool`
#
#   Sets the `DEVICESCAN` directive in the smart daemon config file.  Tells the
#   smart daemon to automatically detect all of the SMART-capable drives in the
#   system.
#
#   defaults to: `true`
#
# [*devicescan_options*]
#   `String`
#
#   Passes options to the `DEVICESCAN` directive.  `devicescan` must equal true
#   for this to have any effect.
#
#   defaults to: `undef`
#
# [*devices*]
#   `Array` of `Hash`
#
#   Explicit list of raw block devices to check.  Eg.
#    [{ device => '/dev/sda', options => '-I 194' }]
#
#   defaults to: `[]`
#
# [*mail_to*]
#   `String`
#
#   Smart daemon notifcation email address.
#
#   defaults to: `root`
#
# [*warning_schedule*]
#   `String`
#
#   Smart daemon problem mail notification frequency. Valid values are:
#   `daily`,`once`,`diminishing`, `exec`
#
#   Note that if the value `exec` is used, then the parameter `exec_script`
#   *must* be specified.
#
#   defaults to: `daily`
#
# [*exec_script*]
#   `String`
#
#   Script that should be executed if warning_schedule is set to `exec`.
#
#   defaults to: `undef`
#
# === Authors
#
# MIT Computer Science & Artificial Intelligence Laboratory
# Joshua Hoblitt <jhoblitt@cpan.org>
#
# === Copyright
#
# Copyright 2012 Massachusetts Institute of Technology
# Copyright (C) 2013 Joshua Hoblitt
#
class smartd (
  Enum['present','latest','absent','purged'] $ensure          = 'present',
  String $package_name                                        = $smartd::params::package_name,
  String $service_name                                        = $smartd::params::service_name,
  Enum['running','stopped'] $service_ensure                   = $smartd::params::service_ensure,
  Boolean $manage_service                                     = $smartd::params::manage_service,
  Stdlib::Absolutepath $config_file                           = $smartd::params::config_file,
  Boolean $devicescan                                         = $smartd::params::devicescan,
  Optional[String] $devicescan_options                        = $smartd::params::devicescan_options,
  Array $devices                                              = $smartd::params::devices,
  String $mail_to                                             = $smartd::params::mail_to,
  Enum['daily','once','diminishing','exec'] $warning_schedule = $smartd::params::warning_schedule,
  Variant[Stdlib::Absolutepath,Boolean[false]] $exec_script   = $smartd::params::exec_script,
  Boolean $enable_default                                     = $smartd::params::enable_default,
  Optional[String] $default_options                           = $smartd::params::default_options,
) inherits smartd::params {
  if $warning_schedule == 'exec' {
    if $exec_script == false {
      fail('$exec_script must be set when $warning_schedule is set to exec.')
    }
    $real_warning_schedule = "${warning_schedule} ${exec_script}"
  }
  else {
    if $exec_script != false {
      fail('$exec_script should not be used when $warning_schedule is not set to exec.')
    }
    $real_warning_schedule = $warning_schedule
  }

  case $ensure {
    'present', 'latest': {
      $pkg_ensure  = $ensure
      $svc_ensure  = $service_ensure
      $svc_enable  = $service_ensure ? { 'running' => true, 'stopped' => false }
      $file_ensure = 'present'
      $srv_manage  = $manage_service
    }
    'absent', 'purged': {
      $pkg_ensure  = $ensure
      $svc_ensure  = 'stopped'
      $svc_enable  = false
      $file_ensure = 'absent'
      $srv_manage  = false
    }
    default: {
      fail("unsupported value of \$ensure: ${ensure}")
    }
  }

  package { $package_name:
    ensure => $pkg_ensure,
  }

  if $srv_manage {
    service { $service_name:
      ensure     => $svc_ensure,
      enable     => $svc_enable,
      hasrestart => true,
      hasstatus  => true,
      subscribe  => File[$config_file],
    }

    Package[$package_name] -> Service[$service_name]
  }

  file { $config_file:
    ensure  => $file_ensure,
    owner   => 'root',
    group   => $::gid,
    mode    => '0644',
    content => template('smartd/smartd.conf'),
    require => Package[$package_name],
  }

  # Special sauce for Debian where it's not enough for the rc script
  # to be enabled, it also needs its own extra special config file.
  if $::osfamily == 'Debian' {
    $debian_augeas_changes = $svc_enable ? {
      false   => 'remove start_smartd',
      default => 'set start_smartd "yes"',
    }

    augeas { 'shell_config_start_smartd':
      lens    => 'Shellvars.lns',
      incl    => '/etc/default/smartmontools',
      changes => $debian_augeas_changes,
      require => Package[$package_name],
    }

    if $srv_manage {
      Augeas['shell_config_start_smartd'] {
        before => Service[$service_name]
      }
    }
  }
}
