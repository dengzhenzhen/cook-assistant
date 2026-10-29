/* Buildless mobile prototype. Recipes/session facts stay in this browser. */
(() => {
'use strict';
const $ = s => document.querySelector(s);
const copy = value => JSON.parse(JSON.stringify(value));
const escape = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const paths = {
  book:'M4 4h6a3 3 0 0 1 2 1 3 3 0 0 1 2-1h6v15h-6a3 3 0 0 0-2 1 3 3 0 0 0-2-1H4z M12 5v15',
  pot:'M4 10h16v7a4 4 0 0 1-4 4H8a4 4 0 0 1-4-4z M2 12h2m16 0h2M3 7h18M10 4h4M9 1v1m6-1v1',
  person:'M16 7a4 4 0 1 1-8 0 4 4 0 0 1 8 0M4 21v-2a8 8 0 0 1 16 0v2',
  link:'M10 13a5 5 0 0 0 7 0l3-3a5 5 0 0 0-7-7l-2 2M14 11a5 5 0 0 0-7 0l-3 3a5 5 0 0 0 7 7l2-2',
  image:'M3 3h18v18H3z M3 17l6-6 5 5 3-3 4 4 M16 7h.01',
  clipboard:'M8 4H5v17h14V4h-3M8 2h8v5H8zM8 12h8m-8 4h5',
  arrow:'M5 12h14m-5-5 5 5-5 5',back:'M19 12H5m5-5-5 5 5 5',
  check:'M5 12l4 4L19 6',clock:'M12 8v5l3 2M22 12a10 10 0 1 1-20 0 10 10 0 0 1 20 0',
  flame:'M13 2c1 6 6 6 6 12a7 7 0 0 1-14 0c0-3 2-5 4-7 0 3 1 4 2 4 2-3 2-6 2-9z',
  pan:'M3 8h13v4a6 6 0 0 1-12 0V8m12 2h6',
  oven:'M3 3h18v18H3zM6 8h12v10H6zM7 5h.01M11 5h.01',
  board:'M5 3h14v19H5zM10 6h4',knife:'M15 2v13H6C6 8 9 4 15 2Zm-3 13v7h3v-7',
  bowl:'M3 10h18c-1 7-4 10-9 10S4 17 3 10ZM9 22h6M7 3v3m5-4v4m5-3v3',
  plate:'M22 12a10 10 0 1 1-20 0 10 10 0 0 1 20 0M18 12a6 6 0 1 1-12 0 6 6 0 0 1 12 0',
  info:'M12 11v6m0-10h.01M22 12a10 10 0 1 1-20 0 10 10 0 0 1 20 0',
  plus:'M12 5v14M5 12h14',heart:'M20 4a5 5 0 0 0-8 1 5 5 0 0 0-8-1c-6 6 8 16 8 16S26 10 20 4Z',
  play:'m8 4 12 8-12 8z',leaf:'M20 3C7 0 0 12 6 18c6 6 16-1 14-15ZM4 21 16 8',
  refresh:'M20 7V2m0 5h-5M4 17v5m0-5h5M20 7A9 9 0 0 0 4 7m0 10a9 9 0 0 0 16 0',
};
const icon = name => `<svg class="icon" aria-hidden="true" viewBox="0 0 24 24"><path d="${paths[name] || paths.pot}"/></svg>`;
function art(kind) {
  let food='';
  if(kind==='chicken') food = [[75,74,-28],[113,70,15],[80,111,20],[117,111,-22]].map(([x,y,r])=>`<g transform="translate(${x} ${y}) rotate(${r})"><ellipse rx="16" ry="29" fill="#a6512c"/><ellipse cx="-3" cy="-3" rx="12" ry="23" fill="#ce753b"/><path d="M-7-16v22M0-19v28" stroke="#e79b56" stroke-width="3" stroke-linecap="round" opacity=".8"/><path d="m-5 24 9 1" stroke="#f5ddad" stroke-width="5"/></g>`).join('');
  else if(kind==='eggs') food = [[72,78,-20],[115,70,25],[107,117,-15],[65,109,30],[100,88,20]].map(([x,y,r],i)=>`<g transform="translate(${x} ${y}) rotate(${r})">${i%2?'<path d="M-20-12Q0-25 22-9L14 17Q-4 23-22 4Z" fill="#ce5535"/><path d="M-13-8Q3-18 15-5" stroke="#f39b63" fill="none" stroke-width="4"/>':'<path d="M-22-4Q-14-22 1-16Q18-22 24-3Q18 8 10 10Q-4 25-21 9Z" fill="#efc658"/><path d="M-12 1 8-8M-6 12l17-8" stroke="#f8dfa0" stroke-width="5" stroke-linecap="round"/>'}</g>`).join('');
  else if(kind==='greens') food = [[60,75,-40],[95,66,-5],[122,85,40],[74,108,-35],[112,117,30]].map(([x,y,r])=>`<g transform="translate(${x} ${y}) rotate(${r})"><path d="M0 34C-15 20-31 1-20-17C-9-29-1-23 1-20C18-30 30-7 18 9Z" fill="#769346"/><path d="M0 32 0-15m0 22-13-13m13 20L12 2" fill="none" stroke="#c1cd8d" stroke-width="3" stroke-linecap="round"/></g>`).join('');
  else food='<ellipse cx="94" cy="97" rx="53" ry="40" fill="#e3d9bf"/><path d="M43 94c5-59 97-59 103 0Z" fill="#fffdf3"/>'+Array.from({length:24},(_,i)=>`<path d="m${57+(i*17)%74} ${66+(i*7)%26} 4 3" stroke="#ddd9c8" stroke-width="2" stroke-linecap="round"/>`).join('')+'<path d="M43 94h103c-4 38-22 51-51 51S48 132 43 94Z" fill="#9ba48a"/><path d="M53 103h83" stroke="#bbc3ac" stroke-width="3"/>';
  return `<svg class="food-art" viewBox="0 0 190 190" aria-hidden="true"><ellipse cx="97" cy="104" rx="78" ry="72" fill="#263622" opacity=".08"/><circle cx="95" cy="95" r="78" fill="#fcf9ef"/><circle cx="95" cy="95" r="65" fill="#f1eddf" stroke="#e3dfd1"/>${food}${kind==='rice'?'':'<g fill="#517644"><ellipse cx="64" cy="58" rx="7" ry="3" transform="rotate(-30 64 58)"/><ellipse cx="131" cy="102" rx="6" ry="3" transform="rotate(25 131 102)"/><ellipse cx="93" cy="135" rx="7" ry="3"/></g>'}</svg>`;
}
const STORE='kaifan-prototype-v1';
const initial=()=>({recipes:copy(CookDemo.recipes),selected:['chicken','eggs','greens','rice'],kitchen:{cook_count:1,capacities:Object.fromEntries(CookDemo.resources.map(r=>[r[0],r[3]]))},session:null,preview:null});
let storageFailed=false;
let state;
try {state=JSON.parse(localStorage.getItem(STORE)) || initial();if(!Array.isArray(state.recipes)||!Array.isArray(state.selected)||!state.kitchen)state=initial();} catch {state=initial();storageFailed=true;}
// Add optional notes to existing browser data without overwriting user edits.
const demoTasks = new Map(CookDemo.recipes.flatMap(r => r.tasks).map(t => [t.id,t]));
for (const recipe of state.recipes) for (const task of recipe.tasks) {
  if (task.notes === undefined) task.notes = demoTasks.get(task.id)?.notes || '';
}
for (const snapshot of [state.preview, state.session]) {
  if (snapshot) for (const task of snapshot.request.tasks) {
    if (task.notes === undefined) task.notes = demoTasks.get(task.id)?.notes || '';
  }
}
state.settings ??= {confirmation_seconds: 60};
let busy=false,route='recipes',filter='all',draft=null,draftSource='',importTab='text',kitchenDraft=null,error='',toastTimer;
function save(){try{localStorage.setItem(STORE,JSON.stringify(state));}catch{if(!storageFailed)toast('浏览器无法保存数据，刷新后可能丢失。');storageFailed=true;}}
function toast(message){$('#toast').textContent=message;$('#toast').classList.add('visible');clearTimeout(toastTimer);toastTimer=setTimeout(()=>$('#toast').classList.remove('visible'),4200);}
const resourceName=key=>key==='cook'?'厨师':(CookDemo.resources.find(r=>r[0]===key)?.[1] || key);
const minutes=seconds=>Math.ceil(seconds/60);
const duration=seconds=>seconds<60?`${seconds} 秒`:`${Math.round(seconds/60*10)/10} 分钟`;
const clock=(origin,offset=0)=>new Date(origin+offset*1000).toLocaleTimeString('zh-CN',{hour:'2-digit',minute:'2-digit',hour12:false});
const dateInput=ms=>{const d=new Date(ms);return new Date(ms-d.getTimezoneOffset()*60000).toISOString().slice(0,16);};
const selectedRecipes=()=>state.recipes.filter(r=>state.selected.includes(r.id));
const activeSession=()=>state.session && state.session.execution.filter(e=>e.actual_end!==undefined).length<state.session.request.tasks.length;
const elapsed=(s=state.session)=>s?Math.max(0,Math.floor(s.offset+(s.paused?0:(Date.now()-s.wallBase)/1000))):0;
function badge(type){return `<span class="tag ${type==='passive'?'':'orange'}">${type==='passive'?'自动等待':type==='intermittent'?'间歇看管':'动手操作'}</span>`;}
const note=(message,type='')=>`<div class="note ${type}">${icon('info')}<span>${escape(message)}</span></div>`;
const heading=(title,subtitle,back)=>`<div class="${back?'back-heading':'page-header'}">${back?`<a href="#${back}" class="icon-button" aria-label="返回">${icon('back')}</a>`:''}<div>${back?'':'<p class="eyebrow">A LITTLE ORDER. A LOVELY DINNER.</p>'}<h2>${title}</h2>${subtitle?`<p class="subtitle">${subtitle}</p>`:''}</div>${back?'':`<button class="icon-button" data-action="help" aria-label="原型说明">${icon('info')}</button>`}</div>`;
function requestFor(recipes){return {tasks:recipes.flatMap(r=>copy(r.tasks)),holds:recipes.flatMap(r=>copy(r.holds)),capacities:copy(state.kitchen.capacities),cook_count:state.kitchen.cook_count,max_holding_seconds:Object.fromEntries(recipes.map(r=>[r.id,r.holding])),execution:[],now_seconds:0};}
async function api(path,body){
  const controller=new AbortController(),timeout=setTimeout(()=>controller.abort(),25000);
  try{
    const response=await fetch(path,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body),signal:controller.signal});
    const data=await response.json();
    if(!response.ok){let message=typeof data.detail==='string'?data.detail:(data.detail || []).map(e=>`${e.loc?.slice(1).join('.')}：${e.msg}`).join('；');
      if(message.includes('insufficient resource')){const m=message.match(/resource (.*): need (\d+), available (\d+)/);message=m?`${resourceName(m[1])}不足：需要 ${m[2]}，厨房只有 ${m[3]}。请调整厨房配置或所选菜谱。`:message;}
      if(message.includes('infeasible'))message='当前执行事实与资源占用冲突，无法生成可行计划。请检查厨具数量和任务状态。';
      if(message.includes('time limit'))message='本次计算未找到可行计划，请减少菜品或稍后重试。';
      throw new Error(message || '请求失败，请重试。');
    }
    $('#connection').className='connection online';$('#connection').textContent='引擎已连接';return data;
  }catch(e){if(e.name==='AbortError')throw new Error('计算超时，请稍后重试。');if(e instanceof TypeError){$('#connection').className='connection offline';$('#connection').textContent='引擎未连接';throw new Error('无法连接调度服务。请启动 python -m service 后重试。');}throw e;}finally{clearTimeout(timeout);}
}
function navigate(next){location.hash=next;}
function render(){
  route=location.hash.slice(1).split('?')[0] || 'recipes';
  const pages={recipes:renderRecipes,import:renderImport,review:renderReview,kitchen:renderKitchen,plan:renderPlan,timeline:renderTimeline,execute:renderExecute,mine:renderMine};
  if(!pages[route])route='recipes';
  $('#app').classList.toggle('execution-page',route==='execute');
  $('#app').innerHTML=pages[route]();
  const tab=['plan','timeline','execute'].includes(route)?'plan':['kitchen','mine'].includes(route)?'mine':'recipes';
  $('#navigation').innerHTML=[['recipes','book','菜谱'],['plan','pot','做饭'],['mine','person','我的']].map(([href,i,title])=>`<a class="nav-item ${tab===href?'active':''}" ${tab===href?'aria-current="page"':''} href="#${href}">${icon(i)}<span>${title}</span></a>`).join('');
  document.querySelectorAll('[data-stage]').forEach(el=>el.classList.toggle('current',el.dataset.stage===(route==='execute'?'execute':tab==='plan'?'plan':'recipes')));
  $('#app').classList.toggle('busy-overlay',busy);
  tick();
}
function renderRecipes(){
 const recipes=state.recipes.filter(r=>filter==='all'||filter==='favorites'&&r.favorite||filter==='selected'&&state.selected.includes(r.id));
 return `${heading('今天，想吃点什么？','好好吃饭，从一份小小的计划开始。')}
 <div class="hero"><div class="hero-copy"><p class="eyebrow">MAKE ROOM FOR DINNER</p><h2>锅里有热气，<br>日子有滋味。</h2><p>几道拿手菜，我们一起安排。</p></div>${art('eggs')}</div>
 <div class="import-row">${[['url','link','粘贴链接'],['image','image','图片导入'],['text','clipboard','文字导入']].map(([tab,i,t])=>`<button class="import-tile" data-action="import" data-tab="${tab}">${icon(i)}${t}</button>`).join('')}</div>
 <div class="section-heading"><h3>我的菜谱</h3><button class="text-button" data-action="manual">${icon('plus')}手动创建</button></div>
 <div class="chips">${[['all','全部菜谱'],['favorites','我的收藏'],['selected','今晚想做']].map(([f,t])=>`<button class="chip ${filter===f?'active':''}" data-action="filter" data-filter="${f}">${t}</button>`).join('')}</div>
 ${recipes.map(r=>`<article class="recipe-card"><div class="recipe-art">${art(r.art)}</div><div class="recipe-info"><button class="recipe-title" data-action="edit" data-id="${escape(r.id)}">${escape(r.name)}</button><p class="recipe-meta">${r.servings} 人份 · ${minutes(r.tasks.reduce((s,t)=>s+t.duration_seconds,0))} 分钟 · ${r.tasks.length} 步</p><span class="tag">${escape(r.tag)}</span> <button class="favorite" data-action="favorite" data-id="${escape(r.id)}" aria-label="${r.favorite?'取消收藏':'收藏'}${escape(r.name)}">${r.favorite?'♥':'♡'}</button></div><button class="select-recipe ${state.selected.includes(r.id)?'selected':''}" data-action="select" data-id="${escape(r.id)}" aria-label="${state.selected.includes(r.id)?'移出':'选择'}${escape(r.name)}" aria-pressed="${state.selected.includes(r.id)}">${state.selected.includes(r.id)?'✓':'+'}</button></article>`).join('') || '<div class="empty">这里还没有菜谱，试试导入或手动创建。</div>'}
 <div class="selection-bar"><div><strong>今晚想做 ${state.selected.length} 道</strong><p>让每一道菜，都刚好上桌</p></div><a href="#plan" class="primary small">安排做饭 ${icon('arrow')}</a></div><p class="quiet-label">示例菜谱可编辑 · 任务时长为演示估算</p>`;
}
function renderImport(){
 return `${heading('把喜欢的味道留下','导入后先确认，再加入你的菜谱。','recipes')}
 <div class="import-tabs">${[['text','文字'],['image','图片'],['url','链接']].map(([k,t])=>`<button class="chip ${importTab===k?'active':''}" data-action="import-tab" data-tab="${k}">${t}</button>`).join('')}</div>
 ${note('演示导入：不会识别输入内容，也不会上传或抓取。下一步固定载入「番茄炒蛋」示例，你可以修改后保存。')}
 <form id="import-form">${importTab==='text'?'<label class="field">菜谱文字<textarea name="source" maxlength="10000" placeholder="在这里粘贴菜谱文字，例如：番茄切块，鸡蛋打散……" required></textarea></label><button class="text-button" type="button" data-action="clipboard">从剪贴板粘贴</button>':importTab==='url'?'<label class="field">菜谱链接<input name="source" type="url" placeholder="https://…" required><small>正式版无法读取的平台，可改用截图导入。</small></label>':'<div class="upload-box">'+icon('image')+'<p>选择一张或多张菜谱截图</p><input type="file" name="images" id="images" accept="image/jpeg,image/png,image/webp" multiple required aria-label="选择菜谱图片"><p class="file-list" id="file-list">仅显示文件名，图片不会上传。</p></div>'}
 <div class="form-actions"><button class="primary wide" type="submit">载入演示识别结果 ${icon('arrow')}</button></div></form>`;
}
function renderReview(){
 if(!draft)return `${heading('确认菜谱','','recipes')}<div class="empty">请先选择菜谱，或导入一份演示结果。</div><a class="primary wide" href="#recipes">返回菜谱</a>`;
 return `${heading(draftSource==='edit'?'编辑菜谱':'确认你的菜谱','时间与依赖都可以调整。','recipes')}<div class="review-cover">${art(draft.art)}</div>${draftSource==='demo'?note('这是固定示例，不是对刚才输入内容的识别结果。步骤和时长需由你确认。'):''}
 <form id="review-form"><label class="field">菜名<input name="name" maxlength="80" value="${escape(draft.name)}" required></label><div class="form-row"><label class="field">份数<input type="number" name="servings" min="1" max="20" value="${draft.servings}" required></label><label class="field">最多等几分钟上桌<input type="number" name="holding" min="0" max="1440" value="${draft.holding/60}" step="0.5" required></label></div><label class="field">食材<textarea name="ingredients" maxlength="5000">${escape(draft.ingredients)}</textarea></label>
 <div class="section-heading"><h3>烹饪步骤</h3><span>时长为估算，可直接修改</span></div>
 ${draft.tasks.map((t,i)=>`<fieldset class="step-editor"><legend>步骤 ${String(i+1).padStart(2,'0')}</legend><label class="field">操作名称<input data-task="${i}" data-field="name" value="${escape(t.name)}" maxlength="120" required></label><label class="field">操作备注<textarea data-task="${i}" data-field="notes" maxlength="4000" placeholder="例如：小火翻炒 30 秒，再转大火；出锅前放盐。">${escape(t.notes || '')}</textarea></label><div class="form-row"><label class="field">预计分钟<input type="number" min="0.5" max="1440" step="0.5" data-task="${i}" data-field="duration" value="${t.duration_seconds/60}" required></label><label class="field">关注方式<select data-task="${i}" data-field="attention">${[['active','持续操作'],['passive','自动等待'],['intermittent','间歇看管']].map(([v,n])=>`<option value="${v}" ${t.attention_type===v?'selected':''}>${n}</option>`).join('')}</select></label></div>
 <details><summary>前置步骤 · ${t.dependencies.length?t.dependencies.map(d=>draft.tasks.findIndex(x=>x.id===d)+1).join('、'):'可独立开始'}</summary><div class="check-list">${draft.tasks.filter(x=>x.id!==t.id).map(x=>`<label><input type="checkbox" data-dep-for="${i}" value="${escape(x.id)}" ${t.dependencies.includes(x.id)?'checked':''}>${escape(x.name)}</label>`).join('')||'暂无其他步骤'}</div></details>
 <details><summary>本步骤占用厨具</summary><div class="check-list">${CookDemo.resources.map(([key,label])=>`<label><input type="checkbox" data-resource-for="${i}" value="${key}" ${t.resources[key]?'checked':''}>${label}</label>`).join('')}</div><p class="subtitle">每项占用 1 件；跨步骤持有的锅具请勿重复勾选。</p></details></fieldset>`).join('')}
 <button class="secondary wide" type="button" data-action="add-step">${icon('plus')} 增加一个步骤</button>
 ${draft.holds.length?`<details class="card" style="margin-top:15px"><summary>跨步骤持续占用 ${draft.holds.length} 项</summary>${draft.holds.map(h=>`<p>${resourceName(h.resource)} × ${h.quantity||1}：${escape(draft.tasks.find(t=>t.id===h.start_task)?.name)} → ${h.end_task?escape(draft.tasks.find(t=>t.id===h.end_task)?.name):'开饭'}</p>`).join('')}<p>原型保留示例的持续占用关系。</p></details>`:''}
 <div id="review-error" class="error-box"></div><button class="primary wide" style="margin-top:20px" type="submit">${icon('check')} 确认并保存菜谱</button></form>`;
}
function renderKitchen(){
 if(!kitchenDraft)kitchenDraft=copy(state.kitchen);
 const row=(key,name,i,value,min=0)=>`<div class="resource-row"><span class="resource-name">${icon(i)}${name}</span><div class="counter"><button data-action="counter" data-key="${key}" data-change="-1" aria-label="减少${name}" ${value<=min?'disabled':''}>−</button><output aria-label="${name}数量">${value}</output><button data-action="counter" data-key="${key}" data-change="1" aria-label="增加${name}" ${value>=20?'disabled':''}>+</button></div></div>`;
 return `${heading('我的厨房','了解你的厨房，才能安排得更好。','mine')}<div class="card">${row('cook_count','一起做饭的人','person',kitchenDraft.cook_count,1)}</div>${['加热设备','锅具','备菜与餐具'].map(group=>`<div class="section-heading"><h3>${group}</h3></div><div class="card">${CookDemo.resources.filter(r=>r[4]===group).map(([key,label,i])=>row(key,label,i,kitchenDraft.capacities[key]||0)).join('')}</div>`).join('')}${note('灶眼和锅具分别计算；没有的设备可以设为 0。')}<button class="primary wide" data-action="save-kitchen">保存厨房配置 ${icon('check')}</button>`;
}
function renderPlan(){
 const recipes=selectedRecipes();
 return `${heading('今晚的饭，安排一下','选好菜和时间，剩下的交给计划。')}
 ${activeSession()?`<div class="card"><h3>你还有一顿饭正在做</h3><p>可以回到执行页继续。当前会话使用开始时的菜谱与厨房快照。</p><a href="#execute" class="primary small" style="margin-top:12px">继续烹饪 ${icon('arrow')}</a></div>`:''}
 <div class="section-heading"><h3>今晚的菜单</h3><a class="text-button" href="#recipes">调整菜品 →</a></div><div class="card">${recipes.map(r=>`<div class="menu-small"><div class="recipe-art">${art(r.art)}</div><span>${escape(r.name)}</span><small>${r.servings} 人份</small></div>`).join('')||'<p>还没选菜，先去菜谱页挑几道吧。</p>'}</div>
 <a class="kitchen-summary" href="#kitchen"><span>${icon('pot')} ${state.kitchen.cook_count} 人 · ${state.kitchen.capacities.burner||0} 灶眼 · ${state.kitchen.capacities.wok||0} 炒锅</span><span>调整 →</span></a>
 <form id="plan-form"><label class="field">希望什么时候开饭？<input type="datetime-local" name="target" value="${dateInput(Date.now()+3600000)}" required><small>按当前时区安排；距离现在需在一周以内。</small></label><label class="field">设备完成后自动确认等待（秒）<input type="number" name="confirmation_seconds" min="5" max="600" step="1" value="${state.settings.confirmation_seconds}" required><small>默认 60 秒，仅自动设备生效；手动与明火步骤仍需确认。</small></label><div id="plan-error" class="error-box">${error?note(error,'error'):''}</div><button class="primary wide" type="submit" ${recipes.length===0||activeSession()?'disabled':''}>${icon('pot')} 生成烹饪计划</button></form>
 ${state.preview?'<a class="secondary wide" href="#timeline" style="margin-top:12px">查看上次生成的计划</a>':''}${note('会综合前后步骤、厨具数量和人员安排。煮饭期间，也能腾出手来备菜。')}<p class="quiet-label">当前计划由真实调度引擎计算</p>`;
}
function renderTimeline(){
 const preview=state.preview;
 if(!preview)return `${heading('烹饪计划','','plan')}<div class="empty">先选择菜品，生成一份计划。</div><a href="#plan" class="primary wide">去安排</a>`;
 const {plan,request,origin}=preview,first=Math.min(...plan.tasks.map(t=>t.start_seconds));
 return `${heading('一顿饭的好节奏','动手和等待，都安排在合适的时间。','plan')}
 <div class="tag">${plan.optimal?'已找到最优计划':'已找到可行计划'}</div><div class="stats"><div><strong>${minutes(plan.finish_seconds-first)}</strong><em>分钟</em><small>预计烹饪跨度</small></div><div><strong>${clock(origin,first)}</strong><small>建议开始</small></div><div><strong>${clock(origin,Math.max(plan.finish_seconds,request.target_finish_seconds))}</strong><small>预计开饭</small></div></div>
 ${plan.lateness_seconds?note(`按当前条件，预计晚 ${minutes(plan.lateness_seconds)} 分钟开饭。可以调整菜单、时间或厨房配置。`,'error'):note('这份计划可以赶上你希望的开饭时间。','success')}
 ${plan.holding_excess_seconds?note(`部分菜品的等待时间超出偏好，累计 ${minutes(plan.holding_excess_seconds)} 分钟。`):''}
 <div class="section-heading"><h3>任务时间线</h3><span>${plan.tasks.length} 个步骤</span></div><div class="legend"><span><i></i>需要你动手或看管</span><span><i class="green"></i>设备自动完成</span></div>
 <div class="timeline">${plan.tasks.map(t=>{const template=request.tasks.find(x=>x.id===t.task_id);return `<div class="timeline-item ${template.attention_type==='passive'?'passive':''}"><span class="timeline-time">${clock(origin,t.start_seconds)}</span><div class="timeline-track"><span class="timeline-dot"></span></div><div class="timeline-body"><strong>${escape(t.name)}</strong><p>${escape(preview.names[t.recipe_id]||t.recipe_id)} · ${duration(t.end_seconds-t.start_seconds)}</p>${badge(template.attention_type)}${template.notes?`<p class="task-notes">${escape(template.notes)}</p>`:''}</div></div>`;}).join('')}</div>
 <details class="card"><summary>查看厨具与人员占用</summary>${[...new Set(plan.allocations.map(a=>a.resource))].map(key=>`<div class="allocation"><span>${escape(resourceName(key))}</span><div class="allocation-bar" aria-label="${escape(resourceName(key))}占用时间">${plan.allocations.filter(a=>a.resource===key).map(a=>`<span title="${escape(resourceName(key))} × ${a.quantity}，${clock(origin,a.start_seconds)}–${clock(origin,a.end_seconds)}" style="left:${a.start_seconds/Math.max(1,request.target_finish_seconds,plan.finish_seconds)*100}%;width:${(a.end_seconds-a.start_seconds)/Math.max(1,request.target_finish_seconds,plan.finish_seconds)*100}%"></span>`).join('')}</div></div>`).join('')}<p>每段代表一项占用；数量容量由引擎校验。</p></details>
 ${plan.warnings.map(w=>note(w)).join('')}<button class="primary wide" data-action="begin-session" ${activeSession()?'disabled':''}>${icon('play')} 开始烹饪演示</button><p class="quiet-label">演示会从建议开始时刻启动，可手动快进</p>`;
}
function renderTaskNotes(task) {
  return task.notes ? `<p class="task-notes">${escape(task.notes)}</p>` : '';
}
function confirmationButton(session, entry, hero = false) {
  const automatic=CookExecution.canAutoConfirm(session,entry);
  return `<div class="timer-actions"><button class="secondary small" data-action="extend" data-id="${escape(entry.task_id)}" ${session.paused?'disabled':''}>再给 5 分钟</button><button class="primary ${hero?'':'small'}" data-action="complete-task" data-id="${escape(entry.task_id)}" ${session.paused?'disabled':''}>${icon('check')} <span data-confirm-label="${escape(entry.task_id)}">确认并进入下一步</span></button></div>${automatic?`<button class="text-button" data-action="cancel-auto" data-id="${escape(entry.task_id)}">本次不自动确认</button>`:''}`;
}
function renderManualTask(session, entry) {
  const task = session.request.tasks.find(t => t.id === entry.task_id);
  return `<article class="execution-hero" data-manual-task="${escape(task.id)}"><div class="execution-label"><p class="eyebrow">当前手动操作</p>${badge(task.attention_type)}</div><h2>${escape(task.name)}</h2><p>${escape(session.names[task.recipe_id])} · 预计 ${duration(task.duration_seconds)}</p>${renderTaskNotes(task)}<div class="timer-number" data-countdown="${escape(task.id)}"></div>${confirmationButton(session,entry,true)}<span class="confirmation-caption" data-confirm-caption="${escape(task.id)}"></span></article>`;
}
function renderApplianceTask(session, entry) {
  const task = session.request.tasks.find(t => t.id === entry.task_id);
  return `<article class="timer-card" data-appliance-task="${escape(task.id)}"><div class="timer-title"><strong>${escape(task.name)}</strong>${badge(task.attention_type)}</div>${renderTaskNotes(task)}<div class="timer-number" data-countdown="${escape(task.id)}"></div>${confirmationButton(session,entry)}<span class="confirmation-caption" data-confirm-caption="${escape(task.id)}"></span></article>`;
}
function renderExecute(){
 const s=state.session;
 if(!s)return `${heading('准备好开火了吗？','先安排一顿饭，再跟着步骤慢慢来。')}<div class="empty">${icon('pot')}还没有进行中的烹饪</div><a href="#plan" class="primary wide">生成烹饪计划</a>`;
 const completed=s.execution.filter(e=>e.actual_end!==undefined).length,total=s.request.tasks.length;
 if(completed===total)return `${heading('开饭啦！','辛苦了，把热气腾腾的饭菜端上桌。')}<div class="completed-mark">${icon('check')}</div><div class="card" style="text-align:center"><h2>这一餐，完成了。</h2><p style="margin-top:10px">${Object.values(s.names).map(escape).join(' · ')}</p><div class="stats"><div><strong>${total}</strong><small>已完成步骤</small></div><div><strong>${minutes(Math.max(...s.execution.map(e=>e.actual_end))-Math.min(...s.execution.map(e=>e.actual_start)))}</strong><small>演示用时 / 分钟</small></div><div><strong>${Object.keys(s.names).length}</strong><small>道菜品</small></div></div></div><a href="#recipes" class="primary wide">安排下一顿饭 ${icon('arrow')}</a>`;
 const running=CookExecution.running(s),templates=CookExecution.tasksById(s);
 const manual=running.filter(e=>!CookExecution.isApplianceTask(s,templates.get(e.task_id)));
 const appliances=running.filter(e=>CookExecution.isApplianceTask(s,templates.get(e.task_id)));
 const ready=CookExecution.readyTasks(s,elapsed(s));
 const next=ready[0] || CookExecution.nextTask(s);
 const nextTemplate=next?templates.get(next.task_id):null;
 return `${heading('跟着节奏，慢慢来',`预计 ${clock(s.origin,Math.max(s.plan.finish_seconds,s.request.target_finish_seconds))} 开饭 · 已完成 ${completed}/${total} 步`)}<div class="progress" aria-label="完成进度 ${Math.round(completed/total*100)}%"><span style="width:${completed/total*100}%"></span></div>
 <div class="demo-toolbar"><span>演示时钟 <strong id="demo-clock"></strong></span><button class="secondary small" data-action="advance">+1 分钟</button><button class="secondary small" data-action="pause">${s.paused?'继续演示':'暂停演示'}</button></div>
 ${error?note(error,'error'):''}
 ${manual.map(e=>renderManualTask(s,e)).join('')}
 ${!manual.length?`<div class="execution-hero"><div class="execution-label"><p class="eyebrow">${nextTemplate?'下一步操作':'稍作等待'}</p>${nextTemplate?badge(nextTemplate.attention_type):''}</div><h2>${nextTemplate?escape(nextTemplate.name):'让设备继续工作'}</h2><p>${nextTemplate?`${escape(s.names[nextTemplate.recipe_id])} · 预计 ${duration(nextTemplate.duration_seconds)}`:'自动任务会继续计时，下方可以查看进度。'}</p>${nextTemplate?renderTaskNotes(nextTemplate):''}${next?ready.length?`<button class="primary wide" data-action="start-task" data-id="${escape(next.task_id)}" ${s.paused?'disabled':''}>${icon('play')} 开始这一步</button>`:`<p style="margin-top:12px">计划于 ${clock(s.origin,next.start_seconds)} 开始${s.auto_continue?'，届时自动衔接':''}</p><button class="primary wide" data-action="jump" data-at="${next.start_seconds}" ${s.paused?'disabled':''}>演示快进到这一步 ${icon('arrow')}</button>`:''}</div>`:''}
 ${appliances.length?`<section class="auto-tasks-panel" aria-label="设备自动进行"><div class="section-heading"><h3>${icon('pot')} 设备自动进行</h3><span>${appliances.length} 个任务</span></div>${appliances.map(e=>renderApplianceTask(s,e)).join('')}</section>`:''}
 ${manual.length&&nextTemplate?`<div class="next-task-panel"><small>接下来 · 完成后按计划自动衔接</small><p>${escape(nextTemplate.name)} · ${duration(nextTemplate.duration_seconds)}</p></div>`:''}
 <details class="confirmation-settings"><summary>完成确认倒计时 · ${CookExecution.confirmationSeconds(s)} 秒</summary><form id="confirmation-form"><div class="form-row"><label class="field">任务到时后的确认等待（秒）<input name="seconds" type="number" min="5" max="600" step="1" value="${CookExecution.confirmationSeconds(s)}" required></label><button class="secondary small" type="submit">保存</button></div><small>默认 60 秒，可设为 5–600 秒。倒计时从任务预计结束时刻计算；延长任务会重新计时。</small></form></details>
 <button class="secondary wide" data-action="recalculate" style="margin-top:15px" ${s.paused?'disabled':''}>${icon('refresh')} 重新安排剩余任务</button>
 <details style="margin-top:15px"><summary>查看全部 ${total} 个步骤</summary>${s.plan.tasks.map(t=>`<p class="subtitle">${s.execution.some(e=>e.task_id===t.task_id&&e.actual_end!==undefined)?'✓':s.execution.some(e=>e.task_id===t.task_id)?'◉':'○'} ${escape(t.name)} · ${clock(s.origin,t.start_seconds)}</p>`).join('')}</details>
 ${note('手动操作与设备计时同时显示；确认后按依赖和资源安排衔接下一步。暂停只冻结演示时钟。')}`;
}
function renderMine(){
 return `${heading('我的小厨房','每一顿认真做的饭，都值得被记住。')}<div class="card"><div class="profile-icon">${icon('person')}</div><h3>今天也好好吃饭</h3><p>本地体验 · 无需登录</p><div class="stats"><div><strong>${state.recipes.length}</strong><small>道菜谱</small></div><div><strong>${state.kitchen.cook_count}</strong><small>位掌勺人</small></div><div><strong>${state.session?.execution.filter(e=>e.actual_end!==undefined).length||0}</strong><small>本餐完成步骤</small></div></div></div>
 <a class="settings-row" href="#kitchen"><span>${icon('pot')}厨房设备</span><small>配置锅灶与餐具 →</small></a><button class="settings-row" data-action="favorites"><span>${icon('heart')}我的收藏</span><small>${state.recipes.filter(r=>r.favorite).length} 道 →</small></button><button class="settings-row" data-action="help"><span>${icon('info')}原型说明</span><small>功能与数据范围 →</small></button><a class="settings-row" href="/project-plan" target="_blank" rel="noopener"><span>${icon('book')}项目规划</span><small>路线与验收标准 ↗</small></a><button class="settings-row" data-action="reset"><span>${icon('refresh')}重置演示数据</span><small>恢复初始菜谱 →</small></button>
 ${note(storageFailed?'当前浏览器无法保存数据，刷新可能丢失。':'菜谱、厨房和执行进度只保存在当前浏览器。AI 导入为演示，生成计划与重排使用真实引擎。')}`;
}
function collectDraft(){
 const form=$('#review-form');if(!form||!draft)return;
 draft.name=form.elements.name.value.trim();draft.servings=Number(form.elements.servings.value);draft.holding=Math.round(Number(form.elements.holding.value)*60);draft.ingredients=form.elements.ingredients.value;
 draft.tasks.forEach((t,i)=>{t.name=form.querySelector(`[data-task="${i}"][data-field="name"]`).value.trim();t.notes=form.querySelector(`[data-task="${i}"][data-field="notes"]`).value.trim();t.duration_seconds=Math.round(Number(form.querySelector(`[data-task="${i}"][data-field="duration"]`).value)*60);t.attention_type=form.querySelector(`[data-task="${i}"][data-field="attention"]`).value;t.dependencies=[...form.querySelectorAll(`[data-dep-for="${i}"]:checked`)].map(e=>e.value);t.resources=Object.fromEntries([...form.querySelectorAll(`[data-resource-for="${i}"]:checked`)].map(e=>[e.value,t.resources[e.value]||1]));});
}
function validateDraft(){
 if(!draft.name||draft.tasks.some(t=>!t.name||t.duration_seconds<=0))throw new Error('请填写菜名、步骤名称和有效时长。');
 const visiting=new Set(),visited=new Set(),tasks=new Map(draft.tasks.map(t=>[t.id,t]));
 const visit=id=>{if(visiting.has(id))throw new Error('步骤存在循环依赖，请调整前置步骤。');if(visited.has(id))return;const task=tasks.get(id);if(!task)throw new Error('某个前置步骤不存在。');visiting.add(id);task.dependencies.forEach(visit);visiting.delete(id);visited.add(id);};draft.tasks.forEach(t=>visit(t.id));
 // A hold must release after acquisition along the task graph.
 const ancestors=id=>{const set=new Set();const walk=key=>tasks.get(key).dependencies.forEach(dep=>{if(!set.has(dep)){set.add(dep);walk(dep);}});walk(id);return set;};
 for(const h of draft.holds){if(h.end_task&&h.end_task!==h.start_task&&!ancestors(h.end_task).has(h.start_task))throw new Error(`${resourceName(h.resource)}的释放步骤必须依赖占用开始步骤，请保留这条依赖链。`);}
}
function freshDraft(source){
 const recipe=copy(CookDemo.recipes.find(r=>r.id==='eggs')),id=`custom_${Date.now().toString(36)}`;
 const idMap=Object.fromEntries(recipe.tasks.map((t,i)=>[t.id,`${id}_${i}`]));
 recipe.id=id;recipe.favorite=false;recipe.tag='刚刚加入的味道';recipe.tasks.forEach(t=>{t.id=idMap[t.id];t.recipe_id=id;t.dependencies=t.dependencies.map(d=>idMap[d]);});recipe.holds.forEach(h=>{h.start_task=idMap[h.start_task];if(h.end_task)h.end_task=idMap[h.end_task];});
 if(source==='manual'){recipe.name='';recipe.ingredients='';recipe.tasks=[{id:`${id}_0`,recipe_id:id,name:'',notes:'',duration_seconds:60,attention_type:'active',dependencies:[],resources:{}}];recipe.holds=[];recipe.tag='我的拿手菜';}
 draft=recipe;draftSource=source;navigate('review');
}
function commitSession(candidate, now) {
  candidate.offset=now;
  candidate.wallBase=Date.now();
  state.session=candidate;
  error='';
  save();
}
async function recalculateSession(candidate, now) {
  candidate.plan=await api('/api/v1/plans/recalculate',CookExecution.requestAt(candidate,now));
}
async function startReadyTasks(candidate, now) {
  const ready=CookExecution.readyTasks(candidate,now);
  if(!ready.length)return candidate;
  const started=copy(candidate);
  for(const task of ready)CookExecution.startTask(started,task.task_id,now);
  await recalculateSession(started,now);
  return started;
}
let autoRetryAt=0;
async function sessionAction(action,id){
 const s=state.session;if(!s)return;
 const now=elapsed(s);let candidate=copy(s);
 const entry=candidate.execution.find(e=>e.task_id===id);
 if(s.paused)throw new Error('请先继续演示，再操作任务。');
 if(action==='start-task'){
   // Actual starts are checked against the displayed plan, then validated by CP-SAT.
   CookExecution.startTask(candidate,id,now);
   candidate.auto_continue=true;
 }else if(action==='complete-task'){
   if(!entry||entry.actual_end!==undefined)throw new Error('任务状态已更新，请刷新页面。');
   entry.actual_end=now;delete entry.estimated_end;
   candidate.auto_continue=true;
 }else if(action==='auto-confirm'){
   const due=CookExecution.dueConfirmations(candidate,now);
   if(!due.length)return;
   for(const task of due){task.actual_end=now;delete task.estimated_end;}
   candidate.auto_continue=true;
 }else if(action==='extend'){
   if(!entry||entry.actual_end!==undefined)throw new Error('这一步没有在执行。');
   entry.estimated_end=Math.max(now,entry.estimated_end)+300;
 }else if(action==='cancel-auto'){
   if(!entry||entry.actual_end!==undefined)throw new Error('这一步没有在执行。');
   entry.auto_confirm_cancelled=true;
   // Cancelling automation is local and must succeed even if the API is offline.
   commitSession(candidate,now);
   if(route==='execute')render();
   toast('本次自动确认已取消，需要手动确认完成。');
   return;
 }
 await recalculateSession(candidate,now);
 // Completion is committed before starting successors. If starting fails,
 // the confirmed fact is retained while all unstarted work stays unstarted.
 commitSession(candidate,now);
 if(candidate.auto_continue){
   try{candidate=await startReadyTasks(candidate,now);commitSession(candidate,now);}
   catch(e){state.session.auto_continue=false;save();throw new Error(`已保存当前进度，但下一步未能自动开始：${e.message}`);}
 }
 autoRetryAt=0;
 if(route==='execute')render();
 const messages={
   'complete-task':'已确认完成，并按计划衔接下一步。',
   'auto-confirm':'设备任务已自动确认，并按计划衔接下一步。',
   'start-task':'计时已开始，自动任务与手动操作将同时显示。',
   'extend':'已增加 5 分钟，完成确认倒计时已重新安排。',
   'cancel-auto':'本次自动确认已取消，需要手动确认完成。',
 };
 if(action!=='continue')toast(messages[action]||'剩余任务已重新安排。');
}
async function run(action){
 if(busy)return false;busy=true;$('#app').classList.add('busy-overlay');
 try{await action();return true;}catch(e){error=e.message;toast(e.message);const box=$('#plan-error')||$('#review-error');if(box)box.innerHTML=note(e.message,'error');else if(route==='execute')render();return false;}
 finally{busy=false;$('#app').classList.remove('busy-overlay');}
}
document.addEventListener('click',event=>{
 const button=event.target.closest('[data-action]');
 if(!button)return;
 const action=button.dataset.action,id=button.dataset.id;
 if(busy){event.preventDefault();return;}
 if(action==='help'){$('#help-dialog').showModal();return;}
 if(action==='select'){state.selected=state.selected.includes(id)?state.selected.filter(x=>x!==id):[...state.selected,id];state.preview=null;save();render();}
 else if(action==='favorite'){state.recipes.find(r=>r.id===id).favorite=!state.recipes.find(r=>r.id===id).favorite;save();render();}
 else if(action==='filter'){filter=button.dataset.filter;render();}
 else if(action==='favorites'){filter='favorites';navigate('recipes');}
 else if(action==='import'){importTab=button.dataset.tab;navigate('import');}
 else if(action==='import-tab'){importTab=button.dataset.tab;render();}
 else if(action==='manual')freshDraft('manual');
 else if(action==='edit'){draft=copy(state.recipes.find(r=>r.id===id));draftSource='edit';navigate('review');}
 else if(action==='add-step'){collectDraft();if(draft.tasks.length>=30){toast('原型每道菜最多支持 30 个步骤。');return;}draft.tasks.push({id:`${draft.id}_new_${Date.now().toString(36)}`,recipe_id:draft.id,name:'',notes:'',duration_seconds:60,attention_type:'active',dependencies:[],resources:{}});render();}
 else if(action==='counter'){const key=button.dataset.key,change=Number(button.dataset.change);if(key==='cook_count')kitchenDraft.cook_count=Math.max(1,Math.min(20,kitchenDraft.cook_count+change));else kitchenDraft.capacities[key]=Math.max(0,Math.min(20,(kitchenDraft.capacities[key]||0)+change));render();}
 else if(action==='save-kitchen'){state.kitchen=copy(kitchenDraft);state.preview=null;save();toast('厨房配置已保存。');navigate('mine');}
 else if(action==='clipboard')run(async()=>{if(!navigator.clipboard?.readText)throw new Error('浏览器不支持读取剪贴板，请手动粘贴。');try{$('#import-form textarea').value=(await navigator.clipboard.readText()).slice(0,10000);}catch{throw new Error('未获得剪贴板权限，请手动粘贴。');}});
 else if(action==='begin-session'){
   if(activeSession()){toast('请先完成当前会话。');return;}
   const p=state.preview;state.session={request:copy(p.request),plan:copy(p.plan),names:copy(p.names),origin:p.origin,execution:[],offset:Math.min(...p.plan.tasks.map(t=>t.start_seconds)),wallBase:Date.now(),paused:false,confirmation_seconds:state.settings.confirmation_seconds,auto_continue:false};save();error='';navigate('execute');
 }
 else if(['start-task','complete-task','extend','recalculate','cancel-auto'].includes(action))run(()=>sessionAction(action,id));
 else if(action==='advance'||action==='jump'){
   const s=state.session;if(!s)return;
   s.offset=action==='jump'?Math.max(elapsed(s),Number(button.dataset.at)):elapsed(s)+60;s.wallBase=Date.now();save();render();
 }
 else if(action==='pause'){const s=state.session;s.offset=elapsed(s);s.wallBase=Date.now();s.paused=!s.paused;save();render();}
 else if(action==='reset'){
   if(window.confirm('重置会清除当前浏览器中的菜谱修改、厨房配置与执行进度。确认恢复演示数据？')){state=initial();kitchenDraft=null;draft=null;error='';save();navigate('recipes');render();toast('已恢复初始演示数据。');}
 }
});
document.addEventListener('submit',event=>{
 const form=event.target;
 if(form.id==='import-form'){
   event.preventDefault();
   if(importTab==='image'){const files=[...form.elements.images.files];if(files.length>5||files.some(f=>f.size>10*1024*1024)){toast('演示最多选择 5 张图片，单张不超过 10MB。');return;}}
   freshDraft('demo');
 }else if(form.id==='review-form'){
   event.preventDefault();try{collectDraft();validateDraft();const index=state.recipes.findIndex(r=>r.id===draft.id);if(index>=0)state.recipes[index]=copy(draft);else{state.recipes.push(copy(draft));state.selected.push(draft.id);}state.preview=null;save();draft=null;navigate('recipes');toast('菜谱已保存，可以加入今晚的菜单。');}catch(e){$('#review-error').innerHTML=note(e.message,'error');toast(e.message);}
 }else if(form.id==='confirmation-form'){
   event.preventDefault();
   const seconds=Number(form.elements.seconds.value);
   if(!Number.isInteger(seconds)||seconds<5||seconds>600){toast('确认等待时间需为 5–600 秒的整数。');return;}
   run(async()=>{if(!state.session)return;const candidate=copy(state.session),now=elapsed(candidate);candidate.confirmation_seconds=seconds;await recalculateSession(candidate,now);state.settings.confirmation_seconds=seconds;commitSession(candidate,now);render();toast('确认等待时间已保存，当前设备任务也会使用新设置。');});
 }else if(form.id==='plan-form'){
   event.preventDefault();run(async()=>{
     const origin=Date.now(),target=new Date(form.elements.target.value).getTime(),seconds=Math.floor((target-origin)/1000);
     if(!Number.isFinite(seconds)||seconds<=0||seconds>604800)throw new Error('请选择未来一周内的开饭时间。');
     const recipes=selectedRecipes();if(!recipes.length)throw new Error('请至少选择一道菜。');
     const request=requestFor(recipes);request.target_finish_seconds=seconds;
     state.settings.confirmation_seconds=Number(form.elements.confirmation_seconds.value);
     const submit=form.querySelector('[type=submit]');submit.innerHTML='<span class="loading"></span> 正在安排锅灶与时间…';
     try{const plan=await api('/api/v1/plans/generate',request);state.preview={request,plan,origin,names:Object.fromEntries(recipes.map(r=>[r.id,r.name]))};error='';save();navigate('timeline');}finally{submit.innerHTML=`${icon('pot')} 生成烹饪计划`;}
   });
 }
});
document.addEventListener('change',event=>{if(event.target.id==='images')$('#file-list').textContent=[...event.target.files].map(f=>f.name).join('、') || '仅显示文件名，图片不会上传。';});
const countdownText=seconds=>`${String(Math.floor(seconds/60)).padStart(2,'0')}:${String(seconds%60).padStart(2,'0')}`;
function tick(){
 if(route!=='execute'||!state.session)return;
 const s=state.session,now=elapsed(s);
 if($('#demo-clock'))$('#demo-clock').textContent=`${clock(s.origin,now)}${s.paused?' · 已暂停':''}`;
 document.querySelectorAll('[data-countdown]').forEach(el=>{
   const e=s.execution.find(e=>e.task_id===el.dataset.countdown);if(!e)return;
   const remaining=Math.max(0,e.estimated_end-now),automatic=CookExecution.canAutoConfirm(s,e);
   const grace=Math.max(0,CookExecution.confirmationDeadline(s,e)-now);
   el.textContent=remaining?countdownText(remaining):'预计时间已到';
   el.classList.toggle('due',remaining===0);
   const label=document.querySelector(`[data-confirm-label="${e.task_id}"]`);
   const caption=document.querySelector(`[data-confirm-caption="${e.task_id}"]`);
   if(label)label.textContent=!remaining&&automatic?`确认完成 · ${countdownText(grace)} 后自动`:'确认并进入下一步';
   if(caption)caption.textContent=automatic?(remaining?`到时后再等待 ${CookExecution.confirmationSeconds(s)} 秒自动确认`:`${s.paused?'演示已暂停 · ':''}${grace?'倒计时结束后自动确认并衔接下一步':'等待调度同步确认…'}`):'本步骤需手动确认完成';
 });
}
let eligibility='';
async function driveExecution(){
 tick();
 const s=state.session;
 if(!s||s.paused||busy||!activeSession())return;
 const now=elapsed(s),ready=CookExecution.readyTasks(s,now);
 const signature=ready.map(t=>t.task_id).join(',');
 if(route==='execute'&&eligibility!==signature&&!$('#confirmation-form')?.contains(document.activeElement)){
   eligibility=signature;render();
 }
 if(Date.now()<autoRetryAt)return;
 const action=CookExecution.dueConfirmations(s,now).length?'auto-confirm':s.auto_continue&&ready.length?'continue':null;
 if(action){
   const ok=await run(()=>sessionAction(action));
   // Avoid a failing network request every second. Explicit actions can retry now.
   if(!ok)autoRetryAt=Date.now()+15000;
 }
}
setInterval(driveExecution,1000);
window.addEventListener('hashchange',()=>{error='';if(location.hash==='#kitchen')kitchenDraft=copy(state.kitchen);render();$('#app').scrollTo(0,0);window.scrollTo(0,0);});
render();
if(storageFailed)toast('浏览器存储不可用，当前数据可能无法保存。');
fetch('/api/health').then(r=>{if(!r.ok)throw new Error();return r.json();}).then(()=>{$('#connection').textContent='引擎已连接';$('#connection').className='connection online';}).catch(()=>{$('#connection').textContent='引擎未连接';$('#connection').className='connection offline';toast('请通过本地 Python 服务打开原型，以使用真实调度。');});
})();
