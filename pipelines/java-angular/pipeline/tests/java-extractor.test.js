'use strict';
// Golden input: tests/fixtures/openwms/ is a verbatim, unedited copy of nine files from the
// open-source OpenWMS services (Apache-2.0, LICENSE alongside; openwms.org), trimmed only by
// file selection: one controller per service, the constants/interfaces/impl it reaches, and
// three enums. Expected counts below were taken by grep over those files, never from the
// extractor's output. Issues #637 (endpoints) and #639 (enum _source / nested names).
const { test } = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync } = require('child_process');

const PIPE = path.join(__dirname, '..');
const FIX = path.join(__dirname, 'fixtures', 'openwms');
const SVC_LIB = path.join(FIX, 'org.openwms.common.service.lib', 'src', 'main', 'java');
const TMS = path.join(FIX, 'openwms-tms', 'src', 'main', 'java');
const CORE = path.join(FIX, 'openwms', 'org.openwms.core.util', 'src', 'main', 'java');

function extract(srcDir, tag) {
  const kb = fs.mkdtempSync(path.join(os.tmpdir(), 'ja-kb-'));
  execFileSync(process.execPath, [path.join(PIPE, 'extractors', 'java-extractor.js'), srcDir, kb, tag], { env: { ...process.env, MODULE_BASE_PACKAGE: '' } });
  return { kb, data: JSON.parse(fs.readFileSync(path.join(kb, 'extracted', `java-${tag}.json`), 'utf8')) };
}

test('#637 controller in package location, service impl in package impl: all 13 mappings land', () => {
  const { data } = extract(SVC_LIB, 'svc');
  const ec = data.meta.endpointCoverage;
  assert.strictEqual(ec.expected, 13, 'grep counts 13 @*Mapping in LocationController.java');
  assert.strictEqual(ec.captured, 13);
  assert.strictEqual(ec.pathUnresolved, 0);
  const eps = data.items.filter(i => i.type === 'logic' && i.httpEndpoint);
  assert.strictEqual(eps.length, 13);
  // Constant expressions resolved: API_LOCATIONS = "/" + API_VERSION + "/locations"
  assert.ok(eps.every(e => e.httpEndpoint.path.startsWith('/v1/location')), eps.map(e => e.httpEndpoint.path).join(','));
  const create = eps.find(e => e.name === 'createLocation');
  assert.deepStrictEqual(create.httpEndpoint, { method: 'POST', path: '/v1/locations' });
  // Joined to LocationServiceImpl.create by injected field type, across packages
  assert.deepStrictEqual(create.delegatesTo, ['java:logic:impl:LocationServiceImpl.create']);
  // Overloaded handlers are two endpoints, not one overwritten map entry
  const changeState = eps.filter(e => e.label === 'changeState');
  assert.strictEqual(changeState.length, 3, 'LocationController declares changeState three times (lines 173, 183, 199)');
  assert.strictEqual(new Set(changeState.map(e => e.uniqueId)).size, 3);
  assert.deepStrictEqual(changeState[0].httpEndpoint, { method: 'PATCH', path: '/v1/location/{pKey}', params: ['op=change-state'] });
  // Overloaded service methods survive too (LocationServiceImpl declares changeState twice)
  const svcChangeState = data.items.filter(i => i.uniqueId && /^java:impl\.LocationServiceImpl\.changeState(~\d+)?$/.test(i.uniqueId));
  assert.strictEqual(svcChangeState.length, 2);
});

test('#637 Class.CONSTANT paths resolve; an unresolvable delegate is a gap, not silence', () => {
  const { data } = extract(TMS, 'tms');
  const ec = data.meta.endpointCoverage;
  assert.strictEqual(ec.expected, 6, 'grep counts 6 @*Mapping in TransportationController.java');
  assert.strictEqual(ec.captured, 6);
  const eps = data.items.filter(i => i.httpEndpoint);
  assert.ok(eps.every(e => e.httpEndpoint.path.startsWith('/v1/transport-orders')));
  // TransportationFacade/Service impls are not in this trimmed fixture -> flagged
  assert.ok(eps.every(e => e._gaps.includes('endpoint-delegate-unresolved')));
});

