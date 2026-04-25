import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'theme/npups_theme.dart';
import 'models/user_model.dart';
import 'services/auth_service.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/timesheet_screen.dart';
import 'screens/worker_list_screen.dart';
import 'screens/export_screen.dart';
import 'screens/worker_timesheet_screen.dart';
import 'screens/worker_detail_screen.dart';
import 'screens/coordinator_review_screen.dart';
import 'screens/hr_review_screen.dart';
import 'screens/accounts_review_screen.dart';
import 'screens/ps_dashboard_screen.dart';
import 'screens/timesheet_upload_screen.dart';
import 'screens/worker_registration_form.dart';
import 'screens/ministers_department_screen.dart';
import 'screens/audit_log_screen.dart';
import 'screens/roster_screen.dart';
import 'screens/employee_import_screen.dart';
import 'screens/hr_management_screen.dart';

// ──────────────────────────────────────────────────────────────────────────────
// NUPS — National Upkeep Programme System
// Worker Registration & Payroll Management Platform
//
// Developed by Laurence Peter · Built with AI support
// Tech: Flutter (Mobile + Web) · Supabase (Dockerized)
// Version: 1.0.0 — March 2026
// ──────────────────────────────────────────────────────────────────────────────

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

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

class _NpupsAppState extends State<NpupsApp> with WidgetsBindingObserver {
  final AuthService _authService = AuthService();
  final ThemeModeNotifier _themeMode = ThemeModeNotifier();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _authService.checkSessionExpiry();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: _themeMode,
      builder: (context, themeMode, _) {
        return MaterialApp(
          title: 'NPUPS Digital System',
          debugShowCheckedModeBanner: false,
          theme: NpupsTheme.lightTheme,
          darkTheme: NpupsTheme.darkTheme,
          themeMode: themeMode,
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
                        key: ValueKey(
                            'authenticated-${_authService.currentUser!.role}'),
                        authService: _authService,
                        themeMode: _themeMode,
                      )
                    : LoginScreen(
                        key: const ValueKey('login'),
                        authService: _authService,
                        onLoginSuccess: () {},
                      ),
              );
            },
          ),
        );
      },
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Authenticated Shell — Role-based navigation with dark mode toggle
// ──────────────────────────────────────────────────────────────────────────────

class _AuthenticatedShell extends StatefulWidget {
  final AuthService authService;
  final ThemeModeNotifier themeMode;

  const _AuthenticatedShell(
      {super.key, required this.authService, required this.themeMode});

  @override
  State<_AuthenticatedShell> createState() => _AuthenticatedShellState();
}

class _AuthenticatedShellState extends State<_AuthenticatedShell> {
  int _currentIndex = 0;
  List<_TabConfig>? _cachedTabs;
  UserRole? _cachedRole;

  NpupsUser get _user => widget.authService.currentUser!;

  void _onTabChanged(int index) {
    if (index != _currentIndex) {
      widget.authService.touchSession();
      setState(() => _currentIndex = index);
    }
  }

