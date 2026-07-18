<?php
/**
 * phpMyAdmin Configuration - SysAdminHCP Integration
 * Uses signon auth mode for SSO from SysAdminHCP, with cookie fallback
 */

declare(strict_types=1);

/**
 * Blowfish secret for cookie encryption.
 * Replaced with a fresh random value at install time (see install-*.sh) -
 * this placeholder should never end up live on a real server.
 */
$cfg['blowfish_secret'] = '__PMA_BLOWFISH_SECRET__';

/**
 * Servers configuration
 */
$i = 0;

/**
 * First server - signon mode for SysAdminHCP SSO
 */
$i++;
$cfg['Servers'][$i]['auth_type'] = 'signon';
$cfg['Servers'][$i]['host'] = 'localhost';
$cfg['Servers'][$i]['port'] = 3306;
$cfg['Servers'][$i]['compress'] = false;
$cfg['Servers'][$i]['AllowNoPassword'] = true;
$cfg['Servers'][$i]['SignonSession'] = 'phpmyadmin_signon';
$cfg['Servers'][$i]['SignonURL'] = '/pma-signon/signon.php';
$cfg['Servers'][$i]['LogoutURL'] = '/display';

/**
 * Second server - Cookie mode for manual login
 */
$i++;
$cfg['Servers'][$i]['auth_type'] = 'cookie';
$cfg['Servers'][$i]['host'] = 'localhost';
$cfg['Servers'][$i]['port'] = 3306;
$cfg['Servers'][$i]['compress'] = false;
$cfg['Servers'][$i]['AllowNoPassword'] = true;

/**
 * Directories for saving/loading files from server
 */
$cfg['UploadDir'] = '/var/lib/phpMyAdmin/upload';
$cfg['SaveDir'] = '/var/lib/phpMyAdmin/save';

/**
 * Session configuration for signon mode
 * Must match the session save path used by the signon script and PHP-FPM
 */
ini_set('session.save_path', '/var/lib/php/session');
ini_set('session.save_handler', 'files');
