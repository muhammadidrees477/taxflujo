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
                _section(
                  'Personal Information',
                  Icons.person_outline,
                  [
                    _field('Display Name', _nameCtrl, required: true),
                    _field('Legal Name', _legalNameCtrl),
                    _field('Mobile Number', _phoneCtrl,
                        keyboard: TextInputType.phone),
                    _field('Landline', _landlineCtrl,
                        keyboard: TextInputType.phone),
                  ],
                ),

                const SizedBox(height: 14),

                _section(
                  'Address',
                  Icons.location_on_outlined,
                  [
                    _field('Street Address', _addressCtrl),

                    _row([
                      _field('City', _cityCtrl),
                      _field('State', _stateCtrl),
                    ]),

                    _row([
                      _field(
                        'ZIP Code',
                        _zipCtrl,
                        keyboard: TextInputType.number,
                      ),
                      _field('Country', _countryCtrl),
                    ]),
                  ],
                ),

                const SizedBox(height: 14),

                _section(
                  'Tax & Identity',
                  Icons.badge_outlined,
                  [
                    _readOnlyField('EIN', _profile?['ein']),
                    _readOnlyField('Email', _profile?['email']),
                    _readOnlyField(
                      'Entity Type',
                      (_profile?['entity_type'] ?? '')
                          .toString()
                          .toUpperCase(),
                    ),
                    _readOnlyField(
                      'Service Type',
                      _profile?['service_type'],
                    ),
                    _readOnlyField(
                      'Balance',
                      '\$${_profile?['balance'] ?? '0.00'}',
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                _section(
                  'Banking Information',
                  Icons.account_balance_outlined,
                  [
                    _field('Bank Name', _bankNameCtrl),

                    _field(
                      'Account Number',
                      _bankAcctCtrl,
                      keyboard: TextInputType.number,
                      obscure: !_isEditing,
                    ),

                    _field('IBAN', _ibanCtrl),
                    _field('SWIFT / BIC', _swiftCtrl),
                  ],
                ),
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

                const SizedBox(height: 50),


                _logoutButton(),

                const SizedBox(height: 100),

              ]),
            ),

    );
  }

  // Widget _avatarSection() {
  //   final name       = _profile?['name'] ?? '';
  //   final entityType = (_profile?['entity_type'] ?? 'contractor').toString();
  //   final initials   = name.isNotEmpty
  //       ? name.split(' ').take(2).map((e) => e[0].toUpperCase()).join()
  //       : '?';
  //
  //   return Column(children: [
  //     Container(
  //       width: 80,
  //       height: 80,
  //       decoration: BoxDecoration(
  //         color: Theme.of(context).colorScheme.primaryContainer,
  //         shape: BoxShape.circle,
  //       ),
  //       child: Center(
  //         child: Text(initials,
  //             style: TextStyle(
  //                 fontSize: 28,
  //                 fontWeight: FontWeight.bold,
  //                 color: Theme.of(context).colorScheme.primary)),
  //       ),
  //     ),
  //     const SizedBox(height: 10),
  //     Text(name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
  //     Text(_profile?['email'] ?? '',
  //         style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
  //     const SizedBox(height: 6),
  //     Container(
  //       padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
  //       decoration: BoxDecoration(
  //         color: entityType == 'vendor'
  //             ? Colors.purple.shade50 : Colors.blue.shade50,
  //         borderRadius: BorderRadius.circular(20),
  //         border: Border.all(
  //           color: entityType == 'vendor'
  //               ? Colors.purple.shade200 : Colors.blue.shade200,
  //         ),
  //       ),
  //       child: Text(
  //         entityType.toUpperCase(),
  //         style: TextStyle(
  //           color: entityType == 'vendor' ? Colors.purple : Colors.blue,
  //           fontWeight: FontWeight.w700,
  //           fontSize: 11,
  //         ),
  //       ),
  //     ),
  //   ]);
  // }
  Widget _avatarSection() {
    final name = _profile?['name'] ?? '';
    final email = _profile?['email'] ?? '';
    final entityType =
    (_profile?['entity_type'] ?? 'contractor')
        .toString()
        .toUpperCase();

    final initials = name.isNotEmpty
        ? name
        .split(' ')
        .take(2)
        .map((e) => e[0].toUpperCase())
        .join()
        : '?';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xff2563EB),
            Color(0xff3B82F6),
          ],
        ),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withOpacity(.2),
            blurRadius: 25,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 45,
            backgroundColor: Colors.white,
            child: Text(
              initials,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Color(0xff2563EB),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            email,
            style: const TextStyle(
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(50),
            ),
            child: Text(
              entityType,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Color(0xff2563EB),
              ),
            ),
          )
        ],
      ),
    );
  }
  Widget _statsCards() {
    return Row(
      children: [
        Expanded(
          child: _statCard(
            Icons.account_balance_wallet,
            "Balance",
            "\$${_profile?['balance'] ?? '0'}",
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _statCard(
            Icons.business,
            "Companies",
            "${(_profile?['companies'] ?? []).length}",
          ),
        ),
      ],
    );
  }
  Widget _statCard(
      IconData icon,
      String title,
      String value,
      ) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.05),
            blurRadius: 20,
          )
        ],
      ),
      child: Column(
        children: [
          Icon(
            icon,
            size: 30,
            color: const Color(0xff2563EB),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(title),
        ],
      ),
    );
  }
  // _section level 1
  // Widget _section(String title, List<Widget> children) {
  //   return Card(
  //     elevation: 0,
  //     color: Colors.white,
  //     shape: RoundedRectangleBorder(
  //       borderRadius: BorderRadius.circular(14),
  //       side: BorderSide(color: Colors.grey.shade200),
  //     ),
  //     child: Padding(
  //       padding: const EdgeInsets.all(16),
  //       child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
  //         Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
  //         const SizedBox(height: 12),
  //         ...children,
  //       ]),
  //     ),
  //   );
  // }

  // section level 2

  // Widget _section(
  //     String title,
  //     IconData icon,
  //     List<Widget> children,
  //     ) {
  //   return Container(
  //     margin: const EdgeInsets.only(bottom: 18),
  //     decoration: BoxDecoration(
  //       color: Colors.white,
  //       borderRadius: BorderRadius.circular(28),
  //       boxShadow: [
  //         BoxShadow(
  //           color: Colors.black.withOpacity(0.04),
  //           blurRadius: 25,
  //           offset: const Offset(0, 12),
  //         ),
  //       ],
  //     ),
  //     child: Padding(
  //       padding: const EdgeInsets.all(22),
  //       child: Column(
  //         crossAxisAlignment: CrossAxisAlignment.start,
  //         children: [
  //
  //           Row(
  //             children: [
  //
  //               Container(
  //                 height: 45,
  //                 width: 45,
  //                 decoration: BoxDecoration(
  //                   color: const Color(0xff2563EB)
  //                       .withOpacity(.10),
  //                   borderRadius:
  //                   BorderRadius.circular(14),
  //                 ),
  //                 child: Icon(
  //                   icon,
  //                   color: const Color(0xff2563EB),
  //                 ),
  //               ),
  //
  //               const SizedBox(width: 12),
  //
  //               Expanded(
  //                 child: Text(
  //                   title,
  //                   style: const TextStyle(
  //                     fontSize: 18,
  //                     fontWeight: FontWeight.w700,
  //                   ),
  //                 ),
  //               ),
  //             ],
  //           ),
  //
  //           const SizedBox(height: 18),
  //
  //           Divider(
  //             color: Colors.grey.shade200,
  //             thickness: 1,
  //           ),
  //
  //           const SizedBox(height: 18),
  //
  //           ...children,
  //         ],
  //       ),
  //     ),
  //   );
  // }

  // section level 3
  Widget _section(
      String title,
      IconData icon,
      List<Widget> children,
      ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.04),
            blurRadius: 30,
            offset: const Offset(0, 15),
          ),
        ],
      ),
      child: Column(
        children: [

          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xff2563EB),
                  Color(0xff3B82F6),
                ],
              ),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(28),
                topRight: Radius.circular(28),
              ),
            ),
            child: Row(
              children: [

                Container(
                  padding:
                  const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white
                        .withOpacity(.15),
                    borderRadius:
                    BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    color: Colors.white,
                  ),
                ),

                const SizedBox(width: 12),

                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight:
                      FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: children,
            ),
          ),
        ],
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
        // decoration: InputDecoration(labelText: label, isDense: true),
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: Colors.grey.shade100,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(
              color: Color(0xff2563EB),
              width: 2,
            ),
          ),
        ),
        validator: required
            ? (v) => (v == null || v.trim().isEmpty) ? '$label is required' : null
            : null,
      ),
    );
  }

  // readonlyfield level 1

  // Widget _readOnlyField(String label, String? value) {
  //   return Padding(
  //     padding: const EdgeInsets.only(bottom: 12),
  //     child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
  //       Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
  //       const SizedBox(height: 2),
  //       Text(
  //         (value == null || value.isEmpty) ? '—' : value,
  //         style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
  //       ),
  //     ]),
  //   );
  // }
  // readonlyfield level 2

  // Widget _readOnlyField(
  //     String label,
  //     String? value,
  //     ) {
  //   return Container(
  //     margin: const EdgeInsets.only(bottom: 12),
  //     child: Row(
  //       crossAxisAlignment:
  //       CrossAxisAlignment.start,
  //       children: [
  //
  //         Container(
  //           width: 42,
  //           height: 42,
  //           decoration: BoxDecoration(
  //             color: const Color(0xff2563EB)
  //                 .withOpacity(.08),
  //             borderRadius:
  //             BorderRadius.circular(12),
  //           ),
  //           child: const Icon(
  //             Icons.info_outline,
  //             color: Color(0xff2563EB),
  //             size: 20,
  //           ),
  //         ),
  //
  //         const SizedBox(width: 12),
  //
  //         Expanded(
  //           child: Container(
  //             padding: const EdgeInsets.all(14),
  //             decoration: BoxDecoration(
  //               color: Colors.grey.shade50,
  //               borderRadius:
  //               BorderRadius.circular(16),
  //             ),
  //             child: Column(
  //               crossAxisAlignment:
  //               CrossAxisAlignment.start,
  //               children: [
  //
  //                 Text(
  //                   label,
  //                   style: TextStyle(
  //                     fontSize: 12,
  //                     color:
  //                     Colors.grey.shade600,
  //                     fontWeight:
  //                     FontWeight.w500,
  //                   ),
  //                 ),
  //
  //                 const SizedBox(height: 5),
  //
  //                 Text(
  //                   value == null ||
  //                       value.isEmpty
  //                       ? "-"
  //                       : value,
  //                   style: const TextStyle(
  //                     fontSize: 15,
  //                     fontWeight:
  //                     FontWeight.w700,
  //                   ),
  //                 ),
  //               ],
  //             ),
  //           ),
  //         ),
  //       ],
  //     ),
  //   );
  // }

  // readonlyfield level 3
  Widget _readOnlyField(
      String label,
      String? value, {
        IconData icon = Icons.info_outline,
      }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xffF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xffE2E8F0),
        ),
      ),
      child: Row(
        children: [

          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xff2563EB)
                  .withOpacity(.08),
              borderRadius:
              BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: const Color(0xff2563EB),
              size: 20,
            ),
          ),

          const SizedBox(width: 14),

          Expanded(
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [

                Text(
                  label,
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),

                const SizedBox(height: 4),

                Text(
                  value == null ||
                      value.isEmpty
                      ? "Not Available"
                      : value,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight:
                    FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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
  Widget _logoutButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () async {
          final confirm = await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: const Text("Logout"),
              content: const Text(
                "Are you sure you want to logout?",
              ),
              actions: [
                TextButton(
                  onPressed: () =>
                      Navigator.pop(context, false),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: () =>
                      Navigator.pop(context, true),
                  child: const Text("Logout"),
                ),
              ],
            ),
          );

          if (confirm != true) return;

          await ApiService.logout();

          if (!mounted) return;

          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
              builder: (_) => const LoginScreen(),
            ),
                (route) => false,
          );
        },
        icon: const Icon(Icons.logout_rounded),
        label: const Text(
          "Logout",
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.red.shade600,
          foregroundColor: Colors.white,
          minimumSize: const Size(
            double.infinity,
            58,
          ),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius:
            BorderRadius.circular(18),
          ),
        ),
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
