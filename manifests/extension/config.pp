# Configure a PHP extension package
#
# === Parameters
#
# [*ensure*]
#   The ensure of the package to install
#   Could be "latest", "installed" or a pinned version
#
# [*provider*]
#   The provider used to install the package
#   Could be "pecl", "apt", "dpkg" or any other OS package provider
#   If set to "none", no package will be installed
#
# [*so_name*]
#   The DSO name of the package (e.g. opcache for zendopcache)
#
# [*php_api_version*]
#   This parameter is used to build the full path to the extension
#   directory for zend_extension in PHP < 5.5 (e.g. 20100525)
#
# [*header_packages*]
#   System packages dependencies to install for extensions (e.g. for
#   memcached libmemcached-dev on Debian)
#
# [*compiler_packages*]
#   System packages dependencies to install for compiling extensions
#   (e.g. build-essential on Debian)
#
# [*zend*]
#  Boolean parameter, whether to load extension as zend_extension.
#  Defaults to false.
#
# [*settings*]
#   Nested hash of global config parameters for php.ini
#
# [*settings_prefix*]
#   Boolean/String parameter, whether to prefix all setting keys with
#   the extension name or specified name. Defaults to false.
#
# [*sapi*]
#   String parameter, whether to specify ALL sapi or a specific sapi.
#   Defaults to ALL.
#
define php::extension::config (
  String                   $ensure          = 'installed',
  Optional[Php::Provider]  $provider        = undef,
  Optional[String]         $so_name         = downcase($name),
  Optional[String]         $php_api_version = undef,
  Boolean                  $zend            = false,
  Hash                     $settings        = {},
  Variant[Boolean, String] $settings_prefix = false,
  Php::Sapi                $sapi            = 'ALL',
) {

  if ! defined(Class['php']) {
    warning('php::extension::config is private')
  }

  if $zend == true {
    $extension_key = 'zend_extension'
    $module_path = $php_api_version? {
      undef   => undef,
      default => "/usr/lib/php5/${php_api_version}/",
    }
  } else {
    $extension_key = 'extension'
    $module_path = undef
  }

  if $::operatingsystem == 'Ubuntu' and $zend != true and $name == 'mysql' {
    # Do not manage the .ini file if it's mysql. PHP 7.0+ do not have mysql.so
    if versioncmp($php::globals::php_version, '7.0') >= 0 {
      exec { 'Remove_php_mysql_ini':
        command => "phpdismod mysql; rm -f /etc/php/${php::globals::php_version}/mods-available/mysql.ini",
        onlyif  => "test -f /etc/php/${php::globals::php_version}/mods-available/mysql.ini",
      }
      if $::php::fpm {
        Package[$::php::fpm::package] ~> Exec['Remove_php_mysql_ini']
      }
    }
  } elsif $::operatingsystem == 'Ubuntu' and $zend != true and $name == 'mcrypt' {
    # Do not manage the .ini file if it's mcrypt. PHP 7.2 and higher does not have mcrypt
    if versioncmp($php::globals::php_version, '7.2') >= 0 {
      exec { 'Remove_php_mcrypt_ini':
        command => "phpdismod mcrypt; rm -f /etc/php/${php::globals::php_version}/mods-available/mcrypt.ini",
        onlyif  => "test -f /etc/php/${php::globals::php_version}/mods-available/mcrypt.ini",
      }
      if $::php::fpm {
        Package[$::php::fpm::package] ~> Exec['Remove_php_mcrypt_ini']
      }
    }
  } else {

    $ini_name = downcase($so_name)

    # Ensure "<extension>." prefix is present in setting keys if requested
    $full_settings = $settings_prefix? {
      true   => ensure_prefix($settings, "${so_name}."),
      false  => $settings,
      String => ensure_prefix($settings, "${settings_prefix}."),
    }

    $final_settings = deep_merge(
      {"${extension_key}" => "${module_path}${so_name}.so"},
      $full_settings
    )

    $config_root_ini = pick_default($::php::config_root_ini, $::php::params::config_root_ini)
    ::php::config { $title:
      file   => "${config_root_ini}/${ini_name}.ini",
      config => $final_settings,
    }

    # Ubuntu/Debian systems use the mods-available folder. We need to enable
    # settings files ourselves with php5enmod command.
    $ext_tool_enable   = pick_default($::php::ext_tool_enable, $::php::params::ext_tool_enable)
    $ext_tool_query    = pick_default($::php::ext_tool_query, $::php::params::ext_tool_query)
    $ext_tool_enabled  = pick_default($::php::ext_tool_enabled, $::php::params::ext_tool_enabled)

    if $::osfamily == 'Debian' and $ext_tool_enabled {
      $cmd = "${ext_tool_enable} -s ${sapi} ${so_name}"

      $_sapi = $sapi? {
        'ALL' => 'cli',
        default => $sapi,
      }
      exec { $cmd:
        onlyif  => "${ext_tool_query} -s ${_sapi} -m ${so_name} | /bin/grep 'No module matches ${so_name}'",
        require => ::Php::Config[$title],
      }

      if $::php::fpm {
        Package[$::php::fpm::package] ~> Exec[$cmd]
      }
    }
  }
}
