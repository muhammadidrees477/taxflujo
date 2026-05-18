// lib/screens/invoice_form_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';

class InvoiceFormScreen extends StatefulWidget {
  final int?  invoiceId; // null = create, set = edit/view
  final bool  viewOnly;  // true = read-only view (like web's view.php)

  const InvoiceFormScreen({super.key, this.invoiceId, this.viewOnly = false});

  @override
  State<InvoiceFormScreen> createState() => _InvoiceFormScreenState();
}

class _InvoiceFormScreenState extends State<InvoiceFormScreen> {
  final _formKey = GlobalKey<FormState>();

  // ── Header controllers ────────────────────────────────────────────────────
  final _invoiceNumCtrl = TextEditingController();
  final _memoCtrl       = TextEditingController();
  DateTime _invoiceDate = DateTime.now();
  DateTime _dueDate     = DateTime.now().add(const Duration(days: 30));

  // ── Invoice number ─────────────────────────────────────────────────────────
  bool   _manualNumber   = false; // mirrors "Manual" checkbox in web
  bool   _generatingNum  = false;
  String _generatedNum   = '';   // last auto-generated value

  // ── Client + Company selection ─────────────────────────────────────────────
  // Companies fetched at login; client comes from selected company's client_id
  List<dynamic>         _companies        = [];
  Map<String, dynamic>? _selectedCompany; // includes company_id and client_id

  // ── Line items ─────────────────────────────────────────────────────────────
  // service_type: only Service or Reimbursement (matches your DB enum + create.php)
  static const _serviceTypes = ['Service', 'Reimbursement'];
  final List<Map<String, dynamic>> _items = [];

  // ── State flags ────────────────────────────────────────────────────────────
  bool _isLoading  = false;
  bool _isSaving   = false;
  bool _isEditing  = false; // true when editing existing invoice
  String _invoiceStatus = '';

  // ── Duplicate check state ──────────────────────────────────────────────────
  Timer?  _dupTimer;
  bool    _dupChecking = false;
  Map<String, dynamic>? _dupWarning; // non-null = show warning
  bool    _dupConfirmed = false;     // user said "submit anyway"

  bool get _isCreate  => widget.invoiceId == null;
  bool get _isView    => widget.viewOnly;
  bool get _canEdit   => !_isView && (_isCreate || _invoiceStatus == 'Pending');

  @override
  void initState() {
    super.initState();
    _loadCompanies().then((_) {
      if (!_isCreate) {
        _loadInvoice();
      } else {
        _addItem();
      }
    });
  }

  Future<void> _loadCompanies() async {
    final companies = await ApiService.getCachedCompanies();
    setState(() {
      _companies = companies;
      if (companies.length == 1 && _isCreate) {
        _selectedCompany = companies.first as Map<String, dynamic>;
        _generateInvoiceNumber();
      }
    });
  }

