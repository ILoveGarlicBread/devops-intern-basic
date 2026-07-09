#!/usr/bin/env python3
import sys
import yaml
import base64
import subprocess
import os

if len(sys.argv) != 2:
    print("Usage: build_kubeconfig.py <username>")
    sys.exit(1)

username = sys.argv[1]
output_dir = "output"
kubeconfig_path = f"{output_dir}/{username}-kubeconfig.yaml"

def read_file_b64(filepath):
    with open(filepath, "rb") as f:
        return base64.b64encode(f.read()).decode("utf-8")

# Get Cluster Info from current context
try:
    cluster_ca = subprocess.check_output(
        "kubectl config view --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}'", 
        shell=True).decode("utf-8").strip()
    server_url = subprocess.check_output(
        "kubectl config view --raw -o jsonpath='{.clusters[0].cluster.server}'", 
        shell=True).decode("utf-8").strip()
    cluster_name = subprocess.check_output(
        "kubectl config view --raw -o jsonpath='{.clusters[0].name}'", 
        shell=True).decode("utf-8").strip()
except Exception as e:
    print(f"Error fetching cluster details: {e}")
    sys.exit(1)

# Read the generated keys
try:
    client_cert = read_file_b64(f"{output_dir}/{username}.crt")
    client_key = read_file_b64(f"{output_dir}/{username}.key")
except FileNotFoundError as e:
    print(f"Keys not found. Did the bash script run? {e}")
    sys.exit(1)

# Build the YAML dictionary
config = {
    "apiVersion": "v1",
    "kind": "Config",
    "preferences": {},
    "current-context": f"{username}-context",
    "clusters": [
        {
            "name": cluster_name,
            "cluster": {
                "certificate-authority-data": cluster_ca,
                "server": server_url
            }
        }
    ],
    "users": [
        {
            "name": username,
            "user": {
                "client-certificate-data": client_cert,
                "client-key-data": client_key
            }
        }
    ],
    "contexts": [
        {
            "name": f"{username}-context",
            "context": {
                "cluster": cluster_name,
                "namespace": "fineract",
                "user": username
            }
        }
    ]
}

with open(kubeconfig_path, "w") as f:
    yaml.dump(config, f, default_flow_style=False)

print(f"Kubeconfig built successfully at {kubeconfig_path}")
