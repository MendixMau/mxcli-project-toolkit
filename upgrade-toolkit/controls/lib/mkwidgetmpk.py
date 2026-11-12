#!/usr/bin/env python3
"""mkwidgetmpk.py: a minimal widget package (.mpk) with the package.xml shape of the real ones (NS-6 controls).

  mkwidgetmpk.py <out.mpk> <clientModule name> <version> [<appstore id>]

With an appstore id the package also carries the "appstore.id" entry the Marketplace adds (Badge.mpk had 36 bytes of
it before notification-service 3fbf1566, where mx convert to 11.12.4 stripped it from 23 packages; NS-10).

The shape is copied from notification-service widgets/com.mendix.widget.web.Datagrid.mpk (2.28.3 before cdd62cc5,
2.30.6 after): package.xml with a clientModule name and version, nothing else.
"""
import os, sys, zipfile

out, name, ver = sys.argv[1:4]
appid = sys.argv[4] if len(sys.argv) > 4 else ""
os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
with zipfile.ZipFile(out, "w") as z:
    z.writestr("package.xml", f'<?xml version="1.0" encoding="utf-8"?>\n<package xmlns="http://www.mendix.com/package/1.0/">\n'
                              f'  <clientModule name="{name}" version="{ver}" xmlns="http://www.mendix.com/clientModule/1.0/">\n'
                              f'    <widgetFiles/>\n  </clientModule>\n</package>\n')
    if appid:
        z.writestr("appstore.id", appid)
