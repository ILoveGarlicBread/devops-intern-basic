#!/bin/sh
echo "Patching default API URL to point to our local Fineract server..."
sed -i 's|https://demo.mifos.io|https://localhost:8443|g' /usr/share/nginx/html/scripts/routes-initialTasks-webstorage-configuration.*.js
