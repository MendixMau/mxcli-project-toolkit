# Extractor Quality Loop

This skill governs Stage 2 of the migration pipeline. Read it in full before writing or running
any extractor. It applies to every stack.

## Purpose

Extractors are the foundation of the entire migration. BRDs, domain models, microflows, and pages
all derive from the inventory. A low-quality inventory silently poisons every downstream stage.

This skill enforces a scored quality loop: write extractor → validate → score → fix → repeat,
until the extraction reaches ≥ 95% across all scored dimensions before Stage 3 is allowed.

## The Loop

```
1. Write (or update) the extractor script
2. Run the extractor → emits analysis/<Project>/inventory.json
3. Run the validator → emits analysis/<Project>/extraction-quality.json
4. Print the score report
5. If overall score < 95%:
     - Identify the lowest-scoring dimension
     - Fix the extractor for that gap
     - Go to step 2
6. If overall score ≥ 95%:
     - Write the quality report to analysis/<Project>/extraction-quality.json
     - Mark Stage 2 COMPLETE in PROJECT.md
     - Proceed to Stage 3
```

Never skip the loop. Never hand-patch inventory.json to inflate a score. The validator must be
able to re-derive the ground truth from source files without reading inventory.json.

## The 6 Scored Dimensions

Each dimension is scored 0–100. The overall score is the unweighted average.

### 1. Entity Fields (weight: 1)
**What it checks:** For each primary entity (one per model file), count the fields in the
TypeScript interface (or equivalent ORM class/schema). Compare to what the inventory captured.
- Score = (fields captured / fields in source) × 100
- Exclude synthetic PKs (`id`, `uuid`) — these are always dropped in Mendix
- Exclude payload/response types (Pick<>, Omit<>, extends types) — primary interface only

### 2. Type Accuracy (weight: 1)
**What it checks:** For each captured field, is the Mendix-mapped type correct?
- `string` → `String` ✓
- `number` / `int` → `Decimal` or `Long` ✓
- `boolean` → `Boolean` ✓
- `Date` → `DateTime` ✓
- Known enum name → `Enumeration(Name)` ✓ (cross-file enums must be resolved)
- Union type containing an enum → resolve to the enum, not `String`
- Score = (correctly typed fields / total fields) × 100

### 3. Associations (weight: 1)
**What it checks:** Every FK field (ending in `Id` or named `*_id`) that references a known
entity must appear as an association in `inventory.associations`.
- Aliased FKs (e.g. `contactUserId` → `User`, `senderId` → `User`) must be manually listed
  in an `FK_ALIASES` map in the validator
- Score = (FK fields with a matching association / total FK fields) × 100

### 4. Enumerations (weight: 1)
**What it checks:** Every `enum` in the source (including cross-file imports used by primary
interfaces) appears in `inventory.enumerations` with the correct values.
- Score = (enums captured with correct values / total source enums) × 100

### 5. Endpoints (weight: 1)
**What it checks:** Every HTTP route defined in the backend (across all route files AND any
non-standard auth/middleware files that define routes) appears in `inventory.endpoints`.
- Score = (endpoints captured / total source endpoints) × 100
- Method + path must both be correct

### 6. Test Coverage Classification (weight: 0.5 — lower weight, classification is harder)
**What it checks:** Every test spec file is classified to the correct capability.
- Score = (correctly classified spec files / total spec files) × 100
- "Other" or "Unknown" classification counts as incorrect

**Overall score = sum(dimension_score × weight) / sum(weights)**

## What Is Explicitly NOT Scored

The following are intentionally excluded — they belong in BRDs and human review, not the
automated inventory:

- Business logic (password hashing, balance calculations, transaction debit/credit)
- Validation rules (field constraints, uniqueness checks)
- UI component mapping (which React component maps to which Mendix widget)
- Authentication provider specifics (Auth0 config, Okta settings)
- Discriminated union subtypes (e.g. PaymentNotification vs LikeNotification) — capture the
  base type; subtype fields are documented in the BRD

Noting these as "BRD-only" in the quality report is correct and expected.

## Output Format: extraction-quality.json

```json
{
  "project": "ProjectName",
  "scoredAt": "ISO timestamp",
  "overallScore": 94.2,
  "passed": false,
  "threshold": 95,
  "dimensions": {
    "entityFields":   { "score": 98.0, "found": 49, "expected": 50, "gaps": ["User.avatar missing"] },
    "typeAccuracy":   { "score": 92.0, "found": 46, "expected": 50, "gaps": ["Transaction.requestStatus typed as String, should be Enumeration(TransactionRequestStatus)"] },
    "associations":   { "score": 90.0, "found": 9,  "expected": 10, "gaps": ["Contact.contactUserId not mapped to User"] },
    "enumerations":   { "score": 100,  "found": 6,  "expected": 6,  "gaps": [] },
    "endpoints":      { "score": 90.0, "found": 27, "expected": 30, "gaps": ["POST /login missing", "POST /logout missing", "GET /checkAuth missing"] },
    "testCoverage":   { "score": 100,  "found": 21, "expected": 21, "gaps": [] }
  },
  "brdOnly": [
    "Password hashing on User creation (bcrypt, 10 rounds)",
    "Balance debit/credit logic on Transaction completion",
    "Notification subtype fields: PaymentNotification.status, LikeNotification.likeId, CommentNotification.commentId"
  ]
}
```

## Validator Requirements

The validator for a stack must:

1. **Derive ground truth from source files directly** — not from inventory.json
2. **Resolve cross-file enum imports** — follow import chains to find enum definitions
3. **Maintain a `FK_ALIASES` map** — for FKs whose name doesn't match the target entity name
4. **Glob all route-defining files** — not just `*-routes.ts`; include auth, middleware, app.ts
5. **Be runnable standalone** — `ts-node validator.ts --source <path> --inventory <path>`
6. **Exit code 0** if score ≥ threshold, **exit code 1** if below — so `run.sh` can loop

## run.sh Requirements

Every stack extractor directory must contain a `run.sh` that:

1. Runs the extractor
2. Runs the validator
3. Prints the score report
4. Exits 0 if ≥ 95%, exits 1 if below (so CI can enforce the gate)

```bash
#!/usr/bin/env bash
set -e
SOURCE=${1:?Usage: run.sh <source-path> <out-path>}
OUT=${2:?Usage: run.sh <source-path> <out-path>}

echo "=== Running extractor ==="
npx ts-node extractor.ts --source "$SOURCE" --out "$OUT"

echo ""
echo "=== Running validator ==="
npx ts-node validator.ts --source "$SOURCE" --inventory "$OUT/inventory.json" --out "$OUT"

echo ""
cat "$OUT/extraction-quality.json" | npx ts-node -e "
  const fs = require('fs');
  const q = JSON.parse(fs.readFileSync(process.argv[1]));
  // ... pretty-print score table
"
```

## Rules for New Stacks

When starting an extractor for a stack not yet in `extractors/`:

1. Create `extractors/<stack>/extractor.ts`
2. Create `extractors/<stack>/validator.ts` following the interface above
3. Create `extractors/<stack>/run.sh`
4. Document the `FK_ALIASES` map for that stack's FK naming conventions
5. Run the loop — do not proceed to Stage 3 below 95%

The validator is as important as the extractor. Writing the extractor without the validator
is a pipeline violation.
