#!/bin/bash
# =============================================================================
# USER DATA TEMPLATE — modules/compute/user_data.sh.tpl
#
# Fase 2: La capa Web ya no apunta a una IP privada estática de la capa App.
# En su lugar, apunta al DNS del Internal ALB que balancea entre todos los
# nodos App del ASG. Variable de plantilla: app_internal_alb_dns
# =============================================================================
set -euo pipefail

dnf update -y

# SSM Agent — preinstalado en AL2023, pero lo forzamos por si acaso
systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent

%{ if tier == "web" ~}
# ── WEB TIER ────────────────────────────────────────────────────────────────
dnf install -y httpd php

# Metadatos IMDSv2 (token obligatorio por configuración del Launch Template)
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

# Fase 2: app_private_ip reemplazada por app_internal_alb_dns
# La URL del Internal ALB es estable aunque las IPs de las instancias App cambien.
cat > /var/www/html/index.php <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>TFG &mdash; Ignacio Colas</title>
  <style>
    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
    body { font-family: 'Segoe UI', system-ui, sans-serif; background: #0f172a; color: #e2e8f0; min-height: 100vh; display: flex; align-items: center; justify-content: center; }
    .card { background: #1e293b; border: 1px solid #334155; border-radius: 12px; padding: 2rem 2.5rem; max-width: 580px; width: 90%; box-shadow: 0 4px 32px rgba(0,0,0,0.4); }
    h1 { font-size: 1.4rem; font-weight: 700; color: #38bdf8; margin-bottom: 0.25rem; }
    .subtitle { font-size: 0.8rem; color: #64748b; margin-bottom: 1.75rem; text-transform: uppercase; letter-spacing: 0.08em; }
    table { width: 100%; border-collapse: collapse; }
    tr + tr td { border-top: 1px solid #1e3a5f22; }
    td { padding: 0.6rem 0; font-size: 0.875rem; }
    td:first-child { color: #64748b; width: 40%; padding-right: 1rem; }
    td:last-child { color: #f1f5f9; font-family: 'Courier New', monospace; }
    .badge { display: inline-block; background: #0ea5e908; border: 1px solid #0ea5e9; color: #38bdf8; border-radius: 999px; padding: 0.1rem 0.6rem; font-size: 0.7rem; font-weight: 600; margin-bottom: 1.5rem; }
    .success { color: #22c55e !important; }
    .error { color: #ef4444 !important; font-weight: bold; }
  </style>
</head>
<body>
  <div class="card">
    <h1>TFG &mdash; Ignacio Colas</h1>
    <p class="subtitle">Trabajo de Fin de Grado &middot; AWS Architecture PoC &middot; Fase 2 DR</p>
    <span class="badge">Web Tier &middot; ASG &middot; Internal ALB</span>
    <table>
      <tr><td>Instance ID</td><td>$INSTANCE_ID</td></tr>
      <tr><td>Availability Zone</td><td>$AZ</td></tr>
      <tr><td>Region</td><td>$REGION</td></tr>
      <tr><td>Private IP</td><td>$PRIVATE_IP</td></tr>
      <tr><td>App Internal ALB</td><td>${app_internal_alb_dns}</td></tr>
      <?php
        // Fase 2: apunta al DNS del Internal ALB en lugar de a una IP estática.
        // Esto es correcto con ASG porque las IPs cambian con cada escaldo/reemplazo.
        \$app_url = "http://${app_internal_alb_dns}:${app_port}";

        // Timeout de 3 segundos para no bloquear la web si el App tier falla
        \$ctx = stream_context_create(array('http'=>array('timeout' => 3)));
        \$app_response = @file_get_contents(\$app_url, false, \$ctx);

        if (\$app_response === FALSE) {
            // HTTP 500 despierta las alarmas de CloudWatch para el experimento
            http_response_code(500);
            echo "<tr><td>App Tier Status</td><td class='error'>Connection Failed / Timeout</td></tr>";
        } else {
            \$data = json_decode(\$app_response, true);
            echo "<tr><td>App Tier Status</td><td class='success'>200 OK &middot; " . htmlspecialchars(\$data['instance'] ?? 'unknown') . "</td></tr>";
            echo "<tr><td>App AZ</td><td>" . htmlspecialchars(\$data['az'] ?? 'unknown') . "</td></tr>";
        }
      ?>
    </table>
  </div>
</body>
</html>
EOF

# ── Health Check estático (Gray Failure / Chaos Engineering) ──────────────────
# El ALB público solo comprueba este archivo. Si httpd está vivo, la instancia
# pasa el health check aunque la App tier esté caída (gray failure observable).
echo "OK" > /var/www/html/health.html

systemctl enable httpd
systemctl start httpd

%{ else ~}
# ── APP TIER ────────────────────────────────────────────────────────────────
dnf install -y python3

mkdir -p /opt/app

# El JSON de respuesta incluye instance_id y az (obtenidos de IMDS)
TOKEN=$(curl -sf -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")

INSTANCE_ID=$(curl -sf -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/instance-id)

AZ=$(curl -sf -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/placement/availability-zone)

# El contenido se genera dinámicamente con los metadatos reales de la instancia
cat > /opt/app/index.html <<JSON_EOF
{"status":"ok","tier":"app","instance":"$INSTANCE_ID","az":"$AZ"}
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