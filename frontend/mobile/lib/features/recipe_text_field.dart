import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// WSA edits recipe text with Android's EditText instead of Flutter's IME
/// connection. Other platforms retain the normal inline form field.
class RecipeTextField extends StatefulWidget {
  const RecipeTextField({
    super.key,
    this.controller,
    this.initialValue,
    this.decoration = const InputDecoration(),
    this.keyboardType,
    this.validator,
    this.onChanged,
    this.maxLength,
    this.minLines,
    this.maxLines = 1,
  }) : assert(controller == null || initialValue == null);
  final TextEditingController? controller;
  final String? initialValue;
  final InputDecoration decoration;
  final TextInputType? keyboardType;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onChanged;
  final int? maxLength, minLines, maxLines;
  @override
  State<RecipeTextField> createState() => _RecipeTextFieldState();
}

class _RecipeTextFieldState extends State<RecipeTextField>
    with AutomaticKeepAliveClientMixin<RecipeTextField> {
  @override
  bool get wantKeepAlive => editing;
  static const channel = MethodChannel('kaifan/input_compat');
  late final owned = TextEditingController(text: widget.initialValue ?? '');
  bool native = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  bool editing = false;
  TextEditingController get controller => widget.controller ?? owned;
  @override
  void initState() {
    super.initState();
    detect();
  }

  Future<void> detect() async {
    if (!native) return;
    var detected = false;
    try {
      detected = await channel.invokeMethod<bool>('isWsa') ?? false;
    } on MissingPluginException {
      /* Flutter-only tests or hosts. */
    } on PlatformException {
      /* Retain standard input when the bridge is absent. */
    }
    if (mounted) setState(() => native = detected);
  }

  Future<void> edit() async {
    if (!native || editing) return;
    editing = true;
    updateKeepAlive();
    // Only Android EditText owns the input connection while its dialog is open.
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      final value = await channel.invokeMethod<String>('editRecipeText', {
        'text': controller.text,
        'title': widget.decoration.labelText ?? '编辑文本',
        'hint': widget.decoration.hintText,
        'multiline': (widget.maxLines ?? 2) > 1 || (widget.minLines ?? 1) > 1,
        'number': widget.keyboardType?.index == TextInputType.number.index,
        'maxLength': widget.maxLength,
      });
      if (value == null || !mounted) return;
      controller.value = TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
      );
      widget.onChanged?.call(value);
    } on PlatformException {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('无法打开编辑框，请重试。')));
      }
    } on MissingPluginException {
      if (mounted) setState(() => native = false);
    } finally {
      editing = false;
      if (mounted) updateKeepAlive();
    }
  }

  @override
  void dispose() {
    owned.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return TextFormField(
      controller: controller,
      decoration: native
          ? widget.decoration.copyWith(
              suffixIcon: IconButton(
                onPressed: edit,
                tooltip: '编辑${widget.decoration.labelText ?? '文本'}',
                icon: const Icon(Icons.edit_outlined),
              ),
            )
          : widget.decoration,
      readOnly: native,
      showCursor: native ? false : null,
      enableInteractiveSelection: !native,
      onTap: native ? edit : null,
      keyboardType: widget.keyboardType,
      validator: widget.validator,
      onChanged: widget.onChanged,
      maxLength: widget.maxLength,
      minLines: widget.minLines,
      maxLines: widget.maxLines,
    );
  }
}
