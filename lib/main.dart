import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'theme/app_theme.dart';
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
import 'screens/executive_department_screen.dart';
import 'screens/audit_log_screen.dart';
import 'screens/roster_screen.dart';
import 'screens/employee_import_screen.dart';
import 'screens/hr_management_screen.dart';
import 'screens/payroll_breakdown_screen.dart';
import 'screens/backpay_screen.dart';

// ──────────────────────────────────────────────────────────────────────────────
// WorkForce — Digital HR & Payroll System
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
      systemNavigationBarColor: AppColors.primary,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const WorkForceApp());
}

class WorkForceApp extends StatefulWidget {
  const WorkForceApp({super.key});

  @override
  State<WorkForceApp> createState() => _WorkForceAppState();
}

class _WorkForceAppState extends State<WorkForceApp> with WidgetsBindingObserver {
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
          title: 'WorkForce',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
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

  AppUser get _user => widget.authService.currentUser!;

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
            Icon(Icons.logout, color: AppColors.error, size: 24),
            SizedBox(width: 10),
            Text('Sign Out'),
          ],
        ),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error),
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
                  key: const ValueKey('roster'), currentUser: _user),
              category: _TabCategory.operations),
          _TabConfig('Timesheet', Icons.edit_calendar_outlined,
              Icons.edit_calendar,
              () => const TimesheetEntryScreen(key: ValueKey('timesheet')),
              category: _TabCategory.operations),
          _TabConfig('Review', Icons.rate_review_outlined, Icons.rate_review,
              () => CoordinatorReviewScreen(
                  key: const ValueKey('coord-review'), user: _user),
              category: _TabCategory.operations),
          _TabConfig('Upload', Icons.upload_file_outlined, Icons.upload_file,
              () => const TimesheetUploadScreen(key: ValueKey('upload')),
              category: _TabCategory.operations),
          _TabConfig('Workers', Icons.people_outlined, Icons.people,
              () => WorkerListScreen(
                  key: const ValueKey('workers'), currentUser: _user),
              category: _TabCategory.people),
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
                  key: const ValueKey('hr-review'), user: _user),
              category: _TabCategory.people),
          _TabConfig('HR Mgmt', Icons.manage_accounts_outlined,
              Icons.manage_accounts,
              () => HrManagementScreen(
                  key: const ValueKey('hr-mgmt'), currentUser: _user),
              category: _TabCategory.people),
          _TabConfig('Workers', Icons.people_outlined, Icons.people,
              () => WorkerListScreen(
                  key: const ValueKey('workers'), currentUser: _user),
              category: _TabCategory.people),
          _TabConfig('Payroll', Icons.payments_outlined, Icons.payments,
              () => PayrollBreakdownScreen(
                  key: const ValueKey('payroll-breakdown'),
                  currentUser: _user),
              category: _TabCategory.payroll),
          _TabConfig('Backpay', Icons.history_edu_outlined,
              Icons.history_edu,
              () => BackpayScreen(
                  key: const ValueKey('backpay'), currentUser: _user),
              category: _TabCategory.payroll),
          _TabConfig('Audit Log', Icons.fact_check_outlined,
              Icons.fact_check,
              () => AuditLogScreen(
                  key: const ValueKey('audit'), currentUser: _user),
              category: _TabCategory.compliance),
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
                  key: const ValueKey('accounts-review'), user: _user),
              category: _TabCategory.payroll),
          _TabConfig('Payroll', Icons.payments_outlined, Icons.payments,
              () => PayrollBreakdownScreen(
                  key: const ValueKey('payroll-breakdown'),
                  currentUser: _user),
              category: _TabCategory.payroll),
          _TabConfig('Upload', Icons.upload_file_outlined, Icons.upload_file,
              () => const TimesheetUploadScreen(key: ValueKey('upload')),
              category: _TabCategory.operations),
          _TabConfig('Export', Icons.download_outlined, Icons.download,
              () => const ExportScreen(key: ValueKey('export')),
              category: _TabCategory.reports),
        ],
      UserRole.ps => [
          _TabConfig('Pipeline', Icons.dashboard_outlined, Icons.dashboard,
              () => PsDashboardScreen(
                  key: const ValueKey('ps-dashboard'), user: _user)),
          _TabConfig('Workers', Icons.people_outlined, Icons.people,
              () => WorkerListScreen(
                  key: const ValueKey('workers'), currentUser: _user),
              category: _TabCategory.people),
          _TabConfig('Payroll', Icons.payments_outlined, Icons.payments,
              () => PayrollBreakdownScreen(
                  key: const ValueKey('payroll-breakdown'),
                  currentUser: _user),
              category: _TabCategory.payroll),
          _TabConfig('Export', Icons.download_outlined, Icons.download,
              () => const ExportScreen(key: ValueKey('export')),
              category: _TabCategory.reports),
          _TabConfig('Audit Log', Icons.history_edu_outlined,
              Icons.history_edu,
              () => AuditLogScreen(
                  key: const ValueKey('audit'), currentUser: _user),
              category: _TabCategory.compliance),
        ],
      UserRole.ministersDepartment => [
          _TabConfig('Workers', Icons.people_outlined, Icons.people,
              () => ExecutiveDepartmentScreen(
                  key: const ValueKey('executive-workers'), user: _user)),
          _TabConfig('Registry', Icons.person_search_outlined,
              Icons.person_search,
              () => WorkerListScreen(
                  key: const ValueKey('workers-list'), currentUser: _user),
              category: _TabCategory.people),
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
                  key: const ValueKey('roster'), currentUser: _user),
              category: _TabCategory.operations),
          _TabConfig('Timesheet', Icons.edit_calendar_outlined,
              Icons.edit_calendar,
              () => const TimesheetEntryScreen(key: ValueKey('timesheet')),
              category: _TabCategory.operations),
          _TabConfig('HR Mgmt', Icons.manage_accounts_outlined,
              Icons.manage_accounts,
              () => HrManagementScreen(
                  key: const ValueKey('hr-mgmt'), currentUser: _user),
              category: _TabCategory.people),
          _TabConfig('Workers', Icons.people_outlined, Icons.people,
              () => WorkerListScreen(
                  key: const ValueKey('workers'), currentUser: _user),
              category: _TabCategory.people),
          _TabConfig('Import', Icons.upload_outlined, Icons.upload,
              () => EmployeeImportScreen(
                  key: const ValueKey('import'), currentUser: _user),
              category: _TabCategory.people),
          _TabConfig('Payroll', Icons.payments_outlined, Icons.payments,
              () => PayrollBreakdownScreen(
                  key: const ValueKey('payroll-breakdown'),
                  currentUser: _user),
              category: _TabCategory.payroll),
          _TabConfig('Backpay', Icons.history_edu_outlined,
              Icons.history_edu,
              () => BackpayScreen(
                  key: const ValueKey('backpay'), currentUser: _user),
              category: _TabCategory.payroll),
          _TabConfig('Audit Log', Icons.fact_check_outlined,
              Icons.fact_check,
              () => AuditLogScreen(
                  key: const ValueKey('audit'), currentUser: _user),
              category: _TabCategory.compliance),
          _TabConfig('Export', Icons.download_outlined, Icons.download,
              () => const ExportScreen(key: ValueKey('export')),
              category: _TabCategory.reports),
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
          _AdaptiveBottomNav(
            tabs: tabs,
            selectedIndex: _currentIndex.clamp(0, tabs.length - 1),
            onSelect: _onTabChanged,
            isDark: isDark,
          ),
        ],
      ),
    );
  }

  Widget _buildRoleSwitcher(bool isDark) {
    return Container(
      color: AppColors.primaryDark,
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
                  _roleChip(UserRole.ministersDepartment, 'Executive'),
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
                ? AppColors.accent
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

enum _TabCategory {
  primary('Main'),
  operations('Operations'),
  people('People'),
  payroll('Payroll'),
  compliance('Compliance'),
  reports('Reports');

  const _TabCategory(this.label);
  final String label;
}

class _TabConfig {
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget Function() builder;
  final _TabCategory category;

  _TabConfig(this.label, this.icon, this.selectedIcon, this.builder,
      {this.category = _TabCategory.primary});
}

// ──────────────────────────────────────────────────────────────────────────────
// Adaptive bottom navigation
//
// Wide screens (≥600px) → standard NavigationBar with all tabs.
// Mobile / narrow → first 4 primary tabs are pinned, the remainder collapse
// into a "More" overflow that opens a category-grouped bottom sheet.
// ──────────────────────────────────────────────────────────────────────────────

class _AdaptiveBottomNav extends StatelessWidget {
  final List<_TabConfig> tabs;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final bool isDark;

  static const double _wideBreakpoint = 600;
  static const int _mobilePrimarySlots = 4;

  const _AdaptiveBottomNav({
    required this.tabs,
    required this.selectedIndex,
    required this.onSelect,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= _wideBreakpoint;

    // Wide screens or short tab lists fit fine.
    if (isWide || tabs.length <= _mobilePrimarySlots + 1) {
      return _buildStandardBar(context, tabs, selectedIndex);
    }

    // Mobile with overflow.
    final primary = tabs.take(_mobilePrimarySlots - 1).toList();
    final overflow = tabs.skip(_mobilePrimarySlots - 1).toList();
    final selectedInOverflow = selectedIndex >= primary.length;

    final visible = <_TabConfig>[
      ...primary,
      _TabConfig(
        'More',
        Icons.menu_outlined,
        Icons.menu,
        () => const SizedBox.shrink(),
      ),
    ];

    final visibleSelected = selectedInOverflow
        ? primary.length // highlight "More"
        : selectedIndex;

    return NavigationBar(
      selectedIndex: visibleSelected.clamp(0, visible.length - 1),
      backgroundColor: isDark ? AppColors.darkCard : Colors.white,
      elevation: 8,
      shadowColor: Colors.black38,
      indicatorColor: isDark
          ? AppColors.darkAccent.withValues(alpha: 0.2)
          : AppColors.accent.withValues(alpha: 0.12),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      animationDuration: const Duration(milliseconds: 400),
      onDestinationSelected: (i) {
        if (i == primary.length) {
          _showMoreSheet(context, overflow, primary.length);
        } else {
          onSelect(i);
        }
      },
      destinations: visible.map((t) {
        return NavigationDestination(
          icon: Icon(t.icon),
          selectedIcon: Icon(
            t.selectedIcon,
            color:
                isDark ? AppColors.darkAccentLight : AppColors.accent,
          ),
          label: t.label,
        );
      }).toList(),
    );
  }

  Widget _buildStandardBar(
      BuildContext context, List<_TabConfig> visible, int selected) {
    return NavigationBar(
      selectedIndex: selected.clamp(0, visible.length - 1),
      onDestinationSelected: onSelect,
      backgroundColor: isDark ? AppColors.darkCard : Colors.white,
      elevation: 8,
      shadowColor: Colors.black38,
      indicatorColor: isDark
          ? AppColors.darkAccent.withValues(alpha: 0.2)
          : AppColors.accent.withValues(alpha: 0.12),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      animationDuration: const Duration(milliseconds: 400),
      destinations: visible.map((tab) {
        return NavigationDestination(
          icon: Icon(tab.icon),
          selectedIcon: Icon(
            tab.selectedIcon,
            color:
                isDark ? AppColors.darkAccentLight : AppColors.accent,
          ),
          label: tab.label,
        );
      }).toList(),
    );
  }

  void _showMoreSheet(
      BuildContext context, List<_TabConfig> overflow, int firstOverflowIndex) {
    // Group by category for browsable navigation.
    final byCategory = <_TabCategory, List<_TabConfigEntry>>{};
    for (var i = 0; i < overflow.length; i++) {
      final t = overflow[i];
      byCategory
          .putIfAbsent(t.category, () => [])
          .add(_TabConfigEntry(t, firstOverflowIndex + i));
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppColors.darkCard : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColors.darkBorder
                            : AppColors.border,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'More',
                    style: Theme.of(sheetCtx).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Browse the rest of your tools by category.',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark
                          ? AppColors.darkTextSecondary
                          : AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...byCategory.entries.map((entry) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding:
                              const EdgeInsets.only(top: 8, bottom: 6),
                          child: Text(
                            entry.key.label.toUpperCase(),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.0,
                              color: isDark
                                  ? AppColors.darkTextHint
                                  : AppColors.textHint,
                            ),
                          ),
                        ),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: entry.value.map((e) {
                            final selected =
                                e.absoluteIndex == selectedIndex;
                            return InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () {
                                Navigator.of(sheetCtx).pop();
                                onSelect(e.absoluteIndex);
                              },
                              child: Container(
                                padding:
                                    const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: selected
                                      ? AppColors.accent
                                          .withValues(alpha: 0.12)
                                      : (isDark
                                          ? AppColors.darkInputFill
                                          : AppColors.inputFill),
                                  borderRadius:
                                      BorderRadius.circular(12),
                                  border: selected
                                      ? Border.all(
                                          color: AppColors.accent,
                                          width: 1)
                                      : null,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      selected
                                          ? e.tab.selectedIcon
                                          : e.tab.icon,
                                      size: 18,
                                      color: selected
                                          ? AppColors.accent
                                          : (isDark
                                              ? AppColors
                                                  .darkTextSecondary
                                              : AppColors
                                                  .textSecondary),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      e.tab.label,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: selected
                                            ? FontWeight.w600
                                            : FontWeight.w500,
                                        color: selected
                                            ? AppColors.accent
                                            : (isDark
                                                ? AppColors
                                                    .darkTextPrimary
                                                : AppColors
                                                    .textPrimary),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    );
                  }),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TabConfigEntry {
  final _TabConfig tab;
  final int absoluteIndex;
  _TabConfigEntry(this.tab, this.absoluteIndex);
}
