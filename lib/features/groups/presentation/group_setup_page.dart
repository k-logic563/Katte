import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../group_providers.dart';

class GroupSetupPage extends ConsumerWidget {
  const GroupSetupPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(userGroupsProvider);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: groups.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => _GroupLoadError(
              onRetry: () => ref.invalidate(userGroupsProvider),
            ),
            data: (_) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(),
                Text(
                  'Katte',
                  style: Theme.of(context).textTheme.headlineMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                Text(
                  '家族と買い物リストを共有しよう',
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const Spacer(),
                FilledButton.icon(
                  key: const Key('open-create-group-button'),
                  onPressed: () => _openCreateGroupSheet(context),
                  icon: const Icon(Icons.add),
                  label: const Text('グループを作成'),
                ),
                const SizedBox(height: 16),
                const Text('または', textAlign: TextAlign.center),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  key: const Key('open-join-group-button'),
                  onPressed: () => _openJoinGroupSheet(context),
                  icon: const Icon(Icons.group_add_outlined),
                  label: const Text('招待コードで参加'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openCreateGroupSheet(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _CreateGroupSheet(),
    );
  }

  Future<void> _openJoinGroupSheet(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _JoinGroupSheet(),
    );
  }
}

class _CreateGroupSheet extends ConsumerStatefulWidget {
  const _CreateGroupSheet();

  @override
  ConsumerState<_CreateGroupSheet> createState() => _CreateGroupSheetState();
}

class _CreateGroupSheetState extends ConsumerState<_CreateGroupSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() => _errorMessage = null);
    final succeeded = await ref
        .read(groupControllerProvider.notifier)
        .createGroup(_nameController.text.trim());
    if (!mounted) {
      return;
    }
    if (succeeded) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _errorMessage = ref.read(groupControllerProvider).error.toString();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isSaving = ref.watch(groupControllerProvider).isLoading;
    return _GroupForm(
      title: 'グループを作成',
      formKey: _formKey,
      field: TextFormField(
        key: const Key('group-name-field'),
        controller: _nameController,
        autofocus: true,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(labelText: 'グループ名'),
        validator: (value) =>
            value == null || value.trim().isEmpty ? 'グループ名を入力してください' : null,
        onFieldSubmitted: (_) {
          if (!isSaving) {
            _submit();
          }
        },
      ),
      errorMessage: _errorMessage,
      buttonKey: const Key('create-group-button'),
      buttonLabel: '作成する',
      isSaving: isSaving,
      onSubmit: _submit,
    );
  }
}

class _JoinGroupSheet extends ConsumerStatefulWidget {
  const _JoinGroupSheet();

  @override
  ConsumerState<_JoinGroupSheet> createState() => _JoinGroupSheetState();
}

class _JoinGroupSheetState extends ConsumerState<_JoinGroupSheet> {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  String? _errorMessage;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() => _errorMessage = null);
    final succeeded = await ref
        .read(groupControllerProvider.notifier)
        .joinGroup(_codeController.text);
    if (!mounted) {
      return;
    }
    if (succeeded) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _errorMessage = ref.read(groupControllerProvider).error.toString();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isSaving = ref.watch(groupControllerProvider).isLoading;
    return _GroupForm(
      title: '招待コードで参加',
      formKey: _formKey,
      field: TextFormField(
        key: const Key('invite-code-field'),
        controller: _codeController,
        autofocus: true,
        textCapitalization: TextCapitalization.characters,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(labelText: '招待コード'),
        validator: (value) =>
            value == null || value.trim().isEmpty ? '招待コードを入力してください' : null,
        onFieldSubmitted: (_) {
          if (!isSaving) {
            _submit();
          }
        },
      ),
      errorMessage: _errorMessage,
      buttonKey: const Key('join-group-button'),
      buttonLabel: '参加する',
      isSaving: isSaving,
      onSubmit: _submit,
    );
  }
}

class _GroupForm extends StatelessWidget {
  const _GroupForm({
    required this.title,
    required this.formKey,
    required this.field,
    required this.errorMessage,
    required this.buttonKey,
    required this.buttonLabel,
    required this.isSaving,
    required this.onSubmit,
  });

  final String title;
  final GlobalKey<FormState> formKey;
  final Widget field;
  final String? errorMessage;
  final Key buttonKey;
  final String buttonLabel;
  final bool isSaving;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        24,
        24,
        24,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 20),
            field,
            if (errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              key: buttonKey,
              onPressed: isSaving ? null : onSubmit,
              child: isSaving
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(buttonLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupLoadError extends StatelessWidget {
  const _GroupLoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('グループを読み込めませんでした。'),
        const SizedBox(height: 16),
        OutlinedButton(onPressed: onRetry, child: const Text('再試行')),
      ],
    );
  }
}
