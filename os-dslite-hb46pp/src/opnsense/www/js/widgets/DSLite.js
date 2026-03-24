/**
 *    Copyright (C) 2024 DS-Lite Plugin Contributors
 *
 *    All rights reserved.
 *
 *    Redistribution and use in source and binary forms, with or without
 *    modification, are permitted provided that the following conditions are met:
 *
 *    1. Redistributions of source code must retain the above copyright notice,
 *       this list of conditions and the following disclaimer.
 *
 *    2. Redistributions in binary form must reproduce the above copyright
 *       notice, this list of conditions and the following disclaimer in the
 *       documentation and/or other materials provided with the distribution.
 *
 *    THIS SOFTWARE IS PROVIDED ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES,
 *    INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY
 *    AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
 */

export default class DSLite extends BaseTableWidget {
    constructor() {
        super();
    }

    _esc(str) {
        return $('<span>').text(str).html();
    }

    getGridOptions() {
        return {
            sizeToContent: 350
        };
    }

    getMarkup() {
        let $container = $('<div></div>');
        let $table = this.createTable('dsliteStatusTable', {
            headerPosition: 'left'
        });
        $container.append($table);
        return $container;
    }

    async onWidgetTick() {
        let response;
        try {
            response = await this.ajaxCall('/api/dslite/service/status');
        } catch (e) {
            this.displayError(this.translations.unconfigured);
            return;
        }

        if (!response || !response.tunnel) {
            this.displayError(this.translations.unconfigured);
            return;
        }

        const t = response.tunnel;

        if (t.status === 'disabled') {
            this.displayError(this.translations.disabled);
            return;
        }

        if (!this.dataChanged('dslite-status', t)) {
            return;
        }

        let statusIcon, statusText, statusClass;
        if (t.status === 'up' && t.connectivity === 'connected') {
            statusIcon = 'fa-check-circle text-success';
            statusText = this.translations.connected;
            statusClass = 'text-success';
        } else if (t.status === 'up' && t.connectivity === 'no internet') {
            statusIcon = 'fa-exclamation-circle text-warning';
            statusText = this.translations.nointernet;
            statusClass = 'text-warning';
        } else if (t.status === 'up') {
            statusIcon = 'fa-circle text-success';
            statusText = this.translations.tunnelup;
            statusClass = 'text-success';
        } else {
            statusIcon = 'fa-circle text-danger';
            statusText = t.reason || this.translations.tunneldown;
            statusClass = 'text-danger';
        }

        let statusRow = `
            <div style="display: flex; align-items: center; gap: 8px;">
                <i class="fa ${statusIcon}" style="font-size: 14px;"></i>
                <span class="${statusClass}"><b>${statusText}</b></span>
            </div>`;

        let detailsRow = '';
        if (t.status === 'up') {
            detailsRow = `
                <div style="padding: 4px 0;">
                    <div><small><b>${this.translations.localv6}:</b> ${this._esc(t.local_v6 || '-')}</small></div>
                    <div><small><b>${this.translations.aftr}:</b> ${this._esc(t.aftr || '-')}</small></div>
                    <div><small><b>${this.translations.ipv4}:</b> ${this._esc(t.ipv4 || '-')}</small></div>
                    <div><small><b>${this.translations.mtu}:</b> ${this._esc(t.mtu || '-')}</small></div>
                </div>`;
        } else if (t.reason) {
            detailsRow = `
                <div style="padding: 4px 0;">
                    <small class="text-muted">${this._esc(t.reason)}</small>
                </div>`;
        }

        super.updateTable('dsliteStatusTable', [[statusRow, detailsRow]], 'dslite-info');
    }

    displayError(message) {
        $('#dsliteStatusTable').empty().append(
            $(`<div class="error-message"><a href="/ui/dslite/general">${message}</a></div>`)
        );
    }
}
