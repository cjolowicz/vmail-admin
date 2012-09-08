#!/bin/bash

set -e

package=vmail-admin
program=ldap-attribute
version=0.1
confdir=/etc
pkgconfdir=$confdir/$package
default_ldap_options=(-H ldapi:/// -Y external -Q)

##
# Print the version.
#
version () {
    echo "\
$program version $version
Copyright (C) 2012 Claudio Jolowicz <cj@dealloc.org>

Print, add and delete LDAP attributes.

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
Usage: $program [options] [name | +name:value | -name:value | -name]..

options:

        --dn DN                DN of the LDAP entry
    -o, --ldap-option OPT      LDAP option
    -n, --dry-run              print commands without executing them
    -v, --verbose              be verbose
    -V, --version              print version number
    -h, --help                 display this message

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
# Parse the command line.
#
dry_run=no
verbose=no
ldap_options=("${default_ldap_options[@]}")
dn=
while [ $# -gt 0 ] ; do
    option=$1
    shift

    case $option in
        -h | --help) usage ; exit 0 ;;
        -V | --version) version ; exit 0 ;;
        -v | --verbose)
            verbose=yes
            ldap_options+=(-v)
            ;;

        -n | --dry-run)
            dry_run=yes
            ldap_options+=(-n)
            ;;

        -o | --ldap-option)
            [ $# -gt 0 ] || missing_argument $option
            ldap_options+=("$1")
            shift
            ;;

        --dn)
            [ $# -gt 0 ] || missing_argument $option
            dn="$1"
            shift
            ;;

        --) break ;;
        -*) bad_option $option ;;
        *) set -- "$option" "$@" ; break ;;
    esac
done

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
# Perform an LDAP search operation.
#
ldap_search () {
    run_command \
        ldapsearch "${ldap_options[@]}" "$@"
}

##
# Print an attribute.
#
do_print_attribute () {
    eval "$(parse_command_arguments 'dn,name' "$@")"

    ldap_search -LLL -b "$dn" -s base "$name" |
    sed -n s/"^$name: *"//p
}

##
# Add a value to an attribute.
#
do_add_attribute_value () {
    eval "$(parse_command_arguments 'dn,name,value' "$@")"

    ldap_modify <<EOF
dn: ${dn}
changetype: modify
add: ${name}
${name}: ${value}
-
EOF
}

##
# Delete an attribute.
#
do_delete_attribute () {
    eval "$(parse_command_arguments 'dn,name' "$@")"

    ldap_modify <<EOF
dn: ${dn}
changetype: modify
delete: ${name}
-
EOF
}

##
# Delete a value from an attribute.
#
do_delete_attribute_value () {
    eval "$(parse_command_arguments 'dn,name,value' "$@")"

    ldap_modify <<EOF
dn: ${dn}
changetype: modify
delete: ${name}
${name}: ${value}
-
EOF
}

for op ; do
    case $op in
        +*)
	    op=${op:1}
            do_add_attribute_value "${dn}" "${op%%:*}" "${op#*:}"
            ;;

        -*:*)
	    op=${op:1}
	    do_delete_attribute_value "${dn}" "${op%%:*}" "${op#*:}"
	    ;;

        -*)
	    op=${op:1}
	    do_delete_attribute "${dn}" "${op}"
            ;;

        *)
            do_print_attribute "${dn}" "${op}"
            ;;
    esac
done

exit 0
