part of 'trade_notes_page.dart';

extension _TradeNotesUiMethods on _NewTradePageState {
  Future<void> _loadTradeNotes() async {
    if (!mounted) return;

    setState(() {
      _tradeNotesLoading = true;
      _tradeNotesError = null;
    });

    try {
      final notes = await _tradeNoteRepository.getAllNotes();

      if (!mounted) return;

      setState(() {
        _tradeNotes =
            notes.map((note) => Map<String, dynamic>.from(note)).toList();
        _tradeNotesLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _tradeNotesLoading = false;
        _tradeNotesError = 'خطا در بارگذاری یادداشت‌ها: $e';
      });
    }
  }

  Future<void> _searchSavedNotes(String value) async {
    final query = value.trim();
    final requestId = ++_searchRequestId;

    if (query.isEmpty) {
      if (!mounted) return;
      setState(() {
        _noteSearchResults = [];
        _noteSearchError = null;
        _noteSearchLoading = false;
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _noteSearchLoading = true;
      _noteSearchError = null;
      _selectedNoteResultIndex = null;
    });

    try {
      final results = await _tradeNoteRepository.searchNoteMatches(query);
      if (!mounted || requestId != _searchRequestId) return;
      setState(() {
        _noteSearchResults = results;
        _noteSearchLoading = false;
      });
    } catch (e) {
      if (!mounted || requestId != _searchRequestId) return;
      setState(() {
        _noteSearchLoading = false;
        _noteSearchError = 'جست‌وجوی یادداشت‌ها ناموفق بود: $e';
      });
    }
  }

  void _openNoteSearchResult(Map<String, dynamic> result) {
    final index = _noteSearchResults.indexOf(result);
    if (index < 0) return;
    setState(() => _selectedNoteResultIndex = index);
  }

  void _moveNoteMatch(int delta) {
    if (_noteSearchResults.isEmpty) return;
    final current = _selectedNoteResultIndex ?? 0;
    final next =
        (current + delta).clamp(0, _noteSearchResults.length - 1).toInt();
    setState(() => _selectedNoteResultIndex = next);
  }

  Widget _buildSelectedNoteResult() {
    final index = _selectedNoteResultIndex;
    if (index == null || index < 0 || index >= _noteSearchResults.length) {
      return const SizedBox.shrink();
    }
    final result = _noteSearchResults[index];
    final note = Map<String, dynamic>.from(result['note'] as Map);
    final field = result['field']?.toString() ?? '';
    final query = result['query']?.toString() ?? '';
    final rawOffset = result['match_start'];
    final offset = rawOffset is num ? rawOffset.toInt() : null;
    final title = note['title']?.toString().trim().isNotEmpty == true
        ? note['title'].toString()
        : 'بدون عنوان';
    return _buildSection(
      title: 'یادداشت انتخاب‌شده: $title',
      icon: Icons.article_outlined,
      children: [
        Row(children: [
          Expanded(
              child: Text(
                  'نتیجه ${numbers.formatInteger(index + 1)} از ${numbers.formatInteger(_noteSearchResults.length)}')),
          IconButton(
              tooltip: 'کلمه/نتیجه قبلی',
              onPressed: index > 0 ? () => _moveNoteMatch(-1) : null,
              icon: const Icon(Icons.skip_previous)),
          IconButton(
              tooltip: 'کلمه/نتیجه بعدی',
              onPressed: index < _noteSearchResults.length - 1
                  ? () => _moveNoteMatch(1)
                  : null,
              icon: const Icon(Icons.skip_next)),
          IconButton(
              tooltip: 'بستن یادداشت',
              onPressed: () => setState(() => _selectedNoteResultIndex = null),
              icon: const Icon(Icons.close)),
        ]),
        NewTradeNotePage(
          key: ValueKey('searched_note_${note['id']}_${field}_${offset ?? 0}'),
          note: note,
          initialSearchTerm: query,
          initialMatchField: field,
          initialMatchOffset: offset,
          embedded: true,
          onSaved: () {
            setState(() => _selectedNoteResultIndex = null);
            _loadTradeNotes();
            if (_noteSearchController.text.trim().isNotEmpty) {
              _searchSavedNotes(_noteSearchController.text);
            }
          },
        ),
      ],
    );
  }

  Widget _buildNoteSearchSection() {
    return _buildSection(
      title: 'جست‌وجوی یادداشت‌ها',
      icon: Icons.search,
      children: [
        TextField(
          controller: _noteSearchController,
          textDirection: TextDirection.rtl,
          onChanged: _searchSavedNotes,
          decoration: InputDecoration(
            hintText: 'جست‌وجو در عنوان، متن، موضوع، برچسب و دارایی',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: IconButton(
              tooltip: 'پاک‌کردن جست‌وجو',
              onPressed: () {
                _noteSearchController.clear();
                _searchSavedNotes('');
              },
              icon: const Icon(Icons.clear),
            ),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        if (_noteSearchLoading) const LinearProgressIndicator(),
        if (_noteSearchError != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              _noteSearchError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (!_noteSearchLoading &&
            _noteSearchError == null &&
            _noteSearchController.text.trim().isNotEmpty &&
            _noteSearchResults.isEmpty)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('نتیجه‌ای پیدا نشد.'),
          ),
        ..._noteSearchResults.map((result) {
          final note = Map<String, dynamic>.from(result['note'] as Map);
          final title = note['title']?.toString() ?? 'بدون عنوان';
          final fieldLabel = result['field_label']?.toString() ?? 'یادداشت';
          final matchedText = result['matched_text']?.toString() ?? '';
          final startValue = result['match_start'];
          final endValue = result['match_end'];
          final start = startValue is num ? startValue.toInt() : 0;
          final end = endValue is num ? endValue.toInt() : 0;

          final safeStart = start.clamp(0, matchedText.length).toInt();
          final safeEnd = end.clamp(safeStart, matchedText.length).toInt();
          final prefixStart =
              (safeStart - 35).clamp(0, matchedText.length).toInt();
          final suffixEnd = (safeEnd + 55).clamp(0, matchedText.length).toInt();

          final prefix = matchedText.substring(prefixStart, safeStart);
          final match = matchedText.substring(safeStart, safeEnd);
          final suffix = matchedText.substring(safeEnd, suffixEnd);

          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: const Icon(Icons.description_outlined),
              title: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('محل تطبیق: $fieldLabel'),
                  const SizedBox(height: 4),
                  Text.rich(
                    TextSpan(
                      children: [
                        if (prefixStart > 0) const TextSpan(text: '…'),
                        TextSpan(text: prefix),
                        TextSpan(
                          text: match,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            backgroundColor:
                                Theme.of(context).colorScheme.primaryContainer,
                          ),
                        ),
                        TextSpan(text: suffix),
                        if (suffixEnd < matchedText.length)
                          const TextSpan(text: '…'),
                      ],
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    textDirection: TextDirection.rtl,
                  ),
                ],
              ),
              trailing: const Icon(Icons.open_in_new),
              onTap: () => _openNoteSearchResult(result),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildTradeNotesSection() {
    return _buildSection(
      title: 'یادداشت‌ها',
      icon: Icons.library_books_outlined,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _loadTradeNotes,
              icon: const Icon(Icons.refresh),
              label: const Text('به‌روزرسانی فهرست'),
            ),
            FilledButton.tonalIcon(
              onPressed: () {
                Navigator.of(context)
                    .push(
                      MaterialPageRoute<void>(
                        builder: (_) => const notes_manager.TradeNotesPage(),
                      ),
                    )
                    .then((_) => _loadTradeNotes());
              },
              icon: const Icon(Icons.manage_search_outlined),
              label: const Text('مدیریت کامل یادداشت‌ها'),
            ),
            OutlinedButton.icon(
              onPressed: () => setState(() => _showNewNoteSection = true),
              icon: const Icon(Icons.note_add_outlined),
              label: const Text('یادداشت جدید'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_tradeNotesLoading)
          const Center(child: CircularProgressIndicator())
        else if (_tradeNotesError != null)
          Text(
            _tradeNotesError!,
            style: const TextStyle(color: Colors.red),
          )
        else if (_tradeNotes.isEmpty)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Text('هنوز یادداشتی ذخیره نشده است.'),
            ),
          )
        else
          ..._tradeNotes.map((note) {
            final title = note['title']?.toString().trim().isNotEmpty == true
                ? note['title'].toString()
                : 'بدون عنوان';

            final content = note['content']?.toString() ?? '';

            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                title: Text(title),
                subtitle: content.trim().isEmpty
                    ? null
                    : Text(
                        content,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                isThreeLine: content.trim().isNotEmpty,
                trailing: const Icon(Icons.notes_outlined),
              ),
            );
          }),
      ],
    );
  }
}
