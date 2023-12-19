#!/usr/bin/env bash

# Utility script for installing CNTLM on a Bosch machine that needs it
# for internet access. Intended to be used in the context of WSL installations.
#
# Original author: Nicholas Clark XC-AD/EFB-NA (@cln1syv)

#-----------------------------------------------------------------------------#

set -eu

TEMPDIR="$(mktemp -d)"

dry_run="${dry_run:-0}"
user="${user:-qdt1fe}"
domain="${domain:-DE}"
passhash="${passhash:-}"

#-----------------------------------------------------------------------------#

cleanup() {
    errcode=$?
    rm -rf "${TEMPDIR}"
    exit $errcode
}

trap cleanup EXIT INT QUIT ERR

install_deb() {
    debfile="$1"
    debfile="$(basename "${debfile}")"

    cp "$1" "${TEMPDIR}/${debfile}"

    if [ "${dry_run:-0}" -eq 0 ]; then
        apt install -y "${TEMPDIR}/${debfile}"
    else
        echo apt install -y "${TEMPDIR}/${debfile}"
    fi

    rm -f "${TEMPDIR}/${debfile}"
}

generate_cntlm_config() {
    user="$1"
    domain="$2"
    passhash="$3"

    proxy_ignores=(
        "localhost"
        "127.*"
        "10.*"
        "192.168.*"
        ".local"
        "*.bosch.*"
    )

    for block in $(seq 16 31); do
        proxy_ignores+=("172.$block.*")
    done

    ignore_string="${proxy_ignores[*]}"
    ignore_string="${ignore_string// /,}"

    echo "Username ${user}"
    echo "Domain ${domain}"
    echo "PassNTLMv2 ${passhash}"
    echo "Proxy rb-proxy-de.bosch.com:8080"
    echo "Proxy rb-proxy-special.bosch.com:8080"
    echo "NoProxy ${ignore_string}"
    echo "Listen 0.0.0.0:3128"
}

generate_environment() {
    proxy_ignores=(
        "localhost"
        "127.*"
        "10.*"
        "192.168.*"
        ".local"
        "*.bosch.*"
    )

    for block in $(seq 16 31); do
        proxy_ignores+=("172.$block.*")
    done

    ignore_string="${proxy_ignores[*]}"
    ignore_string="${ignore_string// /,}"

    proxy_types="ftp_proxy https_proxy http_proxy socks_proxy"

    for var in $proxy_types; do
        echo "export $var=http://127.0.0.1:3128"
    done
    echo "export no_proxy=$ignore_string"

    for var in $proxy_types; do
        echo "export $(printf "%s" "$var" | tr "[:lower:]" "[:upper:]")=http://127.0.0.1:3128"
    done
    echo "export NO_PROXY=$ignore_string"
}


hash_cntlm_password() {
    user="$1"
    domain="$2"

    read -rep "Enter password: " cntlm_passwd
    echo "$cntlm_passwd" | cntlm -u "$user" -d "$domain" -H | \
        awk '/PassNTLMv2/{print $2}'
}

#-----------------------------------------------------------------------------#

usage() {
    echo "usage: $0 [-u USER] [-d DOMAIN] mkhash"
    echo "       $0 [-u USER] [-d DOMAIN] -p PASSWORD_HASH showconfig"
    echo "       $0 [-n] [-u USER] [-d DOMAIN] -p PASSWORD_HASH install CNTLM_PKG.deb"
    echo "       $0 environment"
}

show_help() {
    usage
    echo ""
    echo "Tool for installing / configuring CNTLM on a Bosch computer."
    echo "Command line options:"
    echo "   -n"
    echo "      Dry-run. Doesn't install or modify anything."
    echo ""
    echo "   -u USER"
    echo "      Generate password/config for USER @ DOMAIN (default: ${user})"
    echo ""
    echo "   -d DOMAIN"
    echo "      Generate password/config for USER @ DOMAIN  (default: ${domain})"
    echo ""
    echo "   -p PASSWORD_HASH"
    echo "      Hash to store while generating config. Can be genereated by"
    echo "      this script's 'mkhash' command. Unique to user, password, and domain."
    echo ""
    echo "Commands:"
    echo "   mkhash: Generate a hash for your password."
    echo "   showconfig: Show the config that would be installed by 'install'. "
    echo "   environment: Show the environment file that would be installed by 'installed'."
    echo "   install: Install CNTLM from a .deb and create a Bosch-specific config file."
    echo ""
}

for arg in "$@"; do
    case "$arg" in
        -h) show_help; exit 0; ;;
        --help) show_help; exit 0; ;;
    esac
done


while getopts 'nu:d:p:' flag; do
    case "${flag}" in
        n) dry_run=1 ;;
        u) user="${OPTARG}" ;;
        d) domain="${OPTARG}" ;;
        p) passhash="${OPTARG}" ;;
        *) usage ;;
    esac
done

shift "$((OPTIND-1))"

if [ $# -lt 1 ]; then
    echo "error: incorrect number of arguments" >&2
    usage >&2
    exit 1
fi

case "$1" in
    mkhash)
        if [ $# -ne 1 ]; then
            echo "error: incorrect number of arguments" >&2
            usage >&2
            exit 1
        fi

        if [ "$(which cntlm)" = "" ]; then
            echo "Error: CNTLM must be installed on this machine to calculate hash." >&2
            exit 1
        fi
        hash_cntlm_password "$user" "$domain"
        ;;

    showconfig)
        if [ $# -ne 1 ]; then
            echo "error: incorrect number of arguments" >&2
            usage >&2
            exit 1
        fi

        if [ -z "$passhash" ]; then
            echo "error: password-hash not supplied." >&2
            exit 1
        fi
        generate_cntlm_config "$user" "$domain" "$passhash"
        ;;

    install)
        if [ $# -ne 2 ]; then
            echo "error: incorrect number of arguments" >&2
            usage >&2
            exit 1
        fi

        if [ -z "$passhash" ]; then
            echo "error: password-hash not supplied." >&2
            exit 1
        fi

        install_deb "$2"
        config_file="/etc/cntlm.conf"

        if [ -e "${config_file}" ] && [ ! -e "${config_file}.orig" ]; then
            if [ "${dry_run:-0}" -eq 0 ]; then
                cp "${config_file}" "${config_file}.orig"
            else
                echo cp "${config_file}" "${config_file}.orig"
            fi
        fi
        echo "--------------"
        echo "Creating CNTLM config file..."
        if [ "${dry_run:-0}" -eq 0 ]; then
            generate_cntlm_config "$user" "$domain" "$passhash" | \
                tee "${config_file}"
        else
            generate_cntlm_config "$user" "$domain" "$passhash"
        fi

        echo "--------------"
        echo "Updating environment file..."
        if [ "${dry_run:-0}" -eq 0 ]; then
            generate_environment | tee /etc/profile.d/proxy-vars.sh
        else
            generate_environment
        fi

        echo "--------------"

        if [ "${dry_run:-0}" -eq 0 ]; then
            echo "Restarting CNTLM..."
            systemctl daemon-reload && systemctl restart cntlm
        fi

        echo ""
        echo "Script completed OK."
        ;;

    environment)
        generate_environment
        ;;

    *)
        echo "error: unknown command '$1'." >&2
        usage >&2
        exit 1
        ;;
esac