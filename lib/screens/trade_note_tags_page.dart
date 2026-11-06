// lib/screens/trade_note_tags_page.dart

import 'package:flutter/material.dart';

import '../repositories/note_tag_repository.dart';

class TradeNoteTagsPage extends StatefulWidget {
  const TradeNoteTagsPage({super.key});

  @override
  State<TradeNoteTagsPage> createState() => _TradeNoteTagsPageState();
}

class _TradeNoteTagsPageState extends State<TradeNoteTagsPage> {
  final repository = NoteTagRepository.instance;
  final searchController = TextEditingController();

  List<Map<String, Object?>> tags = [];
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

    tags = searchController.text.trim().isEmpty
        ? await repository.getAllTags()
        : await repository.searchTags(
            searchController.text,
          );

    if (mounted) {
      setState(() => loading = false);
    }
  }

  Future<void> _add() async {
    final name = await _dialog(
      title: 'افزودن برچسب',
    );

    if (name == null) return;

    try {
      await repository.createTag(name);
      await _load();
    } catch (e) {
      _message('خطا:\n$e');
    }
  }

  Future<void> _edit(
    Map<String, Object?> tag,
  ) async {
    final id = tag['tag_id'] as int;

    final name = await _dialog(
      title: 'ویرایش برچسب',
      initial: tag['tag_name']?.toString(),
    );

    if (name == null) return;

    try {
      await repository.updateTag(
        tagId: id,
        name: name,
      );

      await _load();
    } catch (e) {
      _message('خطا:\n$e');
    }
  }

  Future<void> _delete(
    Map<String, Object?> tag,
  ) async {
    final id = tag['tag_id'] as int;
    final name = tag['tag_name']?.toString() ?? '';

    final result = await showDialog<bool>(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text('حذف برچسب'),
          content: Text(
            'برچسب «$name» حذف شود؟\n\n'
            'ارتباط آن با یادداشت‌ها نیز حذف می‌شود.',
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
      await repository.deleteTag(id);
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
              labelText: 'نام برچسب',
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
        title: const Text('برچسب‌ها'),
        actions: [
          IconButton(
            onPressed: _add,
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
                hintText: 'جستجوی برچسب',
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
                : tags.isEmpty
                    ? const Center(
                        child: Text(
                          'برچسبی وجود ندارد.',
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: tags.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, index) {
                          final tag = tags[index];
                          final id = tag['tag_id'] as int;
                          final name = tag['tag_name'].toString();

                          return FutureBuilder<int>(
                            future: repository.getNotesCount(id),
                            builder: (_, snapshot) {
                              return ListTile(
                                leading: const Icon(
                                  Icons.local_offer_outlined,
                                ),
                                title: Text(name),
                                subtitle: Text(
                                  '${snapshot.data ?? 0} یادداشت',
                                ),
                                trailing: PopupMenuButton<String>(
                                  onSelected: (value) {
                                    if (value == 'edit') {
                                      _edit(tag);
                                    } else {
                                      _delete(tag);
                                    }
                                  },
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(
                                      value: 'edit',
                                      child: Text('ویرایش'),
                                    ),
                                    PopupMenuItem(
                                      value: 'delete',
                                      child: Text('حذف'),
                                    ),
                                  ],
                                ),
                              );
                            },
                          );
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _add,
        child: const Icon(Icons.add),
      ),
    );
  }
}
