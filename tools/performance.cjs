// Pure business benchmark on synthetic data; not an emulator frame-rate measurement.
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const ts=require(process.env.TAIPLAN_TYPESCRIPT || 'D:/Program Files/Huawei/DevEco Studio/tools/hvigor/hvigor/node_modules/typescript');
const root=path.join(__dirname,'../entry/src/main/ets'),cache={};
function load(name){const file=path.resolve(root,name);if(cache[file])return cache[file].exports;const module={exports:{}};cache[file]=module;
const js=ts.transpileModule(fs.readFileSync(file,'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020}}).outputText;
vm.runInNewContext(js,{module,exports:module.exports,require:n=>load(path.relative(root,path.resolve(path.dirname(file),n+'.ets')))});return module.exports;}
const {TaskService:S}=load('services/TaskService.ets'),{PlanningService:P}=load('services/PlanningService.ets'),{FocusService:F}=load('services/FocusService.ets'),{CalendarService:C}=load('services/CalendarService.ets'),{ScheduleService:R}=load('services/ScheduleService.ets');
const now=new Date(2026,9,11,9).getTime(),tasks=[];
for(let i=0;i<5000;i++){const day=S.endOfDay(2026,9,1+i%28),minute=480+(i%12)*30;tasks.push(S.create({title:'性能样例'+i,note:'课程与复习',priority:i%3,tagsText:'学习',dueAt:day,startMinute:minute,durationMinutes:30,repeat:i%10===0?'weekly':'none',planning:P.create(day,minute,30)},'bench'+i,i));}
function measure(name,fn){const samples=[];let count=0;for(let i=0;i<5;i++){const t=performance.now();const value=fn();samples.push(performance.now()-t);count=Array.isArray(value)?value.length:value.planned;}samples.sort((a,b)=>a-b);return {name,medianMs:+samples[2].toFixed(2),maxMs:+samples[4].toFixed(2),count};}
const result={platform:process.platform,node:process.version,tasks:5000,recurringSeries:500,scope:'Node pure services, not native UI latency',results:[measure('search',()=>C.search(tasks,'样例49')),measure('today',()=>F.overview(tasks,[],now)),measure('day blocks',()=>C.blocks(tasks,[],'2026-10-11')),measure('month',()=>R.month(tasks,[],'2026-10-01'))]};
console.log(JSON.stringify(result,null,2));
