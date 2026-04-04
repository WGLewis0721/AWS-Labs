#!/bin/bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <bucket> <prefix>" >&2
  exit 1
fi

BUCKET="$1"
PREFIX="${2%/}"
KEY_PATH="${KEY_PATH:-/home/ec2-user/tgw-lab-key.pem}"
WORK_DIR="${WORK_DIR:-/home/ec2-user/tgw-bootstrap}"
BUNDLE_PATH="$WORK_DIR/nginx-al2023-bundle.tgz"
RPM_DIR="$WORK_DIR/nginx-rpms"
BOOTSTRAP_SCRIPT_LOCAL="$WORK_DIR/nginx-bootstrap-node.sh"

mkdir -p "$WORK_DIR" "$RPM_DIR"

chmod 600 "$KEY_PATH"

aws s3 cp "s3://$BUCKET/$PREFIX/nginx-al2023-bundle.tgz" "$BUNDLE_PATH" >/dev/null
aws s3 cp "s3://$BUCKET/$PREFIX/nginx-bootstrap-node.sh" "$BOOTSTRAP_SCRIPT_LOCAL" >/dev/null
chmod +x "$BOOTSTRAP_SCRIPT_LOCAL"

rm -rf "$RPM_DIR"
mkdir -p "$RPM_DIR"
tar -xzf "$BUNDLE_PATH" -C "$RPM_DIR"

nodes=(
  "b1:10.1.3.10"
  "c1_portal:10.2.2.10"
  "c2_gateway:10.2.3.10"
  "c3_controller:10.2.4.10"
)

for node in "${nodes[@]}"; do
  role="${node%%:*}"
  host="${node##*:}"

  scp -i "$KEY_PATH" \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o ConnectTimeout=10 \
    "$BOOTSTRAP_SCRIPT_LOCAL" \
    "$BUNDLE_PATH" \
    "ec2-user@$host:/home/ec2-user/" >/dev/null

  ssh -i "$KEY_PATH" \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o ConnectTimeout=10 \
    "ec2-user@$host" \
    "rm -rf /home/ec2-user/nginx-rpms && mkdir -p /home/ec2-user/nginx-rpms && \
     tar -xzf /home/ec2-user/nginx-al2023-bundle.tgz -C /home/ec2-user/nginx-rpms && \
     bash /home/ec2-user/nginx-bootstrap-node.sh --role $role --rpm-dir /home/ec2-user/nginx-rpms"

  echo "Bootstrapped $role on $host"
done