  Future<void> _loadInvoice() async {
    setState(() => _isLoading = true);
    try {
      final data = await ApiService.getInvoice(widget.invoiceId!);
      setState(() {
        _invoiceStatus    = data['status'] as String? ?? '';
        _isEditing        = true;
        _invoiceDate      = DateTime.parse(data['invoice_date']);
        _dueDate          = DateTime.parse(data['due_date']);
        _memoCtrl.text    = data['memo'] ?? '';
        _invoiceNumCtrl.text = data['invoice_number'] ?? '';
        _generatedNum        = data['invoice_number'] ?? '';

        // Pre-select company
        final companyId = data['company_id']?.toString();
        if (companyId != null) {
          try {
            _selectedCompany = _companies.firstWhere(
                  (c) => c['company_id']?.toString() == companyId,
            ) as Map<String, dynamic>?;
          } catch (_) {}
        }

        // Load items
        _items.clear();
        for (final item in (data['items'] as List? ?? [])) {
          _items.add(_newItemFrom(item));
        }
        if (_items.isEmpty) _addItem();
      });
    } catch (e) {
      _showSnack('Failed to load invoice', Colors.red);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Invoice number generation ─────────────────────────────────────────────

  Future<void> _generateInvoiceNumber() async {
    if (_manualNumber) return;
    final companyId = int.tryParse(_selectedCompany?['company_id']?.toString() ?? '');
    if (companyId == null) return;

    setState(() { _generatingNum = true; _invoiceNumCtrl.text = 'Generating…'; });
    try {
      final num = await ApiService.generateInvoiceNumber(companyId);
      setState(() { _generatedNum = num; _invoiceNumCtrl.text = num; });
    } catch (_) {
      setState(() => _invoiceNumCtrl.text = '');
    } finally {
      if (mounted) setState(() => _generatingNum = false);
    }
  }

  // ── Duplicate check (mirrors check_invoice_duplicate.php) ─────────────────

  void _triggerDupCheck() {
    if (!_isCreate) return; // only check on new invoices
    _dupTimer?.cancel();
    _dupTimer = Timer(const Duration(milliseconds: 600), _checkDuplicate);
  }

  Future<void> _checkDuplicate() async {
    final companyId = int.tryParse(_selectedCompany?['company_id']?.toString() ?? '');
    if (companyId == null) return;

    setState(() => _dupChecking = true);
    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(_invoiceDate);
      final total   = _subtotal;

      final result = await ApiService.checkDuplicate(
        checkType:    'period_amount',
        companyId:    companyId,
        invoiceDate:  dateStr,
        totalAmount:  total,
      );

      if (mounted) {
        setState(() {
          _dupWarning  = (result['duplicate'] as bool? ?? false) ? result : null;
          _dupConfirmed = false;
        });
      }
    } catch (_) {} finally {
      if (mounted) setState(() => _dupChecking = false);
    }
  }

  Future<void> _checkNumberDuplicate(String number) async {
    if (!_manualNumber || number.isEmpty) return;
    try {
      final result = await ApiService.checkDuplicate(
        checkType:     'invoice_number',
        invoiceNumber: number,
      );
      if (mounted && (result['duplicate'] as bool? ?? false)) {
        setState(() => _dupWarning = result);
      }
    } catch (_) {}
  }

  // ── Line item helpers ─────────────────────────────────────────────────────

  Map<String, dynamic> _newItemFrom([Map<String, dynamic>? existing]) => {
    'descCtrl':    TextEditingController(text: existing?['description'] ?? ''),
    'accountCtrl': TextEditingController(text: existing?['account_name'] ?? ''),
    'amountCtrl':  TextEditingController(text: existing?['amount']?.toString() ?? ''),
    'serviceType': existing?['service_type'] ?? 'Service',
  };

  void _addItem() {
    setState(() => _items.add(_newItemFrom()));
  }

  void _removeItem(int index) {
    if (_items.length <= 1) {
      // Clear instead of remove when only 1 row (mirrors web removeItemRow)
      final item = _items[0];
      (item['descCtrl'] as TextEditingController).clear();
      (item['amountCtrl'] as TextEditingController).clear();
      setState(() => item['serviceType'] = 'Service');
      return;
    }
    (_items[index]['descCtrl'] as TextEditingController).dispose();
    (_items[index]['accountCtrl'] as TextEditingController).dispose();
    (_items[index]['amountCtrl'] as TextEditingController).dispose();
    setState(() => _items.removeAt(index));
    _triggerDupCheck();
  }

  double get _subtotal {
    double t = 0;
    for (final item in _items) {
      t += double.tryParse((item['amountCtrl'] as TextEditingController).text) ?? 0;
    }
    return t;
  }

  // ── Save (create or update) ───────────────────────────────────────────────

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCompany == null) { _showSnack('Please select a company', Colors.orange); return; }

    // If there's a non-blocking duplicate warning and not confirmed, show dialog
    if (_dupWarning != null && !_dupConfirmed) {
      final proceed = await _showDupDialog(_dupWarning!);
      if (!proceed) return;
      setState(() => _dupConfirmed = true);
    }

