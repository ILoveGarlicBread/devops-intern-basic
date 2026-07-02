import urllib.request
import json

GRAFANA_URL = "http://10.42.1.75:3000"
HEADERS = {
    "Authorization": "Basic YWRtaW46cGFzc3dvcmQ=",
    "Content-Type": "application/json",
    "Accept": "application/json"
}

def search_dashboards():
    req = urllib.request.Request(f"{GRAFANA_URL}/api/search", headers=HEADERS)
    with urllib.request.urlopen(req) as response:
        return json.loads(response.read().decode())

def unprovision_and_delete(uid):
    # Unprovisioning is tricky, usually we can just delete it
    req = urllib.request.Request(f"{GRAFANA_URL}/api/dashboards/uid/{uid}", method="DELETE", headers=HEADERS)
    try:
        urllib.request.urlopen(req)
        print(f"Deleted {uid}")
    except Exception as e:
        print(f"Failed to delete {uid}: {e}")

dashboards = search_dashboards()
for d in dashboards:
    title = d.get("title", "").lower()
    if "ovhcloud" in title or "influx" in title:
        unprovision_and_delete(d["uid"])
