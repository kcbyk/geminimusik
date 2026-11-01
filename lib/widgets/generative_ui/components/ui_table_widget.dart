import 'package:flutter/material.dart';
import '../../../models/generative_ui/ui_component_model.dart';
import '../../../theme/gemini_colors.dart';

class UiTableWidget extends StatefulWidget {
  final UiComponent component;

  const UiTableWidget({
    super.key,
    required this.component,
  });

  @override
  State<UiTableWidget> createState() => _UiTableWidgetState();
}

class _UiTableWidgetState extends State<UiTableWidget> {
  int? _sortColumnIndex;
  bool _sortAscending = true;
  late List<List<dynamic>> _rows;
  late List<String> _headers;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  @override
  void didUpdateWidget(covariant UiTableWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.component != widget.component) {
      _initData();
    }
  }

  void _initData() {
    final data = widget.component.data;
    _headers = (data['headers'] is List)
        ? (data['headers'] as List).map((e) => e.toString()).toList()
        : (data['columns'] is List)
            ? (data['columns'] as List).map((e) => e.toString()).toList()
            : <String>[];

    final rawRows = (data['rows'] is List) ? (data['rows'] as List) : [];
    _rows = [];

    for (final r in rawRows) {
      if (r is List) {
        _rows.add(List<dynamic>.from(r));
      } else if (r is Map) {
        if (_headers.isEmpty) {
          _headers = r.keys.map((k) => k.toString()).toList();
        }
        _rows.add(_headers.map((h) => r[h] ?? '').toList());
      }
    }
  }

  void _sort(int colIndex) {
    setState(() {
      if (_sortColumnIndex == colIndex) {
        _sortAscending = !_sortAscending;
      } else {
        _sortColumnIndex = colIndex;
        _sortAscending = true;
      }

      _rows.sort((a, b) {
        final valA = (colIndex < a.length) ? a[colIndex].toString() : '';
        final valB = (colIndex < b.length) ? b[colIndex].toString() : '';

        // Try numeric comparison
        final numA = num.tryParse(valA.replaceAll(RegExp(r'[^0-9.]'), ''));
        final numB = num.tryParse(valB.replaceAll(RegExp(r'[^0-9.]'), ''));
        if (numA != null && numB != null) {
          return _sortAscending ? numA.compareTo(numB) : numB.compareTo(numA);
        }

        return _sortAscending ? valA.compareTo(valB) : valB.compareTo(valA);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_headers.isEmpty && _rows.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1F20),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.component.title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Row(
                children: [
                  const Icon(Icons.table_chart_outlined, size: 18, color: GeminiColors.geminiCyan),
                  const SizedBox(width: 8),
                  Text(
                    widget.component.title!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(const Color(0xFF141414)),
              dataRowColor: WidgetStateProperty.resolveWith((states) {
                return Colors.transparent;
              }),
              sortColumnIndex: _sortColumnIndex,
              sortAscending: _sortAscending,
              columnSpacing: 24,
              horizontalMargin: 16,
              headingTextStyle: const TextStyle(
                color: GeminiColors.geminiCyan,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
              dataTextStyle: const TextStyle(
                color: Color(0xFFE0E0E0),
                fontSize: 13,
              ),
              columns: List.generate(_headers.length, (idx) {
                return DataColumn(
                  label: Text(_headers[idx]),
                  onSort: (col, _) => _sort(col),
                );
              }),
              rows: List.generate(_rows.length, (rIdx) {
                final row = _rows[rIdx];
                return DataRow(
                  color: WidgetStateProperty.all(
                    rIdx.isEven ? Colors.transparent : Colors.white.withValues(alpha: 0.02),
                  ),
                  cells: List.generate(_headers.length, (cIdx) {
                    final cellValue = (cIdx < row.length) ? row[cIdx].toString() : '';
                    return DataCell(_buildCellWidget(cellValue));
                  }),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCellWidget(String val) {
    final lower = val.toLowerCase();
    // Check if it's a status badge
    if (lower == 'aktif' || lower == 'tamamlandı' || lower == 'onaylandı' || lower == 'success') {
      return _buildBadge(val, Colors.greenAccent, Colors.green);
    } else if (lower == 'bekliyor' || lower == 'pending' || lower == 'işleniyor') {
      return _buildBadge(val, Colors.orangeAccent, Colors.orange);
    } else if (lower == 'iptal' || lower == 'hata' || lower == 'başarısız' || lower == 'failed') {
      return _buildBadge(val, Colors.redAccent, Colors.red);
    }

    return Text(val);
  }

  Widget _buildBadge(String text, Color fg, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: fg.withValues(alpha: 0.4), width: 0.8),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: fg,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