    // Collect validated items
    final lineItems = <Map<String, dynamic>>[];
    for (int i = 0; i < _items.length; i++) {
      final desc   = (_items[i]['descCtrl'] as TextEditingController).text.trim();
      final amount = double.tryParse((_items[i]['amountCtrl'] as TextEditingController).text) ?? 0;
      final stype  = _items[i]['serviceType'] as String;
      if (desc.isEmpty || amount <= 0) continue; // skip empty rows
      lineItems.add({
        'description':  desc,
        'account_name': (_items[i]['accountCtrl'] as TextEditingController).text.trim(),
        'service_type': stype,
        'amount':       amount,
      });
    }

    if (lineItems.isEmpty) { _showSnack('Add at least one valid line item', Colors.orange); return; }

    final payload = {
      'company_id':    _selectedCompany!['company_id'],
      'client_id':     _selectedCompany!['client_id'],
      'invoice_date':  DateFormat('yyyy-MM-dd').format(_invoiceDate),
      'due_date':      DateFormat('yyyy-MM-dd').format(_dueDate),
      'memo':          _memoCtrl.text.trim(),
      'items':         lineItems,
      if (_manualNumber && _invoiceNumCtrl.text.trim().isNotEmpty)
        'invoice_number': _invoiceNumCtrl.text.trim(),
    };

