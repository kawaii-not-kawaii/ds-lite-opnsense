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

namespace OPNsense\DSLite\Api;

use OPNsense\Base\ApiMutableServiceControllerBase;
use OPNsense\Core\Backend;

class ServiceController extends ApiMutableServiceControllerBase
{
    protected static $internalServiceClass = '\OPNsense\DSLite\DSLite';
    protected static $internalServiceTemplate = 'OPNsense/DSLite';
    protected static $internalServiceEnabled = 'enabled';
    protected static $internalServiceName = 'dslite';

    public function reconfigureAction()
    {
        if (!$this->request->isPost()) {
            return ['result' => 'failed'];
        }

        $backend = new Backend();
        $backend->configdRun('dslite configure');

        return ['result' => 'ok'];
    }

    public function statusAction()
    {
        $backend = new Backend();
        $response = $backend->configdRun('dslite status');
        return json_decode($response, true) ?? ['status' => 'unknown'];
    }

    public function diagnosticsAction()
    {
        $backend = new Backend();
        $response = $backend->configdRun('dslite diagnostics');
        return json_decode($response, true) ?? ['error' => 'failed to run diagnostics'];
    }
}
