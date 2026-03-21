import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'theme/npups_theme.dart';
import 'services/auth_service.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/timesheet_screen.dart';
import 'screens/worker_list_screen.dart';
import 'screens/export_screen.dart';

// ──────────────────────────────────────────────────────────────────────────────
// NPUPS Digital System — Entry Point
// National Programme for the Upkeep of Public Spaces
// Ministry of Rural Development & Local Government
// Republic of Trinidad and Tobago
//
// Tech: Flutter (Mobile + Web) · Supabase (Dockerized)
// Version: 1.0.0 — March 2026
// ──────────────────────────────────────────────────────────────────────────────

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock orientation for mobile devices
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // Status bar styling to match NPUPS branding
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: NpupsColors.primary,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const NpupsApp());
}

class NpupsApp extends StatefulWidget {
  const NpupsApp({super.key});

  @override
  State<NpupsApp> createState() => _NpupsAppState();
}

class _NpupsAppState extends State<NpupsApp> {
  final AuthService _authService = AuthService();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NPUPS Digital System',
      debugShowCheckedModeBanner: false,
      theme: NpupsTheme.lightTheme,
      home: ListenableBuilder(
        listenable: _authService,
        builder: (context, _) {
          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 600),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.05),
                    end: Offset.zero,
                  ).animate(CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                  )),
                  child: child,
                ),
              );
            },
            child: _authService.isAuthenticated
                ? _AuthenticatedShell(
                    key: const ValueKey('authenticated'),
                    authService: _authService,
                  )
                : LoginScreen(
                    key: const ValueKey('login'),
                    authService: _authService,
                    onLoginSuccess: () {
                      // AnimatedSwitcher handles the transition via ListenableBuilder
                    },
                  ),
          );
        },
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Authenticated Shell — Bottom navigation with 4 tabs
// ──────────────────────────────────────────────────────────────────────────────

class _AuthenticatedShell extends StatefulWidget {
  final AuthService authService;

  const _AuthenticatedShell({super.key, required this.authService});

  @override
  State<_AuthenticatedShell> createState() => _AuthenticatedShellState();
}

class _AuthenticatedShellState extends State<_AuthenticatedShell>
    with SingleTickerProviderStateMixin {
  int _currentIndex = 0;
  late final AnimationController _pageTransition;

  @override
  void initState() {
    super.initState();
    _pageTransition = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
  }

  @override
  void dispose() {
    _pageTransition.dispose();
    super.dispose();
  }

  void _onTabChanged(int index) {
    if (index != _currentIndex) {
      setState(() => _currentIndex = index);
    }
  }

  Future<void> _handleLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.logout, color: NpupsColors.error, size: 24),
            SizedBox(width: 10),
            Text('Sign Out'),
          ],
        ),
        content: const Text('Are you sure you want to sign out of NPUPS?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: NpupsColors.error),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await widget.authService.signOut();
    }
  }

  Widget _buildPage() {
    return switch (_currentIndex) {
      0 => DashboardScreen(
          key: const ValueKey('dashboard'),
          authService: widget.authService,
          onLogout: _handleLogout,
          onNavigateToTimesheet: () => _onTabChanged(1),
          onNavigateToWorkers: () => _onTabChanged(2),
          onNavigateToExport: () => _onTabChanged(3),
        ),
      1 => const TimesheetEntryScreen(key: ValueKey('timesheet')),
      2 => const WorkerListScreen(key: ValueKey('workers')),
      3 => const ExportScreen(key: ValueKey('export')),
      _ => const SizedBox(),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 400),
        switchInCurve: Curves.easeOutCubic,
        transitionBuilder: (child, animation) {
          return FadeTransition(opacity: animation, child: child);
        },
        child: _buildPage(),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: _onTabChanged,
        backgroundColor: Colors.white,
        elevation: 8,
        shadowColor: Colors.black26,
        indicatorColor: NpupsColors.accent.withValues(alpha: 0.12),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        animationDuration: const Duration(milliseconds: 400),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard, color: NpupsColors.accent),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.edit_calendar_outlined),
            selectedIcon: Icon(Icons.edit_calendar, color: NpupsColors.accent),
            label: 'Timesheet',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outlined),
            selectedIcon: Icon(Icons.people, color: NpupsColors.accent),
            label: 'Workers',
          ),
          NavigationDestination(
            icon: Icon(Icons.download_outlined),
            selectedIcon: Icon(Icons.download, color: NpupsColors.accent),
            label: 'Export',
          ),
        ],
      ),
    );
  }
}
