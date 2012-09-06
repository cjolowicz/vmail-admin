#!/bin/bash
#
# vmail-ldap - Manage virtual mailboxes and aliases in LDAP.
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

program=vmail-ldap
VERSION=0.1
confdir=/etc
pkgconfdir=$confdir/$program
default_ldap_options=(-H ldapi:/// -xW)
default_ldap_root_options=(-H ldapi:/// -Y external)
minimum_password_length=6
minimum_password_nonalpha=1

##
# Print the version.
#
version () {
    echo "\
$program version $VERSION
Copyright (C) 2012 Claudio Jolowicz <cj@dealloc.org>

Manage virtual mailboxes and aliases in LDAP.

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
       $program [options] create-schema
       $program [options] create-database
       $program [options] drop-database
       $program [options] domains
       $program [options] users     DOMAIN
       $program [options] aliases   DOMAIN
       $program [options] list      DOMAIN
       $program [options] add       DOMAIN | USER
       $program [options] remove    DOMAIN | USER
       $program [options] password  USER
       $program [options] alias     ALIAS USER..
       $program [options] unalias   ALIAS [USER]

options:

    -h, --help                            display this message
    -V, --version                         print version number
    -v, --verbose                         be verbose
    -n, --dry-run                         print commands without executing them
    -f, --force                           override sanity checks
        --ldap-option OPT                 LDAP option
        --ldap-root-option OPT            LDAP option for operations as root
        --non-interactive                 read password from stdin

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
# Build the DN for a given domain name.
#
build_domain_dn () {
    dc=$1
    dn=

    while : ; do
        dn="dc=${dc##*.}${dn:+,}${dn}"
        case $dc in
            *.*) dc=${dc%.*} ;;
              *) break ;;
        esac
    done

    printf 'domain_dn=%q\ndomain_dc=%q\n' "$dn" "$dc"
}

##
# Parse command arguments.
#
parse_command_arguments () {
    parameters="$1"
    shift

    while : ; do
        case $parameters in
            *','*) parameter="${parameters%%,*}" ; parameters="${parameters#*,}" ;;
               '') break ;;
                *) parameter="$parameters" ; parameters="" ;;
        esac

        is_array=false
        is_optional=false

        case $parameter in
            *'+')
                is_array=true
                parameter="${parameter%?}"
                ;;

            *'*')
                is_array=true
                is_optional=true
                parameter="${parameter%?}"
                ;;

            *'?')
                is_optional=true
                parameter="${parameter%?}"
                ;;
        esac

        [ $# -gt 0 ] || $is_optional || missing_parameter "$parameter"

        if $is_array ; then
            printf '%s=()\n' "$parameter"

            for value ; do
                printf '%s+=(%q)\n' "$parameter" "$value"
            done

	    set --

            break
        fi

        if [ $# -eq 0 ] ; then
            value=
        else
            value="$1"
            shift
        fi

        printf '%s=%q\n' "$parameter" "$value"
    done

    [ $# -eq 0 ] || bad_parameter "$1"
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
# Determine the hostname and admin DN.
#
myhostname="$(hostname --fqdn)"
mydomainname="$(hostname --domain)"
eval "$(build_domain_dn "$mydomainname")"
ldap_root_dn="$domain_dn"
ldap_admin_dn="cn=admin,$ldap_root_dn"
vmail_cn="vmail"
vmail_dn="ou=${vmail_cn},$ldap_root_dn"

default_ldap_options+=(-D "$ldap_admin_dn")

##
# Parse the command line.
#
dry_run=no
verbose=no
force=no
ldap_options=("${default_ldap_options[@]}")
ldap_root_options=("${default_ldap_root_options[@]}")
interactive=yes
[ -t 1 ] || interactive=no
while [ $# -gt 0 ] ; do
    option=$1
    shift

    case $option in
        -h | --help) usage ; exit 0 ;;
        -V | --version) version ; exit 0 ;;
        -f | --force) force=yes ;;
        --interactive) interactive=yes ;;
        --non-interactive) interactive=no ;;
        -v | --verbose)
            verbose=yes
            ldap_options+=(-v)
            ldap_root_options+=(-v)
            ;;

        -n | --dry-run)
            dry_run=yes
            ldap_options+=(-n)
            ldap_root_options+=(-n)
            ;;

        --ldap-option)
            [ $# -gt 0 ] || missing_argument $option
            ldap_options+=("$1")
            shift
            ;;

        --ldap-root-option)
            [ $# -gt 0 ] || missing_argument $option
            ldap_root_options+=("$1")
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

if [ -z "$myhostname" ] ; then
    if [ $force = no -a $dry_run = no ] ; then
        error "cannot determine hostname"
    fi
fi

if [ -z "$mydomainname" ] ; then
    if [ $force = no -a $dry_run = no ] ; then
        error "cannot determine domainname"
    fi
fi

##
# Run command.
#
run_command () {
    if [ $dry_run = yes ] ; then
        echo "$@" >&2
    elif [ $verbose = yes ] ; then
        echo "$@" >&2
        "$@"
    else
        "$@"
    fi
}

##
# Run command with input.
#
run_command_with_input () {
    if [ $dry_run = yes ] ; then
        echo "$@" '<<EOF' >&2
        cat >&2
        echo 'EOF' >&2
    elif [ $verbose = yes ] ; then
        echo "$@" '<<EOF' >&2
        tee /dev/stderr | "$@"
        echo 'EOF' >&2
    else
        "$@"
    fi
}

##
# Perform an LDAP modify operation.
#
ldap_modify () {
    run_command_with_input \
        ldapmodify "${ldap_options[@]}" "$@" >/dev/null
}

##
# Perform an LDAP add operation.
#
ldap_add () {
    run_command_with_input \
        ldapadd "${ldap_options[@]}" "$@" >/dev/null
}

##
# Perform an LDAP add operation as root.
#
ldap_root_add () {
    run_command_with_input \
        ldapadd "${ldap_root_options[@]}" "$@" >/dev/null
}

##
# Perform an LDAP delete operation.
#
ldap_delete () {
    run_command \
        ldapdelete "${ldap_options[@]}" "$@" >/dev/null
}

##
# Perform an LDAP delete operation as root.
#
ldap_root_delete () {
    run_command \
        ldapdelete "${ldap_root_options[@]}" "$@" >/dev/null
}

##
# Perform an LDAP search operation.
#
ldap_search () {
    run_command \
        ldapsearch "${ldap_options[@]}" "$@"
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
# Read a password.
#
read_password () {
    if [ $dry_run = yes ] ; then
        user_password=xxxxxx
    elif [ $interactive = no ] ; then
        read password
        check_password_strength "$password"
        user_password="$password"
    else
        read -p 'Enter new password: ' -s password
        echo

        check_password_strength "$password"

        read -p 'Repeat new password: ' -s password_confirm
        echo

        if [ "$password" != "$password_confirm" ] ; then
            error "passwords do not match"
        fi

        user_password=$(slappasswd -n -s "$password")
    fi
}

##
# Create the schema.
#
do_create_schema () {
    eval "$(parse_command_arguments '' "$@")"

    ldap_root_add <<EOF
dn: cn=mailGroup,cn=schema,cn=config
objectClass: olcSchemaConfig
cn: mailGroup
olcAttributeTypes: {1}( 2.16.840.1.113730.3.1.13 NAME 'mailAlternateAddress' DESC 'alternate RFC822 email addresses used to reach this person' EQUALITY caseIgnoreIA5Match SYNTAX 1.3.6.1.4.1.1466.115.121.1.26{256} )
olcAttributeTypes: {4}( 2.16.840.1.113730.3.1.30 NAME 'mgrpRFC822MailMember' DESC 'RFC822 mail address of email only member of group' EQUALITY CaseIgnoreIA5Match SYNTAX 1.3.6.1.4.1.1466.115.121.1.26{256} )
olcAttributeTypes: {5}( 2.16.840.1.113730.3.1.25 NAME 'mgrpDeliverTo' DESC 'LDAP Search URL to describe group membership' SYNTAX 1.3.6.1.4.1.1466.115.121.1.26 EQUALITY caseExactIA5Match )
olcAttributeTypes: {6}( 2.16.840.1.113730.3.1.23 NAME 'mgrpAllowedDomain' DESC 'allowed domains for sender of mail to group' SYNTAX 1.3.6.1.4.1.1466.115.121.1.26 )
olcAttributeTypes: {7}( 2.16.840.1.113730.3.1.22 NAME 'mgrpAllowedBroadcaster' DESC 'mailto: or LDAP: URL of allowed sender of mail to the group' SYNTAX 1.3.6.1.4.1.1466.115.121.1.26 )
olcObjectClasses: {0}( 2.16.840.1.113730.3.2.4 NAME 'mailGroup' SUP top STRUCTURAL MUST mail MAY ( cn \$ mailAlternateAddress \$ mgrpAllowedBroadcaster \$ mgrpAllowedDomain \$ mgrpDeliverTo \$ mgrpRFC822MailMember ) )
EOF
}

##
# Create the database.
#
do_create_database () {
    eval "$(parse_command_arguments '' "$@")"

    ldap_add <<EOF
dn: ${vmail_dn}
objectClass: organizationalUnit
objectClass: top
ou: ${vmail_cn}
EOF
}

##
# Create everything.
#
do_create () {
    eval "$(parse_command_arguments '' "$@")"

    do_create_schema
    do_create_database
}

##
# Drop the database.
#
do_drop_database () {
    eval "$(parse_command_arguments '' "$@")"

    if [ $force = no -a $dry_run = no ] ; then
        error "Use \`--force' to actually drop the database."
    fi

    ldap_delete -r "${vmail_dn}" || return 0
}

##
# List all domains in the database.
#
do_list_domains () {
    eval "$(parse_command_arguments '' "$@")"

    ldap_search -b "${vmail_dn}" -s sub 'o' |
    egrep '^o: ' | cut -c4-
}

##
# List the users of the given domain.
#
do_list_users () {
    eval "$(parse_command_arguments domain "$@")"
    eval "$(build_domain_dn "$domain")"

    domain_dn="${domain_dn},${vmail_dn}"

    ldap_search -b "ou=people,${domain_dn}" -s one 'uid' |
    egrep '^uid: ' | cut -c6-
}

##
# List the aliases of the given domain.
#
do_list_aliases () {
    eval "$(parse_command_arguments domain "$@")"
    eval "$(build_domain_dn "$domain")"

    domain_dn="${domain_dn},${vmail_dn}"

    ldap_search -b "ou=mailGroups,${domain_dn}" -s one 'mail' 'mgrpRFC822MailMember' |
    while read line ; do
        case $line in
            mail:*)
		alias=${line#*: }
		;;

            mgrpRFC822MailMember:*)
		user=${line#*: }
		echo -e "$alias\t$user"
		;;
        esac
    done
}

##
# List users and aliases.
#
do_list () {
    eval "$(parse_command_arguments domain "$@")"
    eval "$(build_domain_dn "$domain")"

    domain_dn="${domain_dn},${vmail_dn}"

    ldap_search -b "ou=people,${domain_dn}" -s one 'uid'
    ldap_search -b "ou=mailGroups,${domain_dn}" -s one 'mail'
}

##
# Add a domain to the database.
#
do_add_domain () {
    eval "$(parse_command_arguments domain "$@")"
    eval "$(build_domain_dn "$domain")"

    domain_dn="${domain_dn},${vmail_dn}"

    ldap_add <<EOF
dn: ${domain_dn}
objectClass: organization
objectClass: dcObject
objectClass: top
o: ${domain}
dc: ${domain_dc}

dn: ou=people,${domain_dn}
objectClass: organizationalUnit
objectClass: top
ou: people

dn: ou=mailGroups,${domain_dn}
objectClass: organizationalUnit
objectClass: top
ou: mailGroups
EOF
}

##
# Add a user to the database.
#
do_add_user () {
    eval "$(parse_command_arguments user "$@")"

    domain="${user##*@}"
    user="${user%@*}"

    eval "$(build_domain_dn "$domain")"

    domain_dn="${domain_dn},${vmail_dn}"
    user_dn="uid=${user},ou=people,${domain_dn}"

    read_password

    user_cn="$user"

    if [ -t 1 -a $interactive = yes ] ; then
        read -p "Full Name: " user_cn
        echo
    fi

    user_cn="$(echo $user_cn)"
    case $user_cn in
        *' '*) user_sn=${user_cn##* } ; user_given_name=${user_cn% *} ;;
            *) user_sn=$user_cn ; user_given_name= ;;
    esac

    [ -z "$user_given_name" ] || line_user_given_name="\
givenName: ${user_given_name}
"

    ldap_add <<EOF
dn: ${user_dn}
uid: ${user}
objectClass: person
objectClass: organizationalPerson
objectClass: inetOrgPerson
objectClass: top
cn: ${user_cn}
sn: ${user_sn}${line_user_given_name}
userPassword: ${user_password}
mail: ${user}@${domain}
EOF
}

##
# Add an alias to the database.
#
do_add_alias () {
    eval "$(parse_command_arguments alias,users+ "$@")"

    domain="${alias##*@}"
    alias="${alias%@*}"

    eval "$(build_domain_dn "$domain")"

    domain_dn="${domain_dn},${vmail_dn}"
    alias_dn="mail=${alias},ou=mailGroups,${domain_dn}"

    ldap_add <<EOF 2>/dev/null ||
dn: ${alias_dn}
mail: ${alias}
objectClass: mailGroup
objectClass: top
EOF
    case $? in
        68) ;; # already exists
         *) error "cannot add alias to LDAP" ;;
    esac

    (
        echo "dn: ${alias_dn}"
        echo "changetype: modify"
        for user in "${users[@]}" ; do
            echo "add: mgrpRFC822MailMember"
            echo "mgrpRFC822MailMember: ${user}"
            echo "-"
        done
    ) | ldap_modify
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
    eval "$(parse_command_arguments user "$@")"

    domain="${user##*@}"
    user="${user%@*}"

    eval "$(build_domain_dn "$domain")"

    domain_dn="${domain_dn},${vmail_dn}"
    user_dn="uid=${user},ou=people,${domain_dn}"

    read_password

    ldap_modify <<EOF
