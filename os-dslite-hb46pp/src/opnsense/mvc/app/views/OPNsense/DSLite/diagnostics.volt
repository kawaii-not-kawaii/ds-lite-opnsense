{#
 # Copyright (C) 2024 DS-Lite Plugin Contributors
 # All rights reserved.
 #}

<script>
    $( document ).ready(function() {
        function runDiagnostics() {
            $('#diag_output').text('Running diagnostics...');
            ajaxGet('/api/dslite/service/diagnostics', {}, function(data, status) {
                if (data) {
                    var output = '';
                    if (data.interface) {
                        output += '=== Tunnel Interface ===\n';
                        output += data.interface + '\n\n';
                    }
                    if (data.routes) {
                        output += '=== IPv4 Routes ===\n';
                        output += data.routes + '\n\n';
                    }
                    if (data.ping) {
                        output += '=== Connectivity Test ===\n';
                        output += data.ping + '\n\n';
                    }
                    if (data.ipv6) {
                        output += '=== WAN IPv6 Address ===\n';
                        output += data.ipv6 + '\n\n';
                    }
                    if (data.nat) {
                        output += '=== NAT Rules ===\n';
                        output += data.nat + '\n';
                    }
                    $('#diag_output').text(output || 'No data returned');
                } else {
                    $('#diag_output').text('Error: No response from backend');
                }
            });
        }

        $('#refreshDiag').click(function() {
            runDiagnostics();
        });

        runDiagnostics();
    });
</script>

<div class="content-box" style="padding: 10px;">
    <div class="content-box-header">
        <h3>{{ lang._('DS-Lite Diagnostics') }}</h3>
    </div>
    <div class="content-box-main">
        <button class="btn btn-primary" id="refreshDiag" type="button">
            <i class="fa fa-refresh"></i> {{ lang._('Refresh') }}
        </button>
        <hr />
        <pre id="diag_output" style="max-height: 500px; overflow-y: auto;">Loading...</pre>
    </div>
</div>
