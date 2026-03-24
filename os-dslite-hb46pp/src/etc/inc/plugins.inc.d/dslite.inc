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
    return [
        'newwanip' => ['dslite_configure_do:3'],
        'vpn' => ['dslite_configure_do:2'],
    ];
}

function dslite_configure_do($verbose = false)
{
    if (!dslite_enabled()) {
        return;
    }

    service_log('Configuring DS-Lite tunnel...', $verbose);
    configd_run('dslite configure');
    service_log("done.\n", $verbose);
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

function dslite_interfaces()
{
    $interfaces = [];

    if (!dslite_enabled()) {
        return $interfaces;
    }

    $interfaces['dslite'] = [
        'descr' => gettext('DS-Lite (gif0)'),
        'if' => 'gif0',
        'virtual' => true,
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
