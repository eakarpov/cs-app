const fs=require('node:fs');
const requireAt=require('node:module').createRequire(process.cwd()+'/package.json');
const DB=requireAt('better-sqlite3');
const {civilKey}=requireAt('./src/lib/cslav/core.ts');
const path='../cs-app/import/wiktionary-pilot/native-index.json';
const db=new DB('../cs-app/import/cs-publication-v1.sqlite',{readonly:true,fileMustExist:true});
const meta=Object.fromEntries(db.prepare('SELECT key,value FROM metadata').all().map(r=>[r.key,r.value]));
const rows=[];
for(const row of db.prepare('SELECT id,name,pos,payload FROM articles').iterate()){
 const a=JSON.parse(row.payload);
 const variants=[...new Set([a.name,a.originalName].filter(Boolean))];
 rows.push({id:row.id,name:row.name,pos:row.pos,properties:a.properties,scheme:a.scheme,morphologyStatus:a.morphologyStatus,variants:variants.map(value=>({value,origin:value===a.name?'lemma':'original-lemma',civilKey:civilKey(value)}))});
}
const byId=new Map(rows.map(row=>[row.id,row]));
for(const row of db.prepare("SELECT DISTINCT lexemeId,surface FROM forms WHERE origin='source-variant'").iterate()){
 const target=byId.get(row.lexemeId);if(target&&!target.variants.some(v=>v.value===row.surface))target.variants.push({value:row.surface,origin:'source-variant',civilKey:civilKey(row.surface)});
}
fs.writeFileSync(path,JSON.stringify({source:'typikon-publication',version:meta.version,exportedAtUtc:new Date().toISOString(),readOnly:true,rows}));
console.log(JSON.stringify({articles:rows.length,variants:rows.reduce((n,r)=>n+r.variants.length,0),version:meta.version}));db.close();
