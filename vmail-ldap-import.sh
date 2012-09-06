#!/bin/bash

set -e

opts=("$@")

vmail-ldap "${opts[@]}" -f drop-database
vmail-ldap "${opts[@]}" create-database

vmail-admin domains |
while read domain ; do
    echo "==> $domain <=="
    vmail-ldap "${opts[@]}" add $domain

    vmail-admin query "\
SELECT user, CONCAT('{SHA}', password) FROM users WHERE user LIKE '%@$domain'" |
    while read user password ; do
        echo "user: ${user%@*}"
        echo "$password" | vmail-ldap --non-interactive "${opts[@]}" add $user
    done
    echo

    vmail-admin aliases $domain |
    while read alias user ; do
        echo "alias: $alias => $user"
        vmail-ldap "${opts[@]}" alias $alias@$domain $user
    done
    echo
done
