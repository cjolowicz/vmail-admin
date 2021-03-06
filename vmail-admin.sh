#!/bin/bash
#
# vmail-admin - Manage virtual mailboxes and aliases in a MySQL database.
#
# Copyright (C) 2012 Claudio Jolowicz <cj@dealloc.org>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2, or (at your option)
# any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111 USA.

set -e

package=vmail-admin
program=vmail-admin
VERSION=0.1
confdir=/etc
pkgconfdir=$confdir/$package
default_database_name=mail
default_database_host=127.0.0.1
default_database_user=mail
default_database_admin=mailadmin
minimum_password_length=6
minimum_password_nonalpha=1

##
# Print the version.
#
version () {
    echo "\
$program version $VERSION
Copyright (C) 2012 Claudio Jolowicz <cj@dealloc.org>

Manage virtual mailboxes and aliases in a MySQL database.

$program comes with ABSOLUTELY NO WARRANTY.  This is free software, and you
are welcome to redistribute it under certain conditions.  See the GNU
General Public Licence for details.
"
}

##
# Print the usage.
#
usage () {
    version
    echo "\
Usage: $program [options] create
       $program [options] create-database-admin [USER]
       $program [options] create-database-user  [USER]
       $program [options] create-database       [NAME]
       $program [options] drop
       $program [options] drop-database-admin   [USER]
       $program [options] drop-database-user    [USER]
       $program [options] drop-database         [NAME]
       $program [options] domains
       $program [options] users     [DOMAIN]
       $program [options] aliases   [DOMAIN]
       $program [options] list      [DOMAIN]
       $program [options] add       DOMAIN | USER
       $program [options] remove    DOMAIN | USER
       $program [options] password  USER
       $program [options] alias     ALIAS USER..
       $program [options] unalias   ALIAS [USER]

options:

    -h, --help                     display this message
    -V, --version                  print version number
    -v, --verbose                  be verbose
    -n, --dry-run                  print commands without executing them
    -f, --force                    override sanity checks
        --database-name      NAME  database name
        --database-host      HOST  database host
        --database-user      USER  database user
        --database-admin     USER  database admin
        --mysql-config       FILE  options file for mysql(1)
        --mysql-user-config  FILE  options file for mysql(1)
        --mysql-admin-config FILE  options file for mysql(1)
        --mysql-option       OPT   command-line option for mysql(1)
        --mysql-user-option  OPT   command-line option for mysql(1)
        --mysql-admin-option OPT   command-line option for mysql(1)
        --interactive              prompt for, and confirm, password
        --non-interactive          read password from stdin

The program reads $pkgconfdir/$program.conf if it exists. Each line in this file
may contain a long option without the leading hyphens. If the option takes
an argument, they must be separated by an \`=' without whitespace. Empty
lines and lines starting with a \`#' are ignored.
"
}

##
# Print an error message and exit.
#
error () {
    echo "$program: $*" >&2
    exit 1
}

##
# Print a notice.
#
notice () {
    echo "$program: $*" >&2
}

##
# Print an informational message.
#
verbose () {
    [ $verbose = no ] || echo "$program: $*" >&2
}

##
# Usage error: invalid option
#
bad_option () {
    echo "$program: unrecognized option \`$1'" >&2
    echo "Try \`$program --help' for more information." >&2
    exit 1
}

##
# Usage error: missing argument
#
missing_argument () {
    echo "$program: option \`$1' requires an argument" >&2
    echo "Try \`$program --help' for more information." >&2
    exit 1
}

##
# Usage error: invalid parameter
#
bad_parameter () {
    echo "$program: unrecognized parameter \`$1'" >&2
    echo "Try \`$program --help' for more information." >&2
    exit 1
}

##
# Usage error: missing parameter
#
missing_parameter () {
    echo "$program: missing required parameter: $1" >&2
    echo "Try \`$program --help' for more information." >&2
    exit 1
}

##
# Parse the configuration file.
#
parse_configuration_file () {
    printf 'configuration_options=()\n'
    if [ -f "$pkgconfdir/$program.conf" ] ; then
        sed '/^[ \t]*\(#\|$\)/d' "$pkgconfdir/$program.conf" |
        while read line ; do
            case $line in
                *'='*) printf 'configuration_options+=(--%q %q)\n' \
                           "${line%%=*}" \
                           "${line#*=}" ;;
                    *) printf 'configuration_options+=(--%q)\n' \
                           "${line}" ;;
            esac
        done
    fi
}

eval "$(parse_configuration_file)"
set -- "${configuration_options[@]}" "$@"

##
# Parse the command line.
#
dry_run=no
verbose=no
force=no
mysql_user_options=()
mysql_admin_options=()
mysql_root_options=()
database_name=$default_database_name
database_host=$default_database_host
database_user=$default_database_user
database_admin=$default_database_admin
interactive=yes
[ -t 1 ] || interactive=no
while [ $# -gt 0 ] ; do
    option=$1
    shift

    case $option in
        -h | --help) usage ; exit 0 ;;
        -V | --version) version ; exit 0 ;;
        -v | --verbose) verbose=yes ;;
        -n | --dry-run) dry_run=yes ;;
        -f | --force) force=yes ;;
        --interactive) interactive=yes ;;
        --non-interactive) interactive=no ;;

        --database-name)
            [ $# -gt 0 ] || missing_argument $option
            database_name="$1"
            shift
            mysql_user_options+=(--database="$database_name")
            mysql_admin_options+=(--database="$database_name")
            ;;

        --database-host)
            [ $# -gt 0 ] || missing_argument $option
            database_host="$1"
            shift
            mysql_user_options+=(--host="$database_host")
            mysql_admin_options+=(--host="$database_host")
            mysql_root_options+=(--host="$database_host")
            ;;

        --database-user)
            [ $# -gt 0 ] || missing_argument $option
            database_user="$1"
            shift
            mysql_user_options+=(--user="$database_user")
            ;;

        --database-admin)
            [ $# -gt 0 ] || missing_argument $option
            database_admin="$1"
            shift
            mysql_admin_options+=(--user="$database_admin")
            ;;

        --mysql-config)
            [ $# -gt 0 ] || missing_argument $option
            mysql_user_config="$1"
            mysql_admin_config="$1"
            shift
            ;;

        --mysql-user-config)
            [ $# -gt 0 ] || missing_argument $option
            mysql_user_config="$1"
            shift
            ;;

        --mysql-admin-config)
            [ $# -gt 0 ] || missing_argument $option
            mysql_admin_config="$1"
            shift
            ;;

        --mysql-option)
            [ $# -gt 0 ] || missing_argument $option
            mysql_user_options+=("$1")
            mysql_admin_options+=("$1")
            mysql_root_options+=("$1")
            shift
            ;;

        --mysql-user-option)
            [ $# -gt 0 ] || missing_argument $option
            mysql_user_options+=("$1")
            shift
            ;;

        --mysql-admin-option)
            [ $# -gt 0 ] || missing_argument $option
            mysql_admin_options+=("$1")
            shift
            ;;

        --) break ;;
        -*) bad_option $option ;;
        *) set -- "$option" "$@" ; break ;;
    esac
done

if [ $# -eq 0 ] ; then
    usage
    exit 0
fi

command="$1"
shift

if [ -n "$mysql_user_config" ] ; then
    if [ "${mysql_user_config::0}" != / ] ; then
        mysql_user_config=$pkgconfdir/"$mysql_user_config"
    fi
    mysql_user_options=(--defaults-file="$mysql_user_config" "${mysql_user_options[@]}")
fi

if [ -n "$mysql_admin_config" ] ; then
    if [ "${mysql_admin_config::0}" != / ] ; then
        mysql_admin_config=$pkgconfdir/"$mysql_admin_config"
    fi
    mysql_admin_options=(--defaults-file="$mysql_admin_config" "${mysql_admin_options[@]}")
fi

##
# Determine the hostname.
#
myhostname="$(hostname --fqdn)"

if [ -z "$myhostname" ] ; then
    if [ $force = no -a $dry_run = no ] ; then
        error "cannot determine hostname"
    fi
fi

##
# Execute a database query as user.
#
db_user_query () {
    if [ $dry_run = yes -o $verbose = yes ] ; then
        echo "*** $*" >&2
    fi

    mysql "${mysql_user_options[@]}" \
          --batch \
          --skip-column-names \
          --execute="$*"
}

##
# Execute a database query as admin.
#
db_admin_query () {
    if [ $dry_run = yes -o $verbose = yes ] ; then
        echo "*** $*" >&2
    fi

    if [ $dry_run = no ] ; then
        mysql "${mysql_admin_options[@]}" \
              --execute="$*"
    fi
}

##
# Execute a database query as root.
#
db_root_query () {
    if [ $dry_run = yes -o $verbose = yes ] ; then
        echo "*** $*" >&2
    fi

    if [ $dry_run = no ] ; then
        mysql "${mysql_root_options[@]}" \
              --user=root \
              --execute="$*"
    fi
}

##
# Send a welcome message to the user.
#
send_welcome_message () {
    [ $# -gt 0 ] || missing_parameter "user"

    user="$1"
    shift

    [ $# -eq 0 ] || bad_parameter "$1"

    if [ $dry_run = no ] ; then
        mail -s 'Welcome to your new mail account' "$user" <<EOF
Hi,

This is the mail system at host $myhostname.  I'm delighted to inform
you that your account has been created.  For further assistance,
please send mail to postmaster.

                   The mail system
EOF
    else
        echo "mail -s 'Welcome to your new mail account' \"$user\"" >&2
    fi
}

##
# Check if a password is strong enough.
#
check_password_strength () {
    password="$1"

    if [ "${#password}" -lt $minimum_password_length ] ; then
        error "password must have at least $minimum_password_length characters"
    fi

    password_nonalpha=$(echo -n "$password" | tr -d 'A-Za-z' | wc -c)

    if [ $password_nonalpha -lt $minimum_password_nonalpha ] ; then
        error "password must contain at least $minimum_password_nonalpha non-alphabetical characters"
    fi
}

##
# Create a database admin.
#
do_create_database_admin () {
    if [ $force = no -a $dry_run = no ] ; then
        error "create-admin is not secure. Use \`--force' to override."
    fi

    if [ $# -gt 0 ] ; then
        database_admin="$1"
        shift
    fi

    [ $# -eq 0 ] || bad_parameter "$1"

    if [ -z "$database_admin" ] ; then
        read -p "Admin ($default_database_admin): " database_admin
        echo
        : ${database_admin:=$default_database_admin}
    fi

    case $database_admin in
        *'@'*)
            database_host=${database_admin##*@}
            database_admin=${database_admin%@*}
            ;;
        *)
            database_host=$default_database_host
            ;;
    esac

    if [ $dry_run = yes ] ; then
        database_admin_password=xxxxxx
    elif [ $interactive = no ] ; then
        read database_admin_password

        check_password_strength "$database_admin_password"
    else
        read -p 'Enter new admin password: ' -s database_admin_password
        echo

        check_password_strength "$database_admin_password"

        read -p 'Repeat new admin password: ' -s database_admin_password_confirm
        echo

        if [ "$database_admin_password" != "$database_admin_password_confirm" ] ; then
            error "passwords do not match"
        fi
    fi

    if ! db_root_query "\
CREATE USER '$database_admin'@'$database_host' IDENTIFIED BY '$database_admin_password';"
    then
        error "cannot create database admin $database_admin"
    fi

    if ! db_root_query "\
GRANT ALL PRIVILEGES ON \`$database_name\`.* TO '$database_admin'@'$database_host';"
    then
        error "cannot grant privileges to database admin $database_admin"
    fi

    if ! db_root_query "FLUSH PRIVILEGES;" ; then
        error "cannot flush privileges"
    fi
}

##
# Create a database user.
#
do_create_database_user () {
    if [ $force = no -a $dry_run = no ] ; then
        error "create-user is not secure. Use \`--force' to override."
    fi

    if [ $# -gt 0 ] ; then
        database_user="$1"
        shift
    fi

    [ $# -eq 0 ] || bad_parameter "$1"

    if [ -z "$database_user" ] ; then
        read -p "User ($default_database_user): " database_user
        echo
        : ${database_user:=$default_database_user}
    fi

    case $database_user in
        *'@'*)
            database_host=${database_user##*@}
            database_user=${database_user%@*}
            ;;
        *)
            database_host=$default_database_host
            ;;
    esac

    if [ $dry_run = yes ] ; then
        database_user_password=xxxxxx
    elif [ $interactive = no ] ; then
        read database_user_password

        check_password_strength "$database_user_password"
    else
        read -p 'Enter new user password: ' -s database_user_password
        echo

        check_password_strength "$database_user_password"

        read -p 'Repeat new user password: ' -s database_user_password_confirm
        echo

        if [ "$database_user_password" != "$database_user_password_confirm" ] ; then
            error "passwords do not match"
        fi
    fi

    if ! db_root_query "\
CREATE USER '$database_user'@'$database_host' IDENTIFIED BY '$database_user_password';"
    then
        error "cannot create database user $database_user"
    fi

    if ! db_root_query "\
GRANT SELECT ON \`$database_name\`.* TO '$database_user'@'$database_host';"
    then
        error "cannot grant privileges to database user $database_user"
    fi

    if ! db_root_query "FLUSH PRIVILEGES;" ; then
        error "cannot flush privileges"
    fi
}

##
# Create the database.
#
do_create_database () {
    if [ $# -gt 0 ] ; then
        database_name="$1"
        shift
    fi

    [ $# -eq 0 ] || bad_parameter "$1"

    if [ -z "$database_name" ] ; then
        read -p "Database ($default_database_name): " database_name
        echo
        : ${database_name:=$default_database_name}
    fi

    if ! db_root_query "CREATE DATABASE \`$database_name\`;" ; then
        error "cannot create database $database_name"
    fi

    if ! db_admin_query 'CREATE TABLE `domains` (
    `id` int(11) NOT NULL auto_increment,
    `domain` varchar(50) NOT NULL,
    PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;'
    then
        error "cannot create the domains table"
    fi

    if ! db_admin_query 'CREATE TABLE `users` (
    `id` int(11) NOT NULL auto_increment,
    `domain_id` int(11) NOT NULL,
    `user` varchar(100) NOT NULL,
    `password` varchar(32) NOT NULL,
    PRIMARY KEY (`id`),
    UNIQUE KEY `user` (`user`),
    FOREIGN KEY (`domain_id`) REFERENCES `domains` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;'
    then
        error "cannot create the users table"
    fi

    if ! db_admin_query 'CREATE TABLE `aliases` (
    `id` int(11) NOT NULL auto_increment,
    `domain_id` int(11) NOT NULL,
    `alias` varchar(100) NOT NULL,
    `user` varchar(100) NOT NULL,
    PRIMARY KEY (`id`),
    FOREIGN KEY (`domain_id`) REFERENCES `domains` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;'
    then
        error "cannot create the aliases table"
    fi
}

##
# Create everything.
#
do_create () {
    [ $# -eq 0 ] || bad_parameter "$1"

    if [ $force = no -a $dry_run = no ] ; then
        error "create is not secure. Use \`--force' to override."
    fi

    do_create_database_admin
    do_create_database_user
    do_create_database
}

##
# Drop a database admin.
#
do_drop_database_admin () {
    if [ $force = no -a $dry_run = no ] ; then
        error "Use \`--force' to actually drop the admin."
    fi

    if [ $# -gt 0 ] ; then
        database_admin="$1"
        shift
    fi

    [ $# -eq 0 ] || bad_parameter "$1"

    if [ -z "$database_admin" ] ; then
        missing_parameter "database-admin"
    fi

    case $database_admin in
        *'@'*)
            database_host=${database_admin##*@}
            database_admin=${database_admin%@*}
            ;;
        *)
            database_host=$default_database_host
            ;;
    esac

    if ! db_root_query "\
REVOKE ALL PRIVILEGES, GRANT OPTION FROM '$database_admin'@'$database_host';"
    then
        notice "cannot revoke privileges from database admin $database_admin"
    fi

    if ! db_root_query "\
DROP USER '$database_admin'@'$database_host';"
    then
        error "cannot drop database admin $database_admin"
    fi

    if ! db_root_query "FLUSH PRIVILEGES;" ; then
        error "cannot flush privileges"
    fi
}

##
# Drop a database user.
#
do_drop_database_user () {
    if [ $force = no -a $dry_run = no ] ; then
        error "Use \`--force' to actually drop the user."
    fi

    if [ $# -gt 0 ] ; then
        database_user="$1"
        shift
    fi

    [ $# -eq 0 ] || bad_parameter "$1"

    if [ -z "$database_user" ] ; then
        missing_parameter "database-user"
    fi

    case $database_user in
        *'@'*)
            database_host=${database_user##*@}
            database_user=${database_user%@*}
            ;;
        *)
            database_host=$default_database_host
            ;;
    esac

    if ! db_root_query "\
REVOKE ALL PRIVILEGES, GRANT OPTION FROM '$database_user'@'$database_host';"
    then
        notice "cannot revoke privileges from database user $database_user"
    fi

    if ! db_root_query "\
DROP USER '$database_user'@'$database_host';"
    then
        error "cannot drop database user $database_user"
    fi

    if ! db_root_query "FLUSH PRIVILEGES;" ; then
        error "cannot flush privileges"
    fi
}

##
# Drop the database.
#
do_drop_database () {
    if [ $force = no -a $dry_run = no ] ; then
        error "Use \`--force' to actually drop the database."
    fi

    if [ $# -gt 0 ] ; then
        database_name="$1"
        shift
    fi

    [ $# -eq 0 ] || bad_parameter "$1"

    if [ -z "$database_name" ] ; then
        missing_parameter "database-name"
    fi

    if ! db_root_query "DROP DATABASE \`$database_name\`;" ; then
        error "cannot drop database $database_name"
    fi
}

##
# Drop everything.
#
do_drop () {
    [ $# -eq 0 ] || bad_parameter "$1"

    if [ $force = no -a $dry_run = no ] ; then
        error "Use \`--force' to actually drop the database."
    fi

    do_drop_database_admin
    do_drop_database_user
    do_drop_database
}

##
# List all domains in the database.
#
do_list_domains () {
    [ $# -eq 0 ] || bad_parameter "$1"

    db_user_query "SELECT \`domain\` FROM \`domains\` ORDER BY \`domain\`;"
}

##
# List the users of the given domain.
#
do_list_users () {
    if [ $# -gt 0 ] ; then
        domain="$1"
        shift
    fi

    [ $# -eq 0 ] || bad_parameter "$1"

    if [ -n "$domain" ] ; then
        domain_id=$(db_user_query "SELECT \`id\` FROM \`domains\` WHERE \`domain\` = '$domain' LIMIT 1;")

        if [ -z "$domain_id" ] ; then
            error "unknown domain $domain"
        fi

        db_user_query "SELECT \`user\` FROM \`users\` WHERE \`domain_id\` = $domain_id ORDER BY \`user\`;" |
        cut -d@ -f1
    else
        db_user_query "SELECT \`user\` FROM \`users\`, \`domains\` WHERE \`domain_id\` = \`domains\`.\`id\` ORDER BY \`domain\`, \`user\`;"
    fi
}

##
# List the aliases of the given domain.
#
do_list_aliases () {
    if [ $# -gt 0 ] ; then
        domain="$1"
        shift
    fi

    [ $# -eq 0 ] || bad_parameter "$1"

    if [ -n "$domain" ] ; then
        domain_id=$(db_user_query "SELECT \`id\` FROM \`domains\` WHERE \`domain\` = '$domain' LIMIT 1;")

        if [ -z "$domain_id" ] ; then
            error "unknown domain $domain"
        fi

        db_user_query "\
SELECT \`alias\`, \`user\` FROM \`aliases\`
    WHERE \`domain_id\` = $domain_id ORDER BY \`alias\`, \`user\`;" |
        sed 's/@[^\t]*//'
    else
        db_user_query "\
SELECT \`alias\`, \`user\` FROM \`aliases\`, \`domains\`
    WHERE \`domain_id\` = \`domains\`.\`id\` ORDER BY \`domain\`, \`alias\`, \`user\`;"
    fi
}

##
# List users and aliases.
#
do_list () {
    if [ $# -gt 0 ] ; then
        domain="$1"
        shift
    fi

    [ $# -eq 0 ] || bad_parameter "$1"

    if [ -n "$domain" ] ; then
        domain_id=$(db_user_query "SELECT \`id\` FROM \`domains\` WHERE \`domain\` = '$domain' LIMIT 1;")

        if [ -z "$domain_id" ] ; then
            error "unknown domain $domain"
        fi

        db_user_query "\
SELECT \`user\` FROM \`users\` WHERE \`domain_id\` = $domain_id UNION
    SELECT DISTINCT \`alias\` AS \`user\` FROM \`aliases\` WHERE \`domain_id\` = $domain_id
    ORDER BY \`user\`;" | sed 's/@[^\t]*//'
    else
        db_user_query "\
SELECT \`user\` FROM (
    SELECT \`user\`, \`domain\` FROM \`users\`, \`domains\` WHERE \`domain_id\` = \`domains\`.\`id\` UNION
    SELECT DISTINCT \`alias\` AS \`user\`, \`domain\` FROM \`aliases\`, \`domains\` WHERE \`domain_id\` = \`domains\`.\`id\`) AS t
    ORDER BY \`domain\`, \`user\`;"
    fi
}

##
# Add a domain to the database.
#
do_add_domain () {
    [ $# -gt 0 ] || missing_parameter "domain"

    domain="$1"
    shift

    [ $# -eq 0 ] || bad_parameter "$1"

    if ! host -q -t mx "$domain" | awk '{print $4}' | grep -q "^${myhostname}\$" ; then
        if [ $force = no -a $dry_run = no ] ; then
            error "$myhostname is not MX for $domain. Use \`--force' to override."
        fi
    fi

    domain_found=$(db_user_query "SELECT 'yes' FROM \`domains\` WHERE \`domain\` = '$domain' LIMIT 1;")

    if [ "$domain_found" = yes ] ; then
        error "$domain already exists in the domains table"
    fi

    if ! db_admin_query "INSERT INTO \`domains\` (\`domain\`) VALUES ('$domain');" ; then
        error "cannot add $domain to the domains table"
    fi
}

##
# Add a user to the database.
#
do_add_user () {
    [ $# -gt 0 ] || missing_parameter "user"

    user="$1"
    shift

    [ $# -eq 0 ] || bad_parameter "$1"

    domain=$(echo "$user" | cut -d@ -f2)

    domain_id=$(db_user_query "SELECT \`id\` FROM \`domains\` WHERE \`domain\` = '$domain' LIMIT 1;")

    if [ -z "$domain_id" ] ; then
        error "unknown domain $domain"
    fi

    user_found=$(db_user_query "SELECT 'yes' FROM \`users\` WHERE \`user\` = '$user' LIMIT 1;")

    if [ "$user_found" = yes ] ; then
        error "$user already exists in the users table"
    fi

    if [ $dry_run = yes ] ; then
        password=xxxxxx
    elif [ $interactive = no ] ; then
        read password

        check_password_strength "$password"
    else
        read -p 'Enter new password: ' -s password
        echo

        check_password_strength "$password"

        read -p 'Repeat new password: ' -s password_confirm
        echo

        if [ "$password" != "$password_confirm" ] ; then
            error "passwords do not match"
        fi
    fi

    hash=$(echo -n "$password" | openssl sha1 -binary | base64)

    if ! db_admin_query "\
INSERT INTO \`users\` (\`domain_id\`, \`user\`, \`password\`)
    VALUES ($domain_id, '$user', '$hash');"
    then
        error "cannot add $user to the users table"
    fi

    if send_welcome_message "$user" ; then
        verbose "sent welcome message to $user"
    else
        error "cannot send welcome message to $user"
    fi
}

##
# Add an alias to the database.
#
do_add_alias () {
    [ $# -gt 0 ] || missing_parameter "alias"

    alias="$1"
    shift

    [ $# -gt 0 ] || missing_parameter "user"

    for user ; do
        domain=$(echo "$alias" | cut -d@ -f2)

        domain_id=$(db_user_query "SELECT \`id\` FROM \`domains\` WHERE \`domain\` = '$domain' LIMIT 1;")

        if [ -z "$domain_id" ] ; then
            error "unknown domain $domain"
        fi

        if ! db_admin_query "\
INSERT INTO \`aliases\` (\`domain_id\`, \`alias\`, \`user\`)
    VALUES ($domain_id, '$alias', '$user');"
        then
            error "cannot add $alias ($user) to the aliases table"
        fi
    done
}

##
# Add a domain or user to the database.
#
do_add () {
    case $1 in
        *'@'*) do_add_user "$@" ;;
            *) do_add_domain "$@" ;;
    esac
}

##
# Change a user's password.
#
do_password () {
    [ $# -gt 0 ] || missing_parameter "user"

    user="$1"
    shift

    [ $# -eq 0 ] || bad_parameter "$1"

    domain=$(echo "$user" | cut -d@ -f2)

    domain_id=$(db_user_query "SELECT \`id\` FROM \`domains\` WHERE \`domain\` = '$domain' LIMIT 1;")

    if [ -z "$domain_id" ] ; then
        error "unknown domain $domain"
    fi

    user_found=$(db_user_query "SELECT 'yes' FROM \`users\` WHERE \`user\` = '$user' LIMIT 1;")

    if [ "$user_found" != yes ] ; then
        error "unknown user $user"
    fi

    if [ $dry_run = yes ] ; then
        password=xxxxxx
    elif [ $interactive = no ] ; then
        read password

        check_password_strength "$password"
    else
        read -p 'Enter new password: ' -s password
        echo

        check_password_strength "$password"

        read -p 'Repeat new password: ' -s password_confirm
        echo

        if [ "$password" != "$password_confirm" ] ; then
            error "passwords do not match"
        fi
    fi

    hash=$(echo -n "$password" | openssl sha1 -binary | base64)

    if ! db_admin_query "\
UPDATE \`users\` SET \`password\` = '$hash'
    WHERE \`domain_id\` = $domain_id AND \`user\` = '$user';"
    then
        error "cannot change password of $user"
    fi
}

##
# Remove a domain from the database.
#
do_remove_domain () {
    if [ $force = no -a $dry_run = no ] ; then
        error "Use \`--force' to actually remove a domain."
    fi

    [ $# -gt 0 ] || missing_parameter "domain"

    domain="$1"
    shift

    [ $# -eq 0 ] || bad_parameter "$1"

    domain_found=$(db_user_query "SELECT 'yes' FROM \`domains\` WHERE \`domain\` = '$domain' LIMIT 1;")

    if [ "$domain_found" != yes ] ; then
        error "unknown domain $domain"
    fi

    if ! db_admin_query "\
DELETE FROM \`domains\` WHERE \`domain\` = '$domain';"
    then
        error "cannot remove $domain from the domains table"
    fi
}

##
# Remove a user from the database.
#
do_remove_user () {
    if [ $force = no -a $dry_run = no ] ; then
        error "Use \`--force' to actually remove a user."
    fi

    [ $# -gt 0 ] || missing_parameter "user"

    user="$1"
    shift

    [ $# -eq 0 ] || bad_parameter "$1"

    domain=$(echo "$user" | cut -d@ -f2)

    domain_id=$(db_user_query "SELECT \`id\` FROM \`domains\` WHERE \`domain\` = '$domain' LIMIT 1;")

    if [ -z "$domain_id" ] ; then
        error "unknown domain $domain"
    fi

    user_found=$(db_user_query "SELECT 'yes' FROM \`users\` WHERE \`user\` = '$user' LIMIT 1;")

    if [ "$user_found" != yes ] ; then
        error "unknown user $user"
    fi

    if ! db_admin_query "\
DELETE FROM \`users\` WHERE \`domain_id\` = $domain_id AND \`user\` = '$user';"
    then
        error "cannot remove $user from the users table"
    fi

    if ! db_admin_query "\
DELETE FROM \`aliases\` WHERE \`domain_id\` = $domain_id AND \`user\` = '$user';"
    then
        error "cannot remove $user from the aliases table"
    fi
}

##
# Remove an alias from the database.
#
do_remove_alias () {
    if [ $force = no -a $dry_run = no ] ; then
        error "Use \`--force' to actually remove an alias."
    fi

    [ $# -gt 0 ] || missing_parameter "alias"

    alias="$1"
    shift

    user=
    if [ $# -gt 0 ] ; then
        user="$1"
        shift
    fi

    [ $# -eq 0 ] || bad_parameter "$1"

    domain=$(echo "$alias" | cut -d@ -f2)

    domain_id=$(db_user_query "SELECT \`id\` FROM \`domains\` WHERE \`domain\` = '$domain' LIMIT 1;")

    if [ -z "$domain_id" ] ; then
        error "unknown domain $domain"
    fi

    if [ -n "$user" ] ; then
        alias_found=$(db_user_query "SELECT 'yes' FROM \`aliases\` WHERE \`alias\` = '$alias' AND \`user\` = '$user' LIMIT 1;")

        if [ "$alias_found" != yes ] ; then
            error "unknown alias $alias for $user"
        fi

        if ! db_admin_query "\
DELETE FROM \`aliases\` WHERE \`domain_id\` = $domain_id AND \`alias\` = '$alias' AND \`user\` = '$user';"
        then
            error "cannot remove $alias ($user) from the aliases table"
        fi
    else
        alias_found=$(db_user_query "SELECT 'yes' FROM \`aliases\` WHERE \`alias\` = '$alias' LIMIT 1;")

        if [ "$alias_found" != yes ] ; then
            error "unknown alias $alias"
        fi

        if ! db_admin_query "\
DELETE FROM \`aliases\` WHERE \`domain_id\` = $domain_id AND \`alias\` = '$alias';"
        then
            error "cannot remove $alias from the aliases table"
        fi
    fi
}

##
# Remove a domain or user from the database.
#
do_remove () {
    case $1 in
        *'@'*) do_remove_user "$@" ;;
            *) do_remove_domain "$@" ;;
    esac
}

##
# Main program.
#
case $command in
    create)                do_create "$@" ;;
    create-database-admin) do_create_database_admin "$@" ;;
    create-database-user)  do_create_database_user "$@" ;;
    create-database)       do_create_database "$@" ;;
    drop)                  do_drop "$@" ;;
    drop-database-admin)   do_drop_database_admin "$@" ;;
    drop-database-user)    do_drop_database_user "$@" ;;
    drop-database)         do_drop_database "$@" ;;
    add)                   do_add "$@" ;;
    alias)                 do_add_alias "$@" ;;
    password | passwd)     do_password "$@" ;;
    remove | rm)           do_remove "$@" ;;
    unalias)               do_remove_alias "$@" ;;
    domains)               do_list_domains "$@" ;;
    users)                 do_list_users "$@" ;;
    aliases)               do_list_aliases "$@" ;;
    list | ls)             do_list "$@" ;;
    query)                 db_user_query "$@" ;;
    help)                  usage ;;
    version)               version ;;
    *)                     bad_parameter "$command" ;;
esac

exit 0
