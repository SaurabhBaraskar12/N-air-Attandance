import 'package:flutter/material.dart';
import '../api_service.dart';
import '../theme_controller.dart';
import '../widgets.dart';
import 'login_screen.dart';
import 'home_tab.dart';
import 'attend_screen.dart';
import 'leave_screen.dart';
import 'profile_screen.dart';
import 'notifications_screen.dart';

/// Log out and return to the login screen. Shared by the drawer and Profile.
Future<void> performLogout(BuildContext context) async {
  await ApiService.instance.logout();
  if (!context.mounted) return;
  Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const LoginScreen()),
    (_) => false,
  );
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  void _goToTab(int i) => setState(() => _index = i);

  static const _titles = ['NHS HRMS', 'Mark Attendance', 'Apply for Leave', 'Profile'];

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeTab(onGoToTab: _goToTab),
      const AttendScreen(),
      const LeaveScreen(),
      const ProfileScreen(),
    ];

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 8,
        title: _index == 0 ? _branding(context) : Text(_titles[_index]),
        actions: [
          IconButton(
            tooltip: 'Toggle dark mode',
            icon: Icon(ThemeController.instance.isDark(context)
                ? Icons.light_mode_outlined
                : Icons.dark_mode_outlined),
            onPressed: () => ThemeController.instance.toggle(context),
          ),
          IconButton(
            tooltip: 'Notifications',
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const NotificationsScreen())),
          ),
          const SizedBox(width: 4),
        ],
      ),
      drawer: _drawer(context),
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _goToTab,
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Home'),
          NavigationDestination(
              icon: Icon(Icons.fingerprint),
              selectedIcon: Icon(Icons.fingerprint),
              label: 'Attend'),
          NavigationDestination(
              icon: Icon(Icons.event_note_outlined),
              selectedIcon: Icon(Icons.event_note),
              label: 'Leave'),
          NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'Profile'),
        ],
      ),
    );
  }

  Widget _branding(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: kPrimaryBlue.withOpacity(0.14),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.fingerprint, color: kPrimaryBlue, size: 20),
        ),
        const SizedBox(width: 10),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('NHS HRMS',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            Text('N.Air HVAC Solutions',
                style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      ],
    );
  }

  Widget _drawer(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            DrawerHeader(
              margin: EdgeInsets.zero,
              decoration: const BoxDecoration(color: kPrimaryBlue),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Icon(Icons.fingerprint, color: Colors.white, size: 36),
                  SizedBox(height: 8),
                  Text('NHS HRMS',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold)),
                  Text('N.Air HVAC Solutions',
                      style: TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.home_outlined),
              title: const Text('Home'),
              onTap: () {
                Navigator.pop(context);
                _goToTab(0);
              },
            ),
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('Profile'),
              onTap: () {
                Navigator.pop(context);
                _goToTab(3);
              },
            ),
            const Spacer(),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('Logout',
                  style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                performLogout(context);
              },
            ),
          ],
        ),
      ),
    );
  }
}
