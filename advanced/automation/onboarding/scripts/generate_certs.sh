#!/bin/bash
set -e

USERNAME=$1
OUTPUT_DIR="output"

if [ -z "$USERNAME" ]; then
  echo "Error: Username is required."
  exit 1
fi

echo "1. Generating Private Key for $USERNAME..."
openssl genrsa -out $OUTPUT_DIR/${USERNAME}.key 2048

echo "2. Generating Certificate Signing Request (CSR)..."
# Subject MUST contain O= (Group) and CN= (User). 
openssl req -new -key $OUTPUT_DIR/${USERNAME}.key -out $OUTPUT_DIR/${USERNAME}.csr -subj "/CN=${USERNAME}/O=fineract-devs"

echo "3. Submitting CSR to Kubernetes..."
# Base64 encode the CSR (using base64 -w 0 to avoid newlines on Linux)
CSR_B64=$(cat $OUTPUT_DIR/${USERNAME}.csr | base64 -w 0)

cat <<EOF | kubectl apply -f -
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: ${USERNAME}-csr
spec:
  request: ${CSR_B64}
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: 8640000
  usages:
  - client auth
EOF

echo "4. Approving the CSR..."
kubectl certificate approve ${USERNAME}-csr

echo "5. Downloading the signed Certificate..."
# Wait for it to be issued
sleep 2
kubectl get csr ${USERNAME}-csr -o jsonpath='{.status.certificate}' | base64 --decode > $OUTPUT_DIR/${USERNAME}.crt

# Clean up the CSR resource from the cluster
kubectl delete csr ${USERNAME}-csr

echo "Certificates generated successfully in $OUTPUT_DIR/"
