<?php
/**
 * SysAdminHCP phpMyAdmin Signon Script
 * 
 * Handles automatic login to phpMyAdmin from SysAdminHCP.
 * Receives an SSO token, validates it against a token file,
 * and creates a phpMyAdmin session with the appropriate credentials.
 * 
 * Usage: /pma-signon/signon.php?token=<sso_token>
 */

// Token directory (must match SysAdminHCP's token storage)
$tokenDir = '/var/lib/sysadminhcp/pma-tokens';

// Get token from query string
$token = $_GET['token'] ?? '';
if (empty($token)) {
    http_response_code(400);
    die('Missing SSO token. Please access phpMyAdmin through SysAdminHCP.');
}

// Validate token format (should be 64 hex chars)
if (!preg_match('/^[a-f0-9]{64}$/', $token)) {
    http_response_code(400);
    die('Invalid token format.');
}

// Check if token file exists
$tokenFile = $tokenDir . '/' . $token;
if (!file_exists($tokenFile)) {
    http_response_code(401);
    die('Invalid or expired SSO token. Please try again from SysAdminHCP.');
}

// Read token data
$tokenData = json_decode(file_get_contents($tokenFile), true);
if (!$tokenData) {
    // Remove invalid token file
    @unlink($tokenFile);
    http_response_code(401);
    die('Corrupted token data. Please try again from SysAdminHCP.');
}

// Check token expiry (60 seconds)
// createdAt is in milliseconds (JavaScript Date.now())
$createdAtMs = $tokenData['createdAt'] ?? 0;
$createdAtSec = intval($createdAtMs / 1000);
if (time() - $createdAtSec > 60) {
    @unlink($tokenFile);
    http_response_code(401);
    die('Token expired. Please try again from SysAdminHCP.');
}

// Consume the token (one-time use)
@unlink($tokenFile);

// Extract credentials
$mysqlUser = $tokenData['mysqlUser'] ?? '';
$mysqlPassword = $tokenData['mysqlPassword'] ?? '';
$mysqlHost = $tokenData['mysqlHost'] ?? 'localhost';
$mysqlPort = $tokenData['mysqlPort'] ?? 3306;

if (empty($mysqlUser)) {
    http_response_code(500);
    die('No MySQL user provided in token.');
}

// Start phpMyAdmin signon session
// Use the same session save path as PHP-FPM
ini_set('session.save_path', '/var/lib/php/session');
ini_set('session.save_handler', 'files');
session_name('phpmyadmin_signon');
session_start();

// Set phpMyAdmin session variables for signon auth
$_SESSION['PMA_single_signon_user'] = $mysqlUser;
$_SESSION['PMA_single_signon_password'] = $mysqlPassword;
$_SESSION['PMA_single_signon_host'] = $mysqlHost;
$_SESSION['PMA_single_signon_port'] = $mysqlPort;

// Debug: Log session data
error_log("PMA Signon: Session ID=" . session_id() . " User=$mysqlUser Host=$mysqlHost");

// Close session to save data
session_write_close();

// Redirect to phpMyAdmin — optionally open a specific database
$db = isset($_GET['db']) ? preg_replace('/[^a-zA-Z0-9_]/', '', $_GET['db']) : '';
$redirect = '/phpMyAdmin/index.php' . ($db ? '?db=' . $db : '');
header('Location: ' . $redirect);
exit;