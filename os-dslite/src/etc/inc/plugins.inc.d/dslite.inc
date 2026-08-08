<?php

/*
 * Copyright (C) 2024 DS-Lite Plugin Contributors
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright notice,
 *    this list of conditions and the following disclaimer.
 *
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES,
 * INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY
 * AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
 */

function dslite_enabled()
{
    $model = new \OPNsense\DSLite\DSLite();
    return (string)$model->enabled == '1';
}

function dslite_configure()
{
    /*
     * Both rc.newwanip and rc.newwanipv6 call plugins_configure() for 'vpn' and
     * for 'newwanip', each with [$interfaces, $family]. plugins_configure()
     * slices that list to the ":N" suffix, so a callback registered at :2 never
     * receives $family and cannot filter on it -- which is why the two hooks
     * need separate entry points rather than one shared callback:
     *
     *   vpn      -> boot only; a renewal always carries a family, so reject it
     *               here and let newwanip own it (otherwise every IPv4 renewal
     *               would rebuild the tunnel and every IPv6 renewal would run
     *               the work twice).
     *   newwanip -> renewal; accept inet6, reject inet.
     */
    return [
        'newwanip' => ['dslite_configure_renew:3'],
        'vpn' => ['dslite_configure_boot:3'],
    ];
}

/*
 * True when this event concerns the WAN the tunnel is built on. rc.newwanip
 * passes an array of OPNsense interface names; an unrelated interface changing
 * address must not trigger a destructive rebuild. An empty or absent list means
 * "no interface context" (boot), which we accept.
 */
function dslite_affects_wan($interfaces)
{
    if (empty($interfaces) || !is_array($interfaces)) {
        return true;
    }

    $model = new \OPNsense\DSLite\DSLite();
    $wan = (string)$model->wan_interface;

    return $wan === '' || in_array($wan, $interfaces);
}

function dslite_configure_run($verbose)
{
    service_log('Configuring DS-Lite tunnel...', $verbose);
    configd_run('dslite configure');
    service_log("done.\n", $verbose);
}

/* 'vpn' hook: boot-time start only. */
function dslite_configure_boot($verbose = false, $interfaces = null, $family = null)
{
    if (!dslite_enabled()) {
        return;
    }

    if ($family !== null) {
        /* an address renewal, not a boot: dslite_configure_renew() handles it */
        return;
    }

    dslite_configure_run($verbose);
}

/* 'newwanip' hook: react to an address renewal on the configured WAN. */
function dslite_configure_renew($verbose = false, $interfaces = null, $family = null)
{
    if (!dslite_enabled()) {
        return;
    }

    /*
     * The WAN is IPv6-only (IPv4 = None), so the tunnel must rebuild on the
     * inet6 renewal. Reject inet outright. A null family means an older
     * OPNsense that did not pass one; treat that as "unknown" and run, since
     * the configure script coalesces the duplicate against the boot call.
     */
    if ($family !== null && $family !== 'inet6') {
        service_log('Skipping DS-Lite reconfigure (non-inet6 trigger).', $verbose);
        return;
    }

    if (!dslite_affects_wan($interfaces)) {
        service_log('Skipping DS-Lite reconfigure (unrelated interface).', $verbose);
        return;
    }

    dslite_configure_run($verbose);
}

function dslite_cron()
{
    $jobs = [];

    if (!dslite_enabled()) {
        return $jobs;
    }

    $model = new \OPNsense\DSLite\DSLite();

    if ((string)$model->mode !== 'fixedip') {
        return $jobs;
    }

    if ((string)$model->fixedip_update_url === '' || (string)$model->fixedip_auth_user === '') {
        return $jobs;
    }

    /*
     * Keep the provider-side registration alive between reconfigurations.
     * Must stay well below PREFIX_UPDATE_MAX_AGE in lib.sh, which is what
     * decides when a stored result counts as stale.
     */
    $jobs[]['autocron'] = ['/usr/local/sbin/configctl -d dslite prefix_update', '*/30'];

    return $jobs;
}

function dslite_firewall(\OPNsense\Firewall\Plugin $fw)
{
    if (!dslite_enabled()) {
        return;
    }

    $fw->registerAnchor('dslite/*', 'nat');
    $fw->registerAnchor('dslite/*', 'rdr');
    $fw->registerAnchor('dslite/*', 'fw');
}

function dslite_services()
{
    $services = [];

    if (!dslite_enabled()) {
        return $services;
    }

    $services[] = [
        'description' => 'DS-Lite Tunnel',
        'configd' => [
            'start' => ['dslite start'],
            'restart' => ['dslite restart'],
            'stop' => ['dslite stop'],
        ],
        'name' => 'dslite',
        'nocheck' => true,
    ];

    return $services;
}

/*
 * The gif unit the tunnel is built on. Kept in sync with the shell side in
 * lib.sh: anything that is not a plain gif unit name falls back to the default
 * rather than being registered as an interface device.
 */
function dslite_tunnel_if()
{
    $model = new \OPNsense\DSLite\DSLite();
    $device = (string)$model->tunnel_interface;

    return preg_match('/^gif[0-9]{1,2}$/', $device) ? $device : 'gif0';
}

function dslite_interfaces()
{
    $interfaces = [];

    if (!dslite_enabled()) {
        return $interfaces;
    }

    $device = dslite_tunnel_if();

    /*
     * Deliberately not virtual. Virtual is for group pseudo-interfaces such as
     * OpenVPN's and WireGuard's; the tunnel is a routable device, so the matching
     * precedent is IPsec's VTI registration. Marking it virtual excludes it from
     * InterfaceField's option list and from Gateways::getDefinedInterfaces(), which
     * makes it impossible to give the tunnel a gateway at all -- and without a
     * gateway there is no monitoring and no failover to a second WAN.
     *
     * The property has to be present and false rather than simply omitted:
     * plugins_interfaces() diffs only the properties a registration supplies and
     * never removes the ones it drops, so an omitted key would leave a stale
     * <virtual>1</virtual> behind in existing configurations.
     *
     * Safe because this registration carries no addressing: interface_configure()
     * flushes addresses only when ipaddr/ipaddrv6 are set and resets the MTU only
     * when mtu is set, so OPNsense will not disturb the address or the 1460-byte
     * MTU that configure.sh puts on the tunnel.
     */
    $interfaces['dslite'] = [
        'descr' => sprintf(gettext('DS-Lite (%s)'), $device),
        'if' => $device,
        'virtual' => false,
        'enable' => true,
        'type' => 'gif',
    ];

    return $interfaces;
}

function dslite_syslog()
{
    return [
        'dslite' => ['facility' => ['dslite']]
    ];
}
