import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_services.dart';
import '../services/gh_login_session.dart';
import 'theme/glass.dart';
import 'widgets/glass_slab.dart';

/// Runs `gh auth login` and shows the one-time code while it waits.
class AddAccountDialog extends StatefulWidget {
  const AddAccountDialog({super.key, required this.createSession});

  /// The dialog needs no more than this, which also lets tests drive the flow
  /// without a real gh process.
  final GhLoginSession Function() createSession;

  /// Returns true when a login completed successfully.
  static Future<bool> show(BuildContext context, AppServices services) async {
    final added = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          AddAccountDialog(createSession: services.createLoginSession),
    );
    return added ?? false;
  }

  @override
  State<AddAccountDialog> createState() => _AddAccountDialogState();
}

class _AddAccountDialogState extends State<AddAccountDialog> {
  late final GhLoginSession _session;
  StreamSubscription<String>? _codeSubscription;
  StreamSubscription<String>? _urlSubscription;
  String? _code;
  String? _url;
  bool _finished = false;
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    _session = widget.createSession();
    _codeSubscription = _session.codes.listen((code) {
      if (mounted) setState(() => _code = code);
    });
    _urlSubscription = _session.urls.listen((url) {
      if (mounted) setState(() => _url = url);
    });
    _run();
  }

  Future<void> _run() async {
    final ok = await _session.run();
    if (!mounted) return;
    setState(() => _finished = true);
    _close(ok);
  }

  /// Closes the dialog exactly once.
  ///
  /// Cancelling kills the process, which makes the awaited run() complete and
  /// try to close again. A second pop would tear down the screen underneath,
  /// leaving an empty window.
  void _close(bool result) {
    if (_closed) return;
    _closed = true;
    Navigator.of(context).pop(result);
  }

  @override
  void dispose() {
    _codeSubscription?.cancel();
    _urlSubscription?.cancel();
    super.dispose();
  }

  /// Launched without a terminal, gh prints the activation URL instead of
  /// opening it, so the app opens it on the user's behalf.
  Future<void> _openUrl() async {
    final url = _url;
    if (url == null) return;
    await Process.run('/usr/bin/open', [url]);
  }

  void _cancel() {
    _session.cancel();
    _close(false);
  }

  @override
  Widget build(BuildContext context) {
    // A dialog sits outside the Scaffold, so it carries no Material of its
    // own. Without one, Flutter falls back to its unstyled-text warning and
    // paints every string with a yellow underline.
    return Material(
      type: MaterialType.transparency,
      child: Center(
        child: SizedBox(
          width: 400,
          child: GlassSlab(
            lit: _code != null,
            accent: Glass.accents.first,
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ADD IDENTITY', style: Glass.eyebrow(context)),
                const SizedBox(height: 10),
                Text(
                  _code == null
                      ? 'Starting the GitHub CLI…'
                      : 'Enter this code on GitHub',
                  style: Glass.display(context, size: 18),
                ),
                const SizedBox(height: 18),
                if (_code == null)
                  const Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else
                  Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SelectableText(
                          _code!,
                          style: Glass.mono(
                            context,
                            size: 26,
                            weight: FontWeight.w600,
                            color: Glass.primaryText(context),
                          ).copyWith(letterSpacing: 3),
                        ),
                        const SizedBox(width: 10),
                        IconButton(
                          tooltip: 'Copy code',
                          iconSize: 16,
                          visualDensity: VisualDensity.compact,
                          color: Glass.secondaryText(context),
                          icon: const Icon(Icons.copy),
                          onPressed: () =>
                              Clipboard.setData(ClipboardData(text: _code!)),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 20),
                Text(
                  'This closes on its own once GitHub confirms the login.',
                  style: Glass.body(context, size: 12),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    TextButton(
                      onPressed: _finished ? null : _cancel,
                      style: TextButton.styleFrom(
                        foregroundColor: Glass.primaryText(
                          context,
                        ).withValues(alpha: 0.75),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 9,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(
                            color: Glass.primaryText(
                              context,
                            ).withValues(alpha: 0.14),
                          ),
                        ),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(fontSize: 12.5),
                      ),
                    ),
                    const Spacer(),
                    if (_url != null)
                      FilledButton.icon(
                        onPressed: _openUrl,
                        icon: const Icon(Icons.open_in_new, size: 15),
                        label: const Text(
                          'Open GitHub',
                          style: TextStyle(fontSize: 12.5),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: Glass.accents.first,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