    setState(() => _isSaving = true);
    try {
      if (_isCreate) {
        await ApiService.createInvoice(payload);
        _showSnack('Invoice submitted!', Colors.green);
      } else {
        await ApiService.updateInvoice(widget.invoiceId!, payload);
        _showSnack('Invoice updated!', Colors.green);
      }
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      _showSnack(e.message, Colors.red);
    } catch (_) {
      _showSnack('Failed to save. Please try again.', Colors.red);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ── Duplicate confirmation dialog ─────────────────────────────────────────
  // Mirrors your dupModal in create.php

  Future<bool> _showDupDialog(Map<String, dynamic> conflict) async {
    final conflictType = conflict['conflict_type'] as String? ?? '';
    final isBlocker    = conflictType == 'exact_number'; // can't proceed on exact number match

    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Icon(
            isBlocker ? Icons.error_outline : Icons.warning_amber_outlined,
            color: isBlocker ? Colors.red : Colors.orange,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(
            isBlocker ? 'Invoice Number Already Used'
                : conflictType == 'exact_period_amount' ? 'Likely Duplicate Detected'
                : 'Possible Duplicate',
            style: const TextStyle(fontSize: 16),
          )),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(conflict['message'] as String? ?? '', style: const TextStyle(fontSize: 14)),
          const SizedBox(height: 10),

          // Details table
          if ((conflict['details'] as List?)?.isNotEmpty == true) ...[
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(children: [
                // Header
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                  ),
                  child: const Row(children: [
                    Expanded(child: Text('Invoice #', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                    Expanded(child: Text('Date', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                    Text('Amount', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  ]),
                ),
                ...(conflict['details'] as List).map((d) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Row(children: [
                    Expanded(child: Text(d['invoice_number'] ?? '', style: const TextStyle(fontSize: 12))),
                    Expanded(child: Text(d['invoice_date'] ?? '', style: const TextStyle(fontSize: 12))),
                    Text(d['amount'] ?? '', style: const TextStyle(fontSize: 12)),
                  ]),
                )),
              ]),
            ),
            const SizedBox(height: 12),
          ],

          if (isBlocker)
            const Text('Please change the invoice number before submitting.',
                style: TextStyle(color: Colors.red, fontSize: 13))
          else
            const Text('Are you sure you want to submit this invoice?',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(isBlocker ? 'Fix Invoice Number' : 'Go Back & Review'),
          ),
          if (!isBlocker)
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
              child: const Text('Yes, Submit Anyway'),
            ),
        ],
      ),
    ) ?? false;
  }

  // ── UI helpers ────────────────────────────────────────────────────────────

  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  Future<void> _pickDate(bool isInvoice) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isInvoice ? _invoiceDate : _dueDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      setState(() { if (isInvoice) _invoiceDate = picked; else _dueDate = picked; });
      if (isInvoice) _triggerDupCheck();
    }
  }

  Color _statusColor(String s) => switch (s) {
    'Approved' => const Color(0xFF16A34A),
    'Paid'     => const Color(0xFF0284C7),
    'Pending'  => const Color(0xFFD97706),
    'Unpaid'   => const Color(0xFFDC2626),
    'Rejected' => const Color(0xFF9333EA),
    _          => Colors.grey,
  };

  @override
  Widget build(BuildContext context) {
    final theme     = Theme.of(context);
    String appTitle = _isView ? 'Invoice Details'
        : _isCreate ? 'New Invoice'
        : 'Edit Invoice';

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: Text(appTitle, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        actions: [
          if (!_isLoading && _canEdit)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton(
                onPressed: _isSaving ? null : _save,
                child: _isSaving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(_isCreate ? 'Submit' : 'Update',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: theme.colorScheme.primary)),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

            // ── Status badge (view/edit mode) ─────────────────────────
            if (!_isCreate && _invoiceStatus.isNotEmpty) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: _statusColor(_invoiceStatus).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _statusColor(_invoiceStatus).withOpacity(0.3)),
                ),
                child: Row(children: [
                  Icon(Icons.info_outline, size: 16, color: _statusColor(_invoiceStatus)),
                  const SizedBox(width: 8),
                  Text('Status: $_invoiceStatus',
                      style: TextStyle(fontWeight: FontWeight.w600, color: _statusColor(_invoiceStatus))),
                  if (!_canEdit) ...[
                    const Spacer(),
                    Icon(Icons.lock_outline, size: 14, color: _statusColor(_invoiceStatus)),
                    const SizedBox(width: 4),
                    Text('Locked', style: TextStyle(fontSize: 12, color: _statusColor(_invoiceStatus))),
                  ],
                ]),
              ),
              const SizedBox(height: 12),
            ],

            // ── Duplicate warning banner ───────────────────────────────
            if (_dupWarning != null && _isCreate) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.orange.shade300),
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.warning_amber, color: Colors.orange.shade700, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_dupWarning!['message'] as String? ?? '',
                        style: TextStyle(fontWeight: FontWeight.w600, color: Colors.orange.shade800, fontSize: 13)),
                    if ((_dupWarning!['details'] as List?)?.isNotEmpty == true) ...[
                      const SizedBox(height: 4),
                      ...(_dupWarning!['details'] as List).map((d) =>
                          Text('• ${d['invoice_number']} — ${d['invoice_date']} — ${d['amount']}',
                              style: TextStyle(fontSize: 12, color: Colors.orange.shade700))),
                    ],
                  ])),
                ]),
              ),
              const SizedBox(height: 12),
            ],

            // ── Invoice Number ────────────────────────────────────────
            _card('Invoice Number', [
              if (_canEdit) ...[
                Row(children: [
                  Checkbox(
                    value: _manualNumber,
                    onChanged: (v) {
                      setState(() {
                        _manualNumber = v!;
                        if (!_manualNumber) {
                          _invoiceNumCtrl.text = _generatedNum;
                        } else {
                          _invoiceNumCtrl.clear();
                        }
                      });
                    },
                  ),
                  const Text('Manual invoice number', style: TextStyle(fontSize: 13)),
                ]),
                const SizedBox(height: 6),
              ],
              TextFormField(
                controller: _invoiceNumCtrl,
                readOnly: !_manualNumber || !_canEdit,
                decoration: InputDecoration(
                  labelText: 'Invoice Number',
                  hintText: _manualNumber ? 'Enter invoice number' : 'Auto-generated',
                  isDense: true,
                  filled: true,
                  fillColor: (!_manualNumber || !_canEdit) ? Colors.grey.shade100 : null,
                  suffixIcon: _generatingNum ? const Padding(
                    padding: EdgeInsets.all(10),
                    child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  ) : null,
                ),
                validator: _manualNumber
                    ? (v) {
                  if (v == null || v.trim().isEmpty) return 'Required';
                  if (!RegExp(r'^[A-Za-z0-9\-]{1,50}$').hasMatch(v)) {
                    return 'Letters, numbers and hyphens only (max 50)';
                  }
                  return null;
                }
                    : null,
                onChanged: _manualNumber
                    ? (v) {
                  _dupTimer?.cancel();
                  _dupTimer = Timer(const Duration(milliseconds: 700), () => _checkNumberDuplicate(v));
                }
                    : null,
              ),
            ]),
            const SizedBox(height: 14),

            // ── Company picker (create only) ───────────────────────────
            if (_isCreate || _isView) ...[
              _card(_isView ? 'Billed To' : 'Bill To Company', [
                if (_isView) ...[
                  _infoRow(Icons.business, _selectedCompany?['company_name'] ?? '—'),
                  if (_selectedCompany?['company_city'] != null)
                    _infoRow(Icons.location_city, '${_selectedCompany!['company_city']} ${_selectedCompany!['company_state'] ?? ''}'),
                ] else if (_companies.isEmpty)
                  const Text('No active companies linked to your account.',
                      style: TextStyle(color: Colors.red))
                else
                  DropdownButtonFormField<Map<String, dynamic>>(
                    value: _selectedCompany,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Select Company *',
                      prefixIcon: Icon(Icons.business_outlined),
                      isDense: true,
                    ),
                    items: _companies.map((c) {
                      final co = c as Map<String, dynamic>;
                      return DropdownMenuItem(
                        value: co,
                        child: Text(co['company_name'] ?? '—', overflow: TextOverflow.ellipsis),
                      );
                    }).toList(),
                    onChanged: (v) {
                      setState(() { _selectedCompany = v; _dupWarning = null; });
                      _generateInvoiceNumber();
                      _triggerDupCheck();
                    },
                    validator: (v) => v == null ? 'Please select a company' : null,
                  ),
              ]),
              const SizedBox(height: 14),
            ],

            // ── Dates ─────────────────────────────────────────────────
            _card('Invoice Details', [
              Row(children: [
                Expanded(child: _dateTile('Invoice Date', _invoiceDate,
                    _canEdit ? () => _pickDate(true) : null)),
                const SizedBox(width: 12),
                Expanded(child: _dateTile('Due Date', _dueDate,
                    _canEdit ? () => _pickDate(false) : null)),
              ]),
            ]),
            const SizedBox(height: 14),

            // ── Line items ─────────────────────────────────────────────
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(_isView ? 'Line Items' : 'Line Items *',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              if (_canEdit)
                TextButton.icon(
                  onPressed: _addItem,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add Item'),
                ),
            ]),
            const SizedBox(height: 6),

            ..._items.asMap().entries.map((e) => _itemCard(e.key, e.value)),

            const SizedBox(height: 14),

            // ── Total ──────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: theme.colorScheme.primary.withOpacity(0.3)),
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Invoice Total', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                Text(
                  '\$${_subtotal.toStringAsFixed(2)}',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: theme.colorScheme.primary),
                ),
              ]),
            ),
            const SizedBox(height: 14),

            // ── Memo ───────────────────────────────────────────────────
            _card('Memo / Notes', [
              if (_isView && _memoCtrl.text.isEmpty)
                Text('No memo', style: TextStyle(color: Colors.grey.shade500, fontStyle: FontStyle.italic))
              else
                TextFormField(
                  controller: _memoCtrl,
                  readOnly: !_canEdit,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    hintText: 'Add any notes or details…',
                    border: InputBorder.none,
                    filled: false,
                    isDense: true,
                  ),
                ),
            ]),

            const SizedBox(height: 100),
          ]),
        ),
      ),
    );
  }

  // ── Item card ──────────────────────────────────────────────────────────────

  Widget _itemCard(int index, Map<String, dynamic> item) {
    final descCtrl    = item['descCtrl']    as TextEditingController;
    final accountCtrl = item['accountCtrl'] as TextEditingController;
    final amountCtrl  = item['amountCtrl']  as TextEditingController;
    final serviceType = item['serviceType'] as String;
    final amount      = double.tryParse(amountCtrl.text) ?? 0;

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
        child: Column(children: [
          // Header
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('Item ${index + 1}',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.primary)),
            ),
            const Spacer(),
            if (_canEdit)
              GestureDetector(
                onTap: () { _removeItem(index); setState(() {}); },
                child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(6)),
                  child: Icon(Icons.close, color: Colors.red.shade400, size: 16),
                ),
              ),
          ]),
          const SizedBox(height: 10),

          // Description
          _isView
              ? _labelValue('Description', descCtrl.text)
              : TextFormField(
            controller: descCtrl,
            readOnly: !_canEdit,
            decoration: const InputDecoration(labelText: 'Description *', isDense: true),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),

          // Account + service type
          _isView
              ? Row(children: [
            Expanded(child: _labelValue('Account', accountCtrl.text.isEmpty ? '—' : accountCtrl.text)),
            Expanded(child: _labelValue('Type', serviceType)),
          ])
              : Row(children: [
            Expanded(child: TextFormField(
              controller: accountCtrl,
              decoration: const InputDecoration(labelText: 'Account Name', isDense: true),
            )),
            const SizedBox(width: 10),
            Expanded(child: DropdownButtonFormField<String>(
              value: serviceType,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Service Type *', isDense: true),
              items: _serviceTypes.map((t) => DropdownMenuItem(
                value: t,
                child: Text(t, style: const TextStyle(fontSize: 13)),
              )).toList(),
              onChanged: (v) => setState(() => item['serviceType'] = v ?? 'Service'),
            )),
          ]),
          const SizedBox(height: 10),

          // Amount
          _isView
              ? _labelValue('Amount', '\$${amount.toStringAsFixed(2)}')
              : Row(children: [
            Expanded(child: TextFormField(
              controller: amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Amount (\$) *', prefixText: '\$ ', isDense: true),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Required';
                if ((double.tryParse(v) ?? -1) <= 0) return 'Must be > 0';
                return null;
              },
              onChanged: (_) { setState(() {}); _triggerDupCheck(); },
            )),
            const SizedBox(width: 12),
            Text('\$${amount.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ]),
        ]),
      ),
    );
  }

  // ── UI helpers ─────────────────────────────────────────────────────────────

  Widget _card(String title, List<Widget> children) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 12),
          ...children,
        ]),
      ),
    );
  }

  Widget _dateTile(String label, DateTime date, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(10),
          color: onTap == null ? Colors.grey.shade50 : Colors.white,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          const SizedBox(height: 4),
          Row(children: [
            Icon(Icons.calendar_today_outlined, size: 13,
                color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 6),
            Text(DateFormat('MMM dd, yyyy').format(date),
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          ]),
        ]),
      ),
    );
  }

  Widget _infoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(children: [
        Icon(icon, size: 14, color: Colors.grey.shade500),
        const SizedBox(width: 6),
        Text(text, style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
      ]),
    );
  }

  Widget _labelValue(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
      ]),
    );
  }

  @override
  void dispose() {
    _dupTimer?.cancel();
    _invoiceNumCtrl.dispose();
    _memoCtrl.dispose();
    for (final item in _items) {
      (item['descCtrl'] as TextEditingController).dispose();
      (item['accountCtrl'] as TextEditingController).dispose();
      (item['amountCtrl'] as TextEditingController).dispose();
    }
    super.dispose();
  }
}
