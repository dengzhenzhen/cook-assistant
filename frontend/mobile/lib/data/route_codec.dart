import 'dart:convert';
import 'models.dart';

/// Keep typed recipe drafts in browser history when the editor is refreshed.
class AppExtraCodec extends Codec<Object?, Object?> {
  const AppExtraCodec();
  @override
  Converter<Object?, Object?> get encoder => const _EncodeExtra();
  @override
  Converter<Object?, Object?> get decoder => const _DecodeExtra();
}

class _EncodeExtra extends Converter<Object?, Object?> {
  const _EncodeExtra();
  @override
  Object? convert(Object? input) =>
      input is Recipe ? {'type': 'recipe', 'document': input.json} : input;
}

class _DecodeExtra extends Converter<Object?, Object?> {
  const _DecodeExtra();
  @override
  Object? convert(Object? input) {
    if (input is Map && input['type'] == 'recipe') {
      return Recipe(Map<String, dynamic>.from(input['document'] as Map));
    }
    return input;
  }
}
