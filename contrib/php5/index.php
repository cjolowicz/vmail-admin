<?php
$main_domain = 'example.com';
$minimum_password_length = 6;
$minimum_password_nonalpha = 1;

/// Return the domain.
function get_domain() {
  if (!isset($_SERVER['SERVER_NAME'])) {
    throw new Exception('SERVER_NAME is not set');
  }

  $SERVER_NAME = $_SERVER['SERVER_NAME'];

  // The domain consists of the top two labels of SERVER_NAME.
  $domain = explode('.', $SERVER_NAME);
  $domain = array_slice($domain, -2);
  $domain = implode('.', $domain);

  return $domain;
}

/// Return the domain DN.
function get_domain_dn($domain) {
  $func = function($value) { return 'dc=' . $value; }

  $domain = explode('.', $domain);
  $domain = array_map($func, $domain);
  $domain = implode(',', $domain);

  return $domain;
}

/// Return the username.
function get_username() {
  if (!isset($_SERVER['REMOTE_USER'])) {
    throw new Exception('you must be logged in to change the password');
  }

  return $_SERVER['REMOTE_USER'];
}

/// Return the new password.
function get_password() {
  if (!isset($_POST['password'])) {
    return '';
  }

  $password = $_POST['password'];
  $password2 = $_POST['password2'];

  if ($password != $password2) {
    throw new Exception('passwords do not match');
  }

  return $password;
}

/// Return the old password.
function get_old_password() {
  if (!isset($_POST['oldpassword'])) {
    return '';
  }

  return $_POST['oldpassword'];
}

/// Hash using SHA1 with a salt.
function ssha($password) {
  $salt = sha1(rand());
  $salt = substr($salt, 0, 4);
  $hash = base64_encode(sha1($password . $salt, TRUE) . $salt);

  return $hash;
}

/// Check if a password is strong enough.
function check_password_strength($password) {
  if (strlen($password) < $minimum_password_length) {
    throw new Exception(
      "password must have at least $minimum_password_length characters");
  }

  $password_nonalpha = preg_replace($password, '[[:alpha:]]+', '');

  if ($password_nonalpha === FALSE) {
    $error = pcre_last_error();
    throw new Exception("pcre error ($error)");
  }

  if (strlen($password_nonalpha) < $minimum_password_nonalpha) {
    throw new Exception(
      "password must contain at least $minimum_password_nonalpha " .
      "non-alphabetical characters");
  }
}

/// Change the password of the specified user.
function change_password($username, $domain, $oldpassword, $password) {
  check_password_strength($password);

  $dn = "uid=" . $username . ",ou=people,"
      . get_domain_dn($domain) . ',ou=vmail,'
      . get_domain_dn($main_domain);

  $hash = '{SSHA}' . ssha($password);
  $connection = ldap_connect("127.0.0.1");

  if (!$connection) {
    throw new Exception('ldap_connect: ' . ldap_error($connection));
  }

  if (!ldap_set_option($connection, LDAP_OPT_PROTOCOL_VERSION, 3)) {
    throw new Exception('ldap_set_option: ' . ldap_error($connection));
  }

  if (!ldap_bind($connection, $dn, $oldpassword)) {
    throw new Exception('ldap_bind: ' . ldap_error($connection));
  }

  if (!ldap_mod_replace($connection, $dn, array('userPassword' => $hash))) {
    throw new Exception('ldap_mod_replace: ' . ldap_error($connection));
  }

  if (!ldap_close($connection)) {
    throw new Exception('ldap_close: ' . ldap_error($connection));
  }
}

/// Main function.
function main(&$username, &$domain, &$error) {
  try {
    $username    = get_username();
    $domain      = get_domain();
    $password    = get_password();
    $oldpassword = get_old_password();

    if (empty($password)) {
      return FALSE;
    }

    change_password($username, $domain, $oldpassword, $password);

    return TRUE;
  }
  catch (Exception $e) {
    $error = $e->getMessage();
  }

  return FALSE;
}

// Go.
$done = main($username, $domain, $error);

?><!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN"
    "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
  <meta http-equiv="Content-Type" content="text/html; charset=UTF-8" />
  <title>Restricted area</title>
  <style type="text/css" media="all">
    #footer   { position: absolute; bottom: 1px; right: 1px; }
    .error    { color: red; font-weight: bold; }
    .success  { color: green; font-weight: bold; }
    img       { border: none; }
    h1        { text-align: center; }
    .username { font-family: monospace; }
  </style>
</head>
<body>
  <h1>Restricted area</h1><?php
if ($done) { ?>
  <p class="success">Your password has been changed.</p><?php
}
elseif (!empty($error)) { ?>
  <p class="error">Sorry, <?= htmlspecialchars($error) ?></p><?php
} ?>
  <form method="post" action="#" autocomplete="off">
    <fieldset>
      <h2>Change password</h2>
      <label for="oldpassword">Enter old password:</label><br />
      <input type="password" id="oldpassword" name="oldpassword" /><br />
      <label for="password">Enter new password:</label><br />
      <input type="password" id="password" name="password" /><br />
      <label for="password2">Repeat password:</label><br />
      <input type="password" id="password2" name="password2" /><br />
      <input type="submit" id="action" value="Submit" />
    </fieldset>
  </form>
  <ul class="menu">
    <li><a href="http://<?= $domain ?>/">Go to the Main Website</a></li>
  </ul>
  <p>You are logged in as <span class="username"><?= htmlspecialchars($username) ?></span>.</p>
</body>
</html>
