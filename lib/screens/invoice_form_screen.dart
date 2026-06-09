// lib/screens/invoice_form_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';

class InvoiceFormScreen extends StatefulWidget {
  final int?  invoiceId; // null = create, set = edit/view
  final bool  viewOnly;  // true = read-only view

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

  // ── Invoice number ────────────────────────────────────────────────────────
  // In CREATE: _originalNum is the auto-generated value; manual toggle lets
  //            the user type their own instead.
  // In EDIT:   _originalNum is the existing invoice number (always shown when
  //            manual toggle is OFF); manual toggle lets them type a new one.
  bool   _manualNumber  = false;
  bool   _generatingNum = false;
  String _originalNum   = ''; // auto-gen (create) or current DB value (edit)

  // ── Company / client ──────────────────────────────────────────────────────
  List<dynamic>         _companies       = [];
  Map<String, dynamic>? _selectedCompany;

  // ── Line items ────────────────────────────────────────────────────────────
  static const _serviceTypes = ['Service', 'Reimbursement'];
  final List<Map<String, dynamic>> _items = [];

  // ── State ─────────────────────────────────────────────────────────────────
  bool   _isLoading     = false;
  bool   _isSaving      = false;
  String _invoiceStatus = '';

  // ── Duplicate-check state ─────────────────────────────────────────────────
  Timer?  _dupTimer;
  Timer?  _numDupTimer;
  // Separate warnings so both can show at once (mirrors edit.php dupNumberAlert
  // + dupPeriodAlert being independent)
  Map<String, dynamic>? _periodWarning; // period/amount conflict
  Map<String, dynamic>? _numberWarning; // invoice number conflict
  bool _dupConfirmed = false;

  // ── Derived ───────────────────────────────────────────────────────────────
  bool get _isCreate => widget.invoiceId == null;
  bool get _isView   => widget.viewOnly;
  // Only Pending invoices are editable (mirrors edit.php status check)
  bool get _canEdit  => !_isView && (_isCreate || _invoiceStatus == 'Pending');

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

  // ── Load companies (from login cache) ─────────────────────────────────────

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

  // ── Load existing invoice for edit / view ─────────────────────────────────

