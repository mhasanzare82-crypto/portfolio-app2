// lib/screens/trade_notes_list_page.dart

import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import '../utils/number_formatter.dart' as numbers;

import '../repositories/trade_note_repository.dart';
import 'trade_note_detail_page.dart';

class TradeNotesListPage extends StatefulWidget {
  const TradeNotesListPage({super.key});

  @override
  State<TradeNotesListPage> createState() => _TradeNotesListPageState();
}

class _TradeNotesListPageState extends State<TradeNotesListPage> {
  final repository = TradeNoteRepository.instance;
  final searchController = TextEditingController();

  List<Map<String, Object?>> notes = [];
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

    try {
      notes = await repository.searchNotes(
        searchController.text,
      );
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _delete(
    Map<String, Object?> note,
  ) async {
    final id = note['note_id'] as int;
    final title = note['title']?.toString() ?? '';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('حذف یادداشت'),
          content: Text(
            'یادداشت «$title» حذف شود؟\n\n'
            'رسانه‌های مربوط به آن نیز حذف خواهند شد.',
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

    if (confirmed != true) return;

    await repository.deleteNote(id);
    await _load();
  }

  Future<void> _open(
    Map<String, Object?> note,
  ) async {
    final id = note['note_id'] as int;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TradeNoteDetailPage(
          noteId: id,
        ),
      ),
    );

    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('همه یادداشت‌ها'),
        actions: [
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
                hintText: 'جستجو در عنوان، متن، موضوع، برچسب و دارایی',
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
                : notes.isEmpty
                    ? const Center(
                        child: Text(
                          'یادداشتی پیدا نشد.',
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: notes.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final note = notes[index];

                            return _NoteTile(
                              note: note,
                              onTap: () => _open(note),
                              onDelete: () => _delete(note),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _NoteTile extends StatefulWidget {
  final Map<String, Object?> note;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _NoteTile({
    required this.note,
    required this.onTap,
    required this.onDelete,
  });

  @override
  State<_NoteTile> createState() => _NoteTileState();
}

class _NoteTileState extends State<_NoteTile> {
  final repository = TradeNoteRepository.instance;
  final player = AudioPlayer();

  List<Map<String, Object?>> subjects = [];
  List<Map<String, Object?>> tags = [];
  List<Map<String, Object?>> media = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final id = widget.note['note_id'] as int;

    subjects = await repository.getSubjectsForNote(id);
    tags = await repository.getTagsForNote(id);
    media = await repository.getMediaForNote(id);

    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.note['title']?.toString() ?? '';
    final content = widget.note['content']?.toString() ?? '';
    final asset = widget.note['asset_symbol']?.toString() ?? '';

    final images = media.where((e) => e['media_type'] == 'image').toList();

    final audios = media.where((e) => e['media_type'] == 'audio').toList();

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        vertical: 8,
        horizontal: 4,
      ),
      leading: images.isEmpty
          ? const CircleAvatar(
              child: Icon(Icons.note_outlined),
            )
          : ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(
                File(
                  images.first['file_path'].toString(),
                ),
                width: 54,
                height: 54,
                fit: BoxFit.cover,
              ),
            ),
      title: Text(
        title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (asset.isNotEmpty) Text(asset),
          if (content.isNotEmpty)
            Text(
              content,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          if (subjects.isNotEmpty)
            Text(
              'موضوع: ${subjects.map((e) => e['subject_name']).join('، ')}',
            ),
          if (tags.isNotEmpty)
            Text(
              'برچسب: ${tags.map((e) => e['tag_name']).join('، ')}',
            ),
          if (audios.isNotEmpty)
            Text(
              '${numbers.formatInteger(audios.length)} فایل صوتی',
            ),
        ],
      ),
      isThreeLine: true,
      trailing: PopupMenuButton<String>(
        onSelected: (value) {
          if (value == 'delete') {
            widget.onDelete();
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(
            value: 'delete',
            child: Text('حذف'),
          ),
        ],
      ),
      onTap: widget.onTap,
    );
  }
}
