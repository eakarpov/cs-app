// Run from typikon-web with node --import tsx. Reuses the actual backend search key.
const fs=require('node:fs');
const requireAt=require('node:module').createRequire(process.cwd()+'/package.json');
const {civilKey}=requireAt('./src/lib/cslav/core.ts');
const root='../cs-app/import/wiktionary-pilot';
const readline=require('node:readline');
(async()=>{
 const terms=new Set();
 for await(const line of readline.createInterface({input:fs.createReadStream(root+'/selected.jsonl')})){
  const r=JSON.parse(line);terms.add(r.word);
  for(const f of r.raw.forms??[])if(f.form)terms.add(f.form);
  for(const s of r.raw.senses??[])for(const parent of s.form_of??[])if(parent.word)terms.add(parent.word);
  function walk(rows){for(const d of rows){
   const code=d.lang_code??'';
   if(d.word&&(['cu','chu','chu-ru','zls-chs'].includes(code)||code.startsWith('zls-chs-')))terms.add(d.word);
   for(const t of d.templates??[]){
    const code=t.args?.['1']??'';
    if(!['cu','chu','chu-ru','zls-chs'].includes(code)&&!code.startsWith('zls-chs-'))continue;
    for(const [key,value] of Object.entries(t.args))if(/^\d+$/.test(key)&&Number(key)>=2&&typeof value==='string')terms.add(value.split('<')[0]);
   }
   walk(d.descendants??[]);
  }}
  walk(r.raw.descendants??[]);
 }
 const keys={};for(const term of terms)keys[term]=civilKey(term);
 fs.writeFileSync(root+'/civil-keys.json',JSON.stringify(keys));
 console.log(JSON.stringify({searchKeys:terms.size}));
})().catch(e=>{console.error(e);process.exitCode=1;});