  Future<void> _loadInvoice() async {
    setState(() => _isLoading = true);
    try {
      final data = await ApiService.getInvoice(widget.invoiceId!);
      setState(() {
        _invoiceStatus        = data['status'] as String? ?? '';
        _invoiceDate          = DateTime.parse(data['invoice_date']);
        _dueDate              = DateTime.parse(data['due_date']);
        _memoCtrl.text        = data['memo'] ?? '';

        // Store current number as _originalNum; show it in the field
        final currentNum      = data['invoice_number'] as String? ?? '';
        _originalNum          = currentNum;
        _invoiceNumCtrl.text  = currentNum;

        // Pre-select company (locked in edit — just for display)
        final companyId = data['company_id']?.toString();
        if (companyId != null) {
          try {
            _selectedCompany = _companies.firstWhere(
              (c) => c['company_id']?.toString() == companyId,
            ) as Map<String, dynamic>?;
          } catch (_) {}
          // Fallback: build a minimal display map from the invoice data
          _selectedCompany ??= {
            'company_id':   data['company_id'],
            'client_id':    data['client_id'],
            'company_name': data['company_name'] ?? '—',
            'company_city': data['company_city'],
            'company_state':data['company_state'],
          };
        }

        // Load line items
        _items.clear();
        for (final item in (data['items'] as List? ?? [])) {
          _items.add(_newItemFrom(item as Map<String, dynamic>));
        }
        if (_items.isEmpty) _addItem();
      });

      // Run period duplicate check immediately when loading edit form
      // (mirrors edit.php calling triggerPeriodCheck on DOMContentLoaded)
      if (_canEdit) _triggerPeriodCheck();

    } catch (e) {
      _showSnack('Failed to load invoice: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Invoice number ────────────────────────────────────────────────────────

  Future<void> _generateInvoiceNumber() async {
    if (_manualNumber) return;
    final companyId = int.tryParse(_selectedCompany?['company_id']?.toString() ?? '');
    if (companyId == null) return;

    setState(() { _generatingNum = true; _invoiceNumCtrl.text = 'Generating…'; });
    try {
      final num = await ApiService.generateInvoiceNumber(companyId);
      setState(() { _originalNum = num; _invoiceNumCtrl.text = num; });
    } catch (_) {
      setState(() => _invoiceNumCtrl.text = '');
    } finally {
      if (mounted) setState(() => _generatingNum = false);
    }
  }

  void _onManualToggleChanged(bool manual) {
    setState(() {
      _manualNumber = manual;
      _numberWarning = null;
      if (!manual) {
        // Revert to the original/auto-generated number
        _invoiceNumCtrl.text = _originalNum;
      } else {
        // Clear so user types a new one (mirrors web toggle behaviour)
        _invoiceNumCtrl.clear();
      }
    });
    // In create mode, if switching back to auto and no original yet, regenerate
    if (!manual && _isCreate && _originalNum.isEmpty) {
      _generateInvoiceNumber();
    }
  }

  void _onInvoiceNumChanged(String value) {
    if (!_manualNumber) return;
    _numDupTimer?.cancel();
    setState(() => _numberWarning = null);
    if (value.trim().isEmpty) return;
    // Don't flag if user typed back the original number
    if (value.trim().toUpperCase() == _originalNum.toUpperCase()) return;
    _numDupTimer = Timer(const Duration(milliseconds: 600), () => _checkNumberDup(value.trim()));
  }

  Future<void> _checkNumberDup(String number) async {
    if (number.isEmpty) return;
    try {
      final result = await ApiService.checkDuplicate(
        checkType:     'invoice_number',
        invoiceNumber: number,
        excludeId:     widget.invoiceId, // null for create — PHP ignores it
      );
      if (mounted) {
        setState(() => _numberWarning = (result['duplicate'] as bool? ?? false) ? result : null);
      }
    } catch (_) {}
  }

  // ── Period/amount duplicate check ─────────────────────────────────────────
  // Runs in BOTH create and edit modes (unlike v3 which only ran in create)

  void _triggerPeriodCheck() {
    _dupTimer?.cancel();
    _dupTimer = Timer(const Duration(milliseconds: 600), _checkPeriodDup);
  }

  Future<void> _checkPeriodDup() async {
    final companyId = int.tryParse(_selectedCompany?['company_id']?.toString() ?? '');
    if (companyId == null) return;

    try {
      final result = await ApiService.checkDuplicate(
        checkType:   'period_amount',
        companyId:   companyId,
        invoiceDate: DateFormat('yyyy-MM-dd').format(_invoiceDate),
        totalAmount: _subtotal,
        excludeId:   widget.invoiceId, // excludes this invoice in edit mode
      );
      if (mounted) {
        setState(() {
          _periodWarning = (result['duplicate'] as bool? ?? false) ? result : null;
          _dupConfirmed  = false;
        });
      }
    } catch (_) {}
  }

  // ── Line items ────────────────────────────────────────────────────────────

  Map<String, dynamic> _newItemFrom([Map<String, dynamic>? existing]) => {
    'descCtrl':    TextEditingController(text: existing?['description']  ?? ''),
    'accountCtrl': TextEditingController(text: existing?['account_name'] ?? ''),
    'amountCtrl':  TextEditingController(text: existing?['amount']?.toString() ?? ''),
    'serviceType': existing?['service_type'] ?? 'Service',
  };

  void _addItem() => setState(() => _items.add(_newItemFrom()));

  void _removeItem(int index) {
    if (_items.length <= 1) {
      (_items[0]['descCtrl']    as TextEditingController).clear();
      (_items[0]['amountCtrl']  as TextEditingController).clear();
      setState(() => _items[0]['serviceType'] = 'Service');
      return;
    }
    (_items[index]['descCtrl']    as TextEditingController).dispose();
    (_items[index]['accountCtrl'] as TextEditingController).dispose();
    (_items[index]['amountCtrl']  as TextEditingController).dispose();
    setState(() => _items.removeAt(index));
    _triggerPeriodCheck();
  }

  double get _subtotal {
    double t = 0;
    for (final item in _items) {
      t += double.tryParse((item['amountCtrl'] as TextEditingController).text) ?? 0;
    }
    return t;
  }

  // ── Save ──────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCompany == null) { _showSnack('Please select a company', Colors.orange); return; }

    // Block on exact-number duplicates; prompt for period conflicts
    if (_numberWarning != null) {
      final ct = _numberWarning!['conflict_type'] as String? ?? '';
      if (ct == 'exact_number') {
        _showSnack('Invoice number already exists. Please choose another.', Colors.red);
        return;
      }
    }

    final activeWarning = _numberWarning ?? _periodWarning;
    if (activeWarning != null && !_dupConfirmed) {
      final proceed = await _showDupDialog(activeWarning);
      if (!proceed) return;
      setState(() => _dupConfirmed = true);
    }

    // Collect line items (skip empty rows)
    final lineItems = <Map<String, dynamic>>[];
    for (final item in _items) {
      final desc   = (item['descCtrl']   as TextEditingController).text.trim();
      final amount = double.tryParse((item['amountCtrl'] as TextEditingController).text) ?? 0;
      if (desc.isEmpty || amount <= 0) continue;
      lineItems.add({
        'description':  desc,
        'account_name': (item['accountCtrl'] as TextEditingController).text.trim(),
        'service_type': item['serviceType'] as String,
        'amount':       amount,
      });
    }
    if (lineItems.isEmpty) { _showSnack('Add at least one valid line item', Colors.orange); return; }

    // Build payload
    final payload = <String, dynamic>{
      'company_id':   _selectedCompany!['company_id'],
      'client_id':    _selectedCompany!['client_id'],
      'invoice_date': DateFormat('yyyy-MM-dd').format(_invoiceDate),
      'due_date':     DateFormat('yyyy-MM-dd').format(_dueDate),
      'memo':         _memoCtrl.text.trim(),
      'items':        lineItems,
    };

    // Only send invoice_number when in manual mode
    // CREATE: send if manual toggle is on
    // EDIT:   send if manual toggle is on AND user typed something different
    if (_manualNumber) {
      final typed = _invoiceNumCtrl.text.trim();
      if (typed.isNotEmpty) {
        payload['invoice_number'] = typed;
      }
    }

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

  // ── Duplicate dialog (mirrors dupModal in edit.php) ───────────────────────

  Future<bool> _showDupDialog(Map<String, dynamic> conflict) async {
    final ct        = conflict['conflict_type'] as String? ?? '';
    final isBlocker = ct == 'exact_number';

    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Icon(
            isBlocker ? Icons.error_outline : Icons.warning_amber_outlined,
            color: isBlocker ? Colors.red : Colors.orange,
            size: 22,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(
            isBlocker             ? 'Invoice Number Already Used'   :
            ct == 'exact_period_amount' ? 'Likely Duplicate Detected'     :
            ct == 'same_period_diff_amount' ? 'Invoice Exists — Same Period' :
            'Possible Duplicate',
            style: const TextStyle(fontSize: 15),
          )),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(conflict['message'] as String? ?? '', style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 10),

          if ((conflict['details'] as List?)?.isNotEmpty == true) ...[
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                  ),
                  child: const Row(children: [
                    Expanded(child: Text('Invoice #', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                    Expanded(child: Text('Date',      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                    Text('Amount',                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                  ]),
                ),
                ...(conflict['details'] as List).map((d) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Row(children: [
                    Expanded(child: Text(d['invoice_number'] ?? '', style: const TextStyle(fontSize: 11))),
                    Expanded(child: Text(d['invoice_date']   ?? '', style: const TextStyle(fontSize: 11))),
                    Text(d['amount'] ?? '',                          style: const TextStyle(fontSize: 11)),
                  ]),
                )),
              ]),
            ),
            const SizedBox(height: 12),
          ],

          Text(
            isBlocker
              ? 'Please change the invoice number before saving.'
              : 'Are you sure you want to ${_isCreate ? "submit" : "update"} this invoice?',
            style: TextStyle(
              fontWeight: FontWeight.w600, fontSize: 13,
              color: isBlocker ? Colors.red : Colors.grey.shade800,
            ),
          ),
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
                backgroundColor: Colors.orange.shade700,
                foregroundColor: Colors.white,
              ),
              child: Text('Yes, ${_isCreate ? "Submit" : "Update"} Anyway'),
            ),
        ],
      ),
    ) ?? false;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

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
      firstDate: DateTime(2020), lastDate: DateTime(2035),
    );
    if (picked != null) {
      setState(() { if (isInvoice) _invoiceDate = picked; else _dueDate = picked; });
      if (isInvoice) _triggerPeriodCheck();
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

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = _isView ? 'Invoice Details' : _isCreate ? 'New Invoice' : 'Edit Invoice';

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
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
                    : Text(
                        _isCreate ? 'Submit' : 'Update',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: theme.colorScheme.primary),
                      ),
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

                  // ── Status banner ──────────────────────────────────────────
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

                  // ── Invoice Number card ────────────────────────────────────
                  _card('Invoice Number', [
                    // Manual toggle — shown in both create AND edit (when editable)
                    if (_canEdit)
                      Row(children: [
                        Transform.scale(
                          scale: 0.85,
                          child: Switch(
                            value: _manualNumber,
                            onChanged: _onManualToggleChanged,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(
                            _manualNumber ? 'Manual number' : 'Auto-generated number',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                          if (!_isCreate && !_manualNumber)
                            Text(
                              'Toggle to change invoice number',
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                            ),
                        ]),
                      ]),

                    if (_canEdit && !_manualNumber && !_isCreate)
                      // Edit mode, auto (locked) — show current number read-only
                      const SizedBox(height: 6),

                    TextFormField(
                      controller: _invoiceNumCtrl,
                      // Read-only when: not in manual mode, OR not editable, OR generating
                      readOnly: !_manualNumber || !_canEdit || _generatingNum,
                      decoration: InputDecoration(
                        labelText: 'Invoice Number',
                        hintText: _manualNumber
                            ? (_isCreate ? 'Enter invoice number' : 'Enter new invoice number')
                            : (_isCreate ? 'Auto-generated' : 'Current number'),
                        isDense: true,
                        filled: true,
                        fillColor: (!_manualNumber || !_canEdit) ? Colors.grey.shade100 : null,
                        suffixIcon: _generatingNum
                            ? const Padding(
                                padding: EdgeInsets.all(10),
                                child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                              )
                            : (_canEdit && !_manualNumber && !_isCreate)
                                ? Tooltip(
                                    message: 'Toggle switch above to edit',
                                    child: Icon(Icons.lock_outline, size: 18, color: Colors.grey.shade400),
                                  )
                                : null,
                      ),
                      validator: _manualNumber
                          ? (v) {
                              if (v == null || v.trim().isEmpty) return 'Required';
                              if (!RegExp(r'^[A-Za-z0-9\-]{1,50}$').hasMatch(v.trim())) {
                                return 'Letters, numbers and hyphens only (max 50)';
                              }
                              return null;
                            }
                          : null,
                      onChanged: _onInvoiceNumChanged,
                    ),

                    // ── Number duplicate warning ───────────────────────────
                    if (_numberWarning != null) ...[
                      const SizedBox(height: 8),
                      _dupBanner(_numberWarning!, isError: _numberWarning!['conflict_type'] == 'exact_number'),
                    ],
                  ]),
                  const SizedBox(height: 14),

                  // ── Company display ────────────────────────────────────────
                  // CREATE: dropdown picker
                  // EDIT/VIEW: read-only info (company is locked once invoice is created)
                  if (_isCreate)
                    _card('Bill To Company', [
                      if (_companies.isEmpty)
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
                            setState(() { _selectedCompany = v; _periodWarning = null; });
                            _generateInvoiceNumber();
                            _triggerPeriodCheck();
                          },
                          validator: (v) => v == null ? 'Please select a company' : null,
                        ),
                    ])
                  else
                    // Edit/View — company is locked, show as info row
                    _card('Company', [
                      _infoRow(Icons.business_outlined, _selectedCompany?['company_name'] ?? '—'),
                      if (_selectedCompany?['company_city'] != null)
                        _infoRow(Icons.location_city_outlined,
                          '${_selectedCompany!['company_city']} ${_selectedCompany!['company_state'] ?? ''}'.trim()),
                    ]),
                  const SizedBox(height: 14),

                  // ── Period/amount duplicate warning ────────────────────────
                  // Shown in BOTH create and edit (unlike v3 which was create-only)
                  if (_periodWarning != null) ...[
                    _dupBanner(_periodWarning!, isError: _periodWarning!['conflict_type'] == 'exact_period_amount'),
                    const SizedBox(height: 14),
                  ],

                  // ── Dates ──────────────────────────────────────────────────
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

  // ── Duplicate warning banner ───────────────────────────────────────────────

  Widget _dupBanner(Map<String, dynamic> conflict, {required bool isError}) {
    final details = conflict['details'] as List? ?? [];
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: isError ? Colors.red.shade50 : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isError ? Colors.red.shade300 : Colors.orange.shade300),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(
              isError ? Icons.error_outline : Icons.warning_amber_outlined,
              size: 16,
              color: isError ? Colors.red.shade700 : Colors.orange.shade700,
            ),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                conflict['message'] as String? ?? '',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: isError ? Colors.red.shade800 : Colors.orange.shade800,
                ),
              ),
              if (conflict['sub'] != null && (conflict['sub'] as String).isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  conflict['sub'] as String,
                  style: TextStyle(fontSize: 12, color: isError ? Colors.red.shade700 : Colors.orange.shade700),
                ),
              ],
            ])),
          ]),
        ),
        if (details.isNotEmpty)
          Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: isError ? Colors.red.shade200 : Colors.orange.shade200),
            ),
            child: Column(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: isError ? Colors.red.shade100 : Colors.orange.shade100,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                ),
                child: const Row(children: [
                  Expanded(child: Text('Invoice #', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                  Expanded(child: Text('Date',      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                  Text('Amount',                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                ]),
              ),
              ...details.map((d) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                child: Row(children: [
                  Expanded(child: Text(d['invoice_number'] ?? '', style: const TextStyle(fontSize: 11))),
                  Expanded(child: Text(d['invoice_date']   ?? '', style: const TextStyle(fontSize: 11))),
                  Text(d['amount'] ?? '',                          style: const TextStyle(fontSize: 11)),
                ]),
              )),
            ]),
          ),
      ]),
    );
  }

  // ── Item card ─────────────────────────────────────────────────────────────

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
          // Row header
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
                onTap: () => _removeItem(index),
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
                    readOnly: !_canEdit,
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
                    onChanged: _canEdit ? (v) => setState(() => item['serviceType'] = v ?? 'Service') : null,
                  )),
                ]),
          const SizedBox(height: 10),

          // Amount
          _isView
              ? _labelValue('Amount', '\$${amount.toStringAsFixed(2)}')
              : Row(children: [
                  Expanded(child: TextFormField(
                    controller: amountCtrl,
                    readOnly: !_canEdit,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Amount (\$) *', prefixText: '\$ ', isDense: true),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Required';
                      if ((double.tryParse(v) ?? -1) <= 0) return 'Must be > 0';
                      return null;
                    },
                    onChanged: (_) { setState(() {}); _triggerPeriodCheck(); },
                  )),
                  const SizedBox(width: 12),
                  Text('\$${amount.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ]),
        ]),
      ),
    );
  }

  // ── Small UI helpers ───────────────────────────────────────────────────────

  Widget _card(String title, List<Widget> children) => Card(
    elevation: 0, color: Colors.white,
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

  Widget _dateTile(String label, DateTime date, VoidCallback? onTap) => GestureDetector(
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

  Widget _infoRow(IconData icon, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(children: [
      Icon(icon, size: 14, color: Colors.grey.shade500),
      const SizedBox(width: 6),
      Expanded(child: Text(text, style: TextStyle(fontSize: 13, color: Colors.grey.shade700))),
    ]),
  );

  Widget _labelValue(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
    ]),
  );

  @override
  void dispose() {
    _dupTimer?.cancel();
    _numDupTimer?.cancel();
    _invoiceNumCtrl.dispose();
    _memoCtrl.dispose();
    for (final item in _items) {
      (item['descCtrl']    as TextEditingController).dispose();
      (item['accountCtrl'] as TextEditingController).dispose();
      (item['amountCtrl']  as TextEditingController).dispose();
    }
    super.dispose();
  }
}
