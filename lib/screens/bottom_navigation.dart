
import 'package:flutter/material.dart';
import 'package:taxflujo/screens/profile_screen.dart';

import 'dashboard.dart';
import 'invoice_list_screen.dart';

class bottom_navigations extends StatefulWidget {
   bottom_navigations({super.key});

  @override
  State<bottom_navigations> createState() => _bottom_navigationsState();
}

class _bottom_navigationsState extends State<bottom_navigations> {
  int _selectedTab = 0;

  final List<Widget> _screens = [
    const DashboardScreen(),
    const InvoiceListScreen(),
    const ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_selectedTab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTab,
        onDestinationSelected: (index) {
          setState(() {
            _selectedTab = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Invoices',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
