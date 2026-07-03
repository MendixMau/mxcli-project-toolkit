'use strict';
const { convertType } = require('../lib/type-converter');

const OS_SYSTEM_ENTITY_MAP = {
  'User':   'Administration.Account',
  'Group':  'System.UserRole',
  'Tenant': 'System.Tenant',
  'NullIdentifier': 'System.NullIdentifier',
};

// ── Binary entity classification ─────────────────────────────────────────────
// A - File:  has file metadata companions (FileName/MimeType/FileSize) OR entity
//            name suggests file storage → EXTENDS System.FileDocument, drop Binary
// B - Blob:  raw binary data (logs, session claims, tokens) with no file metadata
//            → keep Binary attribute as-is (Mendix supports Binary on persistent entities)
// C - Image: binary attribute name or entity name indicates an image/photo/picture
//   C-pure:  entity exists solely to store an image (no non-audit business attrs)
//            → EXTENDS System.Image, drop Binary
//   C-embed: large business entity with a single image attribute
//            → keep entity unchanged, generate a split *_Picture EXTENDS System.Image

const FILE_META_ATTR_RE  = /^(filename|filetype|filecontent|mimetype|filesize|contenttype|binarycontenttype)$/i;
const FILE_ENTITY_RE     = /upload|attach|file/i;  // 'content' removed — too broad (matches RawContent_Log)
const IMAGE_ATTR_RE      = /picture|photo|image|thumbnail|icon/i;
const IMAGE_ENTITY_RE    = /image|picture|photo/i;
const AUDIT_ATTR_RE      = /^(insert_on|update_on|insert_user.*|update_user.*|insert_pgid|update_pgid|update_on_for.*|created_at|updated_at|created_by|updated_by)$/i;

function classifyBinary(item) {
  const binAttrs = item.attributes.filter(a => a.type === 'Binary Data');
  if (binAttrs.length === 0) return null;

  const allNames = item.attributes.map(a => a.name);

  // C — Image: binary attr name or entity name is image-like
  const imageBinAttr = binAttrs.find(a => IMAGE_ATTR_RE.test(a.name));
  if (imageBinAttr || IMAGE_ENTITY_RE.test(item.name)) {
    // Distinguish pure image storage vs. embedded image field in a business entity.
    // Pure: after removing binary, id (autoNumber), FK, and audit columns, nothing remains.
    const businessAttrs = item.attributes.filter(a =>
      !a.isAutoNumber && !a.isForeignKey &&
      a.type !== 'Binary Data' &&
      !AUDIT_ATTR_RE.test(a.name)
    );
    const subtype = businessAttrs.length === 0 ? 'pure' : 'embed';
    const attrName = imageBinAttr ? imageBinAttr.name : binAttrs[0].name;
    return { category: 'C', subtype, imageAttrName: attrName };
  }

  // A — File: companion file-metadata attributes or file-storage entity name
  const hasFileMeta = allNames.some(n => FILE_META_ATTR_RE.test(n));
  if (hasFileMeta || FILE_ENTITY_RE.test(item.name)) {
    return { category: 'A' };
  }

  // B — Blob: raw binary, keep as-is
  return { category: 'B' };
}

// ── Association helper ────────────────────────────────────────────────────────
function makeAssoc(lines, fromModule, fromEntity, toFqn, deleteClause = '') {
  const assocName = `${fromModule}.${fromEntity}_${toFqn.replace('.', '_')}`;
  lines.push(`CREATE ASSOCIATION ${assocName} (`);
  lines.push(`  FROM ${fromModule}.${fromEntity} TO ${toFqn},`);
  lines.push(`  Type: Reference${deleteClause}`);
  lines.push(');\n');
}

// ── Main mapper ───────────────────────────────────────────────────────────────
function mapEntity(item, allEntities) {
  const entityIndex = {};
  for (const e of allEntities) entityIndex[e.name] = e.module;

  const bin = classifyBinary(item);
  const sections = [];

  if (bin?.category === 'C' && bin.subtype === 'embed') {
    // ── C-embed: keep business entity, strip binary attr, generate split image entity + assoc
    const normalAttrs = item.attributes.filter(a =>
      !a.isAutoNumber && !a.isForeignKey && a.type !== 'Binary Data'
    );
    const fkAttrs = item.attributes.filter(a => a.isForeignKey);
    sections.push(...buildEntityLines(item, '', normalAttrs, fkAttrs, entityIndex));

    // Split image entity
    const splitName = `${item.name}_${bin.imageAttrName}`;
    sections.push(`CREATE PERSISTENT ENTITY ${item.module}.${splitName} EXTENDS System.Image (`);
    sections.push(`  -- no non-id attributes; Name=filename, Contents=image bytes`);
    sections.push(');\n');

    const assocLines = [];
    makeAssoc(assocLines, item.module, item.name, `${item.module}.${splitName}`);
    sections.push(...assocLines);

  } else {
    // A, B, C-pure, or no binary
    const extendsClause =
      bin?.category === 'A'      ? ' EXTENDS System.FileDocument' :
      bin?.category === 'C'      ? ' EXTENDS System.Image'        : '';

    const normalAttrs = item.attributes.filter(a =>
      !a.isAutoNumber && !a.isForeignKey &&
      !(extendsClause && a.type === 'Binary Data')   // drop Binary only for A and C-pure
    );
    const fkAttrs = item.attributes.filter(a => a.isForeignKey);
    sections.push(...buildEntityLines(item, extendsClause, normalAttrs, fkAttrs, entityIndex));
  }

  return sections.join('\n') + '\n';
}

function buildEntityLines(item, extendsClause, normalAttrs, fkAttrs, entityIndex) {
  const lines = [`CREATE PERSISTENT ENTITY ${item.module}.${item.name}${extendsClause} (`];
  normalAttrs.forEach((a, i) => {
    const mdlType = convertType(a.type, a.length);
    const notNull  = a.isMandatory ? ' NOT NULL' : '';
    const dflt     = (a.defaultValue && a.defaultValue !== '') ? ` DEFAULT ${a.defaultValue}` : '';
    const comma    = i < normalAttrs.length - 1 ? ',' : '';
    lines.push(`  ${a.name}: ${mdlType}${notNull}${dflt}${comma}`);
  });
  if (normalAttrs.length === 0) lines.push('  -- no non-id attributes');
  lines.push(');\n');

  for (const a of fkAttrs) {
    const ref = a.referencedEntity;
    let refFqn;
    if (OS_SYSTEM_ENTITY_MAP[ref]) {
      refFqn = OS_SYSTEM_ENTITY_MAP[ref];
    } else if (entityIndex[ref]) {
      refFqn = `${entityIndex[ref]}.${ref}`;
    } else {
      refFqn = `${item.module}.${ref} /* UNRESOLVED: ${ref} not found in KB */`;
    }
    const deleteClause = a.deleteRule === 'Delete' ? ' ON DELETE DELETE'
      : a.deleteRule === 'Protect' ? ' ON DELETE RESTRICT' : '';
    lines.push(`CREATE ASSOCIATION ${item.module}.${item.name}_${ref} (`);
    lines.push(`  FROM ${item.module}.${item.name} TO ${refFqn},`);
    lines.push(`  Type: Reference${deleteClause}`);
    lines.push(');\n');
  }
  return lines;
}

module.exports = { mapEntity };
