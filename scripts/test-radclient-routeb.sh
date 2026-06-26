#!/usr/bin/env bash
set -euo pipefail
cat > /tmp/rb.txt <<'EOF'
User-Name = "testuser"
User-Password = "User@123"
NAS-IP-Address = 127.0.0.1
TunnelGroupName = "demo_agent"
EOF
radclient -x 157.15.107.244:1812 auth testing123 < /tmp/rb.txt
