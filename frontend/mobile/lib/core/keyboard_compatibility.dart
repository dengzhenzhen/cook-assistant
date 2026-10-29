import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Reset WSA's cached IME buffer after a field is completely cleared. Never
/// rewrites text or composing ranges, so normal Android IME composition stays intact.
class KeyboardCompatibility extends StatefulWidget {
  const KeyboardCompatibility({super.key, required this.child});
  final Widget child;
  @override
  State<KeyboardCompatibility> createState() => _KeyboardCompatibilityState();
}

class _KeyboardCompatibilityState extends State<KeyboardCompatibility> {
  static const channel = MethodChannel('kaifan/input_compat');
  TextEditingController? controller;
  String previous = '';
  bool isWsa = false;
  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(trackFocus);
    initialize();
  }

  Future<void> initialize() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final detected = await channel.invokeMethod<bool>('isWsa') ?? false;
      if (!mounted) return;
      isWsa = detected;
      if (isWsa) trackFocus();
    } on MissingPluginException {
      /* Native bridge is Android-only. */
    }
  }

  void trackFocus() {
    if (!isWsa || !mounted) return;
    final editable = FocusManager.instance.primaryFocus?.context
        ?.findAncestorStateOfType<EditableTextState>();
    final next = editable?.widget.readOnly == true
        ? null
        : editable?.widget.controller;
    if (identical(next, controller)) return;
    controller?.removeListener(onEdit);
    controller = next;
    previous = next?.text ?? '';
    next?.addListener(onEdit);
  }

  void onEdit() {
    final current = controller;
    if (current == null) return;
    final cleared = previous.isNotEmpty && current.text.isEmpty;
    previous = current.text;
    if (!cleared) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted ||
          !identical(controller, current) ||
          current.text.isNotEmpty) {
        return;
      }
      try {
        await SystemChannels.textInput.invokeMethod<void>(
          'TextInput.setEditingState',
          current.value.toJSON(),
        );
        if (mounted && identical(controller, current) && current.text.isEmpty) {
          await channel.invokeMethod<void>('resetAfterClear');
        }
      } on PlatformException {
        /* Keep the editable field usable if the IME disappeared. */
      } on MissingPluginException {
        /* Widget tests and unsupported hosts have no bridge. */
      }
    });
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(trackFocus);
    controller?.removeListener(onEdit);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
