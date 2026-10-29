/* Fixed demo recipes. No content in this file is the result of AI recognition. */
(() => {
  const step = (id, recipe, name, duration, dependencies = [], attention = 'active', resources = {}) => ({
    id: `${recipe}_${id}`, recipe_id: recipe, name, duration_seconds: duration,
    dependencies: dependencies.map(d => `${recipe}_${d}`), attention_type: attention, resources
  });
  const recipes = [
    {id:'chicken',name:'可乐鸡翅',art:'chicken',servings:2,category:'荤菜',tag:'慢慢焖，更入味',favorite:true,holding:600,
      ingredients:'鸡翅 500g\n可乐 330ml\n生抽 2 勺\n姜 3 片',
      tasks:[step('prep','chicken','清洗鸡翅，切姜片',240),step('fry','chicken','煎至鸡翅两面金黄',300,['prep'],'active',{burner:1}),step('sauce','chicken','加入可乐和调味料',60,['fry'],'active',{burner:1}),step('simmer','chicken','小火焖煮，定时查看',900,['sauce'],'intermittent',{burner:1}),step('reduce','chicken','收汁并检查熟度',180,['simmer'],'active',{burner:1}),step('serve','chicken','鸡翅装盘',60,['reduce'])],
      holds:[{resource:'wok',start_task:'chicken_fry',end_task:'chicken_serve'},{resource:'plate',start_task:'chicken_serve'}]},
    {id:'eggs',name:'番茄炒蛋',art:'eggs',servings:2,category:'家常菜',tag:'酸甜开胃',favorite:true,holding:180,
      ingredients:'番茄 2 个\n鸡蛋 3 个\n盐 适量\n食用油 适量',
      tasks:[step('cut','eggs','清洗并切番茄',180),step('beat','eggs','打散鸡蛋',60),step('fry','eggs','滑炒鸡蛋',120,['beat'],'active',{burner:1}),step('mix','eggs','炒番茄，加入鸡蛋',180,['cut','fry'],'active',{burner:1}),step('serve','eggs','番茄炒蛋装盘',30,['mix'])],
      holds:[{resource:'wok',start_task:'eggs_fry',end_task:'eggs_serve'},{resource:'plate',start_task:'eggs_serve'}]},
    {id:'greens',name:'清炒生菜',art:'greens',servings:2,category:'素菜',tag:'最后炒，才鲜脆',favorite:false,holding:120,
      ingredients:'生菜 300g\n蒜 2 瓣\n盐 适量\n食用油 适量',
      tasks:[step('wash','greens','清洗生菜，切蒜末',180),step('fry','greens','蒜香快炒生菜',120,['wash'],'active',{burner:1}),step('serve','greens','生菜装盘',30,['fry'])],
      holds:[{resource:'wok',start_task:'greens_fry',end_task:'greens_serve'},{resource:'plate',start_task:'greens_serve'}]},
    {id:'rice',name:'香软米饭',art:'rice',servings:2,category:'主食',tag:'让电饭煲帮忙',favorite:false,holding:1200,
      ingredients:'大米 200g\n水 按电饭煲刻度',
      tasks:[step('wash','rice','淘米、加水并启动电饭煲',120),step('cook','rice','电饭煲自动煮饭',1800,['wash'],'passive'),step('serve','rice','确认米饭煮熟，盛饭',60,['cook'])],
      holds:[{resource:'rice_cooker',start_task:'rice_wash',end_task:'rice_serve'},{resource:'bowl',quantity:2,start_task:'rice_serve'}]}
  ];
  const notes = {
    chicken_prep: '鸡翅沥干并擦去表面水分；姜切薄片。生熟食材分开处理。',
    chicken_fry: '锅内放少量油，中小火煎约 150 秒后翻面，再煎约 150 秒；观察表面上色，避免焦糊。',
    chicken_sauce: '先放姜片、生抽，再倒入可乐；中火煮至微沸后转小火。',
    chicken_simmer: '盖锅盖保持小火，约每 3 分钟查看一次水量并翻动；不要离开正在加热的炉灶。',
    chicken_reduce: '先开中火翻动约 60 秒，再按汤汁情况调大火收汁；最后少量加盐，确认鸡肉熟透后关火。',
    chicken_serve: '关火后将鸡翅和酱汁装盘，锅中不再盛放食物后再释放炒锅。',
    eggs_cut: '番茄洗净去蒂，切成大小相近的小块；汁水一起保留。',
    eggs_beat: '鸡蛋打入碗中，加少量盐，搅打约 30 秒至蛋液均匀。',
    eggs_fry: '中火热油后倒入蛋液；先等约 20 秒，再轻推翻炒至刚凝固，暂盛出。',
    eggs_mix: '中小火炒番茄约 90 秒出汁，再加入鸡蛋；转大火翻炒约 30 秒，放少量盐后拌匀并关火。',
    eggs_serve: '将番茄和鸡蛋一起装盘，趁热食用。',
    greens_wash: '生菜逐片洗净沥水；蒜瓣拍碎切末，避免叶片带太多水入锅。',
    greens_fry: '中火炒蒜约 10 秒，加入生菜转大火翻炒；临出锅前加盐，叶片变软后及时关火。',
    greens_serve: '关火后立即装盘，避免继续受热失去脆嫩口感。',
    rice_wash: '淘米后按电饭煲刻度加水，合盖并按下煮饭键；确认设备已开始工作。',
    rice_cook: '保持锅盖关闭，让电饭煲自动完成煮饭。时间为估算，实际状态以设备提示为准。',
    rice_serve: '查看电饭煲是否已煮熟并转保温，小心蒸汽，翻松后盛入饭碗。'
  };
  recipes.forEach(recipe => recipe.tasks.forEach(task => { task.notes = notes[task.id] || ''; }));
  const resources = [
    ['burner','灶眼','flame',2,'加热设备'],['rice_cooker','电饭煲','pot',1,'加热设备'],['oven','烤箱','oven',0,'加热设备'],['microwave','微波炉','oven',1,'加热设备'],['air_fryer','空气炸锅','pot',0,'加热设备'],
    ['wok','炒锅','pan',1,'锅具'],['pot','汤锅','pot',1,'锅具'],['steamer','蒸锅','pot',0,'锅具'],
    ['board','菜板','board',1,'备菜与餐具'],['knife','菜刀','knife',1,'备菜与餐具'],['large_bowl','大碗','bowl',3,'备菜与餐具'],['bowl','小碗','bowl',4,'备菜与餐具'],['plate','盘子','plate',4,'备菜与餐具']
  ];
  window.CookDemo = {recipes, resources};
})();
