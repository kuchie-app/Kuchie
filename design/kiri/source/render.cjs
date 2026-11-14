const fs = require('node:fs');
const path = require('node:path');
const sharp = require(process.env.KUCHIE_SHARP_MODULE || 'sharp');
const {scenes, draw} = require('./scenes.cjs');

const svg = fs.readFileSync(path.join(__dirname,'kiri-rig.svg'),'utf8');
const rig = {
  defs: svg.match(/<defs>([\s\S]*?)<\/defs>/)[1],
  content: svg.slice(svg.indexOf('<g id="kiri"'), svg.lastIndexOf('</svg>')),
};
const framesDir = process.argv[2];
if (!framesDir) throw new Error('Pass an output directory for temporary PNG frames.');
fs.mkdirSync(framesDir,{recursive:true});
fs.writeFileSync(path.join(__dirname,'scenes.json'),JSON.stringify(scenes,null,2)+'\n');

async function render(){
  const sample = process.env.KUCHIE_SAMPLE === '1';
  for(const [id,{duration}] of Object.entries(scenes)){
    const dir=path.join(framesDir,id);
    fs.mkdirSync(dir,{recursive:true});
    const count=Math.ceil(duration/66.67);
    const times=sample ? [0,.32,.58,1] : Array.from({length:count},(_,i)=>i/(count-1));
    for(const [i,t] of times.entries()){
      const source=draw(id,t,rig);
      if(i===times.length-1){
        fs.writeFileSync(path.join(dir,'final.svg'),source);
      }
      await sharp(Buffer.from(source)).resize(480,360).png().toFile(path.join(dir,String(i).padStart(3,'0')+'.png'));
    }
  }
}
render().catch(err=>{console.error(err);process.exitCode=1;});
