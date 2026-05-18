// lib/screens/profile_screen.dart
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'login_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _profile;
  bool _isLoading = true;
  bool _isEditing = false;
  bool _isSaving  = false;

  // Editable fields matching your contractors table
  final _nameCtrl        = TextEditingController();
  final _legalNameCtrl   = TextEditingController();
  final _phoneCtrl       = TextEditingController();
  final _landlineCtrl    = TextEditingController();
  final _addressCtrl     = TextEditingController();
  final _cityCtrl        = TextEditingController();
  final _stateCtrl       = TextEditingController();
  final _countryCtrl     = TextEditingController();
  final _zipCtrl         = TextEditingController();
  final _bankNameCtrl    = TextEditingController();
  final _bankAcctCtrl    = TextEditingController();
  final _ibanCtrl        = TextEditingController();
  final _swiftCtrl       = TextEditingController();

  // Password change
  final _currentPwCtrl = TextEditingController();
  final _newPwCtrl     = TextEditingController();
  bool _showPasswordSection = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() => _isLoading = true);
    try {
      // Try cache first for instant display
      final cached = await ApiService.getCachedProfile();
      if (cached != null) _fillForm(cached);

      // Then fetch fresh from server
      final profile = await ApiService.getProfile();
      _fillForm(profile);
      setState(() => _profile = profile);

    } on UnauthorizedException {
      await ApiService.logout();
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(context,
          MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
    } catch (e) {
      if (_profile == null) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to load profile')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _fillForm(Map<String, dynamic> p) {
    setState(() {
      _profile = p;
      _nameCtrl.text      = p['name'] ?? '';
      _legalNameCtrl.text = p['legal_name'] ?? '';
      _phoneCtrl.text     = p['phone_number'] ?? '';
      _landlineCtrl.text  = p['landline_number'] ?? '';
      _addressCtrl.text   = p['street_address'] ?? '';
      _cityCtrl.text      = p['city'] ?? '';
      _stateCtrl.text     = p['state'] ?? '';
      _countryCtrl.text   = p['country'] ?? '';
      _zipCtrl.text       = p['zip_code'] ?? '';
      _bankNameCtrl.text  = p['bank_name'] ?? '';
      _bankAcctCtrl.text  = p['bank_account_number'] ?? '';
      _ibanCtrl.text      = p['iban'] ?? '';
      _swiftCtrl.text     = p['swift'] ?? '';
    });
  }

  Future<void> _saveProfile() async {
    setState(() => _isSaving = true);
    try {
      final data = {
        'name':                _nameCtrl.text.trim(),
        'legal_name':          _legalNameCtrl.text.trim(),
        'phone_number':        _phoneCtrl.text.trim(),
        'landline_number':     _landlineCtrl.text.trim(),
        'street_address':      _addressCtrl.text.trim(),
        'city':                _cityCtrl.text.trim(),
        'state':               _stateCtrl.text.trim(),
        'country':             _countryCtrl.text.trim(),
        'zip_code':            _zipCtrl.text.trim(),
        'bank_name':           _bankNameCtrl.text.trim(),
        'bank_account_number': _bankAcctCtrl.text.trim(),
        'iban':                _ibanCtrl.text.trim(),
        'swift':               _swiftCtrl.text.trim(),
        if (_showPasswordSection && _newPwCtrl.text.isNotEmpty) ...{
          'current_password': _currentPwCtrl.text,
          'new_password':     _newPwCtrl.text,
        },
      };

      await ApiService.updateProfile(data);
      setState(() {
        _isEditing = false;
        _showPasswordSection = false;
      });
      _currentPwCtrl.clear();
      _newPwCtrl.clear();

      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated!'),
              backgroundColor: Colors.green));
      _loadProfile();

    } on ApiException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: const Text('My Profile', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        actions: [
          if (!_isLoading)
            TextButton(
              onPressed: _isSaving ? null : () {
                if (_isEditing) {
                  _saveProfile();
                } else {
                  setState(() => _isEditing = true);
                }
              },
              child: _isSaving
                  ? const SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(
                _isEditing ? 'Save' : 'Edit',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: Theme.of(context).colorScheme.primary),
              ),
            ),
          if (_isEditing)
            TextButton(
              onPressed: () {
                setState(() { _isEditing = false; _showPasswordSection = false; });
                _fillForm(_profile ?? {});
              },
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
        ],
      ),
      body: _isLoading && _profile == null
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          // ── Avatar & entity badge ────────────────────────────────────
          _avatarSection(),
          const SizedBox(height: 20),

          // ── Personal info ────────────────────────────────────────────
          _section('Personal Information', [
            _field('Display Name', _nameCtrl, required: true),
            _field('Legal Name', _legalNameCtrl),
            _field('Mobile Number', _phoneCtrl, keyboard: TextInputType.phone),
            _field('Landline', _landlineCtrl, keyboard: TextInputType.phone),
          ]),
          const SizedBox(height: 14),

          // ── Address ──────────────────────────────────────────────────
          _section('Address', [
            _field('Street Address', _addressCtrl),
            _row([
              _field('City', _cityCtrl),
              _field('State', _stateCtrl),
            ]),
            _row([
              _field('ZIP Code', _zipCtrl, keyboard: TextInputType.number),
              _field('Country', _countryCtrl),
            ]),
          ]),
          const SizedBox(height: 14),

          // ── Tax & identity ───────────────────────────────────────────
          _section('Tax & Identity', [
            _readOnlyField('EIN', _profile?['ein']),
            _readOnlyField('Email', _profile?['email']),
            _readOnlyField('Entity Type',
                (_profile?['entity_type'] ?? '').toString().toUpperCase()),
            _readOnlyField('Service Type', _profile?['service_type']),
            _readOnlyField('Balance', '\$${_profile?['balance'] ?? '0.00'}'),
          ]),
          const SizedBox(height: 14),

          // ── Banking ──────────────────────────────────────────────────
          _section('Banking Information', [
            _field('Bank Name', _bankNameCtrl),
            _field('Account Number', _bankAcctCtrl,
                keyboard: TextInputType.number, obscure: !_isEditing),
            _field('IBAN', _ibanCtrl),
            _field('SWIFT / BIC', _swiftCtrl),
          ]),
          const SizedBox(height: 14),

          // ── Linked companies ─────────────────────────────────────────
          if (_profile?['companies'] != null &&
              (_profile!['companies'] as List).isNotEmpty)
            _companiesSection(),

          // ── Change password ──────────────────────────────────────────
          if (_isEditing) ...[
            const SizedBox(height: 14),
            _passwordSection(),
          ],

          const SizedBox(height: 40),
        ]),
      ),
    );
  }

  Widget _avatarSection() {
    final name       = _profile?['name'] ?? '';
    final entityType = (_profile?['entity_type'] ?? 'contractor').toString();
    final initials   = name.isNotEmpty
        ? name.split(' ').take(2).map((e) => e[0].toUpperCase()).join()
        : '?';

    return Column(children: [
      Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer,
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Text(initials,
              style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary)),
        ),
      ),
      const SizedBox(height: 10),
      Text(name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      Text(_profile?['email'] ?? '',
          style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
      const SizedBox(height: 6),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: entityType == 'vendor'
              ? Colors.purple.shade50 : Colors.blue.shade50,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: entityType == 'vendor'
                ? Colors.purple.shade200 : Colors.blue.shade200,
          ),
        ),
        child: Text(
          entityType.toUpperCase(),
          style: TextStyle(
            color: entityType == 'vendor' ? Colors.purple : Colors.blue,
            fontWeight: FontWeight.w700,
            fontSize: 11,
          ),
        ),
      ),
    ]);
  }

  Widget _section(String title, List<Widget> children) {
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

  Widget _row(List<Widget> children) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children.map((c) => Expanded(child: Padding(
        padding: EdgeInsets.only(right: c == children.last ? 0 : 8),
        child: c,
      ))).toList(),
    );
  }

  Widget _field(String label, TextEditingController ctrl, {
    TextInputType keyboard = TextInputType.text,
    bool required = false,
    bool obscure = false,
  }) {
    if (!_isEditing) {
      return _readOnlyField(label, ctrl.text);
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: ctrl,
        keyboardType: keyboard,
        obscureText: obscure,
        decoration: InputDecoration(labelText: label, isDense: true),
        validator: required
            ? (v) => (v == null || v.trim().isEmpty) ? '$label is required' : null
            : null,
      ),
    );
  }

  Widget _readOnlyField(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 2),
        Text(
          (value == null || value.isEmpty) ? '—' : value,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
        ),
      ]),
    );
  }

  Widget _companiesSection() {
    final companies = _profile!['companies'] as List;
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
          const Text('Linked Companies',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 12),
          ...companies.map((c) {
            final co = c as Map<String, dynamic>;
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.business, color: Colors.blue.shade700, size: 20),
              ),
              title: Text(co['company_name'] ?? '—',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(co['tax_exemption_type'] ?? '',
                  style: const TextStyle(fontSize: 12)),
              dense: true,
            );
          }),
        ]),
      ),
    );
  }

  Widget _passwordSection() {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.orange.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Text('Change Password',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const Spacer(),
            Switch(
              value: _showPasswordSection,
              onChanged: (v) => setState(() => _showPasswordSection = v),
            ),
          ]),
          if (_showPasswordSection) ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: _currentPwCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                  labelText: 'Current Password', isDense: true),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _newPwCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                  labelText: 'New Password (min 8 chars)', isDense: true),
            ),
          ],
        ]),
      ),
    );
  }

  @override
  void dispose() {
    for (final c in [
      _nameCtrl, _legalNameCtrl, _phoneCtrl, _landlineCtrl,
      _addressCtrl, _cityCtrl, _stateCtrl, _countryCtrl, _zipCtrl,
      _bankNameCtrl, _bankAcctCtrl, _ibanCtrl, _swiftCtrl,
      _currentPwCtrl, _newPwCtrl,
    ]) c.dispose();
    super.dispose();
  }
}
