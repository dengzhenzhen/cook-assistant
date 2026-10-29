"""One explicitly initiated real recipe parse, with no keys or raw output logged."""
import asyncio
from service.config import get_settings
from service.deepseek import complete,parse_result

async def main():
    content,usage=await complete(get_settings(),'番茄炒蛋，两人份：番茄2个切块，鸡蛋3个加少量盐打散。先中火炒鸡蛋1分钟盛出，炒番茄2分钟出汁，倒回鸡蛋翻炒30秒，放盐后关火装盘。切番茄与打鸡蛋可独立进行。')
    recipe=parse_result(content,'text')
    print({'name':recipe.name,'tasks':len(recipe.tasks),'has_notes':all(bool(t.notes) for t in recipe.tasks),'confirmed':recipe.confirmed,'usage':usage})
asyncio.run(main())
