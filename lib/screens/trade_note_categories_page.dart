// lib/screens/trade_note_categories_page.dart

import 'package:flutter/material.dart';

import '../repositories/note_subject_repository.dart';

class TradeNoteCategoriesPage extends StatefulWidget {
  const TradeNoteCategoriesPage({super.key});

  @override
  State<TradeNoteCategoriesPage> createState() =>
      _TradeNoteCategoriesPageState();
}

class _TradeNoteCategoriesPageState extends State<TradeNoteCategoriesPage> {
  final repository = NoteSubjectRepository.instance;
  final searchController = TextEditingController();

  List<Map<String, Object?>> roots = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => loading = true);

    roots = searchController.text.trim().isEmpty
        ? await repository.getRootSubjects()
        : await repository.searchSubjects(
            searchController.text,
          );

    if (mounted) {
      setState(() => loading = false);
    }
  }

  Future<void> _addRoot() async {
    final name = await _dialog(
      title: 'موضوع اصلی جدید',
    );

    if (name == null) return;

    try {
      await repository.createSubject(
        name: name,
      );

      await _load();
    } catch (e) {
      _message('خطا:\n$e');
    }
  }

  Future<void> _addChild(
    int parentId,
  ) async {
    final name = await _dialog(
      title: 'زیرموضوع جدید',
    );

    if (name == null) return;

    try {
      await repository.createSubject(
        name: name,
        parentId: parentId,
      );

      await _load();
    } catch (e) {
      _message('خطا:\n$e');
    }
  }

  Future<void> _edit(
    Map<String, Object?> item,
  ) async {
    final id = item['subject_id'] as int;

    final name = await _dialog(
      title: 'ویرایش موضوع',
      initial: item['subject_name']?.toString(),
    );

    if (name == null) return;

    try {
      await repository.updateSubject(
        subjectId: id,
        name: name,
      );

      await _load();
    } catch (e) {
      _message('خطا:\n$e');
    }
  }

  Future<void> _move(
    Map<String, Object?> item,
  ) async {
    final id = item['subject_id'] as int;

    final all = await repository.getAllSubjects();

    final available = all.where((subject) {
      final candidate = subject['subject_id'] as int;

      return candidate != id;
    }).toList();

    int? selectedParent;

    final result = await showDialog<bool>(
      context: context,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('انتقال موضوع'),
              content: DropdownButtonFormField<int?>(
                value: selectedParent,
                decoration: const InputDecoration(
                  labelText: 'والد جدید',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text('موضوع اصلی'),
                  ),
                  ...available.map(
                    (subject) {
                      return DropdownMenuItem<int?>(
                        value: subject['subject_id'] as int,
                        child: Text(
                          subject['subject_name'].toString(),
                        ),
                      );
                    },
                  ),
                ],
                onChanged: (value) {
                  setDialogState(() {
                    selectedParent = value;
                  });
                },
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('انصراف'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('انتقال'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != true) return;

    try {
      await repository.moveSubject(
        subjectId: id,
        parentId: selectedParent,
      );

      await _load();
    } catch (e) {
      _message('خطا:\n$e');
    }
  }

  Future<void> _delete(
    Map<String, Object?> item,
  ) async {
    final id = item['subject_id'] as int;
    final name = item['subject_name'].toString();

    final result = await showDialog<bool>(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text('حذف موضوع'),
          content: Text(
            'موضوع «$name» حذف شود؟\n\n'
            'زیرموضوع‌های مستقیم آن به موضوع اصلی تبدیل می‌شوند.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('انصراف'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('حذف'),
            ),
          ],
        );
      },
    );

    if (result != true) return;

    try {
      await repository.deleteSubject(id);
      await _load();
    } catch (e) {
      _message('خطا:\n$e');
    }
  }

  Future<String?> _dialog({
    required String title,
    String? initial,
  }) async {
    final controller = TextEditingController(text: initial ?? '');

    final result = await showDialog<String>(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'نام موضوع',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('انصراف'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(
                  context,
                  controller.text.trim(),
                );
              },
              child: const Text('ذخیره'),
            ),
          ],
        );
      },
    );

    controller.dispose();

    if (result == null || result.trim().isEmpty) {
      return null;
    }

    return result.trim();
  }

  void _message(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('موضوعات'),
        actions: [
          IconButton(
            onPressed: _addRoot,
            icon: const Icon(Icons.add),
          ),
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: searchController,
              onChanged: (_) => _load(),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'جستجوی موضوع',
                border: const OutlineInputBorder(),
                suffixIcon: searchController.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          searchController.clear();
                          _load();
                          setState(() {});
                        },
                        icon: const Icon(Icons.clear),
                      ),
              ),
            ),
          ),
          Expanded(
            child: loading
                ? const Center(
                    child: CircularProgressIndicator(),
                  )
                : roots.isEmpty
                    ? const Center(
                        child: Text(
                          'موضوعی وجود ندارد.',
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.all(8),
                        children: roots.map(
                          (root) {
                            return _SubjectTreeNode(
                              subject: root,
                              onChanged: _load,
                              onAddChild: _addChild,
                              onEdit: _edit,
                              onMove: _move,
                              onDelete: _delete,
                            );
                          },
                        ).toList(),
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addRoot,
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _SubjectTreeNode extends StatefulWidget {
  final Map<String, Object?> subject;
  final Future<void> Function() onChanged;
  final Future<void> Function(int parentId) onAddChild;
  final Future<void> Function(Map<String, Object?> item) onEdit;
  final Future<void> Function(Map<String, Object?> item) onMove;
  final Future<void> Function(Map<String, Object?> item) onDelete;

  const _SubjectTreeNode({
    required this.subject,
    required this.onChanged,
    required this.onAddChild,
    required this.onEdit,
    required this.onMove,
    required this.onDelete,
  });

  @override
  State<_SubjectTreeNode> createState() => _SubjectTreeNodeState();
}

class _SubjectTreeNodeState extends State<_SubjectTreeNode> {
  final repository = NoteSubjectRepository.instance;

  List<Map<String, Object?>> children = [];

  @override
  void initState() {
    super.initState();
    _loadChildren();
  }

  Future<void> _loadChildren() async {
    final id = widget.subject['subject_id'] as int;

    children = await repository.getChildren(id);

    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.subject['subject_id'] as int;
    final name = widget.subject['subject_name']?.toString() ?? '';

    return ExpansionTile(
      title: Text(name),
      leading: const Icon(
        Icons.folder_outlined,
      ),
      childrenPadding: const EdgeInsets.only(right: 20),
      trailing: PopupMenuButton<String>(
        onSelected: (value) async {
          if (value == 'add') {
            await widget.onAddChild(id);
            await _loadChildren();
          } else if (value == 'edit') {
            await widget.onEdit(widget.subject);
          } else if (value == 'move') {
            await widget.onMove(widget.subject);
          } else if (value == 'delete') {
            await widget.onDelete(widget.subject);
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(
            value: 'add',
            child: Text('افزودن زیرموضوع'),
          ),
          PopupMenuItem(
            value: 'edit',
            child: Text('ویرایش'),
          ),
          PopupMenuItem(
            value: 'move',
            child: Text('انتقال'),
          ),
          PopupMenuItem(
            value: 'delete',
            child: Text('حذف'),
          ),
        ],
      ),
      children: children.map(
        (child) {
          return _SubjectTreeNode(
            subject: child,
            onChanged: widget.onChanged,
            onAddChild: widget.onAddChild,
            onEdit: widget.onEdit,
            onMove: widget.onMove,
            onDelete: widget.onDelete,
          );
        },
      ).toList(),
    );
  }
}
