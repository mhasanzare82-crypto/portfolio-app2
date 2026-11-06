import 'package:flutter/material.dart';

import '../repositories/trade_note_repository.dart';
import 'trade_note_detail_page.dart';

class TradeNoteFilteredListPage extends StatefulWidget {
  final String title;
  final String filterName;
  final bool isTag;

  const TradeNoteFilteredListPage({
    super.key,
    required this.title,
    required this.filterName,
    required this.isTag,
  });

  @override
  State<TradeNoteFilteredListPage> createState() =>
      _TradeNoteFilteredListPageState();
}

class _TradeNoteFilteredListPageState extends State<TradeNoteFilteredListPage> {
  final TradeNoteRepository _repository = TradeNoteRepository.instance;

  List<Map<String, Object?>> _notes = [];

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();

    _loadNotes();
  }

  Future<void> _loadNotes() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final notes = widget.isTag
          ? await _repository.getNotesByTag(
              widget.filterName,
            )
          : await _repository.getNotesBySubject(
              widget.filterName,
            );

      if (!mounted) {
        return;
      }

      setState(() {
        _notes = notes;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'خطا در خواندن یادداشت‌ها: $e',
          ),
        ),
      );
    }
  }

  String _value(
    Map<String, Object?> note,
    String key,
  ) {
    return note[key]?.toString() ?? '';
  }

  Future<void> _openNote(
    int noteId,
  ) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) {
          return TradeNoteDetailPage(
            noteId: noteId,
          );
        },
      ),
    );

    if (result == true) {
      await _loadNotes();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.title,
        ),
        actions: [
          IconButton(
            onPressed: _loadNotes,
            icon: const Icon(
              Icons.refresh,
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : _notes.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'برای «${widget.filterName}» یادداشتی وجود ندارد.',
                      textDirection: TextDirection.rtl,
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadNotes,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _notes.length,
                    itemBuilder: (
                      context,
                      index,
                    ) {
                      final note = _notes[index];

                      final noteId = note['note_id'];

                      final title = _value(
                        note,
                        'title',
                      );

                      final subject = _value(
                        note,
                        'subject',
                      );

                      final noteType = _value(
                        note,
                        'note_type',
                      );

                      final symbol = _value(
                        note,
                        'asset_symbol',
                      );

                      final content = _value(
                        note,
                        'content',
                      );

                      return Card(
                        margin: const EdgeInsets.only(
                          bottom: 10,
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          leading: Icon(
                            widget.isTag
                                ? Icons.label_outline
                                : Icons.folder_outlined,
                          ),
                          title: Text(
                            title.isEmpty ? 'بدون عنوان' : title,
                            textDirection: TextDirection.rtl,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(
                              top: 8,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (subject.isNotEmpty)
                                  Text(
                                    'موضوع: $subject',
                                    textDirection: TextDirection.rtl,
                                  ),
                                if (noteType.isNotEmpty)
                                  Text(
                                    'نوع: $noteType',
                                    textDirection: TextDirection.rtl,
                                  ),
                                if (symbol.isNotEmpty)
                                  Text(
                                    'دارایی: $symbol',
                                    textDirection: TextDirection.ltr,
                                  ),
                                if (content.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      top: 6,
                                    ),
                                    child: Text(
                                      content,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                      textDirection: TextDirection.rtl,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          trailing: const Icon(
                            Icons.chevron_left,
                          ),
                          onTap: noteId is int
                              ? () {
                                  _openNote(
                                    noteId,
                                  );
                                }
                              : null,
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
