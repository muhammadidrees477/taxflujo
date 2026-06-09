// lib/screens/invoice_list_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import 'login_screen.dart';
import 'invoice_form_screen.dart';
import 'profile_screen.dart';

class InvoiceListScreen extends StatefulWidget {
  const InvoiceListScreen({super.key});
  @override
  State<InvoiceListScreen> createState() => _InvoiceListScreenState();
}

class _InvoiceListScreenState extends State<InvoiceListScreen> {
  List<dynamic> _invoices   = [];
  List<dynamic> _companies  = [];
  bool   _isLoading         = true;
  String? _error;
  // int    _selectedTab       = 0;

  // Filters (mirrors your index.php filters)
  String? _statusFilter;
  int?    _companyFilter;
  String? _fromDate;
  String? _toDate;
  String  _search = '';
  final   _searchCtrl = TextEditingController();

  static const _statusOptions = [null, 'Pending', 'Approved', 'Paid', 'Unpaid', 'Rejected'];
  static const _statusLabels  = ['All',  'Pending', 'Approved', 'Paid', 'Unpaid', 'Rejected'];

  @override
  void initState() {
    super.initState();
    _loadCompanies();
    _loadInvoices();
  }

  Future<void> _loadCompanies() async {
    final companies = await ApiService.getCachedCompanies();
    if (mounted) setState(() => _companies = companies);
  }

