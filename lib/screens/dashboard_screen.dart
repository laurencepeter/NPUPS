import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../models/audit_model.dart';
import '../models/timesheet_model.dart';
import '../models/user_model.dart';
import '../models/worker_model.dart';
import '../services/api_client.dart';
import '../services/audit_service.dart';
import '../services/auth_service.dart';
import '../services/backpay_service.dart';
import '../services/timesheet_data_store.dart';
import '../services/worker_data_store.dart';
import '../widgets/backend_status_banner.dart';

// ──────────────────────────────────────────────────────────────────────────────
// WorkForce
// Dashboard Screen
//
// Every KPI on this screen is computed from live data store contents — the
// previous build hardcoded the headline numbers (the infamous "2,847 active
// workers") which made the dashboard look populated even when the database
// was empty or unreachable. KPIs now reflect what is actually in the
// database for the signed-in user's scope.
//
// Recent Activity is sourced from the AuditService chain, so every demo
// action (registrations, stage advances, payments, backpay, etc.) appears
// without anyone having to seed the dashboard fixture by hand.
// ──────────────────────────────────────────────────────────────────────────────

class DashboardScreen extends StatefulWidget {
  final AuthService authService;
  final VoidCallback onLogout;
  final VoidCallback onNavigateToTimesheet;
  final VoidCallback onNavigateToWorkers;
  final VoidCallback onNavigateToExport;