test('#639 enums carry _source/sourceRef; nested enums are qualified by their outer type', () => {
  const svc = extract(SVC_LIB, 'svc').data.items.filter(i => i.type === 'staticEntity');
  const tms = extract(TMS, 'tms').data.items.filter(i => i.type === 'staticEntity');
  const core = extract(CORE, 'core').data.items.filter(i => i.type === 'staticEntity');
  for (const e of [...svc, ...tms, ...core]) {
    assert.ok(e._source && fs.existsSync(e._source), `${e.name} has _source`);
    assert.ok(e.sourceRef, `${e.name} has sourceRef`);
  }
  const lc = svc.find(e => e.outerType === 'LocationCommand');
  assert.strictEqual(lc.name, 'LocationCommand_Type');
  assert.strictEqual(lc.label, 'LocationCommand.Type');
  assert.strictEqual(tms.find(e => e.outerType === 'TransportServiceEvent').name, 'TransportServiceEvent_TYPE');
  assert.strictEqual(core[0].name, 'PriorityLevel', 'top-level enum names are unchanged');
  assert.strictEqual(core[0].outerType, undefined);
});

test('#639 capability grouping uses enum path evidence: api/values/state roll up', () => {
  const { capabilityForItem } = require('../generators/lib/capability-grouper');
  const svc = extract(SVC_LIB, 'svc').data.items;
  const lc = svc.find(e => e.outerType === 'LocationCommand');
  assert.strictEqual(lc.module, 'commands');
  assert.strictEqual(capabilityForItem(lc), 'location');
  const core = extract(CORE, 'core').data.items[0];
  assert.strictEqual(core.module, 'values');
  assert.strictEqual(capabilityForItem(core), 'core');
  // a real OpenWMS state-machine path (openwms-tms .../tms/impl/state/Starter.java)
  assert.strictEqual(capabilityForItem({ module: 'state', _source: 'openwms-tms/src/main/java/org/openwms/tms/impl/state/Starter.java' }), 'tms');
});