  Future<void> _loadInvoices() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final invoices = await ApiService.getInvoices(
        status:    _statusFilter,
        companyId: _companyFilter,
        fromDate:  _fromDate,
        toDate:    _toDate,
        search:    _search.isNotEmpty ? _search : null,
      );
      if (mounted) setState(() => _invoices = invoices);
    } on UnauthorizedException {
      _handleSessionExpiry();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Failed to load invoices. Check your connection.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _handleSessionExpiry() async {
    await ApiService.logout();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(context,
        MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
  }

  Future<void> _deleteInvoice(Map<String, dynamic> inv) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Invoice'),
        content: Text('Delete invoice ${inv['invoice_number']}?\nThis cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await ApiService.deleteInvoice(int.parse(inv['id'].toString()));
      _showSnack('Invoice deleted', Colors.green);
      _loadInvoices();
    } on ApiException catch (e) {
      _showSnack(e.message, Colors.red);
    } catch (_) {
      _showSnack('Failed to delete invoice', Colors.red);
    }
  }

  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  // Can edit: only Pending (matches your index.php — Approved, Paid, Rejected are locked)
  bool _canEdit(String status)   => status == 'Pending';
  // Can delete: not Approved or Paid (matches your delete.php)
  bool _canDelete(String status) => !['Approved', 'Paid'].contains(status);

  Color _statusColor(String status) => switch (status) {
    'Approved' => const Color(0xFF16A34A),
    'Paid'     => const Color(0xFF0284C7),
    'Pending'  => const Color(0xFFD97706),
    'Unpaid'   => const Color(0xFFDC2626),
    'Rejected' => const Color(0xFF9333EA),
    _          => Colors.grey,
  };

  IconData _statusIcon(String status) => switch (status) {
    'Approved' => Icons.check_circle_outline,
    'Paid'     => Icons.paid_outlined,
    'Pending'  => Icons.schedule,
    'Unpaid'   => Icons.warning_amber_outlined,
    'Rejected' => Icons.cancel_outlined,
    _          => Icons.receipt_outlined,
  };

  void _openFilters() {
    // Temp state for dialog
    String? tmpStatus  = _statusFilter;
    int?    tmpCompany = _companyFilter;
    String  tmpFrom    = _fromDate ?? '';
    String  tmpTo      = _toDate ?? '';
    final fromCtrl = TextEditingController(text: tmpFrom);
    final toCtrl   = TextEditingController(text: tmpTo);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setModal) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Text('Filters', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Spacer(),
            TextButton(
              onPressed: () {
                setModal(() { tmpStatus = null; tmpCompany = null; tmpFrom = ''; tmpTo = ''; });
                fromCtrl.clear(); toCtrl.clear();
              },
              child: const Text('Reset'),
            ),
          ]),
          const SizedBox(height: 12),

          // Status
          const Text('Status', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, children: List.generate(_statusOptions.length, (i) =>
            ChoiceChip(
              label: Text(_statusLabels[i]),
              selected: tmpStatus == _statusOptions[i],
              onSelected: (_) => setModal(() => tmpStatus = _statusOptions[i]),
            ),
          )),
          const SizedBox(height: 14),

          // Company filter
          if (_companies.isNotEmpty) ...[
            const Text('Company', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 6),
            DropdownButtonFormField<int?>(
              value: tmpCompany,
              isExpanded: true,
              decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
              items: [
                const DropdownMenuItem<int?>(value: null, child: Text('All Companies')),
                ..._companies.map((c) => DropdownMenuItem<int?>(
                  value: int.tryParse(c['company_id'].toString()),
                  child: Text(c['company_name'] ?? '', overflow: TextOverflow.ellipsis),
                )),
              ],
              onChanged: (v) => setModal(() => tmpCompany = v),
            ),
            const SizedBox(height: 14),
          ],

          // Date range
          const Text('Date Range', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(child: TextFormField(
              controller: fromCtrl,
              readOnly: true,
              decoration: const InputDecoration(labelText: 'From', isDense: true,
                  border: OutlineInputBorder(), suffixIcon: Icon(Icons.calendar_today, size: 16)),
              onTap: () async {
                final d = await showDatePicker(context: ctx,
                    initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2035));
                if (d != null) { final s = DateFormat('yyyy-MM-dd').format(d); fromCtrl.text = s; setModal(() => tmpFrom = s); }
              },
            )),
            const SizedBox(width: 10),
            Expanded(child: TextFormField(
              controller: toCtrl,
              readOnly: true,
              decoration: const InputDecoration(labelText: 'To', isDense: true,
                  border: OutlineInputBorder(), suffixIcon: Icon(Icons.calendar_today, size: 16)),
              onTap: () async {
                final d = await showDatePicker(context: ctx,
                    initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2035));
                if (d != null) { final s = DateFormat('yyyy-MM-dd').format(d); toCtrl.text = s; setModal(() => tmpTo = s); }
              },
            )),
          ]),
          const SizedBox(height: 20),

          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: () {
              setState(() {
                _statusFilter  = tmpStatus;
                _companyFilter = tmpCompany;
                _fromDate      = tmpFrom.isNotEmpty ? tmpFrom : null;
                _toDate        = tmpTo.isNotEmpty ? tmpTo : null;
              });
              Navigator.pop(ctx);
              _loadInvoices();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Apply Filters', style: TextStyle(fontWeight: FontWeight.bold)),
          )),
        ]),
      )),
    );
  }

  bool get _hasActiveFilters =>
      _statusFilter != null || _companyFilter != null || _fromDate != null || _toDate != null || _search.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: const Text('My Invoices', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        actions: [
          // Filter button with badge if active
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(icon: const Icon(Icons.tune), onPressed: _openFilters, tooltip: 'Filter'),
              if (_hasActiveFilters)
                Positioned(
                  top: 8, right: 8,
                  child: Container(width: 8, height: 8,
                    decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle)),
                ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.logout_outlined),
            tooltip: 'Sign out',
            onPressed: () => showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Sign Out'),
                content: const Text('Are you sure?'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                  TextButton(
                    onPressed: () async { Navigator.pop(ctx); await ApiService.logout(); if (mounted) Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false); },
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                    child: const Text('Sign Out'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: Column(children: [
        // ── Search bar ────────────────────────────────────────────────────────
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: 'Search invoice number…',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _search.isNotEmpty
                  ? IconButton(icon: const Icon(Icons.close, size: 18),
                      onPressed: () { _searchCtrl.clear(); setState(() => _search = ''); _loadInvoices(); })
                  : null,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
              filled: true, fillColor: Colors.grey.shade50,
            ),
            onSubmitted: (v) { setState(() => _search = v.trim()); _loadInvoices(); },
            textInputAction: TextInputAction.search,
          ),
        ),

        // ── Active filter chips ───────────────────────────────────────────────
        if (_hasActiveFilters)
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                if (_statusFilter != null)
                  _filterChip('Status: $_statusFilter', () { setState(() => _statusFilter = null); _loadInvoices(); }),
                if (_companyFilter != null)
                  _filterChip('Company filter active', () { setState(() => _companyFilter = null); _loadInvoices(); }),
                if (_fromDate != null || _toDate != null)
                  _filterChip('Date: ${_fromDate ?? '...'} → ${_toDate ?? '...'}', () { setState(() { _fromDate = null; _toDate = null; }); _loadInvoices(); }),
                if (_search.isNotEmpty)
                  _filterChip('Search: $_search', () { _searchCtrl.clear(); setState(() => _search = ''); _loadInvoices(); }),
              ]),
            ),
          ),

        // ── Invoice list ──────────────────────────────────────────────────────
        Expanded(child: RefreshIndicator(
          onRefresh: _loadInvoices,
          child: _buildBody(),
        )),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final created = await Navigator.push(context,
              MaterialPageRoute(builder: (_) => const InvoiceFormScreen()));
          if (created == true) _loadInvoices();
        },
        icon: const Icon(Icons.add),
        label: const Text('New Invoice'),
      ),
      // bottomNavigationBar: NavigationBar(
      //   selectedIndex: _selectedTab,
      //   backgroundColor: Colors.white,
      //   onDestinationSelected: (i) {
      //     if (i == 1) {
      //       Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen()));
      //     } else {
      //       setState(() => _selectedTab = i);
      //     }
      //   },
      //   destinations: const [
      //     NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Invoices'),
      //     NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
      //   ],
      // ),
    );
  }

  Widget _filterChip(String label, VoidCallback onRemove) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Chip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        deleteIcon: const Icon(Icons.close, size: 14),
        onDeleted: onRemove,
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    if (_error != null) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.error_outline, size: 48, color: Colors.red.shade400),
          const SizedBox(height: 12),
          Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade700)),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: _loadInvoices, child: const Text('Retry')),
        ]),
      ));
    }

    if (_invoices.isEmpty) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.receipt_long_outlined, size: 64, color: Colors.grey.shade400),
        const SizedBox(height: 16),
        Text(_hasActiveFilters ? 'No invoices match your filters' : 'No invoices yet',
            style: TextStyle(fontSize: 18, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        if (_hasActiveFilters)
          TextButton(
            onPressed: () { setState(() { _statusFilter = null; _companyFilter = null; _fromDate = null; _toDate = null; _search = ''; _searchCtrl.clear(); }); _loadInvoices(); },
            child: const Text('Clear all filters'),
          )
        else
          Text('Tap + to create your first invoice', style: TextStyle(color: Colors.grey.shade500)),
      ]));
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      itemCount: _invoices.length,
      itemBuilder: (context, i) => _invoiceCard(_invoices[i]),
    );
  }

  Widget _invoiceCard(Map<String, dynamic> inv) {
    final status  = inv['status'] as String? ?? 'Pending';
    final total   = double.tryParse(inv['total']?.toString() ?? '0') ?? 0;
    final company = inv['company_name'] as String? ?? '—';
    final canEdit   = _canEdit(status);
    final canDelete = _canDelete(status);

    String dateStr = '—';
    if (inv['invoice_date'] != null) {
      try { dateStr = DateFormat('MMM dd, yyyy').format(DateTime.parse(inv['invoice_date'])); } catch (_) {}
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── Top row: number + status ────────────────────────────────────────
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _statusColor(status).withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(_statusIcon(status), color: _statusColor(status), size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(inv['invoice_number']?.toString() ?? 'Invoice',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              Text(company, style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  overflow: TextOverflow.ellipsis),
            ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('\$${total.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _statusColor(status).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(status,
                    style: TextStyle(color: _statusColor(status), fontSize: 11, fontWeight: FontWeight.w700)),
              ),
            ]),
          ]),

          const SizedBox(height: 10),
          Divider(height: 1, color: Colors.grey.shade100),
          const SizedBox(height: 10),

          // ── Bottom row: date + action buttons ───────────────────────────────
          Row(children: [
            Icon(Icons.calendar_today_outlined, size: 13, color: Colors.grey.shade500),
            const SizedBox(width: 4),
            Text(dateStr, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            if (inv['client_name'] != null) ...[
              const SizedBox(width: 12),
              Icon(Icons.person_outline, size: 13, color: Colors.grey.shade500),
              const SizedBox(width: 4),
              Expanded(child: Text(inv['client_name'].toString(),
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  overflow: TextOverflow.ellipsis)),
            ] else const Spacer(),

            // Action buttons — Edit & Delete (same logic as your index.php)
            Row(mainAxisSize: MainAxisSize.min, children: [
              // View button (always available)
              _actionBtn(Icons.visibility_outlined, Colors.blueGrey, () async {
                await Navigator.push(context,
                    MaterialPageRoute(builder: (_) => InvoiceFormScreen(
                      invoiceId: int.tryParse(inv['id'].toString()),
                      viewOnly: true,
                    )));
              }),
              const SizedBox(width: 6),

              // Edit — only for Pending
              _actionBtn(
                Icons.edit_outlined,
                canEdit ? Colors.orange : Colors.grey.shade300,
                canEdit ? () async {
                  final updated = await Navigator.push(context,
                      MaterialPageRoute(builder: (_) => InvoiceFormScreen(
                        invoiceId: int.tryParse(inv['id'].toString()),
                      )));
                  if (updated == true) _loadInvoices();
                } : null,
              ),
              const SizedBox(width: 6),

              // Delete — blocked if Approved or Paid
              _actionBtn(
                Icons.delete_outline,
                canDelete ? Colors.red : Colors.grey.shade300,
                canDelete ? () => _deleteInvoice(inv) : null,
              ),
            ]),
          ]),

          // Rejection reason (if rejected)
          if (status == 'Rejected' && inv['rejection_reason'] != null) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.red.shade100),
              ),
              child: Row(children: [
                Icon(Icons.info_outline, size: 14, color: Colors.red.shade600),
                const SizedBox(width: 6),
                Expanded(child: Text('Reason: ${inv['rejection_reason']}',
                    style: TextStyle(fontSize: 12, color: Colors.red.shade700))),
              ]),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _actionBtn(IconData icon, Color color, VoidCallback? onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: color.withOpacity(onTap != null ? 0.1 : 0.05),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 18, color: onTap != null ? color : Colors.grey.shade300),
      ),
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }
}
