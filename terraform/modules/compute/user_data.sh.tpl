#!/bin/bash
# =============================================================================
# USER DATA TEMPLATE — modules/compute/user_data.sh.tpl
# =============================================================================
set -euo pipefail

dnf update -y

# Ensure SSM Agent is running (pre-installed on AL2023, this guarantees it)
systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent

%{ if tier == "web" ~}
# ── WEB TIER ────────────────────────────────────────────────────────────────
# Añadimos 'php' a la instalación para poder hacer contenido dinámico
dnf install -y httpd php

# Fetch instance metadata using IMDSv2 (token-based, required by our IMDSv2 config)
TOKEN=$(curl -sf -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")

INSTANCE_ID=$(curl -sf -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/instance-id)

PRIVATE_IP=$(curl -sf -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/local-ipv4)

AZ=$(curl -sf -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/placement/availability-zone)

REGION=$(curl -sf -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/placement/region)

HOSTNAME=$(hostname -f)

# ATENCIÓN: Ahora creamos un archivo .php en lugar de .html
cat > /var/www/html/index.php <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>TFG &mdash; Ignacio Colas</title>
  <style>
    /* ... (Mantén aquí exactamente el mismo CSS que ya tenías, no lo he borrado para no alargar el código) ... */
    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
    body { font-family: 'Segoe UI', system-ui, sans-serif; background: #0f172a; color: #e2e8f0; min-height: 100vh; display: flex; align-items: center; justify-content: center; }
    .card { background: #1e293b; border: 1px solid #334155; border-radius: 12px; padding: 2rem 2.5rem; max-width: 550px; width: 90%; box-shadow: 0 4px 32px rgba(0,0,0,0.4); }
    h1 { font-size: 1.4rem; font-weight: 700; color: #38bdf8; margin-bottom: 0.25rem; }
    .subtitle { font-size: 0.8rem; color: #64748b; margin-bottom: 1.75rem; text-transform: uppercase; letter-spacing: 0.08em; }
    table { width: 100%; border-collapse: collapse; }
    tr + tr td { border-top: 1px solid #1e3a5f22; }
    td { padding: 0.6rem 0; font-size: 0.875rem; }
    td:first-child { color: #64748b; width: 38%; padding-right: 1rem; }
    td:last-child { color: #f1f5f9; font-family: 'Courier New', monospace; }
    .badge { display: inline-block; background: #0ea5e908; border: 1px solid #0ea5e9; color: #38bdf8; border-radius: 999px; padding: 0.1rem 0.6rem; font-size: 0.7rem; font-weight: 600; margin-bottom: 1.5rem; }
    .success { color: #22c55e !important; }
    .error { color: #ef4444 !important; font-weight: bold; }
  </style>
</head>
<body>
  <div class="card">
    <h1>TFG &mdash; Ignacio Colas</h1>
    <p class="subtitle">Trabajo de Fin de Grado &middot; AWS Architecture PoC</p>
    <span class="badge">Web tier &middot; Dynamic PHP Response</span>
    <table>
      <tr><td>Web Instance</td><td>${instance_name}</td></tr>
      <tr><td>Web AZ</td><td>$AZ</td></tr>
      <tr><td>Web Region</td><td>$REGION</td></tr>
      
      <?php
        // Escapamos las variables de PHP con barra invertida para que Bash no las interprete al crear el archivo
        \$app_url = "http://${app_private_ip}:${app_port}";
        
        // Timeout de 2 segundos para no colgar la web si la App muere
        \$ctx = stream_context_create(array('http'=>array('timeout' => 2)));
        \$app_response = @file_get_contents(\$app_url, false, \$ctx);
        
        if (\$app_response === FALSE) {
            // ===> ESTA ES LA LÍNEA NUEVA QUE DESPIERTA A CLOUDWATCH <===
            http_response_code(500); 
            echo "<tr><td>App Tier Status</td><td class='error'>Connection Failed / Timeout</td></tr>";
        } else {
            \$data = json_decode(\$app_response, true);
            echo "<tr><td>App Tier Status</td><td class='success'>200 OK &middot; Connected to " . htmlspecialchars(\$data['instance']) . "</td></tr>";
            echo "<tr><td>App AZ</td><td>" . htmlspecialchars(\$data['az']) . "</td></tr>";
        }
      ?>
      </table>
  </div>
</body>
</html>
EOF

# ── SHALLOW HEALTH CHECK FILE (Gray Failure / Chaos Engineering) ─────────────
# This static file is the ONLY target the ALB health check will probe.
# It returns HTTP 200 as long as Apache is running — regardless of whether
# the PHP app can reach the backend App tier.
# Experiment: kill all App instances → ALB keeps routing to Web instances
# (health check still passes) but end-users see "Connection Failed" in the UI.
# This simulates a real-world gray failure invisible to the load balancer.
echo "OK" > /var/www/html/health.html

systemctl enable httpd
systemctl start httpd

%{ else ~}
# ── APP TIER ────────────────────────────────────────────────────────────────
dnf install -y python3

mkdir -p /opt/app

cat > /opt/app/index.html <<'JSON_EOF'
{"status":"ok","tier":"app","instance":"${instance_name}","az":"${availability_zone}"}
JSON_EOF

cat > /etc/systemd/system/app-server.service <<'SVC_EOF'
[Unit]
Description=TFG App Tier HTTP Server
After=network.target

[Service]
Type=simple
User=nobody
WorkingDirectory=/opt/app
ExecStart=/usr/bin/python3 -m http.server ${app_port}
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
SVC_EOF

systemctl daemon-reload
systemctl enable app-server
systemctl start app-server

%{ endif ~}