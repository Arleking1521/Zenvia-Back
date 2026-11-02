import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/parent_repository.dart';
import '../l10n/app_strings.dart';

Future<bool> showParentPinVerifyDialog({
  required BuildContext context,
  required ParentRepository repository,
  String? title,
  String? message,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);

  final route = DialogRoute<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ParentPinVerifyDialog(
      repository: repository,
      title: title ?? context.tr('parentPin'),
      message: message ?? context.tr('enterPinToExit'),
    ),
  );

  final result = await navigator.push<bool>(route);

  // Navigator.push завершается сразу после pop(result), а обратная анимация
  // DialogRoute в этот момент ещё может идти. Ждём полного удаления диалога
  // из дерева, прежде чем родительский код сможет закрыть ChildRootShell.
  await route.completed;

  return result == true;
}

Future<bool> showParentPinSetupDialog({
  required BuildContext context,
  required ParentRepository repository,
  bool changing = false,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);

  final route = DialogRoute<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ParentPinSetupDialog(
      repository: repository,
      changing: changing,
    ),
  );

  final result = await navigator.push<bool>(route);
  await route.completed;

  return result == true;
}

class _ParentPinVerifyDialog extends StatefulWidget {
  final ParentRepository repository;
  final String title;
  final String message;

  const _ParentPinVerifyDialog({
    required this.repository,
    required this.title,
    required this.message,
  });

  @override
  State<_ParentPinVerifyDialog> createState() => _ParentPinVerifyDialogState();
}

class _ParentPinVerifyDialogState extends State<_ParentPinVerifyDialog> {
  final TextEditingController _pinController = TextEditingController();

  String? _error;
  bool _loading = false;

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading) return;

    final pin = _pinController.text.trim();
    if (pin.length != 4) {
      setState(() {
        _error = context.tr('pin4Digits');
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final valid = await widget.repository.verifyParentPin(pin);
      if (!mounted) return;

      if (valid) {
        Navigator.of(context).pop(true);
        return;
      }

      setState(() {
        _loading = false;
        _error = context.tr('wrongPin');
        _pinController.clear();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.message),
          const SizedBox(height: 14),
          TextField(
            controller: _pinController,
            autofocus: true,
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: 4,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(4),
            ],
            decoration: const InputDecoration(
              labelText: 'PIN',
              hintText: '••••',
              counterText: '',
            ),
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: const TextStyle(color: Colors.red),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(false),
          child: Text(context.tr('cancel')),
        ),
        FilledButton(
          onPressed: _loading ? null : _submit,
          child: _loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(context.tr('confirm')),
        ),
      ],
    );
  }
}

class _ParentPinSetupDialog extends StatefulWidget {
  final ParentRepository repository;
  final bool changing;

  const _ParentPinSetupDialog({
    required this.repository,
    required this.changing,
  });

  @override
  State<_ParentPinSetupDialog> createState() => _ParentPinSetupDialogState();
}

class _ParentPinSetupDialogState extends State<_ParentPinSetupDialog> {
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _pinController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();

  String? _error;
  bool _loading = false;

  @override
  void dispose() {
    _passwordController.dispose();
    _pinController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading) return;

    final password = _passwordController.text;
    final pin = _pinController.text.trim();
    final confirm = _confirmController.text.trim();

    if (password.isEmpty) {
      setState(() => _error = context.tr('enterParentPassword'));
      return;
    }

    if (pin.length != 4) {
      setState(() => _error = context.tr('pinMust4'));
      return;
    }

    if (pin != confirm) {
      setState(() => _error = context.tr('pinMismatch'));
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await widget.repository.setParentPin(
        password: password,
        pin: pin,
        pinConfirm: confirm,
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.changing
            ? context.tr('changeParentPin')
            : context.tr('createParentPin'),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(context.tr('pinNeededHint')),
            const SizedBox(height: 14),
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: context.tr('parentPassword'),
              ),
            ),
            const SizedBox(height: 10),
            _PinField(controller: _pinController, label: context.tr('newPin')),
            const SizedBox(height: 10),
            _PinField(
              controller: _confirmController,
              label: context.tr('repeatPin'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: const TextStyle(color: Colors.red),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(false),
          child: Text(context.tr('cancel')),
        ),
        FilledButton(
          onPressed: _loading ? null : _submit,
          child: _loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(context.tr('save')),
        ),
      ],
    );
  }
}

class _PinField extends StatelessWidget {
  final TextEditingController controller;
  final String label;

  const _PinField({required this.controller, required this.label});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: true,
      enableSuggestions: false,
      autocorrect: false,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      maxLength: 4,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(4),
      ],
      decoration: InputDecoration(
        labelText: label,
        hintText: '••••',
        counterText: '',
      ),
    );
  }
}