  const DashboardScreen({
    super.key,
    required this.authService,
    required this.onLogout,
    required this.onNavigateToTimesheet,
    required this.onNavigateToWorkers,
    required this.onNavigateToExport,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entranceController;
  late final List<Animation<double>> _cardAnimations;

  final WorkerDataStore _workerStore = WorkerDataStore();
  final TimesheetDataStore _timesheetStore = TimesheetDataStore();
  final AuditService _auditService = AuditService();
  final BackpayService _backpayService = BackpayService();

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

    // Re-render when any source store changes so KPIs / activity stay live
    // as workers are added, timesheets advance, audit entries are appended.
    _workerStore.addListener(_onStoreChanged);
    _timesheetStore.addListener(_onStoreChanged);
    _auditService.addListener(_onStoreChanged);
    _backpayService.addListener(_onStoreChanged);
  }

  @override
  void dispose() {
    _workerStore.removeListener(_onStoreChanged);
    _timesheetStore.removeListener(_onStoreChanged);
    _auditService.removeListener(_onStoreChanged);
    _backpayService.removeListener(_onStoreChanged);
    _entranceController.dispose();
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  AppUser get _user => widget.authService.currentUser!;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: CustomScrollView(
        slivers: [
          _buildAppBar(),
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                const BackendStatusBanner(),
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
      backgroundColor: AppColors.primary,
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.only(left: 16, bottom: 14),
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'WorkForce',
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
                color: Colors.white.withValues(alpha: 0.7),
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        background: Container(
          decoration: const BoxDecoration(gradient: AppColors.primaryGradient),
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
        // Notification bell
        IconButton(
          icon: Badge(
            smallSize: 8,
            backgroundColor: AppColors.brandRed,
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
              backgroundColor: AppColors.accent,
              child: Text(
                _user.initials,
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          itemBuilder: (ctx) => <PopupMenuEntry<dynamic>>[
            PopupMenuItem(
              enabled: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_user.fullName, style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  Text(_user.email, style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  if (_user.corporationName != null) ...[
                    const SizedBox(height: 4),
                    Text(_user.corporationName!, style: const TextStyle(fontSize: 11, color: AppColors.accent)),
                  ],
                ],
              ),
            ),
            const PopupMenuDivider(),
            PopupMenuItem(
              onTap: widget.onLogout,
              child: const Row(
                children: [
                  Icon(Icons.logout, size: 18, color: AppColors.error),
                  SizedBox(width: 8),
                  Text('Sign Out', style: TextStyle(color: AppColors.error)),
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
            colors: [AppColors.accent, AppColors.accent.withValues(alpha: 0.8)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppColors.accent.withValues(alpha: 0.3),
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
                    style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.85)),
                  ),
                ],
              ),
            ),
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
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
      UserRole.ministersDepartment => 'Oversee worker registry and manage corporation exports.',
      UserRole.worker => 'Submit your timesheet and track progress.',
    };
  }

  // ── KPI Grid ───────────────────────────────────────────────────────────────
  Widget _buildKpiGrid() {
    final kpis = _getKpisForRole();
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth > 600;
        final crossAxisCount = isDesktop ? 4 : 2;
        final aspectRatio = isDesktop ? 2.0 : 1.6;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Overview',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: crossAxisCount,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: isDesktop ? 10 : 12,
              mainAxisSpacing: isDesktop ? 10 : 12,
              childAspectRatio: aspectRatio,
              children: kpis.asMap().entries.map((entry) {
                return _animatedCard(
                  (entry.key + 1).clamp(0, 5),
                  _buildKpiCard(entry.value, compact: isDesktop),
                );
              }).toList(),
            ),
          ],
        );
      },
    );
  }

  // Workers visible to this user — admins and head-office roles see all,
  // corporation-scoped roles only see their own.
  Iterable<Worker> get _scopedWorkers {
    if (_user.corporationId == null) return _workerStore.workers;
    return _workerStore.getByCorpId(_user.corporationId!);
  }

  Iterable<Timesheet> get _scopedTimesheets {
    if (_user.corporationId == null) return _timesheetStore.timesheets;
    return _timesheetStore.getByCorporation(_user.corporationId!);
  }

  static final NumberFormat _intFmt = NumberFormat.decimalPattern();
  static final NumberFormat _moneyFmt =
      NumberFormat.compactSimpleCurrency(decimalDigits: 1);

  List<_KpiData> _getKpisForRole() {
    final allWorkers = _workerStore.workers;
    final scopedWorkers = _scopedWorkers.toList();
    final scopedActive = scopedWorkers.where((w) => w.isActive).length;
    final scopedTimesheets = _scopedTimesheets.toList();
    final fortnightPayroll = scopedTimesheets.fold<double>(
        0, (sum, t) => sum + t.grandTotal);
    final corporations =
        allWorkers.map((w) => w.corporationId).toSet().length;

    int countByStages(List<TimesheetStage> stages) =>
        scopedTimesheets.where((t) => stages.contains(t.stage)).length;

    return switch (_user.role) {
      UserRole.systemAdmin => [
        _KpiData('Active Workers', _intFmt.format(scopedActive),
            Icons.people, AppColors.accent, 'Live'),
        _KpiData('Corporations', '$corporations',
            Icons.location_city, AppColors.success, 'Seeded'),
        _KpiData(
          'Pending Approvals',
          '${countByStages([
            TimesheetStage.submitted,
            TimesheetStage.coordinatorReview,
            TimesheetStage.hrProcessing,
            TimesheetStage.accountsProcessing,
          ])}',
          Icons.pending_actions,
          AppColors.warning,
          'Action',
        ),
        _KpiData('This Fortnight', _moneyFmt.format(fortnightPayroll),
            Icons.payments, AppColors.brandRed, 'Payroll'),
      ],
      UserRole.regionalCoordinator => [
        _KpiData('My Workers', '$scopedActive', Icons.people,
            AppColors.accent, 'Assigned'),
        _KpiData(
          'Timesheets Due',
          '${countByStages([TimesheetStage.submitted, TimesheetStage.coordinatorReview])}',
          Icons.timer,
          AppColors.warning,
          'Pending',
        ),
        _KpiData('Docs Complete', _docsCompletePct(scopedWorkers),
            Icons.check_circle, AppColors.success, 'Progress'),
        _KpiData('This Fortnight', _moneyFmt.format(fortnightPayroll),
            Icons.payments, AppColors.brandRed, 'Payroll'),
      ],
      UserRole.hr => [
        _KpiData(
          'Payroll Queue',
          '${countByStages([TimesheetStage.hrProcessing])}',
          Icons.receipt_long,
          AppColors.accent,
          'Pending',
        ),
        _KpiData(
          'Awaiting Sign-off',
          '${countByStages([TimesheetStage.coordinatorReview])}',
          Icons.description,
          AppColors.warning,
          'For HR',
        ),
        _KpiData('Workers Onboarded', '$scopedActive',
            Icons.person_add, AppColors.success, 'Active'),
        _KpiData(
          'Packages Sent',
          '${countByStages([
            TimesheetStage.accountsProcessing,
            TimesheetStage.approvedForPayment,
            TimesheetStage.exported,
            TimesheetStage.chequePrinting,
          ])}',
          Icons.send,
          AppColors.brandRed,
          'To Accounts',
        ),
      ],
      _ => [
        _KpiData('Active Workers', _intFmt.format(scopedActive),
            Icons.people, AppColors.accent, 'Live'),
        _KpiData(
          'Pending Items',
          '${countByStages([
            TimesheetStage.submitted,
            TimesheetStage.coordinatorReview,
            TimesheetStage.hrProcessing,
            TimesheetStage.accountsProcessing,
          ])}',
          Icons.pending_actions,
          AppColors.warning,
          'Action',
        ),
        _KpiData('Docs Complete', _docsCompletePct(scopedWorkers),
            Icons.check_circle, AppColors.success, 'Progress'),
        _KpiData('This Fortnight', _moneyFmt.format(fortnightPayroll),
            Icons.payments, AppColors.brandRed, 'Payroll'),
      ],
    };
  }

  String _docsCompletePct(List<Worker> workers) {
    if (workers.isEmpty) return '—';
    final fully = workers.where((w) => w.isFullyVerified).length;
    final pct = (fully / workers.length * 100).round();
    return '$pct%';
  }

  Widget _buildKpiCard(_KpiData kpi, {bool compact = false}) {
    return Container(
      padding: EdgeInsets.all(compact ? 10 : 16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(compact ? 10 : 14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
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
                padding: EdgeInsets.all(compact ? 5 : 8),
                decoration: BoxDecoration(
                  color: kpi.color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(compact ? 6 : 8),
                ),
                child: Icon(kpi.icon, size: compact ? 14 : 18, color: kpi.color),
              ),
              Container(
                padding: EdgeInsets.symmetric(horizontal: compact ? 4 : 6, vertical: 2),
                decoration: BoxDecoration(
                  color: kpi.color.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  kpi.badge,
                  style: TextStyle(fontSize: compact ? 8 : 9, fontWeight: FontWeight.w600, color: kpi.color),
                ),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                kpi.value,
                style: TextStyle(fontSize: compact ? 16 : 22, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
              ),
              Text(
                kpi.label,
                style: TextStyle(fontSize: compact ? 10 : 11, color: AppColors.textSecondary),
                overflow: TextOverflow.ellipsis,
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
          Text(
            'Quick Actions',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
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
      _ActionData('View Workers', Icons.people_outline, widget.onNavigateToWorkers),
      _ActionData('Export Timesheet', Icons.download, widget.onNavigateToExport),
    ];

    return switch (_user.role) {
      UserRole.systemAdmin => [
        _ActionData('Manage Users', Icons.admin_panel_settings, widget.onNavigateToWorkers),
        _ActionData('Enter Timesheet', Icons.edit_calendar, widget.onNavigateToTimesheet),
        ...common,
      ],
      UserRole.regionalCoordinator => [
        _ActionData('Enter Timesheet', Icons.edit_calendar, widget.onNavigateToTimesheet),
        _ActionData('Upload Documents', Icons.upload_file, widget.onNavigateToWorkers),
        ...common,
      ],
      UserRole.hr => [
        _ActionData('Payroll Packages', Icons.receipt_long, widget.onNavigateToExport),
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
      color: AppColors.card,
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
              Icon(action.icon, size: 18, color: AppColors.accent),
              const SizedBox(width: 8),
              Text(
                action.label,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textPrimary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Recent Activity (real audit feed) ──────────────────────────────────────
  Widget _buildRecentActivity() {
    final entries = _auditService.getAll().take(6).toList();

    return _animatedCard(
      4,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Recent Activity',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
              ),
              const SizedBox(width: 8),
              if (entries.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'live',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: AppColors.accent,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2)),
              ],
            ),
            child: entries.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        Icon(Icons.history,
                            size: 18, color: AppColors.textSecondary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            ApiClient().isConfigured
                                ? 'No audit entries yet — actions taken in the app will appear here.'
                                : 'Backend not configured — set --dart-define=API_BASE_URL to load audit history.',
                            style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary),
                          ),
                        ),
                      ],
                    ),
                  )
                : Column(
                    children: [
                      for (int i = 0; i < entries.length; i++) ...[
                        if (i > 0) const Divider(height: 1, indent: 56),
                        _buildActivityItem(
                          _activityLine(entries[i]),
                          _relativeTime(entries[i].timestamp),
                          _actionIcon(entries[i].action),
                          _actionColor(entries[i].action),
                        ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  String _activityLine(AuditLogEntry e) {
    final who = e.userName;
    final what = e.action.displayName.toLowerCase();
    final target = e.entityDisplayName;
    return '$who $what — $target';
  }

  String _relativeTime(DateTime ts) {
    final diff = DateTime.now().difference(ts);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 30) return '${diff.inDays}d ago';
    return DateFormat.yMMMd().format(ts);
  }

  IconData _actionIcon(AuditAction a) {
    return switch (a) {
      AuditAction.create || AuditAction.activate => Icons.add_circle_outline,
      AuditAction.update || AuditAction.allowanceUpdated ||
          AuditAction.wageRateChanged => Icons.edit_outlined,
      AuditAction.delete || AuditAction.deactivate ||
          AuditAction.allowanceRemoved => Icons.remove_circle_outline,
      AuditAction.documentUpload || AuditAction.attachmentAdded =>
          Icons.upload_file,
      AuditAction.documentApprove || AuditAction.approve ||
          AuditAction.stageAdvanced => Icons.check_circle_outline,
      AuditAction.documentReject || AuditAction.reject ||
          AuditAction.stageRejected => Icons.cancel_outlined,
      AuditAction.login => Icons.login,
      AuditAction.logout => Icons.logout,
      AuditAction.export => Icons.download,
      AuditAction.import => Icons.file_upload,
      AuditAction.rosterUpdate => Icons.event_available,
      AuditAction.replacementAdded => Icons.swap_horiz,
      AuditAction.backpayCalculated || AuditAction.backpayApproved ||
          AuditAction.backpayDisbursed => Icons.account_balance_wallet,
      AuditAction.paymentRecorded => Icons.payments,
      AuditAction.paymentReversed => Icons.undo,
      AuditAction.allowanceAdded => Icons.add_card,
      AuditAction.attachmentRemoved => Icons.attach_file,
      AuditAction.settingsChange => Icons.settings,
      AuditAction.duplicateIdAttempt => Icons.warning_amber,
    };
  }

  Color _actionColor(AuditAction a) {
    return switch (a) {
      AuditAction.create || AuditAction.activate ||
          AuditAction.allowanceAdded => AppColors.success,
      AuditAction.update || AuditAction.allowanceUpdated ||
          AuditAction.wageRateChanged => AppColors.accent,
      AuditAction.delete || AuditAction.deactivate ||
          AuditAction.documentReject || AuditAction.reject ||
          AuditAction.stageRejected || AuditAction.duplicateIdAttempt =>
          AppColors.error,
      AuditAction.documentUpload || AuditAction.documentApprove ||
          AuditAction.approve || AuditAction.stageAdvanced ||
          AuditAction.paymentRecorded => AppColors.success,
      AuditAction.export || AuditAction.import => AppColors.info,
      _ => AppColors.warning,
    };
  }

  Widget _buildActivityItem(String text, String time, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text, style: TextStyle(fontSize: 13, color: AppColors.textPrimary)),
                const SizedBox(height: 2),
                Text(time, style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
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
        backgroundColor: AppColors.info,
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
