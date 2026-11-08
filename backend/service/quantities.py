"""Conservative parsing of ingredient quantities; never invent unit conversions."""
import re
from decimal import Decimal, InvalidOperation
from unicodedata import normalize

UNITS = {'克': 'g', '千克': 'kg', '公斤': 'kg', '毫升': 'ml', '升': 'l', '公克': 'g',
         'g': 'g', 'kg': 'kg', 'ml': 'ml', 'l': 'l', '个': '个', '只': '只', '颗': '颗',
         '根': '根', '片': '片', '瓣': '瓣', '斤': '斤', '勺': '勺', '小勺': '小勺',
         '大勺': '大勺', '杯': '杯', '碗': '碗', '把': '把', '袋': '袋'}
DIGITS = dict(zip('零一二三四五六七八九两', [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 2]))


def decimal_text(value):
    result = format(value, 'f')
    return result.rstrip('0').rstrip('.') if '.' in result else result


def number(text):
    text = text.strip()
    if text == '半': return Decimal('0.5')
    if text in DIGITS: return Decimal(DIGITS[text])
    if re.fullmatch('[一二三四五六七八九两]?十[一二三四五六七八九]?', text):
        before, after = text.split('十')
        return Decimal(DIGITS.get(before, 1) * 10 + DIGITS.get(after, 0))
    if '/' in text:
        parts = text.split('/')
        if len(parts) != 2: raise ValueError('invalid fraction')
        numerator, denominator = map(Decimal, parts)
        if denominator <= 0: raise ValueError('invalid denominator')
        result = numerator / denominator
    else:
        result = Decimal(text)
    if not result.is_finite() or result < 0 or result > Decimal('1000000000'):
        raise ValueError('invalid quantity')
    return result


def parse_amount(quantity, unit=''):
    text = normalize('NFKC', str(quantity)).strip()
    unit = normalize('NFKC', str(unit)).strip()
    canonical_unit = UNITS.get(unit, unit)
    result = {'kind': 'unknown', 'value': None, 'upper': None, 'unit': canonical_unit}
    if any(word in text for word in ('适量', '少许', '酌量', '随意')):
        return {**result, 'kind': 'to_taste'}
    # Split a unit suffix only if it is unambiguous and agrees with the unit column.
    suffix = next((u for u in sorted(UNITS, key=len, reverse=True) if text.endswith(u)), None)
    if suffix:
        if unit and UNITS[suffix] != canonical_unit: return result
        canonical_unit = UNITS[suffix]
        text = text[:-len(suffix)].strip()
    result['unit'] = canonical_unit
    try:
        bounds = re.split(r'\s*(?:~|～|至|到|–|—|-)\s*', text)
        if len(bounds) == 2:
            low, high = map(number, bounds)
            if low > high: return result
            return {**result, 'kind': 'range', 'value': decimal_text(low), 'upper': decimal_text(high)}
        value = number(text)
        return {**result, 'kind': 'exact', 'value': decimal_text(value)}
    except (InvalidOperation, ValueError, ZeroDivisionError):
        return result
