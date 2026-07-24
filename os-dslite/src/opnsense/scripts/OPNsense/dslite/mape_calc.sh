#!/bin/sh

# MAP-E parameter calculator (read-only, no side effects).
#
# Derives the IPv4 address, PSID, CE IPv6 address and port set from a delegated
# prefix and a Basic Mapping Rule, without creating a tunnel or touching pf.
#
# The point of this is cross-checking. The VNEs do not publish their mapping
# rules, so the only trustworthy source for your line is a device already
# running MAP-E on it. Read the rule off that device, run it through here, and
# confirm the derived IPv4 and PSID match what it actually uses before cutting
# anything over.
#
# Usage:
#   mape_calc.sh
#       Use the configured rule and the live delegated prefix.
#   mape_calc.sh <pd_prefix>
#       Override the prefix, take the rule from the configuration.
#   mape_calc.sh <pd_prefix> <rule_ipv6> <rule_ipv4> <ea_length> <psid_offset>
#       Fully explicit; reads nothing from the configuration.
#
# Example (published v6plus parameters):
#   mape_calc.sh 240b:10:1234:5600::/56 240b:10::/31 106.72.0.0/15 25 4

SCRIPT_DIR=$(dirname "$0")
. "${SCRIPT_DIR}/lib.sh"

get_config

PD_PREFIX="$1"
RULE_IPV6="$2"
RULE_IPV4="$3"
EA_LENGTH="$4"
PSID_OFFSET="$5"

if [ -z "${RULE_IPV6}" ]; then
    RULE_IPV6=$(config_get "//OPNsense/dslite/mape_rule_ipv6")
    RULE_IPV4=$(config_get "//OPNsense/dslite/mape_rule_ipv4")
    EA_LENGTH=$(config_get "//OPNsense/dslite/mape_ea_length")
    PSID_OFFSET=$(config_get "//OPNsense/dslite/mape_psid_offset")

    MAPE_PROFILE=$(config_get "//OPNsense/dslite/mape_profile")
    if [ -n "${MAPE_PROFILE}" ] && [ "${MAPE_PROFILE}" != "custom" ]; then
        if mape_profile_lookup "${MAPE_PROFILE}"; then
            [ -n "${PSID_OFFSET}" ] || PSID_OFFSET="${MAPE_P_OFFSET}"
            BR_ADDRESS="${MAPE_P_BR}"
        fi
    fi
    CONFIGURED_BR=$(config_get "//OPNsense/dslite/mape_br")
    [ -n "${CONFIGURED_BR}" ] && BR_ADDRESS="${CONFIGURED_BR}"
fi
PSID_OFFSET="${PSID_OFFSET:-6}"

if [ -z "${PD_PREFIX}" ]; then
    PD_PREFIX=$(get_pd_prefix)
fi

if [ -z "${PD_PREFIX}" ]; then
    echo "ERROR: no delegated prefix given and none could be detected." >&2
    echo "       Pass one explicitly: mape_calc.sh 240b:10:1234:5600::/56" >&2
    exit 1
fi

if [ -z "${RULE_IPV6}" ] || [ -z "${RULE_IPV4}" ] || [ -z "${EA_LENGTH}" ]; then
    echo "ERROR: no mapping rule configured or supplied." >&2
    echo "       Usage: mape_calc.sh <pd_prefix> <rule_ipv6> <rule_ipv4> <ea_length> <psid_offset>" >&2
    exit 1
fi

DERIVED=$(mape_derive "${PD_PREFIX}" "${RULE_IPV6}" "${RULE_IPV4}" "${EA_LENGTH}" "${PSID_OFFSET}")
if [ -z "${DERIVED}" ]; then
    echo "REFUSED: the delegated prefix does not fall inside this rule, or the"
    echo "         parameters are inconsistent."
    echo
    echo "  delegated prefix : ${PD_PREFIX}"
    echo "  rule IPv6        : ${RULE_IPV6}"
    echo "  rule IPv4        : ${RULE_IPV4}"
    echo "  EA-bits length   : ${EA_LENGTH}"
    echo "  PSID offset      : ${PSID_OFFSET}"
    echo
    echo "The prefix must sit inside the rule IPv6 prefix and be long enough to"
    echo "carry the EA bits. This is a refusal, not a guess: a rule that does not"
    echo "match would otherwise produce a plausible but wrong port set, and the BR"
    echo "would silently drop the traffic."
    exit 1
fi

set -- ${DERIVED}
IPV4="$1"
PSID="$2"
PSID_LEN="$3"
CE="$4"
RANGES="$5"
PORTS="$6"

echo "MAP-E derivation (RFC 7597)"
echo
echo "  Input"
echo "    delegated prefix : ${PD_PREFIX}"
echo "    rule IPv6        : ${RULE_IPV6}"
echo "    rule IPv4        : ${RULE_IPV4}"
echo "    EA-bits length   : ${EA_LENGTH}"
echo "    PSID offset      : ${PSID_OFFSET}"
[ -n "${BR_ADDRESS}" ] && echo "    BR address       : ${BR_ADDRESS}"
echo
echo "  Derived"
echo "    IPv4 address     : ${IPV4}"
echo "    PSID             : ${PSID}  (${PSID_LEN} bits)"
echo "    CE IPv6 address  : ${CE}"
echo "    port set         : ${PORTS} ports in ${RANGES} ranges"
echo
echo "    pf nat rule      : map-e-portset ${PSID_OFFSET}/${PSID_LEN}/${PSID}"
echo
echo "  Port ranges"
mape_port_ranges "${PSID_OFFSET}" "${PSID_LEN}" "${PSID}" | while read -r start end; do
    echo "    ${start}-${end}"
done
echo
echo "  Compare the IPv4 address and PSID against the device currently running"
echo "  MAP-E on this line. A mismatch means the rule is wrong for this prefix."

exit 0
