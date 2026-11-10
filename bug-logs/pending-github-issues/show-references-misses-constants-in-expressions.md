**Repo:** `mendixlabs/mxcli`
**Source:** field run in an unattended CI harness on a Mendix-internal app (2026-10-14, mxcli v0.24.0), reproduced here 2026-11-05
**Status:** DRAFT — not filed
**Suggested labels:** bug, catalog

---

**Title:** `SHOW REFERENCES TO` misses a constant used inside a microflow expression

**Body:**

## Summary

The catalog's reference graph does not record a constant used as `@Module.Constant` in a
microflow expression. `SHOW REFERENCES TO <constant>` then reports no references for a constant
that is in use, so an impact check reads "unused" before a rename, delete or value change.

## Environment

- mxcli: `v0.30.0` and `nightly-20261105-f3c4d531d`
- Mendix: 11.15.0, small scratch app
- Reproducible: yes

## Steps to reproduce

```
mdl 1;
CREATE CONSTANT MyFirstModule.SenderAddress ( Type: String, DefaultValue: 'noreply@example.com' );
CREATE PERSISTENT ENTITY MyFirstModule.Msg ( Recipient: String(200) );
CREATE MICROFLOW MyFirstModule.ACT_MakeMsg ()
BEGIN
  $M = CREATE MyFirstModule.Msg (Recipient = @MyFirstModule.SenderAddress) COMMIT;
END;
```

```
$ mxcli exec repro.mdl -p App.mpr
$ mxcli -p App.mpr -c "refresh catalog full source"
$ mxcli -p App.mpr -c "SHOW REFERENCES TO MyFirstModule.SenderAddress"
References to MyFirstModule.SenderAddress
(no references found: nothing in the catalog's reference graph points at MyFirstModule.SenderAddress)
$ mxcli search -p App.mpr "SenderAddress" --format names
microflow	MyFirstModule.ACT_MakeMsg
```

## Expected

`MyFirstModule.ACT_MakeMsg` listed as a reference to the constant.

## Workaround

`refresh catalog full source`, then `mxcli search "<ConstantName>"`.