test('#637 merger: a missed endpoint is counted in the gaps total, never "0 gaps"', async () => {
  const { Merger } = require('../lib/merger');
  const { kb } = extract(SVC_LIB, 'svc');
  // Same real extraction, with one capture removed — exercises the reporting path only.
  const f = path.join(kb, 'extracted', 'java-svc.json');
  const data = JSON.parse(fs.readFileSync(f, 'utf8'));
  data.meta.endpointCoverage.captured -= 1;
  data.meta.endpointCoverage.disagreements = 1;
  data.meta.endpointCoverage.files = [{ file: 'LocationController.java', expected: 13, captured: 12 }];
  fs.writeFileSync(f, JSON.stringify(data));
  await new Merger({ extractedDir: path.join(kb, 'extracted'), knowledgeBaseDir: kb, logger: { log() {}, error() {} } }).run();
  const summary = fs.readFileSync(path.join(kb, 'reports', 'summary.md'), 'utf8');
  const gaps = fs.readFileSync(path.join(kb, 'reports', 'gaps-report.md'), 'utf8');
  assert.match(summary, /REST endpoints captured: \*\*12 of 13\*\*.*1 missed/);
  assert.doesNotMatch(summary, /Total gaps \(missing links\): \*\*0\*\*/);
  assert.match(gaps, /LocationController\.java`: 12 captured of 13/);
  // delegation links reach the cross-reference map
  const xref = JSON.parse(fs.readFileSync(path.join(kb, 'cross-reference-map.json'), 'utf8'));
  const links = xref['java:logic:location:LocationController.createLocation'].linkedTo;
  assert.ok(links.some(l => l.matchedBy === 'controller-delegate' && l.id === 'java:logic:impl:LocationServiceImpl.create'));
});

// ── Review fixes on #649. Golden input, verbatim and Apache-2.0 per each file's header:
// tests/fixtures/petclinic/ = spring-projects/spring-petclinic @3450c3d (2016-10-17), two
// controllers using method-level @RequestMapping; tests/fixtures/kylin/ = apache/kylin @705dd08
// SparderUIController (`@RequestMapping(value = "/**")`); and OpenWMS AbstractWebController
// (`"://"` string literals). Counts taken by grep over those files.
const PETCLINIC = path.join(__dirname, 'fixtures', 'petclinic', 'src', 'main', 'java');
const KYLIN = path.join(__dirname, 'fixtures', 'kylin', 'src', 'query-server', 'src', 'main', 'java');
const { stripCommentsAndStrings, regexEndpointCount } = require('../extractors/endpoint-count');
const read = (...p) => fs.readFileSync(path.join(...p), 'utf8');

test('independent count: "/*" and "/**" inside string literals do not open a comment', () => {
  // VisitController: "/owners/*/pets/..." on line 76; the comments-first stripper counted 1 of 3.
  const visit = read(PETCLINIC, 'org/springframework/samples/petclinic/web/VisitController.java');
  assert.strictEqual(regexEndpointCount(visit), 3, 'lines 76, 82, 92; the javadoc @RequestMapping on line 58 does not count');
  const sparder = read(KYLIN, 'org/apache/kylin/rest/controller/SparderUIController.java');
  assert.strictEqual(regexEndpointCount(sparder), 2, '@RequestMapping("/**") line 45 + @GetMapping line 52');
});

test('independent count: "//" inside a string literal does not truncate the line', () => {
  const awc = read(FIX, 'openwms/org.openwms.core.util/src/main/java/org/openwms/core/http/AbstractWebController.java');
  const line = awc.split('\n')[297]; // line 298
  assert.match(line, /endsWith\("\:\/\/"\) \? req\.getScheme\(\)/);
  assert.match(stripCommentsAndStrings(line), /endsWith\(""\) \? req\.getScheme\(\) : req\.getScheme\(\) \+ ""\)/);
  assert.strictEqual(regexEndpointCount(awc), null, 'abstract base class carries no controller stereotype');
});

test('method-level @RequestMapping: verbs from method=, ANY without it, one endpoint per listed path', () => {
  const { data } = extract(PETCLINIC, 'pc');
  const ec = data.meta.endpointCoverage;
  assert.deepStrictEqual([ec.expected, ec.captured, ec.disagreements], [5, 5, 0]);
  const eps = Object.fromEntries(data.items.filter(i => i.httpEndpoint).map(i => [i.uniqueId, i.httpEndpoint]));
  assert.deepStrictEqual(eps['java:web.VisitController.initNewVisitForm'], { method: 'GET', path: '/owners/*/pets/{petId}/visits/new' });
  assert.deepStrictEqual(eps['java:web.VisitController.processNewVisitForm'], { method: 'POST', path: '/owners/{ownerId}/pets/{petId}/visits/new' });
  assert.deepStrictEqual(eps['java:web.VetController.showVetList'], { method: 'ANY', path: '/vets.html' });
  // value = {"/vets.json", "/vets.xml"} -> two endpoints
  assert.deepStrictEqual([eps['java:web.VetController.showResourcesVetList'].path, eps['java:web.VetController.showResourcesVetList~2'].path], ['/vets.json', '/vets.xml']);
  const k = extract(KYLIN, 'ky').data;
  assert.deepStrictEqual([k.meta.endpointCoverage.expected, k.meta.endpointCoverage.captured], [2, 2]);
  assert.ok(k.items.find(i => i.name === 'proxy')._gaps.some(g => g.startsWith('endpoint-path-unresolved:')), 'SparderUIUtil is not in the fixture');
});

test('overloads get distinct names; no BRD lists two microflows with one name', async () => {
  const { data, kb } = extract(SVC_LIB, 'svc');
  const names = data.items.filter(i => i.type === 'logic' && i.label === 'changeState').map(i => i.name).sort();
  // controller: 3 overloads; LocationServiceImpl: 2
  assert.deepStrictEqual(names, ['changeState', 'changeState', 'changeState_2', 'changeState_2', 'changeState_3']);
  assert.ok(data.items.filter(i => i.name === 'changeState_2').every(i => i.overloadOf === 'changeState'));
  const { Merger } = require('../lib/merger');
  await new Merger({ extractedDir: path.join(kb, 'extracted'), knowledgeBaseDir: kb, logger: { log() {}, error() {} } }).run();
  const { generate } = require('../generators/brd-mappers/index');
  const out = path.join(kb, 'brd');
  await generate(kb, out, {});
  const brds = fs.readdirSync(out).filter(f => f.endsWith('.brd.json'));
  assert.ok(brds.length > 0);
  for (const f of brds) {
    const mf = JSON.parse(fs.readFileSync(path.join(out, f), 'utf8')).microflows || [];
    const seen = mf.map(m => m.name);
    assert.strictEqual(new Set(seen).size, seen.length, `${f}: duplicate microflow names`);
  }
  const loc = JSON.parse(fs.readFileSync(path.join(out, 'location.brd.json'), 'utf8')).microflows;
  const renamed = loc.find(m => m.renamedFrom === 'changeState');
  assert.ok(renamed && /^(LocationServiceImpl|LocationController)_changeState/.test(renamed.name), JSON.stringify(renamed));
});
