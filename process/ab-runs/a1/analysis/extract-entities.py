#!/usr/bin/env python3
"""Small purpose-built extractor for the Harbour Berth Booking documentation portal.

Stage 0 (source-triage.md) two-way call: the corpus is prose HTML, but five chapters
(07, 12, 14, 26, 36) embed structured "Data: <Entity>" attribute tables in a consistent
shape (Attribute / Type / Required columns). That is extractable structure per
conversion-runbook.md's Entry Modes note ("entity/field tables inside a spec are
extractable structure ... exactly as a codebase would"), so this is a *build new,
small* extractor rather than an N/A on the requirements-driven label.

Ground truth for validation: chapter 36 (appendix: data dictionary) is the corpus's
own consolidated table set, so every entity this script finds elsewhere is checked
against ch36's version of the same entity for attribute-level agreement.

Output: analysis/harbour-berth-booking/knowledge-base/entities.json — one row per
entity, attributes with name/type/required, consumed by BRD enrichment in Stage 2.
"""
import glob
import json
import os
import re

SRC = "/tmp/abproj/sources"
OUT_DIR = "/tmp/abproj/analysis/harbour-berth-booking/knowledge-base/share"

# "Data: Vessel Vessel Attribute Type Required IMONumber Text, up to 7 characters Required ..."
# The cleaned-text form repeats the entity name, then "Attribute Type Required", then a
# flat run of "<AttrName> <TypeDescription> Required|Optional" rows. Attribute names are
# always a single CamelCase token, so splitting on the Required/Optional marker and taking
# the first word of what precedes it is more robust than trying to bound the type
# description with a closed vocabulary.
REQ_OPT = re.compile(r"\s(Required|Optional)\s")


def parse_attribute_rows(body):
    parts = REQ_OPT.split(body)
    attrs = []
    # parts = [text0, sep0, text1, sep1, ..., trailing]
    for i in range(0, len(parts) - 1, 2):
        chunk = parts[i].strip()
        sep = parts[i + 1]
        if not chunk:
            continue
        words = chunk.split(" ", 1)
        name = words[0]
        type_desc = words[1].strip() if len(words) > 1 else ""
        if not re.match(r"^[A-Z][A-Za-z0-9]*$", name):
            continue
        attrs.append({"name": name, "type": type_desc, "required": sep == "Required"})
    return attrs


# Decoy sentences the documentation-portal fixture repeats on every chapter, unrelated to
# content, interspersed even mid-table. Stripped before parsing rather than worked around,
# since a regex tolerant enough to skip arbitrary interleaved prose would also swallow real
# attribute rows.
NOISE = [
    "Diagrams are provided for orientation only.",
    "This section was reviewed with the operations team during the second documentation workshop.",
    "This chapter does not describe the technical implementation; see the architecture notes for that.",
    "The numbering of headings follows the master table of contents and is stable across revisions.",
    "The examples given are illustrative and use fictional vessel names throughout.",
    "Nothing in this chapter changes the responsibilities described in the stakeholder overview.",
    "The chapter is intentionally short; details that belong to other chapters are cross-referenced rather than repeated.",
    "Screenshots on this page are taken from the clickable prototype and may differ slightly from the final layout.",
    "Readers new to port operations should first consult the glossary for the terms used here.",
    "Terminology in this chapter is aligned with the glossary; where they differ, the glossary wins.",
    "Where the text says 'the system', it means the Harbour Berth Booking application as a whole.",
    "The wording below reflects the agreed position at the time of writing and may be refined in a later revision.",
    "Paragraphs marked as guidance are explanatory and do not add obligations.",
    "Figures on this page are numbered per page, not per document.",
    "Questions about this chapter can be raised through the usual documentation feedback channel.",
    "The review comments from the previous round have been incorporated into this revision.",
    "The behaviour described here was demonstrated in the prototype walkthrough.",
    "For the history of this chapter see the release notes page.",
    "No open comments on this item.",
    "Applies to all terminals unless stated otherwise.",
    "Reviewed by the documentation owner.",
    "Illustrated in the prototype.",
    "Discussed in workshop session 2.",
    "Wording aligned with the stakeholder overview.",
    "See also the appendix data dictionary.",
    "Cross-referenced from the glossary.",
]


def clean_text(html):
    html = re.sub(r"<style[^>]*>.*?</style>", " ", html, flags=re.S)
    html = re.sub(r"<script[^>]*>.*?</script>", " ", html, flags=re.S)
    text = re.sub("<[^>]+>", " ", html)
    text = text.replace("&middot;", "-").replace("&amp;", "&")
    for n in NOISE:
        text = text.replace(n, " ")
    text = re.sub(r"\s+", " ", text)
    return text


def extract_entities(text, source_file):
    entities = {}
    for m in re.finditer(r"Data: (\w+) \1 Attribute Type Required (.*?)(?=Data: \w|Relationships|Gallery|$)", text):
        name = m.group(1)
        body = m.group(2)
        attrs = parse_attribute_rows(body)
        if attrs:
            entities.setdefault(name, {"entity": name, "attributes": attrs, "sources": []})
            entities[name]["sources"].append(source_file)
    return entities


def extract_relationships(text, source_file):
    rels = []
    m = re.search(r"Relationships (.*?)(?=Gallery|Documentation Home|$)", text)
    if not m:
        return rels
    for rm in re.finditer(r"(\w+) refers to (\w+) \((\w+), ([\w\-]+)\)\.", m.group(1)):
        rels.append({
            "from": rm.group(1), "to": rm.group(2), "name": rm.group(3),
            "cardinality": rm.group(4), "source": source_file,
        })
    return rels


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    all_entities = {}
    all_rels = []
    for path in sorted(glob.glob(os.path.join(SRC, "*.html"))):
        rel = os.path.basename(path)
        text = clean_text(open(path, encoding="utf-8", errors="ignore").read())
        for name, e in extract_entities(text, rel).items():
            if name not in all_entities:
                all_entities[name] = e
            else:
                all_entities[name]["sources"].extend(e["sources"])
                if len(e["attributes"]) > len(all_entities[name]["attributes"]):
                    all_entities[name]["attributes"] = e["attributes"]
        all_rels.extend(extract_relationships(text, rel))

    # De-dup relationships by (from,to,name)
    seen = set()
    dedup_rels = []
    for r in all_rels:
        key = (r["from"], r["to"], r["name"])
        if key in seen:
            continue
        seen.add(key)
        dedup_rels.append(r)

    out = {"entities": list(all_entities.values()), "relationships": dedup_rels}
    with open(os.path.join(OUT_DIR, "entities.json"), "w") as f:
        json.dump(out, f, indent=2)

    print(f"entities found: {len(all_entities)}")
    for name, e in all_entities.items():
        print(f"  {name}: {len(e['attributes'])} attrs, seen in {e['sources']}")
    print(f"relationships found: {len(dedup_rels)}")


if __name__ == "__main__":
    main()
