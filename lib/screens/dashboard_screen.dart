import 'package:flutter/material.dart';
import '../theme/npups_theme.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';

// ──────────────────────────────────────────────────────────────────────────────
// NPUPS Role-Based Dashboard
// Implements §5.2 Dashboard (Role-Specific) and §7 Wireframe (P0)
//
// Each role sees different KPI cards and pending actions per the process map.
// Admin sees all data; test users see their corporation-scoped view.
// ──────────────────────────────────────────────────────────────────────────────

class DashboardScreen extends StatefulWidget {
  final AuthService authService;
  final VoidCallback onLogout;
  final VoidCallback onNavigateToTimesheet;

  const DashboardScreen({
    super.key,
    required this.authService,
    required this.onLogout,
    required this.onNavigateToTimesheet,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entranceController;
  late final List<Animation<double>> _cardAnimations;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    // Stagger 6 card animations
    _cardAnimations = List.generate(6, (i) {
      final start = 0.08 * i;
      final end = (start + 0.4).clamp(0.0, 1.0);
      return CurvedAnimation(
        parent: _entranceController,
        curve: Interval(start, end, curve: Curves.easeOutCubic),
      );
    });

    _entranceController.forward();
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  NpupsUser get _user => widget.authService.currentUser!;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NpupsColors.surface,
      body: CustomScrollView(
        slivers: [
          _buildAppBar(),
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _buildWelcomeCard(),
                const SizedBox(height: 20),
                _buildKpiGrid(),
                const SizedBox(height: 20),
                _buildQuickActions(),
                const SizedBox(height: 20),
                _buildRecentActivity(),
                const SizedBox(height: 32),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  // ── App Bar ────────────────────────────────────────────────────────────────
  Widget _buildAppBar() {
    return SliverAppBar(
      expandedHeight: 120,
      pinned: true,
      backgroundColor: NpupsColors.primary,
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.only(left: 16, bottom: 14),
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'NPUPS',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: 2,
              ),
            ),
            Text(
              _user.role.displayName,
              style: TextStyle(
                fontSize: 10,
                color: Colors.white.withOpacity(0.7),
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        background: Container(
          decoration: const BoxDecoration(gradient: NpupsColors.primaryGradient),
          child: Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Opacity(
                opacity: 0.08,
                child: Icon(Icons.account_balance, size: 100, color: Colors.white),
              ),
            ),
          ),
        ),
      ),
      actions: [
        // Notification bell (§5.7)
        IconButton(
          icon: Badge(
            smallSize: 8,
            backgroundColor: NpupsColors.trinidadRed,
            child: const Icon(Icons.notifications_outlined, color: Colors.white),
          ),
          onPressed: () => _showSnack('Notification centre coming soon.'),
        ),
        // User avatar & logout
        PopupMenuButton(
          offset: const Offset(0, 50),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: CircleAvatar(
              radius: 16,
              backgroundColor: NpupsColors.accent,
              child: Text(
                _user.initials,
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          itemBuilder: (ctx) => [
            PopupMenuItem(
              enabled: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_user.fullName, style: const TextStyle(fontWeight: FontWeight.w600, color: NpupsColors.textPrimary)),
                  Text(_user.email, style: const TextStyle(fontSize: 12, color: NpupsColors.textSecondary)),
                  if (_user.corporationName != null) ...[
                    const SizedBox(height: 4),
                    Text(_user.corporationName!, style: const TextStyle(fontSize: 11, color: NpupsColors.accent)),
                  ],
                ],
              ),
            ),
            const PopupMenuDivider(),
            PopupMenuItem(
              onTap: widget.onLogout,
              child: const Row(
                children: [
                  Icon(Icons.logout, size: 18, color: NpupsColors.error),
                  SizedBox(width: 8),
                  Text('Sign Out', style: TextStyle(color: NpupsColors.error)),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Welcome Card ───────────────────────────────────────────────────────────
  Widget _buildWelcomeCard() {
    return _animatedCard(
      0,
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [NpupsColors.accent, NpupsColors.accent.withOpacity(0.8)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: NpupsColors.accent.withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Welcome, ${_user.fullName.split(' ').first}',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _getRoleGreeting(),
                    style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.85)),
                  ),
                ],
              ),
            ),
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.dashboard_outlined, color: Colors.white, size: 28),
            ),
          ],
        ),
      ),
    );
  }

  String _getRoleGreeting() {
    return switch (_user.role) {
      UserRole.systemAdmin => 'Full system overview across all 14 Corporations.',
      UserRole.regionalCoordinator => 'Manage timesheets and worker attendance.',
      UserRole.hr => 'Process payroll packages and employment notes.',
      UserRole.ps => 'Review and approve pending items.',
      UserRole.dmcr => 'Coordinate worker data across Corporations.',
      UserRole.subAccounts => 'Process pay sheets and vouchers.',
      UserRole.mainAccounts => 'Authorise payments and manage cheques.',
    };
  }

  // ── KPI Grid ───────────────────────────────────────────────────────────────
  Widget _buildKpiGrid() {
    final kpis = _getKpisForRole();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Overview',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: NpupsColors.textPrimary),
        ),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.6,
          children: kpis.asMap().entries.map((entry) {
            return _animatedCard(
              (entry.key + 1).clamp(0, 5),
              _buildKpiCard(entry.value),
            );
          }).toList(),
        ),
      ],
    );
  }

  List<_KpiData> _getKpisForRole() {
    return switch (_user.role) {
      UserRole.systemAdmin => [
        _KpiData('Active Workers', '2,847', Icons.people, NpupsColors.accent, '+12%'),
        _KpiData('Corporations', '14', Icons.location_city, NpupsColors.success, 'Active'),
        _KpiData('Pending Approvals', '23', Icons.pending_actions, NpupsColors.warning, 'Action'),
        _KpiData('This Fortnight', '\$1.2M', Icons.payments, NpupsColors.trinidadRed, 'Payroll'),
      ],
      UserRole.regionalCoordinator => [
        _KpiData('My Workers', '48', Icons.people, NpupsColors.accent, 'Assigned'),
        _KpiData('Timesheets Due', '3', Icons.timer, NpupsColors.warning, 'Pending'),
        _KpiData('Docs Complete', '92%', Icons.check_circle, NpupsColors.success, 'Progress'),
        _KpiData('This Fortnight', '\$72K', Icons.payments, NpupsColors.trinidadRed, 'Payroll'),
      ],
      UserRole.hr => [
        _KpiData('Payroll Queue', '8', Icons.receipt_long, NpupsColors.accent, 'Pending'),
        _KpiData('Employment Notes', '5', Icons.description, NpupsColors.warning, 'PS Review'),
        _KpiData('Workers Onboarded', '156', Icons.person_add, NpupsColors.success, 'This Cycle'),
        _KpiData('Packages Sent', '12', Icons.send, NpupsColors.trinidadRed, 'To Accounts'),
      ],
      _ => [
        _KpiData('Active Workers', '2,847', Icons.people, NpupsColors.accent, '+12%'),
        _KpiData('Pending Items', '15', Icons.pending_actions, NpupsColors.warning, 'Action'),
        _KpiData('Completed', '89%', Icons.check_circle, NpupsColors.success, 'Progress'),
        _KpiData('This Fortnight', '\$1.2M', Icons.payments, NpupsColors.trinidadRed, 'Payroll'),
      ],
    };
  }

  Widget _buildKpiCard(_KpiData kpi) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: kpi.color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(kpi.icon, size: 18, color: kpi.color),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: kpi.color.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  kpi.badge,
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: kpi.color),
                ),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                kpi.value,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: NpupsColors.textPrimary),
              ),
              Text(
                kpi.label,
                style: const TextStyle(fontSize: 11, color: NpupsColors.textSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Quick Actions ──────────────────────────────────────────────────────────
  Widget _buildQuickActions() {
    return _animatedCard(
      3,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Quick Actions',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: NpupsColors.textPrimary),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _getActionsForRole().map((action) {
              return _buildActionChip(action);
            }).toList(),
          ),
        ],
      ),
    );
  }

  List<_ActionData> _getActionsForRole() {
    final common = [
      _ActionData('View Workers', Icons.people_outline, () => _showSnack('Worker list coming soon.')),
      _ActionData('Reports', Icons.bar_chart, () => _showSnack('Reports module coming soon.')),
    ];

    return switch (_user.role) {
      UserRole.systemAdmin => [
        _ActionData('Manage Users', Icons.admin_panel_settings, () => _showSnack('User management coming soon.')),
        _ActionData('Enter Timesheet', Icons.edit_calendar, widget.onNavigateToTimesheet),
        ...common,
      ],
      UserRole.regionalCoordinator => [
        _ActionData('Enter Timesheet', Icons.edit_calendar, widget.onNavigateToTimesheet),
        _ActionData('Upload Documents', Icons.upload_file, () => _showSnack('Document upload coming soon.')),
        ...common,
      ],
      UserRole.hr => [
        _ActionData('Payroll Packages', Icons.receipt_long, () => _showSnack('Payroll builder coming soon.')),
        _ActionData('Employment Notes', Icons.description, () => _showSnack('Employment notes coming soon.')),
        ...common,
      ],
      _ => [
        _ActionData('Enter Timesheet', Icons.edit_calendar, widget.onNavigateToTimesheet),
        ...common,
      ],
    };
  }

  Widget _buildActionChip(_ActionData action) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      elevation: 1,
      child: InkWell(
        onTap: action.onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(action.icon, size: 18, color: NpupsColors.accent),
              const SizedBox(width: 8),
              Text(
                action.label,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: NpupsColors.textPrimary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Recent Activity ────────────────────────────────────────────────────────
  Widget _buildRecentActivity() {
    return _animatedCard(
      4,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Recent Activity',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: NpupsColors.textPrimary),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2)),
              ],
            ),
            child: Column(
              children: [
                _buildActivityItem(
                  'Timesheet submitted for Port of Spain — Group 3',
                  '2 hours ago',
                  Icons.check_circle,
                  NpupsColors.success,
                ),
                const Divider(height: 1, indent: 56),
                _buildActivityItem(
                  'Payroll package approved by PS',
                  '5 hours ago',
                  Icons.thumb_up,
                  NpupsColors.accent,
                ),
                const Divider(height: 1, indent: 56),
                _buildActivityItem(
                  '3 worker documents pending verification',
                  'Yesterday',
                  Icons.warning_amber,
                  NpupsColors.warning,
                ),
                const Divider(height: 1, indent: 56),
                _buildActivityItem(
                  'New workers registered: Kevin Rampersad, Sasha Mohammed',
                  'Yesterday',
                  Icons.person_add,
                  NpupsColors.info,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivityItem(String text, String time, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text, style: const TextStyle(fontSize: 13, color: NpupsColors.textPrimary)),
                const SizedBox(height: 2),
                Text(time, style: const TextStyle(fontSize: 11, color: NpupsColors.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  Widget _animatedCard(int index, Widget child) {
    final safeIndex = index.clamp(0, _cardAnimations.length - 1);
    return AnimatedBuilder(
      animation: _cardAnimations[safeIndex],
      builder: (context, _) {
        final value = _cardAnimations[safeIndex].value;
        return Transform.translate(
          offset: Offset(0, 30 * (1 - value)),
          child: Opacity(opacity: value, child: child),
        );
      },
    );
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: NpupsColors.info,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

// ── Data classes ─────────────────────────────────────────────────────────────

class _KpiData {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String badge;

  _KpiData(this.label, this.value, this.icon, this.color, this.badge);
}

class _ActionData {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  _ActionData(this.label, this.icon, this.onTap);
}
