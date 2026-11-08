"""Compare a real kitchen schedule against the user's menu preferences."""
import math

WORK_MINUTES = {'low': 10, 'medium': 30, 'high': 90}


def assess_menu(preferences, recipes, plan, portions):
    if preferences is None: return None
    # Exclude waiting until a specified future start; include all work and
    # passive cooking after the earliest task actually starts.
    seconds = max(t.end_seconds for t in plan.tasks) - min(t.start_seconds for t in plan.tasks)
    work_seconds = sum(t.duration_seconds for recipe in recipes for t in recipe.tasks if t.attention_type != 'passive')
    limit = WORK_MINUTES[preferences.effort]
    warnings = []
    if seconds > preferences.time_minutes * 60:
        warnings.append(f'按当前厨房排程约需 {math.ceil(seconds / 60)} 分钟，超过 {preferences.time_minutes} 分钟目标，可返回菜单减菜或换菜。')
    if work_seconds > limit * 60:
        warnings.append(f'操作及看管约 {math.ceil(work_seconds / 60)} 人分钟，超出当前工作量倾向（参考上限 {limit} 人分钟）。')
    scaled = any(portions.get(r.recipe_id, r.servings) != r.servings for r in recipes)
    if scaled:
        warnings.append('本餐更改了份量，排程时长仍按原配方估算，请确认备料量、锅具容量和实际烹饪时间。')
    return {'preferences': preferences.model_dump(), 'estimated_total_minutes': math.ceil(seconds / 60),
            'estimated_work_minutes': math.ceil(work_seconds / 60), 'work_limit_minutes': limit,
            'within_time_target': seconds <= preferences.time_minutes * 60,
            'within_work_target': work_seconds <= limit * 60,
            'portions_changed': scaled, 'warnings': warnings}
