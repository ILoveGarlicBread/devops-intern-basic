#!/bin/bash

# Suppress the "Defaulted container" warning from kubectl
export KUBECTL_EXEC_QUIET=true

echo "Fetching the latest snapshot from Elasticsearch S3 repository (s3_backup)..."

# Query Elasticsearch for the latest snapshot, suppress stderr to avoid polluting jq
LATEST_SNAPSHOT=$(kubectl exec -n logging elasticsearch-master-0 -c elasticsearch -- curl -s -X GET "localhost:9200/_snapshot/s3_backup/_all" 2>/dev/null | jq -r '.snapshots[-1].snapshot')

if [ -z "$LATEST_SNAPSHOT" ] || [ "$LATEST_SNAPSHOT" == "null" ]; then
    echo "Error: No snapshots found in s3_backup repository!"
    exit 1
fi

echo "Found latest snapshot: $LATEST_SNAPSHOT"
echo "Triggering restore process for fineract-logs..."

# Trigger the restore
kubectl exec -n logging elasticsearch-master-0 -c elasticsearch -- curl -s -X POST "localhost:9200/_snapshot/s3_backup/$LATEST_SNAPSHOT/_restore" -H 'Content-Type: application/json' -d'
{
  "indices": "fineract-logs-*",
  "ignore_unavailable": true,
  "include_global_state": false,
  "rename_pattern": "fineract-logs-(.+)",
  "rename_replacement": "restored-fineract-logs-$1"
}' 2>/dev/null

echo ""
echo "Restore request sent successfully!"
echo "Elasticsearch is now downloading the index from S3."
echo "Check your Kibana dashboard for the restored-fineract-logs-* index patterns."
