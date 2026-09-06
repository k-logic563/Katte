import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../category_providers.dart';
import '../models/shopping_category.dart';

class CategoryManagementPage extends ConsumerWidget {
  const CategoryManagementPage({required this.groupId, super.key});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesByGroupProvider(groupId));
    return Scaffold(
      appBar: AppBar(title: const Text('カテゴリ')),
      body: categories.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('カテゴリを読み込めませんでした。'),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () =>
                    ref.invalidate(categoriesByGroupProvider(groupId)),
                child: const Text('再試行'),
              ),
            ],
          ),
        ),
        data: (categories) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            if (categories.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Text('カテゴリはまだありません。', textAlign: TextAlign.center),
              ),
            for (final category in categories)
              ListTile(
                key: Key('category-${category.id}'),
                title: Text(category.name),
                trailing: PopupMenuButton<_CategoryAction>(
                  tooltip: '${category.name}のメニュー',
                  onSelected: (action) {
                    switch (action) {
                      case _CategoryAction.rename:
                        _showNameDialog(context, category: category);
                      case _CategoryAction.delete:
                        _confirmDelete(context, ref, category);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: _CategoryAction.rename,
                      child: Text('編集'),
                    ),
                    PopupMenuItem(
                      value: _CategoryAction.delete,
                      child: Text('削除'),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('add-category-button'),
              onPressed: () => _showNameDialog(context),
              icon: const Icon(Icons.add),
              label: const Text('カテゴリを追加'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showNameDialog(
    BuildContext context, {
    ShoppingCategory? category,
  }) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CategoryNameDialog(groupId: groupId, category: category),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    ShoppingCategory category,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('「${category.name}」を削除しますか？'),
        content: const Text('このカテゴリの商品は「未分類」に移動します。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            key: const Key('confirm-delete-category-button'),
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final succeeded = await ref
        .read(categoryControllerProvider.notifier)
        .delete(groupId, category.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(succeeded ? 'カテゴリを削除しました' : 'カテゴリを削除できませんでした。')),
    );
  }
}

enum _CategoryAction { rename, delete }

class _CategoryNameDialog extends ConsumerStatefulWidget {
  const _CategoryNameDialog({required this.groupId, this.category});

  final String groupId;
  final ShoppingCategory? category;

  @override
  ConsumerState<_CategoryNameDialog> createState() =>
      _CategoryNameDialogState();
}

class _CategoryNameDialogState extends ConsumerState<_CategoryNameDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller;
  var _isSaving = false;
  String? _operationError;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.category?.name);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSaving || !_formKey.currentState!.validate()) {
      return;
    }
    setState(() {
      _isSaving = true;
      _operationError = null;
    });
    final notifier = ref.read(categoryControllerProvider.notifier);
    final succeeded = widget.category == null
        ? await notifier.create(widget.groupId, _controller.text)
        : await notifier.rename(
            widget.groupId,
            widget.category!,
            _controller.text,
          );
    if (!mounted) {
      return;
    }
    if (succeeded) {
      FocusScope.of(context).unfocus();
      Navigator.of(context).pop();
      return;
    }
    final error = ref.read(categoryControllerProvider).error;
    setState(() {
      _isSaving = false;
      _operationError = error is CategoryOperationException
          ? error.message
          : '更新できませんでした。';
    });
  }

  @override
  Widget build(BuildContext context) {
    final isCreate = widget.category == null;
    return AlertDialog(
      title: Text(isCreate ? 'カテゴリを追加' : 'カテゴリ名を編集'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          key: const Key('category-name-field'),
          controller: _controller,
          autofocus: true,
          maxLength: categoryNameMaxLength,
          decoration: InputDecoration(
            labelText: 'カテゴリ名',
            errorText: _operationError,
          ),
          validator: validateCategoryName,
          onFieldSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          key: const Key('save-category-button'),
          onPressed: _isSaving ? null : _submit,
          child: Text(isCreate ? '追加' : '保存'),
        ),
      ],
    );
  }
}
