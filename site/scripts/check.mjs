import { readFile, readdir, stat } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
const root = fileURLToPath(new URL('../dist/', import.meta.url));
const files = [];
async function walk(dir) { for (const entry of await readdir(dir,{withFileTypes:true})) { const p=path.join(dir,entry.name); if(entry.isDirectory())await walk(p);else files.push(p); } }
await walk(root);
const errors=[];
for(const file of files){
  if((await stat(file)).size>25*1024*1024)errors.push(`${file} exceeds Pages asset limit`);
  if(file.endsWith('.js')){const r=spawnSync(process.execPath,['--check',file]);if(r.status)errors.push(r.stderr.toString());}
  if(!file.endsWith('.html'))continue;
  const html=await readFile(file,'utf8');
  for(const m of html.matchAll(/(?:src|href|poster|srcset)="(\/[^"#?]*)"/g)){
    let target=path.join(root,m[1]);if(m[1].endsWith('/'))target=path.join(target,'index.html');
    try{await stat(target);}catch{errors.push(`Missing ${m[1]} in ${file}`);}
  }
  for(const m of html.matchAll(/href="#([^"]+)"/g))if(!html.includes(`id="${m[1]}"`))errors.push(`Missing anchor ${m[1]}`);
  if((html.match(/<h1>/g)||[]).length!==1)errors.push(`Expected one h1: ${file}`);
  if(/localhost|TODO|PLACEHOLDER/.test(html))errors.push(`Unfinished content: ${file}`);
}
if(errors.length){console.error(errors.join('\n'));process.exit(1);}
console.log(`Checked ${files.length} deploy assets: references, anchors, JS syntax, page headings, file sizes.`);