dn: ${user_dn}
changetype: modify
replace: userPassword
userPassword: ${user_password}
-
EOF
}

##
# Remove a domain from the database.
#
do_remove_domain () {
    if [ $force = no -a $dry_run = no ] ; then
        error "Use \`--force' to actually remove a domain."
    fi

    eval "$(parse_command_arguments domain "$@")"
    eval "$(build_domain_dn "$domain")"

    domain_dn="${domain_dn},${vmail_dn}"

    ldap_delete -r "$domain_dn"
}

##
# Remove a user from the database.
#
do_remove_user () {
    if [ $force = no -a $dry_run = no ] ; then
        error "Use \`--force' to actually remove a user."
    fi

    eval "$(parse_command_arguments user "$@")"

    domain="${user##*@}"
    user="${user%@*}"

    eval "$(build_domain_dn "$domain")"

    domain_dn="${domain_dn},${vmail_dn}"
    user_dn="uid=${user},ou=people,${domain_dn}"

    ldap_delete "$user_dn"
}

##
# Remove an alias from the database.
#
do_remove_alias () {
    if [ $force = no -a $dry_run = no ] ; then
        error "Use \`--force' to actually remove an alias."
    fi

    eval "$(parse_command_arguments "alias,user?" "$@")"

    domain="${alias##*@}"
    alias="${alias%@*}"

    eval "$(build_domain_dn "$domain")"

    domain_dn="${domain_dn},${vmail_dn}"
    alias_dn="mail=${alias},ou=mailGroups,${domain_dn}"

    if [ -z "$user" ] ; then
        ldap_delete "$alias_dn"
    else
        ldap_modify <<EOF
dn: ${alias_dn}
changetype: modify
delete: mgrpRFC822MailMember
mgrpRFC822MailMember: ${user}
-
EOF
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
    create-schema)         do_create_schema "$@" ;;
    create-database)       do_create_database "$@" ;;
    drop-database)         do_drop_database "$@" ;;
    domains)               do_list_domains "$@" ;;
    users)                 do_list_users "$@" ;;
    aliases)               do_list_aliases "$@" ;;
    list | ls)             do_list "$@" ;;
    add)                   do_add "$@" ;;
    remove | rm)           do_remove "$@" ;;
    password | passwd)     do_password "$@" ;;
    alias)                 do_add_alias "$@" ;;
    unalias)               do_remove_alias "$@" ;;
    help)                  usage ;;
    *)                     bad_parameter "$command" ;;
esac

exit 0
