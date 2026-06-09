import 'package:flutter/material.dart';
import 'package:taxflujo/screens/profile_screen.dart';
import '../services/api_service.dart';
import 'invoice_form_screen.dart';
import 'invoice_list_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Map<String, dynamic>? profile;
  List<dynamic> invoices = [];

  bool isLoading = true;

  int totalInvoices = 0;
  int pendingInvoices = 0;
  int approvedInvoices = 0;
  int paidInvoices = 0;
  int    _selectedTab       = 0;
  @override
  void initState() {
    super.initState();
    loadDashboard();
  }

  Future<void> loadDashboard() async {
    try {
      final p = await ApiService.getProfile();
      final inv = await ApiService.getInvoices();

      totalInvoices = inv.length;

      // pendingInvoices =
      //     inv.where((e) => e['status'] == 'pending').length;
      pendingInvoices = inv.where((invoice) {
        final status = invoice['status']
            .toString()
            .toLowerCase()
            .trim();

        return status.contains('pending');
      }).length;
      approvedInvoices =
          inv.where((e) => e['status'] == 'approved').length;
      // paidInvoices =
      //     inv.where((e) => e['status'] == 'paid').length;
      paidInvoices = inv.where((invoice) {
        return invoice['status']
            .toString()
            .toLowerCase()
            .trim() == 'paid';
      }).length;

      setState(() {

        profile = p;
        invoices = inv;
        isLoading = false;
      });
    } catch (e) {
      setState(() => isLoading = false);
    }
  }

  Future<void> refresh() async {
    setState(() => isLoading = true);
    await loadDashboard();
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      backgroundColor: const Color(0xffF4F6FA),

      body: isLoading
          ? const Center(
        child: CircularProgressIndicator(),
      )
          : RefreshIndicator(
        onRefresh: refresh,
        child: SingleChildScrollView(
          physics:
          const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [

              const SizedBox(height: 50),

              /// PROFILE HEADER
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                ),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius:
                    BorderRadius.circular(40),
                  ),
                  child: Row(
                    children: [

                      CircleAvatar(
                        radius: 30,
                        backgroundImage: profile?['profile_image'] != null
                            ? NetworkImage(profile!['profile_image'])
                            : null,
                        child: profile?['profile_image'] == null
                            ? const Icon(Icons.person)
                            : null,
                      ),

                      const SizedBox(width: 10),

                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                          CrossAxisAlignment.start,
                          children: [
                            // Text(
                            //   profile?['display_name'] ??
                            //       'Contractor',
                            //   style: const TextStyle(
                            //     fontWeight:
                            //     FontWeight.bold,
                            //   ),
                            // ),
                            Text(
                              profile?['display_name'] ??
                                  profile?['name'] ??
                                  profile?['full_name'] ??
                                  profile?['legal_name'] ??
                                  'Contractor',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const Text(
                              "Active",
                              style: TextStyle(
                                color: Colors.green,
                              ),
                            )
                          ],
                        ),
                      ),

                      const Icon(
                        Icons.keyboard_arrow_down,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 25),

              /// WELCOME CARD
              _welcomeCard(),

              const SizedBox(height: 20),

              /// STATS
              _statCard(
                title: "Pending Invoices",
                value:
                pendingInvoices.toString(),
                startColor:
                const Color(0xffFB7185),
                endColor:
                const Color(0xffF87171),
                icon: Icons.hourglass_empty,
              ),

              _statCard(
                title: "Total Invoices",
                value:
                totalInvoices.toString(),
                startColor:
                const Color(0xff0EA5E9),
                endColor:
                const Color(0xff22D3EE),
                icon: Icons.description,
              ),

              // _statCard(
              //   title: "Approved Invoices",
              //   value:
              //   approvedInvoices.toString(),
              //   startColor:
              //   const Color(0xff8B5CF6),
              //   endColor:
              //   const Color(0xffC4B5FD),
              //   icon: Icons.check_circle,
              // ),
              _statCard(
                title: "Approved Invoices",
                value: invoices.where((invoice) {
                  final status = invoice['status']
                      .toString()
                      .toLowerCase()
                      .trim();

                  return status == 'approved' ||
                      status == 'approve' ||
                      status == 'accepted';
                }).length.toString(),
                startColor: const Color(0xff8B5CF6),
                endColor: const Color(0xffC4B5FD),
                icon: Icons.check_circle,
              ),
              _statCard(
                title: "Paid Invoices",
                value:
                paidInvoices.toString(),
                startColor:
                const Color(0xff14B8A6),
                endColor:
                const Color(0xff2563EB),
                icon: Icons.receipt_long,
              ),

              const SizedBox(height: 20),

              /// SUBMIT INVOICE
              _actionCard(
                title: "Submit Invoice",
                subtitle:
                "Create and submit new invoices",
                icon: Icons.add,
                buttonText: "Create Now",
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                      const InvoiceFormScreen(),
                    ),
                  );
                },
              ),

              /// UPDATE PROFILE
              _actionCard(
                title: "Update Profile",
                subtitle:
                "Manage your account details",
                icon: Icons.edit,
                buttonText: "Edit Profile",
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ProfileScreen(),
                    ),
                  );
                },              ),

              /// PAYMENT
              _actionCard(
                title: "Payment & Balance",
                subtitle:
                "Track payment status",
                icon: Icons.account_balance_wallet,
                buttonText: "View Balance",
                onTap: () {},
              ),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
      // bottomNavigationBar: NavigationBar(
      //   selectedIndex: _selectedTab,
      //   backgroundColor: Colors.white,
      //   onDestinationSelected: (i) {
      //     if (i == 1) {
      //       Navigator.push(context, MaterialPageRoute(builder: (_) => const  InvoiceListScreen ()));
      //     } else if(i == 2){
      //       Navigator.push(context, MaterialPageRoute(builder: (_) => const  ProfileScreen ()));
      //     }
      //     else {
      //     setState(() => _selectedTab = i);
      //     }
      //   },
      //   destinations: const [
      //     NavigationDestination(icon: Icon(Icons.dashboard_customize_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Dashboard'),
      //     NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Invoices'),
      //     NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
      //   ],
      // ),
    );
  }

  // Widget _welcomeCard() {
  //   return Container(
  //     margin:
  //     const EdgeInsets.symmetric(horizontal: 20),
  //     padding: const EdgeInsets.all(25),
  //     decoration: BoxDecoration(
  //       borderRadius: BorderRadius.circular(24),
  //       gradient: const LinearGradient(
  //         colors: [
  //           Color(0xff4F46E5),
  //           Color(0xff4338CA),
  //         ],
  //       ),
  //     ),
  //     child: Column(
  //       crossAxisAlignment:
  //       CrossAxisAlignment.start,
  //       children: [
  //         Text(
  //           "Welcome, ${profile?['display_name'] ?? ''}",
  //           // "Welcome, $profile?['display_name']",
  //           style: const TextStyle(
  //             color: Colors.white,
  //             fontSize: 30,
  //             fontWeight: FontWeight.bold,
  //           ),
  //         ),
  //         const SizedBox(height: 15),
  //         Text(
  //           "Email: ${profile?['email'] ?? ''}",
  //           style: const TextStyle(
  //             color: Colors.white70,
  //           ),
  //         ),
  //         Text(
  //           "Phone: ${profile?['phone'] ?? ''}",
  //           // "Phone: $profile?[display_phone]",
  //           style: const TextStyle(
  //             color: Colors.white70,
  //           ),
  //         ),
  //       ],
  //     ),
  //   );
  // }
  Widget _welcomeCard() {
    final displayName =
        profile?['display_name'] ??
            profile?['name'] ??
            profile?['full_name'] ??
            'Contractor';

    final email =
        profile?['email'] ?? '';

    final phone =
        profile?['phone'] ??
            profile?['mobile'] ??
            profile?['phone_number'] ??
            '';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [
            Color(0xff4F46E5),
            Color(0xff4338CA),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Welcome, $displayName",
            style: const TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 15),
          Text(
            "Email: $email",
            style: const TextStyle(color: Colors.white70),
          ),
          Text(
            "Phone: $phone",
            style: const TextStyle(color: Colors.white70),
          ),
        ],
      ),
    );
  }
  Widget _statCard({
    required String title,
    required String value,
    required Color startColor,
    required Color endColor,
    required IconData icon,
  }) {
    return Container(
      height: 110,
      margin: const EdgeInsets.symmetric(
        horizontal: 20,
        vertical: 10,
      ),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [startColor, endColor],
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                  ),
                ),
                const Spacer(),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            icon,
            size: 45,
            color: Colors.white30,
          ),
        ],
      ),
    );
  }

  Widget _actionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required String buttonText,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
      ),
      child: Column(
        children: [

          CircleAvatar(
            radius: 35,
            backgroundColor:
            Colors.indigo.withOpacity(.1),
            child: Icon(
              icon,
              color: Colors.indigo,
              size: 35,
            ),
          ),

          const SizedBox(height: 20),

          Text(
            title,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 10),

          Text(
            subtitle,
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 20),

          ElevatedButton(
            onPressed: onTap,
            style: ElevatedButton.styleFrom(
              backgroundColor:
              const Color(0xff4338CA),
              foregroundColor: Colors.white,
            ),
            child: Text(buttonText),
          ),
        ],
      ),
    );
  }
}