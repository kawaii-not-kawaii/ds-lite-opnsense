{#
 # Copyright (C) 2024 DS-Lite Plugin Contributors
 # All rights reserved.
 #}

<script>
    $( document ).ready(function() {
        function badge(status) {
            var cls = 'label-default', txt = status;
            switch (status) {
                case 'ok':             cls = 'label-success'; break;
                case 'ng':             cls = 'label-danger';  break;
                case 'stale':          cls = 'label-warning'; break;
                case 'skipped':        cls = 'label-default'; break;
                case 'not-configured': cls = 'label-info';    break;
                case 'untested':       cls = 'label-warning'; break;
            }
            return '<span class="label ' + cls + '">' + $('<span>').text(txt).html() + '</span>';
        }

        function esc(v) { return $('<span>').text(v === undefined || v === null ? '-' : v).html(); }

        function labelFor(key) {
            var map = {
                tunnel_state: 'Tunnel state',
                default_route: 'Default IPv4 route',
                wan_alias: 'WAN /128 alias',
                ce_to_aftr: 'CE → AFTR reachability',
                prefix_update: 'Prefix update API',
                internet_v4: 'IPv4 Internet',
                internet_v6: 'IPv6 Internet',
                resolve_a: 'DNS A resolution',
                resolve_aaaa: 'DNS AAAA resolution',
                mtu: 'MTU (config vs actual)',
                mtu_probe: 'MTU DF probe',
                mtu_fragmentation: 'Large packet / fragmentation'
            };
            return map[key] || key;
        }

        function detailFor(c) {
            var parts = [];
            ['detail','source','target','gateway','interface','answer','result','rtt_ms','payload','expected','actual'].forEach(function(k){
                if (c[k] !== undefined && c[k] !== '' && c[k] !== '-') {
                    parts.push('<small class="text-muted">' + k + '=' + esc(c[k]) + '</small>');
                }
            });
            return parts.join(' &middot; ');
        }

        function runDiagnostics() {
            $('#diag_rows').html('<tr><td colspan="3">{{ lang._('Running diagnostics...') }}</td></tr>');
            ajaxGet('/api/dslite/service/diagnostics', {}, function(data, status) {
                if (!data || !data.checks) {
                    $('#diag_rows').html('<tr><td colspan="3" class="text-danger">{{ lang._('Error: no response from backend') }}</td></tr>');
                    return;
                }
                $('#diag_mode').text(data.mode || '-');
                var order = ['tunnel_state','default_route','wan_alias','ce_to_aftr','prefix_update',
                             'internet_v4','internet_v6','resolve_a','resolve_aaaa','mtu','mtu_probe','mtu_fragmentation'];
                var rows = '';
                order.forEach(function(key){
                    var c = data.checks[key];
                    if (!c) return;
                    rows += '<tr><td>' + esc(labelFor(key)) + '</td>' +
                            '<td>' + badge(c.status) + '</td>' +
                            '<td>' + detailFor(c) + '</td></tr>';
                });
                $('#diag_rows').html(rows || '<tr><td colspan="3">{{ lang._('No data') }}</td></tr>');
            });
        }

        // Diagnostics is read-only; it reports the stored result of the last
        // prefix update. Contacting the ISP is an explicit, separate action so
        // that opening or refreshing this page never spends credentials or
        // changes provider-side state.
        function runPrefixUpdate() {
            var $btn = $('#runPrefixUpdate');
            $btn.prop('disabled', true);
            ajaxCall('/api/dslite/service/prefixUpdate', {}, function(data, status) {
                $btn.prop('disabled', false);
                runDiagnostics();
            });
        }

        $('#refreshDiag').click(runDiagnostics);
        $('#runPrefixUpdate').click(runPrefixUpdate);
        runDiagnostics();
    });
</script>

<div class="content-box" style="padding: 10px;">
    <div class="content-box-header">
        <h3>{{ lang._('DS-Lite Diagnostics') }} <small>{{ lang._('mode') }}: <span id="diag_mode">-</span></small></h3>
    </div>
    <div class="content-box-main">
        <button class="btn btn-primary" id="refreshDiag" type="button">
            <i class="fa fa-refresh"></i> {{ lang._('Refresh') }}
        </button>
        <button class="btn btn-default" id="runPrefixUpdate" type="button">
            <i class="fa fa-cloud-upload"></i> {{ lang._('Run prefix update now') }}
        </button>
        <span class="text-muted"><small>{{ lang._('Contacts your ISP and refreshes the Fixed IP registration. Fixed IP mode only.') }}</small></span>
        <hr />
        <table class="table table-striped table-condensed">
            <thead>
                <tr>
                    <th>{{ lang._('Check') }}</th>
                    <th>{{ lang._('Result') }}</th>
                    <th>{{ lang._('Details') }}</th>
                </tr>
            </thead>
            <tbody id="diag_rows">
                <tr><td colspan="3">{{ lang._('Loading...') }}</td></tr>
            </tbody>
        </table>
    </div>
</div>
