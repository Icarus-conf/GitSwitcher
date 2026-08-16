import 'dart:io';

import 'package:flutter/material.dart';

import '../models/account.dart';
import '../services/account_resolver.dart';
import '../services/profile_store.dart';
import 'theme/glass.dart';
import 'widgets/glass_slab.dart';

/// One identity, rendered as a slab that is lit when the account is active.
class AccountSlab extends StatefulWidget {
  const AccountSlab({
    super.key,
    required this.resolved,
    required this.profile,
    required this.accent,
    required this.onSave,
    required this.onApplyToRepo,
  });

  final ResolvedAccount resolved;
  final AccountProfile? profile;
  final Color accent;
  final Future<void> Function(Account) onSave;
  final Future<void> Function(Account) onApplyToRepo;

  @override
  State<AccountSlab> createState() => _AccountSlabState();
}

class _AccountSlabState extends State<AccountSlab> {
  late final TextEditingController _label;
  late final TextEditingController _gitName;
  late final TextEditingController _gitEmail;
  late final TextEditingController _sshKeyPath;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    final account = widget.resolved.account;
    _label = TextEditingController(text: account.label);
    _gitName = TextEditingController(text: account.gitName);
    _gitEmail = TextEditingController(text: account.gitEmail);
    _sshKeyPath = TextEditingController(text: account.sshKeyPath);
  }

  @override
  void dispose() {
    _label.dispose();
    _gitName.dispose();
    _gitEmail.dispose();
    _sshKeyPath.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    await widget.onSave(widget.resolved.account.copyWith(
      label: _label.text.trim(),
      gitName: _gitName.text.trim(),
      gitEmail: _gitEmail.text.trim(),
      sshKeyPath: _sshKeyPath.text.trim(),
    ));
    if (mounted) setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    final resolved = widget.resolved;
    final account = resolved.account;
    final blocked = resolved.disabledReason;

    return GlassSlab(
      lit: resolved.isActive,
      accent: widget.accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _Avatar(
                path: widget.profile?.avatarPath,
                accent: widget.accent,
                lit: resolved.isActive,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      account.label.isNotEmpty
                          ? account.label
                          : widget.profile?.profile.displayName ??
                              account.ghUsername,
                      style: Glass.display(context),
                    ),
                    const SizedBox(height: 2),
                    // The machine's name for this identity, set in mono.
                    Text(account.ghUsername, style: Glass.mono(context)),
                  ],
                ),
              ),
              if (resolved.isActive) _LiveDot(accent: widget.accent),
            ],
          ),
          if (blocked != null) ...[
            const SizedBox(height: 12),
            _Problem(text: blocked),
          ],
          const SizedBox(height: 14),
          _Summary(account: account, editing: _editing),
          const SizedBox(height: 12),
          if (_editing) ...[
            _Field(controller: _label, label: 'Menu label', hint: 'Work'),
            _Field(
              controller: _gitName,
              label: 'Commit name',
              hint: 'Muhammad Fathy',
              mono: true,
            ),
            _Field(
              controller: _gitEmail,
              label: 'Commit email',
              hint: 'you@example.com',
              mono: true,
            ),
            _Field(
              controller: _sshKeyPath,
              label: 'SSH private key',
              hint: '~/.ssh/id_ed25519',
              mono: true,
            ),
            const SizedBox(height: 4),
          ],
          Row(
            children: [
              _QuietButton(
                label: _editing ? 'Cancel' : 'Edit',
                onPressed: () => setState(() => _editing = !_editing),
              ),
              const SizedBox(width: 8),
              _QuietButton(
                label: 'Set for a repo',
                icon: Icons.folder_outlined,
                onPressed: () => widget.onApplyToRepo(account),
              ),
              const Spacer(),
              if (_editing)
                _AccentButton(
                  label: 'Save',
                  accent: widget.accent,
                  onPressed: _handleSave,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// What this identity will actually change, in the machine's own words.
class _Summary extends StatelessWidget {
  const _Summary({required this.account, required this.editing});

  final Account account;
  final bool editing;

  @override
  Widget build(BuildContext context) {
    if (editing) return const SizedBox.shrink();

    final rows = <(String, String, bool)>[
      ('commits as', account.gitEmail, account.gitEmail.isNotEmpty),
      ('signs with', _shorten(account.sshKeyPath), account.sshKeyPath.isNotEmpty),
    ];

    return Column(
      children: [
        for (final (label, value, set) in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 74,
                  child: Text(label, style: Glass.body(context, size: 12)),
                ),
                Expanded(
                  child: Text(
                    set ? value : 'not set — this step is skipped',
                    style: set
                        ? Glass.mono(context,
                            color: Glass.primaryText(context)
                                .withValues(alpha: 0.75))
                        : Glass.body(context, size: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  static String _shorten(String path) {
    if (path.isEmpty) return path;
    final home = Platform.environment['HOME'];
    if (home != null && path.startsWith(home)) {
      return '~${path.substring(home.length)}';
    }
    return path;
  }
}

/// Shown only when gh cannot switch to this account at all.
class _Problem extends StatelessWidget {
  const _Problem({required this.text});

  final String text;

  static const Color _red = Color(0xFFFF453A);

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.error_outline, size: 14, color: _red),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: Glass.body(context, size: 12).copyWith(color: _red),
          ),
        ),
      ],
    );
  }
}

class _LiveDot extends StatelessWidget {
  const _LiveDot({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: Glass.live,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Glass.live.withValues(alpha: 0.6),
                blurRadius: 8,
              ),
            ],
          ),
        ),
        const SizedBox(width: 7),
        Text('IN USE', style: Glass.eyebrow(context)),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.path,
    required this.accent,
    required this.lit,
  });

  final String? path;
  final Color accent;
  final bool lit;

  @override
  Widget build(BuildContext context) {
    const size = 42.0;

    Widget image = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      color: accent.withValues(alpha: 0.18),
      child: Icon(Icons.person_outline, size: 22, color: accent),
    );

    if (path != null) {
      image = Image.file(
        File(path!),
        width: size,
        height: size,
        fit: BoxFit.cover,
        // A cached file can vanish underneath us; fall back rather than
        // showing a broken-image glyph.
        errorBuilder: (_, _, _) => image,
      );
    }

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: lit ? accent : accent.withValues(alpha: 0.28),
          width: 1.5,
        ),
      ),
      child: ClipOval(child: image),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    required this.hint,
    this.mono = false,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final dark = Glass.isDark(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: Glass.eyebrow(context)),
          const SizedBox(height: 5),
          TextField(
            controller: controller,
            style: mono
                ? Glass.mono(context,
                    size: 12.5, color: Glass.primaryText(context))
                : TextStyle(fontSize: 13, color: Glass.primaryText(context)),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: Glass.body(context, size: 12.5),
              isDense: true,
              filled: true,
              fillColor: dark
                  ? Colors.black.withValues(alpha: 0.22)
                  : Colors.white.withValues(alpha: 0.62),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(9),
                borderSide: BorderSide(
                  color: Glass.primaryText(context).withValues(alpha: 0.10),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(9),
                borderSide: BorderSide(
                  color: Glass.primaryText(context).withValues(alpha: 0.10),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(9),
                borderSide: BorderSide(
                  color: Glass.accents.first.withValues(alpha: 0.8),
                  width: 1.4,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuietButton extends StatelessWidget {
  const _QuietButton({required this.label, required this.onPressed, this.icon});

  final String label;
  final VoidCallback onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: Glass.primaryText(context).withValues(alpha: 0.8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: Glass.primaryText(context).withValues(alpha: 0.14),
          ),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14),
            const SizedBox(width: 5),
          ],
          Text(label, style: const TextStyle(fontSize: 12.5)),
        ],
      ),
    );
  }
}

class _AccentButton extends StatelessWidget {
  const _AccentButton({
    required this.label,
    required this.accent,
    required this.onPressed,
  });

  final String label;
  final Color accent;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      child: Text(label, style: const TextStyle(fontSize: 12.5)),
    );
  }
}