  Future<void> _handleLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
            style: ElevatedButton.styleFrom(
                backgroundColor: NpupsColors.error),
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
    final tabs = _getCachedTabs();
    if (_currentIndex >= tabs.length) {
      _currentIndex = 0;
    }
    return tabs[_currentIndex].builder();
  }

  List<_TabConfig> _getCachedTabs() {
    if (_cachedTabs == null || _cachedRole != _user.role) {
      _cachedRole = _user.role;
      _cachedTabs = _getTabsForRole();
    }
    return _cachedTabs!;
  }

  List<_TabConfig> _getTabsForRole() {
    return switch (_user.role) {
      UserRole.worker => [
          _TabConfig('Timesheet', Icons.edit_calendar_outlined,
              Icons.edit_calendar,
              () => WorkerTimesheetScreen(
                  key: const ValueKey('worker-ts'), user: _user)),
          _TabConfig('My Documents', Icons.folder_outlined, Icons.folder,
              () => WorkerDetailScreen(
                    key: const ValueKey('worker-docs'),
                    workerId: _user.fullName == 'Kevin Rampersad'
                        ? 'WRK-001'
                        : _user.id,
                  )),
        ],
      UserRole.regionalCoordinator => [
          _TabConfig('Dashboard', Icons.dashboard_outlined, Icons.dashboard,
              () => DashboardScreen(
                    key: const ValueKey('dashboard'),
                    authService: widget.authService,
                    onLogout: _handleLogout,
                    onNavigateToTimesheet: () => _onTabChanged(2),
                    onNavigateToWorkers: () => _onTabChanged(5),
                    onNavigateToExport: () => _onTabChanged(5),
                  )),
          _TabConfig('Roster', Icons.calendar_month_outlined,
              Icons.calendar_month,
              () => RosterScreen(
                  key: const ValueKey('roster'), currentUser: _user)),
          _TabConfig('Timesheet', Icons.edit_calendar_outlined,
              Icons.edit_calendar,
              () => const TimesheetEntryScreen(key: ValueKey('timesheet'))),
          _TabConfig('Review', Icons.rate_review_outlined, Icons.rate_review,
              () => CoordinatorReviewScreen(
                  key: const ValueKey('coord-review'), user: _user)),
          _TabConfig('Upload', Icons.upload_file_outlined, Icons.upload_file,
              () => const TimesheetUploadScreen(key: ValueKey('upload'))),
          _TabConfig('Workers', Icons.people_outlined, Icons.people,
              () => WorkerListScreen(
                  key: const ValueKey('workers'), currentUser: _user)),
        ],
      UserRole.hr => [
          _TabConfig('Dashboard', Icons.dashboard_outlined, Icons.dashboard,
              () => DashboardScreen(
                    key: const ValueKey('dashboard'),
                    authService: widget.authService,
                    onLogout: _handleLogout,
                    onNavigateToTimesheet: () => _onTabChanged(2),
                    onNavigateToWorkers: () => _onTabChanged(3),
                    onNavigateToExport: () => _onTabChanged(3),
                  )),
          _TabConfig('HR Review', Icons.badge_outlined, Icons.badge,
              () => HrReviewScreen(
                  key: const ValueKey('hr-review'), user: _user)),
          _TabConfig('HR Mgmt', Icons.manage_accounts_outlined,
              Icons.manage_accounts,
              () => HrManagementScreen(
                  key: const ValueKey('hr-mgmt'), currentUser: _user)),
          _TabConfig('Workers', Icons.people_outlined, Icons.people,
              () => WorkerListScreen(
                  key: const ValueKey('workers'), currentUser: _user)),
          _TabConfig('Audit Log', Icons.history_edu_outlined,
              Icons.history_edu,
              () => AuditLogScreen(
                  key: const ValueKey('audit'), currentUser: _user)),
        ],
      UserRole.subAccounts || UserRole.mainAccounts => [
          _TabConfig('Dashboard', Icons.dashboard_outlined, Icons.dashboard,
              () => DashboardScreen(
                    key: const ValueKey('dashboard'),
                    authService: widget.authService,
                    onLogout: _handleLogout,
                    onNavigateToTimesheet: () => _onTabChanged(1),
                    onNavigateToWorkers: () => _onTabChanged(1),
                    onNavigateToExport: () => _onTabChanged(3),
                  )),
          _TabConfig(
              'Accounts',
              Icons.account_balance_outlined,
              Icons.account_balance,
              () => AccountsReviewScreen(
                  key: const ValueKey('accounts-review'), user: _user)),
          _TabConfig('Upload', Icons.upload_file_outlined, Icons.upload_file,
              () => const TimesheetUploadScreen(key: ValueKey('upload'))),
          _TabConfig('Export', Icons.download_outlined, Icons.download,
              () => const ExportScreen(key: ValueKey('export'))),
        ],
      UserRole.ps => [
          _TabConfig('Pipeline', Icons.dashboard_outlined, Icons.dashboard,
              () => PsDashboardScreen(
                  key: const ValueKey('ps-dashboard'), user: _user)),
          _TabConfig('Workers', Icons.people_outlined, Icons.people,
              () => WorkerListScreen(
                  key: const ValueKey('workers'), currentUser: _user)),
          _TabConfig('Export', Icons.download_outlined, Icons.download,
              () => const ExportScreen(key: ValueKey('export'))),
          _TabConfig('Audit Log', Icons.history_edu_outlined,
              Icons.history_edu,
              () => AuditLogScreen(
                  key: const ValueKey('audit'), currentUser: _user)),
        ],
      UserRole.ministersDepartment => [
          _TabConfig('Workers', Icons.people_outlined, Icons.people,
              () => MinistersDepartmentScreen(
                  key: const ValueKey('ministers-workers'), user: _user)),
          _TabConfig('Registry', Icons.person_search_outlined,
              Icons.person_search,
              () => WorkerListScreen(
                  key: const ValueKey('workers-list'), currentUser: _user)),
        ],
      UserRole.systemAdmin || UserRole.dmcr => [
          _TabConfig('Dashboard', Icons.dashboard_outlined, Icons.dashboard,
              () => DashboardScreen(
                    key: const ValueKey('dashboard'),
                    authService: widget.authService,
                    onLogout: _handleLogout,
                    onNavigateToTimesheet: () => _onTabChanged(2),
                    onNavigateToWorkers: () => _onTabChanged(4),
                    onNavigateToExport: () => _onTabChanged(5),
                  )),
          _TabConfig('Roster', Icons.calendar_month_outlined,
              Icons.calendar_month,
              () => RosterScreen(
                  key: const ValueKey('roster'), currentUser: _user)),
          _TabConfig('Timesheet', Icons.edit_calendar_outlined,
              Icons.edit_calendar,
              () => const TimesheetEntryScreen(key: ValueKey('timesheet'))),
          _TabConfig('HR Mgmt', Icons.manage_accounts_outlined,
              Icons.manage_accounts,
              () => HrManagementScreen(
                  key: const ValueKey('hr-mgmt'), currentUser: _user)),
          _TabConfig('Workers', Icons.people_outlined, Icons.people,
              () => WorkerListScreen(
                  key: const ValueKey('workers'), currentUser: _user)),
          _TabConfig('Import', Icons.upload_outlined, Icons.upload,
              () => EmployeeImportScreen(
                  key: const ValueKey('import'), currentUser: _user)),
          _TabConfig('Audit Log', Icons.history_edu_outlined,
              Icons.history_edu,
              () => AuditLogScreen(
                  key: const ValueKey('audit'), currentUser: _user)),
          _TabConfig('Export', Icons.download_outlined, Icons.download,
              () => const ExportScreen(key: ValueKey('export'))),
        ],
    };
  }

  @override
  Widget build(BuildContext context) {
    final tabs = _getCachedTabs();
    if (_currentIndex >= tabs.length) {
      _currentIndex = 0;
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 400),
        switchInCurve: Curves.easeOutCubic,
        transitionBuilder: (child, animation) {
          return FadeTransition(opacity: animation, child: child);
        },
        child: _buildPage(),
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildRoleSwitcher(isDark),
          NavigationBar(
            selectedIndex: _currentIndex.clamp(0, tabs.length - 1),
            onDestinationSelected: _onTabChanged,
            backgroundColor:
                isDark ? NpupsColors.darkCard : Colors.white,
            elevation: 8,
            shadowColor: Colors.black38,
            indicatorColor: isDark
                ? NpupsColors.darkAccent.withValues(alpha: 0.2)
                : NpupsColors.accent.withValues(alpha: 0.12),
            labelBehavior:
                NavigationDestinationLabelBehavior.alwaysShow,
            animationDuration: const Duration(milliseconds: 400),
            destinations: tabs
                .map((tab) => NavigationDestination(
                      icon: Icon(tab.icon),
                      selectedIcon: Icon(
                        tab.selectedIcon,
                        color: isDark
                            ? NpupsColors.darkAccentLight
                            : NpupsColors.accent,
                      ),
                      label: tab.label,
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildRoleSwitcher(bool isDark) {
    return Container(
      color: NpupsColors.primaryDark,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          const Icon(Icons.swap_horiz, color: Colors.white60, size: 16),
          const SizedBox(width: 6),
          const Text('DEMO:',
              style: TextStyle(
                  color: Colors.white60,
                  fontSize: 11,
                  fontWeight: FontWeight.bold)),
          const SizedBox(width: 6),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _roleChip(UserRole.worker, 'Worker'),
                  _roleChip(UserRole.regionalCoordinator, 'Coordinator'),
                  _roleChip(UserRole.hr, 'HR'),
                  _roleChip(UserRole.subAccounts, 'Accounts'),
                  _roleChip(UserRole.ps, 'Perm. Sec.'),
                  _roleChip(UserRole.ministersDepartment, 'Minister'),
                  _roleChip(UserRole.systemAdmin, 'Admin'),
                ],
              ),
            ),
          ),
          // Dark mode toggle
          ValueListenableBuilder<ThemeMode>(
            valueListenable: widget.themeMode,
            builder: (_, mode, __) => IconButton(
              icon: Icon(
                mode == ThemeMode.dark
                    ? Icons.light_mode_outlined
                    : Icons.dark_mode_outlined,
                color: Colors.white70,
                size: 18,
              ),
              onPressed: widget.themeMode.toggle,
              tooltip: mode == ThemeMode.dark ? 'Light Mode' : 'Dark Mode',
              padding: EdgeInsets.zero,
              constraints:
                  const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white60, size: 18),
            onPressed: _handleLogout,
            tooltip: 'Sign Out',
            padding: EdgeInsets.zero,
            constraints:
                const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }

  Widget _roleChip(UserRole role, String label) {
    final isActive = _user.role == role;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: InkWell(
        onTap: () {
          widget.authService.switchRole(role);
          setState(() => _currentIndex = 0);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isActive
                ? NpupsColors.accent
                : Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: isActive ? null : Border.all(color: Colors.white24),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isActive ? Colors.white : Colors.white70,
              fontSize: 11,
              fontWeight:
                  isActive ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}

class _TabConfig {
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget Function() builder;

  _TabConfig(this.label, this.icon, this.selectedIcon, this.builder);
}
