import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../widgets/common.dart';

class VaultScreen extends ConsumerStatefulWidget {
  const VaultScreen({super.key});

  @override
  ConsumerState<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends ConsumerState<VaultScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _hint = TextEditingController();
  final _recovery = TextEditingController();
  bool _acknowledged = false;
  bool _busy = false;
  bool _useRecovery = false;
  bool _obscure = true;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    _hint.dispose();
    _recovery.dispose();
    super.dispose();
  }

  Future<void> _setup() async {
    FocusScope.of(context).unfocus();
    if (_password.text.length < 8) {
      showAppSnack(context, 'Use at least 8 characters.', error: true);
      return;
    }
    if (_password.text != _confirm.text) {
      showAppSnack(context, 'Passwords do not match.', error: true);
      return;
    }
    if (!_acknowledged) {
      showAppSnack(
        context,
        'Please acknowledge the password warning.',
        error: true,
      );
      return;
    }
    setState(() => _busy = true);
    final ok = await ref
        .read(vaultProvider.notifier)
        .setup(_password.text, hint: _hint.text.trim());
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      final recovery = await ref
          .read(vaultProvider.notifier)
          .exportRecoveryKey();
      if (!mounted) return;
      if (recovery != null) {
        await _showRecovery(recovery);
      }
    } else {
      showAppSnack(
        context,
        ref.read(vaultProvider).error ?? 'Could not create the vault.',
        error: true,
      );
    }
  }

  Future<void> _unlock() async {
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    final ok = _useRecovery
        ? await ref
              .read(vaultProvider.notifier)
              .unlockWithRecovery(_recovery.text)
        : await ref.read(vaultProvider.notifier).unlock(_password.text);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      showAppSnack(
        context,
        ref.read(vaultProvider).error ?? 'Could not unlock the vault.',
        error: true,
      );
    }
  }

  Future<void> _showRecovery(String key) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Save your recovery key'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This key can unlock your vault if you forget the password. '
              'Store it somewhere safe and offline. We cannot recover it for you.',
            ),
            const SizedBox(height: 14),
            SelectableText(
              key,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: key));
              if (context.mounted) {
                showAppSnack(context, 'Recovery key copied.');
              }
            },
            child: const Text('Copy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('I saved it'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vault = ref.watch(vaultProvider);
    final setupMode = !vault.initialized;
    final colors = context.colors;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const BrandMark(size: 44),
                    const SizedBox(height: 28),
                    Text(
                      setupMode
                          ? 'Create your encrypted vault'
                          : 'Unlock BRASSPLATES',
                      style: context.theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      setupMode
                          ? 'Your notes, tasks and pictures are encrypted with a key derived from this password. '
                                'The password is never stored or sent anywhere.'
                          : 'Enter your vault password to decrypt your workspace.',
                      style: context.theme.textTheme.bodyMedium?.copyWith(
                        color: colors.onSurface.withValues(alpha: 0.65),
                      ),
                    ),
                    const SizedBox(height: 22),
                    if (setupMode) ...[
                      TextField(
                        controller: _password,
                        obscureText: _obscure,
                        decoration: InputDecoration(
                          labelText: 'Vault password',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _confirm,
                        obscureText: _obscure,
                        decoration: const InputDecoration(
                          labelText: 'Confirm password',
                          prefixIcon: Icon(Icons.lock_reset_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _hint,
                        decoration: const InputDecoration(
                          labelText: 'Password hint (optional)',
                          prefixIcon: Icon(Icons.lightbulb_outline),
                        ),
                      ),
                      const SizedBox(height: 12),
                      CheckboxListTile(
                        value: _acknowledged,
                        onChanged: (value) =>
                            setState(() => _acknowledged = value ?? false),
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: const Text(
                          'I understand that a lost password means lost data unless I keep my recovery key.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _busy ? null : _setup,
                        icon: _busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.shield_outlined),
                        label: const Text('Create encrypted vault'),
                      ),
                    ] else ...[
                      if (!_useRecovery) ...[
                        TextField(
                          controller: _password,
                          obscureText: _obscure,
                          autofocus: true,
                          onSubmitted: (_) => _unlock(),
                          decoration: InputDecoration(
                            labelText: 'Vault password',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscure
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                            ),
                          ),
                        ),
                      ] else ...[
                        TextField(
                          controller: _recovery,
                          autofocus: true,
                          decoration: const InputDecoration(
                            labelText: 'Recovery key',
                            prefixIcon: Icon(Icons.key_outlined),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _busy ? null : _unlock,
                        icon: _busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.lock_open_outlined),
                        label: Text(
                          _useRecovery ? 'Unlock with recovery key' : 'Unlock',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () =>
                            setState(() => _useRecovery = !_useRecovery),
                        child: Text(
                          _useRecovery
                              ? 'Use vault password instead'
                              : 'Use a recovery key',
                        ),
                      ),
                    ],
                    const Divider(height: 32),
                    Row(
                      children: [
                        Icon(
                          Icons.enhanced_encryption_outlined,
                          size: 16,
                          color: colors.onSurface.withValues(alpha: 0.5),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'AES-256-GCM · Argon2id · local-first.',
                            style: context.theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSurface.withValues(alpha: 0.5),
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
        ),
      ),
    );
  }
}
