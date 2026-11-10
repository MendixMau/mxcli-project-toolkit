#!/usr/bin/env bash
# contract-check.sh — published/consumed service contracts across the Mendix apps of one system:
#                     snapshot them, diff them against the committed snapshot, and say which
#                     consumer apps a change breaks.
#
# WHY THIS EXISTS. mxcli answers every question about ONE .mpr; nothing joins one app's consumer
# to another app's publisher. Measured 2026-11-05 on mxcli v0.28.0: `mxcli impact` and `refs`
# report "no references found" for an entity and an attribute that a published OData service
# exposes, and dropping that attribute from the entity passed `check` and `exec` with zero
# warnings while the service still advertised it. Renaming a published REST resource under an
# unchanged Version also passed both, and the sibling app that called it was broken silently.
# The Mendix Catalog keys a contract on its version, so a breaking change under an unchanged
# version overwrites the contract every environment sees.
#
# THE SYSTEM REGISTRY. One TAB-separated file per system of apps that talk to each other, in the
# same shape as a company brain's projects.tsv (skills/company-brain.md): '#' comments, one row
# per app. Recommended home: <company-brain>/systems/<system>/system.tsv (or a repo of its own
# for the system). Columns:
#   name   letters/digits/_/-; names the snapshot file
#   path   the .mpr, or a project root holding exactly one .mpr at the root (single-tree) or
#          under app/ (two-tree); relative paths resolve against the registry file's folder
#   role   publisher | consumer | both   (documentation; every app is read both ways)
#   url    optional: the app's runtime base URL (e.g. http://localhost:8081). Given, a consumer's
#          base URL host must match it; without it apps are matched on URL path alone, and two
#          apps publishing the same path read AMBIGUOUS.
# Snapshots go to <registry folder>/contracts/<name>.json (--contracts DIR to move them).
# PRODUCER: the registry is written by hand when a second app joins the system (there is no
# mandatory chain step that writes it; with no registry this exits 2 and says so). The snapshots
# are produced by `snapshot` below and must be committed — `check` reads the committed copy.
#
# WHAT IT READS. Per app, two read-only mxcli calls (no builds; mxcli refreshes its own catalog
# cache .mxcli/ beside the .mpr): catalog tables for published OData and REST services and
# operations, business event services and messages, consumed REST services and operations,
# consumed OData services and external entities, attributes, associations, generalizations and
# constants (a base URL held in a constant resolves to its default value); plus `describe odata
# service` for the exposed members, which are RESOLVED against the entity — the step mxcli's own
# impact analysis skips. Engine: bin/lib/contract-check.py.
#
# Usage:
#   bin/contract-check.sh snapshot [--registry FILE] [--contracts DIR] [--app NAME]
#   bin/contract-check.sh check    [--registry FILE] [--contracts DIR] [--baseline auto|git|file]
#   bin/contract-check.sh --impact <app>:<Module.Element>  [--registry FILE]
#       element: Module.Entity, Module.Entity.Attribute, Module.Microflow or Module.Service
# --registry defaults to $MXTK_SYSTEM_REGISTRY, then ./system.tsv. mxcli: $MXCLI, else ./mxcli
# (mxcli.exe first on Windows) beside the app or its parent, else mxcli on PATH.
# Baseline (check): auto = the file as committed at git HEAD when tracked, else the file on disk.
#
# Output rows (check):
#   BREAKING   removed/renamed service, path, operation, entity set or exposed member; a type or
#              KEY change; an exposed member whose attribute is gone; a removed business event
#              message or message attribute
#   VIOLATION  a REST/OData service with BREAKING rows and the same MAJOR version as the baseline
#   DANGLING   an exposed OData member the entity no longer has (current state, baseline or not)
#   ADDITIVE / VERSION   informational
#   EDGE / BROKEN / EXTERNAL / AMBIGUOUS / UNRESOLVED / STALE   the cross-app join: each consumed
#              REST operation and external entity against every OTHER app's published services.
#              BROKEN = a registry app serves that service path but not the operation / entity
#              set / attribute (or the attribute is dangling, or its type differs). EXTERNAL = no
#              registry app serves the path (not a violation). STALE = consumed OData contract
#              major version differs from the publisher's.
#   denominator / summary lines always print; NOT RUN names apps with no baseline.
#
# Exit (snapshot, check): 0 clean · 1 at least one VIOLATION, DANGLING or BROKEN · 2 cannot run
#   (no registry, malformed row, no .mpr, no mxcli, mxcli failed, an app has no baseline).
# Exit (--impact): 0 answered (consumers or none) · 2 cannot run.
#
# WHAT IT CANNOT SEE: business event subscribers are snapshotted and diffed but not joined across
# apps (no subscriber fixture existed); published OData microflow actions and other publish
# kinds are printed as UNPARSED, never silently dropped; external-entity attributes are matched
# by name (a remote name that differs from the local one reads as "not exposed"); REST request
# and response bodies (JSON structures, mappings) are not compared; a change to the source entity
# behind a published VIEW entity (--impact on it reads NOT-EXPOSED); consumers outside the registry.
#
# Field run (2026-11-05, mxcli v0.28.0, Mendix 11.14.0): two copies of mxcli's own
# testdata/testapp-views TestApp — "cars" publishing OData CarOdataApi (VCars: ModelID KEY,
# Brand), REST CarsApi rest/cars/v1 (GET cars) and a business event service; "shop" consuming
# GET /cars over REST and VCars as external entity ECar. See tests/wave2/fixtures/contract-check/
# CAPTURE.txt for the numbers. No real multi-app system was available to this run.
#
# portability-ok: bash 3.2, Python 3 resolved through portable.sh

set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/lib/portable.sh"
case "${1:-}" in -h|--help) sed -n '2,80p' "$0"; exit 0 ;; esac
require_py
exec "$PY" "$(native_path "$HERE/lib/contract-check.py")" "$@"
