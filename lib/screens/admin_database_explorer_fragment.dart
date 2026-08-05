import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/database_service.dart';
import '../utils/theme.dart';

class AdminDatabaseExplorerFragment extends StatefulWidget {
  const AdminDatabaseExplorerFragment({super.key});

  @override
  State<AdminDatabaseExplorerFragment> createState() =>
      _AdminDatabaseExplorerFragmentState();
}

class _AdminDatabaseExplorerFragmentState
    extends State<AdminDatabaseExplorerFragment> {
  String? _selectedTable;
  List<String> _tables = [];
  List<Map<String, dynamic>> _tableData = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTables();
  }

  Future<void> _loadTables() async {
    setState(() => _isLoading = true);
    final tables = await DatabaseService.instance.getTableNames();
    setState(() {
      _tables = tables;
      if (_tables.isNotEmpty && _selectedTable == null) {
        _selectedTable = _tables.first;
      }
      _isLoading = false;
    });
    if (_selectedTable != null) {
      _loadTableData(_selectedTable!);
    }
  }

  Future<void> _loadTableData(String tableName) async {
    setState(() => _isLoading = true);
    final data = await DatabaseService.instance.getTableData(tableName);
    setState(() {
      _tableData = data;
      _isLoading = false;
    });
  }

  Future<void> _deleteRow(String id) async {
    if (_selectedTable == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.adminSurface,
        title:
            const Text("Confirm Delete", style: TextStyle(color: Colors.white)),
        content: Text(
            "Are you sure you want to delete this record from $_selectedTable?",
            style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("CANCEL")),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child:
                const Text("DELETE", style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await DatabaseService.instance.deleteRecord(_selectedTable!, id);
      _loadTableData(_selectedTable!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 30),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppTheme.adminPrimary))
                : _tableData.isEmpty
                    ? _buildEmptyState()
                    : _buildModernTable(),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Database Explorer",
              style: GoogleFonts.inter(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.adminPrimary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    "LIVE DATABASE",
                    style: GoogleFonts.inter(
                      color: AppTheme.adminPrimary,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  "Total Records: ${_tableData.length}",
                  style: GoogleFonts.inter(color: AppTheme.adminMuted, fontSize: 12),
                ),
              ],
            ),
          ],
        ),
        Row(
          children: [
            Container(
              height: 45,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedTable,
                  dropdownColor: const Color(0xFF1E293B),
                  style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  icon: const Padding(
                    padding: EdgeInsets.only(left: 10),
                    child: Icon(Icons.table_chart_outlined, color: AppTheme.adminPrimary, size: 20),
                  ),
                  items: _tables
                      .map((t) => DropdownMenuItem(
                          value: t, child: Text(t.toUpperCase(), style: const TextStyle(letterSpacing: 1))))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _selectedTable = val);
                      _loadTableData(val);
                    }
                  },
                ),
              ),
            ),
            const SizedBox(width: 15),
            if (!(_selectedTable?.toLowerCase().contains('rider') ?? false) &&
                !(_selectedTable?.toLowerCase().contains('driver') ?? false) &&
                !(_selectedTable?.toLowerCase().contains('trip') ?? false))
              ElevatedButton.icon(
                onPressed: () => _showEditDialog(),
                icon: const Icon(Icons.add_rounded, color: Colors.black, size: 20),
                label: Text("NEW RECORD",
                    style: GoogleFonts.inter(
                        color: Colors.black, fontWeight: FontWeight.w900, fontSize: 13)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.adminPrimary,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildModernTable() {
    final columns = _tableData.first.keys.toList();
    
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Scrollbar(
          thickness: 8,
          radius: const Radius.circular(10),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SingleChildScrollView(
              child: DataTable(
                columnSpacing: 40,
                horizontalMargin: 30,
                headingRowHeight: 70,
                dataRowMinHeight: 65,
                dataRowMaxHeight: 65,
                headingRowColor: WidgetStateProperty.all(Colors.white.withValues(alpha: 0.02)),
                border: const TableBorder(
                  horizontalInside: BorderSide(color: Colors.white10, width: 0.5),
                ),
                columns: [
                  ...columns.map((col) => DataColumn(
                        label: Text(col.toUpperCase(),
                            style: GoogleFonts.inter(
                                color: AppTheme.adminMuted,
                                fontWeight: FontWeight.w900,
                                fontSize: 11,
                                letterSpacing: 1.5)),
                      )),
                  DataColumn(
                      label: Text("ACTIONS",
                          style: GoogleFonts.inter(
                              color: AppTheme.adminPrimary,
                              fontWeight: FontWeight.w900,
                              fontSize: 11,
                              letterSpacing: 1.5))),
                ],
                rows: _tableData.map((row) {
                  return DataRow(
                    cells: [
                      ...columns.map((col) {
                        final val = row[col];
                        final isId = col.toLowerCase() == 'id' || col.toLowerCase() == 'key';
                        final isTimestamp = col.toLowerCase().contains('date') || col.toLowerCase().contains('time');
                        
                        return DataCell(
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 300),
                            child: Text(
                              val?.toString() ?? "-",
                              style: isId || isTimestamp 
                                  ? GoogleFonts.robotoMono(color: Colors.white, fontSize: 12)
                                  : GoogleFonts.inter(color: Colors.white70, fontSize: 13),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        );
                      }),
                      DataCell(
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildActionButton(
                              icon: Icons.edit_note_rounded,
                              color: Colors.blueAccent,
                              onTap: () => _showEditDialog(row),
                            ),
                            const SizedBox(width: 8),
                            _buildActionButton(
                              icon: Icons.delete_sweep_rounded,
                              color: Colors.redAccent,
                              onTap: () => _deleteRow(row['id']?.toString() ??
                                  row['key']?.toString() ??
                                  ''),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({required IconData icon, required Color color, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
    );
  }

  void _showEditDialog([Map<String, dynamic>? existingData]) {
    if (_selectedTable == null) return;

    List<String> columns = [];
    String tableName = _selectedTable!.toLowerCase();

    if (tableName.contains('staff')) {
      columns = ['id', 'name', 'email', 'role', 'departmentId'];
    } else if (tableName.contains('department')) {
      columns = ['id', 'name', 'description'];
    } else if (tableName.contains('setting')) {
      columns = ['key', 'value'];
    } else {
      if (_tableData.isNotEmpty) {
        columns = _tableData.first.keys
            .where((k) => k != 'rawJson' && k != 'lastLogin')
            .toList();
      } else {
        columns = ['id', 'name'];
      }
    }

    final Map<String, TextEditingController> controllers = {};
    for (var col in columns) {
      String initialValue = '';
      if (existingData != null) {
        initialValue = existingData[col]?.toString() ?? '';
      } else if (col == 'id') {
        initialValue =
            "STF-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}";
      } else if (col == 'role' && tableName.contains('staff')) {
        initialValue = 'Support';
      }
      controllers[col] = TextEditingController(text: initialValue);
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(existingData == null ? "New Database Entry" : "Modify Record",
                style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
            Text("Table: ${_selectedTable?.toUpperCase()}", 
                style: GoogleFonts.inter(color: AppTheme.adminPrimary, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1)),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: columns.map((col) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: TextField(
                    controller: controllers[col],
                    style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      labelText: col.toUpperCase(),
                      labelStyle: GoogleFonts.inter(color: AppTheme.adminMuted, fontSize: 12, fontWeight: FontWeight.bold),
                      filled: true,
                      fillColor: Colors.black.withValues(alpha: 0.2),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppTheme.adminPrimary)),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text("CANCEL", style: GoogleFonts.inter(color: AppTheme.adminMuted))),
          ElevatedButton(
            onPressed: () async {
              final Map<String, dynamic> newData = {};
              controllers.forEach((key, controller) {
                newData[key] = controller.text;
              });

              final String docId = newData['id'] ??
                  newData['_id'] ??
                  newData['key'] ??
                  DateTime.now().millisecondsSinceEpoch.toString();
              final table = _selectedTable!;
              await DatabaseService.instance
                  .insertOrUpdateRecord(table, docId, newData);
              if (mounted) {
                Navigator.pop(context);
                _loadTableData(table);
              }
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.adminPrimary,
                padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: const Text("COMMIT CHANGES",
                style: TextStyle(
                    color: Colors.black, fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    bool canAdd = !(_selectedTable?.toLowerCase().contains('rider') ?? false) &&
        !(_selectedTable?.toLowerCase().contains('driver') ?? false) &&
        !(_selectedTable?.toLowerCase().contains('trip') ?? false);

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(30),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.02),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.storage_rounded, size: 80, color: Colors.white10),
          ),
          const SizedBox(height: 24),
          Text("Table is empty",
              style: GoogleFonts.inter(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text("No data found in ${_selectedTable?.toUpperCase()}",
              style: GoogleFonts.inter(color: AppTheme.adminMuted)),
          if (canAdd) ...[
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: () => _showEditDialog(),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.adminPrimary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 15)),
              child: const Text("Create First Record",
                  style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ],
        ],
      ),
    );
  }
}
