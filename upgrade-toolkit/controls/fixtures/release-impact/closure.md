# Release impact: Mendix 9.24.3.8044 to 11.12.5

Closure-rule fixture (QJ-2). Row 230 is verbatim from runs/b5-forms evidence/r2/release-impact-r2full.md; rows 45 (scan), 52 (cites the source default), 231 (not a setting row) and 229 (handled) must stay closed.

## Studio Pro (5 rows)

| # | version | type | area | change | affected | source | handled |
|---|---|---|---|---|---|---|---|
| 230 | 11.0.0 | removal | runtime | Removed deprecated Objects.SetSystemAttributesOnChange runtime setting; system attributes updated on commit only. | Objects.SetSystemAttributesOnChange | [notes](https://docs.mendix.com/releasenotes/studio-pro/11.0/#1100-general-availability) | not relevant: setting never set (0 custom runtime settings in the model (Settings Configurations: Default, CustomSettings []); runapp.py:288 passes only -Dfile.encoding and -Xmx); the app already ran with the default behaviour |
| 45 | 10.0.0 | removal | runtime | Removed deprecated com.mendix.core.UseMimeDecoderForBase64 setting. Base64 decoding is now always strict per RFC 4648. | com.mendix.core.UseMimeDecoderForBase64 | [notes](https://docs.mendix.com/releasenotes/studio-pro/10.0/) | not relevant: setting not set; no microflow calls a Base64 Java action (refs) |
| 52 | 10.0.0 | removal | runtime | Removed custom setting for Mendix Runtime uniqueness validation; database uniqueness validation is now mandatory. | uniqueness validation | [notes](https://docs.mendix.com/releasenotes/studio-pro/10.0/) | not relevant: not set, and the source version already had the new default (database uniqueness validation only since 9.0.5) |
| 231 | 11.0.0 | removal | client-web | Removed mx.logger client API; use window.console logging functions instead. | mx.logger | [notes](https://docs.mendix.com/releasenotes/studio-pro/11.0/) | not relevant: mx.logger not set anywhere; 0 in javascriptsource |
| 229 | 11.0.0 | removal | runtime | Removed deprecated Microflows.RemoveVariableOnDeleteObjectsActivity runtime setting; Delete object activity now always clears list. | Microflows.RemoveVariableOnDeleteObjectsActivity | [notes](https://docs.mendix.com/releasenotes/studio-pro/11.0/) | handled: evidence/delete-list-walk.md (every list used after a Delete walked) |
