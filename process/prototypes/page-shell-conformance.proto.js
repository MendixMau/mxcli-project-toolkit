// Two shell-level checks that need no app, no Studio Pro, no screenshot.
const fs=require('fs');
const wfDir='design/wireframes', mdl='app/mdlsource/1-domain/';
const first=['10-practice-stub-pages.mdl','12-practice-pages.mdl','13-practice-pages-batch2.mdl'];
const src=first.map(f=>{try{return fs.readFileSync(mdl+f,'utf8')}catch(e){return''}}).join('\n');
const pages=[...src.matchAll(/CREATE OR MODIFY PAGE "Practice"\."(\w+)"[\s\S]*?\n\}/g)];
let fail1=0,fail2=0,n=0;
console.log('page                  wf-column  page-caps-width   wf-nav  page-layout');
for(const m of pages){
  const name=m[1], body=m[0];
  const wfPath=`${wfDir}/${name}.html`; if(!fs.existsSync(wfPath)) continue; n++;
  const wf=fs.readFileSync(wfPath,'utf8');
  const col=(wf.match(/main\{max-width:(\d+)px/)||[])[1];
  const caps=/max-width|page-column|kt-page|container-fluid|\bcol\b/.test(body);
  const wfNav=/<nav class="tabs"/.test(wf)?'topbar':'—';
  const layout=(body.match(/Layout:\s*"Atlas_Core"\."(\w+)"/)||[])[1];
  const bad1=col&&!caps, bad2=wfNav==='topbar'&&layout!=='Atlas_TopBar';
  if(bad1)fail1++; if(bad2)fail2++;
  console.log(name.padEnd(22),(col?col+'px':'—').padEnd(10),(caps?'yes':'NO  <-- FAIL').padEnd(17),wfNav.padEnd(7),layout+(bad2?'  <-- FAIL':''));
}
console.log(`\nCHECK A (page column honoured):  ${n-fail1}/${n} pass`);
console.log(`CHECK B (layout matches wireframe shell): ${n-fail2}/${n} pass`);
