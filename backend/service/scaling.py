"""Per-ingredient reference curves evaluated against the original recipe."""
from decimal import Decimal, localcontext, ROUND_HALF_UP
from .quantities import decimal_text
from .schemas import Recipe, ScalingRule

RULE_VERSION = 'ingredient-curves-1'
SEASONINGS = {'盐', '食盐', '白糖', '糖', '生抽', '老抽', '酱油', '醋', '胡椒粉', '辣椒粉', '鸡精', '蚝油'}
OILS = {'油', '食用油', '植物油', '花生油', '菜籽油', '橄榄油'}


def inherit_ingredient_rules(recipe: Recipe, previous: Recipe):
    """Old editors may write only name/quantity/unit. Preserve unambiguous rules.

    An explicitly supplied auto rule still resets a prior custom rule. Never
    guess which duplicate ingredient line corresponds to a previous one.
    """
    def key(ingredient):
        return ingredient.name.strip(), ingredient.amount.unit if ingredient.amount else ingredient.unit
    old, new_counts = {}, {}
    for ingredient in previous.ingredients:
        old.setdefault(key(ingredient), []).append(ingredient)
    for ingredient in recipe.ingredients:
        new_counts[key(ingredient)] = new_counts.get(key(ingredient), 0) + 1
    for ingredient in recipe.ingredients:
        choices = old.get(key(ingredient), [])
        if len(choices) != 1 or new_counts[key(ingredient)] != 1: continue
        if 'scaling' not in ingredient.model_fields_set:
            ingredient.scaling = choices[0].scaling.model_copy(deep=True)
        if 'role' not in ingredient.model_fields_set:
            ingredient.role = choices[0].role
    return recipe


def reference_rule(ingredient):
    rule = ingredient.scaling
    if rule.mode != 'auto': return rule, False
    if ingredient.name.strip() in OILS:
        return ScalingRule(mode='affine', fixed_fraction=0.3, note='锅底用油参考：30% 固定，70% 随食材变化'), True
    if ingredient.role == 'seasoning' or ingredient.name.strip() in SEASONINGS:
        return ScalingRule(mode='power', exponent=0.8, note='调味参考曲线，可按口味修改'), True
    if ingredient.role == 'liquid' or ingredient.name.strip() in {'水', '清水', '高汤'}:
        return ScalingRule(mode='manual', note='吸水、蒸发与锅具有关，请按实际情况确认'), True
    return ScalingRule(mode='linear', note='主辅料比例参考'), True


def multiplier(rule, ratio):
    if rule.mode == 'manual': return None
    if rule.mode == 'fixed': return Decimal(1)
    if rule.mode == 'power': return ratio ** Decimal(str(rule.exponent))
    if rule.mode == 'affine':
        fixed = Decimal(str(rule.fixed_fraction))
        return fixed + (1 - fixed) * ratio
    if rule.mode == 'piecewise':
        points = [(Decimal(str(p.ratio)), Decimal(str(p.factor))) for p in rule.points]
        for x, y in points:
            if ratio == x: return y
        for (x0, y0), (x1, y1) in zip(points, points[1:]):
            if x0 <= ratio <= x1: return y0 + (ratio - x0) * (y1 - y0) / (x1 - x0)
        return None
    return ratio


def display_number(value):
    return decimal_text(value.quantize(Decimal('0.01'), rounding=ROUND_HALF_UP))


def scale_recipe(recipe: Recipe, target_servings: int):
    ratio = Decimal(target_servings) / Decimal(recipe.servings)
    warnings = []
    if ratio != 1:
        warnings.append('用量为参考：烹饪时间、火力和锅具容量不会随份数自动改变，请核对步骤中的用量。')
    if ratio > 2 or ratio < Decimal('0.5'):
        warnings.append('本次份量超出原配方的 0.5–2 倍范围，建议重新核对容量、调味和分锅安排。')
    lines = []
    with localcontext() as context:
        context.prec = 28
        for ingredient in recipe.ingredients:
            rule, estimated = reference_rule(ingredient)
            amount = ingredient.amount
            factor = Decimal(1) if ratio == 1 else multiplier(rule, ratio)
            line_warnings = []
            scaled = amount.model_dump() if amount else {'kind': 'unknown', 'unit': ingredient.unit}
            quantity = ingredient.quantity
            if amount and amount.kind in ('exact', 'range') and factor is not None:
                value = Decimal(amount.value) * factor
                scaled['value'] = decimal_text(value)
                quantity = display_number(value)
                if amount.kind == 'range':
                    upper = Decimal(amount.upper) * factor
                    scaled['upper'] = decimal_text(upper)
                    quantity += '–' + display_number(upper)
                if amount.unit in ('个', '只', '颗', '根') and value != value.to_integral_value():
                    line_warnings.append('计数食材保留理论用量，请自行决定如何分取。')
                if estimated and ratio != 1 and rule.mode != 'linear':
                    line_warnings.append('使用默认参考曲线，请按配方和实际口味确认。')
            elif ratio != 1:
                line_warnings.append('此项保留原用量，需人工确认。')
            lines.append({**ingredient.model_dump(), 'quantity': quantity,
                          'unit': (amount.unit if amount and amount.kind in ('exact', 'range') else ingredient.unit), 'amount': scaled,
                          'original_quantity': ingredient.quantity, 'original_unit': ingredient.unit,
                          'effective_rule': rule.model_dump(), 'rule_estimated': estimated,
                          'factor': decimal_text(factor) if factor is not None else None,
                          'warnings': line_warnings})
    return {'recipe_id': recipe.recipe_id, 'name': recipe.name, 'base_servings': recipe.servings,
            'target_servings': target_servings, 'rule_version': RULE_VERSION,
            'ingredients': lines, 'warnings': warnings}
