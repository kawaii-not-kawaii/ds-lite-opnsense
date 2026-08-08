#!/bin/sh

# DS-Lite Fixed IP periodic prefix update.
#
# Refreshes the provider-side registration of our tunnel-local IPv6 address so
# it does not lapse between reconfigurations. Registered as a cron job by
# dslite_cron() in plugins.inc.d/dslite.inc and reachable through the configd
# action "dslite prefix_update".
#
# Shipped as a real file in the package: nothing generates it at runtime, so
# pkg owns it and removes it on uninstall.

SCRIPT_DIR=$(dirname "$0")
. "${SCRIPT_DIR}/lib.sh"

get_config

if [ "${DSLITE_ENABLED}" != "1" ]; then
    exit 0
fi

if [ "$(get_mode)" != "fixedip" ]; then
    exit 0
fi

UPDATE_URL=$(config_get "//OPNsense/dslite/fixedip_update_url")
AUTH_USER=$(config_get "//OPNsense/dslite/fixedip_auth_user")
AUTH_PASS=$(config_get "//OPNsense/dslite/fixedip_auth_pass")

if [ -z "${UPDATE_URL}" ] || [ -z "${AUTH_USER}" ]; then
    exit 0
fi

# Bind the refresh to the CE address: transix registers whatever source address
# the request arrives from, so an unbound request can register the wrong one.
CE_ADDR=$(fixedip_local_v6 "$(config_get "//OPNsense/dslite/fixedip_interface_id")")

RESULT=$(dslite_authed_get "${UPDATE_URL}" "${AUTH_USER}" "${AUTH_PASS}" "${FIXEDIP_ALLOW_INSECURE}" "${CE_ADDR}")
RC=$?
CODE=$(printf '%s' "${RESULT}" | awk '{print $1; exit}')

write_prefix_update_state "${RC}" "${CODE}"
logger -t dslite "Periodic prefix update: rc=${RC} ${RESULT}"

exit 0
