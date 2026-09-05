#!/usr/bin/env bash
# Oracle — reference fix, used only to validate the task is solvable. Never shown to the agent.
#
# Two independent, coordinated fixes — neither alone makes the cross-repo consistency test pass:
#   1. ChannelForge (/app/app/services/fast.py): origin_urls() puts org_id AFTER output_id
#      instead of before it.
#   2. ssaiadserver (/ssai/packages/data-plane/src/origin.ts): the org id is appended as a
#      "?org=" query string instead of substituted into the template's {org} placeholder.
set -euo pipefail

patch -p1 -d /app <<'PATCH'
--- a/app/services/fast.py
+++ b/app/services/fast.py
@@ -35,8 +35,8 @@
     base = base_url.rstrip("/")
     if org_id:
         return {
-            "master": f"{base}/{output_id}/{org_id}/delivery_master.m3u8",
-            "media": f"{base}/{output_id}/{org_id}/delivery.m3u8",
+            "master": f"{base}/{org_id}/{output_id}/delivery_master.m3u8",
+            "media": f"{base}/{org_id}/{output_id}/delivery.m3u8",
         }
     return {
         "master": f"{base}/{output_id}/delivery_master.m3u8",
PATCH

patch -p1 -d /ssai <<'PATCH'
--- a/packages/data-plane/src/origin.ts
+++ b/packages/data-plane/src/origin.ts
@@ -50,8 +50,11 @@
       opts.urlFor ??
       (pathTemplate
         ? (channel, variant) => {
-            const path = pathTemplate.replace("{channel}", channel).replace("{variant}", variant);
-            return orgId ? `${this.baseUrl}/${path}?org=${orgId}` : `${this.baseUrl}/${path}`;
+            const path = pathTemplate
+              .replace("{org}", orgId ?? "")
+              .replace("{channel}", channel)
+              .replace("{variant}", variant);
+            return `${this.baseUrl}/${path}`;
           }
         : (channel, variant) => `${this.baseUrl}/${channel}/${variant}.m3u8`);
   }
PATCH

cd /ssai && npm run build
