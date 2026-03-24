{#
 # DS-Lite / Fixed IP Plugin with HB46PP Auto-Provisioning
 #}

<script>
    // Advanced fields per mode
    var dsliteAdvanced = ['dslite\\.isp_profile', 'dslite\\.aftr_hostname', 'dslite\\.aftr_address',
                          'dslite\\.b4_address', 'dslite\\.aftr_v4_address'];
    var fixedipAdvanced = ['dslite\\.fixedip_interface_id', 'dslite\\.fixedip_aftr', 'dslite\\.fixedip_v4'];
    var allAdvanced = dsliteAdvanced.concat(fixedipAdvanced);

    $(document).ready(function() {
        mapDataToFormUI({'frm_general_settings':"/api/dslite/settings/get"}).done(function(){
            formatTokenizersUI();
            $('.selectpicker').selectpicker('refresh');
            updateModeFields();
        });

        $('#dslite\\.mode').on('changed.bs.select', updateModeFields);

        function updateModeFields() {
            var mode = $('#dslite\\.mode').val();
            allAdvanced.forEach(function(f) { $('#' + f).closest('tr').hide(); });

            // Provisioning credentials only needed for Fixed IP
            if (mode === 'dslite') {
                $('#dslite\\.hb46pp_user').closest('tr').hide();
                $('#dslite\\.hb46pp_pass').closest('tr').hide();
            } else {
                $('#dslite\\.hb46pp_user').closest('tr').show();
                $('#dslite\\.hb46pp_pass').closest('tr').show();
            }
        }

        function setStatus(text, icon, badge) {
            $('#tunnel_status').html('<span class="label ' + badge + '">' + text + '</span>');
            $('#status_icon').attr('class', 'fa ' + icon);
        }

        $("#saveAct").SimpleActionButton({
            onPreAction: function() {
                const dfObj = new $.Deferred();
                setStatus('Provisioning...', 'fa-spinner fa-spin text-warning', 'label-warning');
                $('#tunnel_connectivity').text('configuring...');
                saveFormToEndpoint("/api/dslite/settings/set", 'frm_general_settings', function(){
                    dfObj.resolve();
                });
                return dfObj;
            },
            onAction: function() {
                ajaxCall("/api/dslite/service/reconfigure", {}, function() {
                    updateServiceControlUI('dslite');
                    setTimeout(refreshStatus, 3000);
                    setTimeout(refreshStatus, 8000);
                    setTimeout(refreshStatus, 15000);
                });
            }
        });

        function refreshStatus() {
            ajaxGet('/api/dslite/service/status', {}, function(data) {
                if (!data || !data.tunnel) return;
                var t = data.tunnel;
                if (t.status === 'up' && t.connectivity === 'connected') {
                    setStatus('Connected', 'fa-check-circle text-success', 'label-success');
                } else if (t.status === 'up') {
                    setStatus('Tunnel Up (No Internet)', 'fa-exclamation-circle text-warning', 'label-warning');
                } else if (t.status === 'disabled') {
                    setStatus('Disabled', 'fa-minus-circle text-muted', 'label-default');
                } else {
                    setStatus('Not Running', 'fa-circle text-danger', 'label-danger');
                }
                $('#tunnel_connectivity').text(t.connectivity === 'connected' ? 'OK' : (t.connectivity || '-'));
                $('#tunnel_local_v6').text(t.local_v6 || '-');
                $('#tunnel_aftr').text(t.aftr || '-');
                $('#tunnel_ipv4').text(t.ipv4 || '-');
                $('#tunnel_mtu').text(t.mtu || '-');
                if (t.reason) { $('#tunnel_reason').text(t.reason).parent().show(); }
                else { $('#tunnel_reason').parent().hide(); }
            });
        }

        refreshStatus();
        setInterval(refreshStatus, 10000);
        updateServiceControlUI('dslite');
    });
</script>

<div class="content-box" style="padding: 10px;">
    <h3>{{ lang._('Tunnel Status') }}</h3>
    <table class="table table-condensed">
        <tbody>
            <tr><td style="width:150px"><strong>Status</strong></td><td><i id="status_icon" class="fa fa-circle text-muted"></i> <span id="tunnel_status"><span class="label label-default">Loading...</span></span></td></tr>
            <tr><td><strong>Connectivity</strong></td><td><span id="tunnel_connectivity">-</span></td></tr>
            <tr><td><strong>Local IPv6</strong></td><td><span id="tunnel_local_v6">-</span></td></tr>
            <tr><td><strong>AFTR</strong></td><td><span id="tunnel_aftr">-</span></td></tr>
            <tr><td><strong>IPv4</strong></td><td><span id="tunnel_ipv4">-</span></td></tr>
            <tr><td><strong>MTU</strong></td><td><span id="tunnel_mtu">-</span></td></tr>
            <tr style="display:none"><td><strong>Info</strong></td><td><span id="tunnel_reason" class="text-warning"></span></td></tr>
        </tbody>
    </table>
</div>

<div class="content-box" style="padding: 10px;">
    {{ partial("layout_partials/base_form",['fields':generalForm,'id':'frm_general_settings'])}}
    <div class="col-md-12">
        <hr />
        <button class="btn btn-primary" id="saveAct"
                data-endpoint='/api/dslite/service/reconfigure'
                data-label="{{ lang._('Apply') }}"
                data-error-title="{{ lang._('Error configuring tunnel') }}"
                type="button">
        </button>
    </div>
</div>
