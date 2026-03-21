import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/npups_theme.dart';
import '../services/auth_service.dart';

// ──────────────────────────────────────────────────────────────────────────────
// NPUPS Login Screen
// Implements §5.1 Authentication & Onboarding + §7 Wireframe (Login / SSO — P0)
//
// Features:
//   - Staggered entrance animations for polished UX
//   - Animated floating particles background
//   - Smooth field focus transitions
//   - Demo account quick-fill bottom sheet
//   - Password visibility toggle
//   - Error/success feedback with animated snackbars
//   - Government branding per §8.1 colour palette
// ──────────────────────────────────────────────────────────────────────────────

class LoginScreen extends StatefulWidget {
  final AuthService authService;
  final VoidCallback onLoginSuccess;

  const LoginScreen({
    super.key,
    required this.authService,
    required this.onLoginSuccess,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();

  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _errorMessage;

  // ── Animation controllers ──────────────────────────────────────────────────
  late final AnimationController _bgController;
  late final AnimationController _entranceController;
  late final AnimationController _shakeController;
  late final AnimationController _pulseController;

  // Staggered entrance animations
  late final Animation<double> _logoSlide;
  late final Animation<double> _logoFade;
  late final Animation<double> _titleSlide;
  late final Animation<double> _titleFade;
  late final Animation<double> _cardSlide;
  late final Animation<double> _cardFade;
  late final Animation<double> _buttonSlide;
  late final Animation<double> _buttonFade;
  late final Animation<double> _footerFade;

  // Shake animation for error feedback
  late final Animation<double> _shakeAnimation;

  // Pulse for the login button glow
  late final Animation<double> _pulseAnimation;

  // Floating particles data
  late final List<_Particle> _particles;

  @override
  void initState() {
    super.initState();
    _initParticles();
    _initAnimations();
    _entranceController.forward();
  }

  void _initParticles() {
    final rng = math.Random(42);
    _particles = List.generate(20, (i) {
      return _Particle(
        x: rng.nextDouble(),
        y: rng.nextDouble(),
        radius: 1.5 + rng.nextDouble() * 3,
        speed: 0.2 + rng.nextDouble() * 0.6,
        opacity: 0.1 + rng.nextDouble() * 0.2,
        phase: rng.nextDouble() * math.pi * 2,
      );
    });
  }

  void _initAnimations() {
    // Background particle float
    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();

    // Staggered entrance — total 1200ms
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    // Logo: 0–400ms
    _logoSlide = Tween<double>(begin: -40, end: 0).animate(
      CurvedAnimation(parent: _entranceController, curve: const Interval(0.0, 0.35, curve: Curves.easeOutCubic)),
    );
    _logoFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _entranceController, curve: const Interval(0.0, 0.3, curve: Curves.easeOut)),
    );

    // Title: 150–550ms
    _titleSlide = Tween<double>(begin: -30, end: 0).animate(
      CurvedAnimation(parent: _entranceController, curve: const Interval(0.1, 0.4, curve: Curves.easeOutCubic)),
    );
    _titleFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _entranceController, curve: const Interval(0.1, 0.35, curve: Curves.easeOut)),
    );

    // Card: 300–800ms
    _cardSlide = Tween<double>(begin: 50, end: 0).animate(
      CurvedAnimation(parent: _entranceController, curve: const Interval(0.2, 0.65, curve: Curves.easeOutCubic)),
    );
    _cardFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _entranceController, curve: const Interval(0.2, 0.55, curve: Curves.easeOut)),
    );

    // Button: 500–1000ms
    _buttonSlide = Tween<double>(begin: 30, end: 0).animate(
      CurvedAnimation(parent: _entranceController, curve: const Interval(0.4, 0.75, curve: Curves.easeOutCubic)),
    );
    _buttonFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _entranceController, curve: const Interval(0.4, 0.7, curve: Curves.easeOut)),
    );

    // Footer: 700–1200ms
    _footerFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _entranceController, curve: const Interval(0.55, 1.0, curve: Curves.easeOut)),
    );

    // Shake for login errors
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _shakeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.elasticIn),
    );

    // Pulse glow on button
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _bgController.dispose();
    _entranceController.dispose();
    _shakeController.dispose();
    _pulseController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  // ── Login handler ──────────────────────────────────────────────────────────
  Future<void> _handleLogin() async {
    // Clear previous error
    setState(() => _errorMessage = null);

    if (!_formKey.currentState!.validate()) {
      _shakeController.forward(from: 0);
      return;
    }

    setState(() => _isLoading = true);

    final result = await widget.authService.signIn(
      _emailController.text,
      _passwordController.text,
    );

    if (!mounted) return;

    setState(() => _isLoading = false);

    if (result.success) {
      // Success haptic feedback
      HapticFeedback.mediumImpact();
      widget.onLoginSuccess();
    } else {
      // Error shake + message
      HapticFeedback.heavyImpact();
      _shakeController.forward(from: 0);
      setState(() => _errorMessage = result.errorMessage);
    }
  }

  // ── Quick-fill demo account ────────────────────────────────────────────────
  void _fillDemoAccount(DemoAccountInfo account) {
    Navigator.of(context).pop(); // close bottom sheet
    _emailController.text = account.email;
    _passwordController.text = account.password;
    setState(() => _errorMessage = null);
  }

  void _showDemoAccounts() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _DemoAccountsSheet(
        accounts: AuthService.demoAccounts,
        onSelect: _fillDemoAccount,
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isWide = size.width > 600;

    return Scaffold(
      body: AnimatedBuilder(
        animation: Listenable.merge([_bgController, _entranceController]),
        builder: (context, child) {
          return Stack(
            children: [
              // Gradient background
              Container(decoration: const BoxDecoration(gradient: NpupsColors.loginGradient)),

              // Floating particles
              CustomPaint(
                size: size,
                painter: _ParticlePainter(
                  particles: _particles,
                  animationValue: _bgController.value,
                ),
              ),

              // Subtle grid pattern overlay
              Opacity(
                opacity: 0.03,
                child: CustomPaint(
                  size: size,
                  painter: _GridPainter(),
                ),
              ),

              // Main content
              SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.symmetric(
                      horizontal: isWide ? size.width * 0.25 : 24,
                      vertical: 24,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildLogo(),
                          const SizedBox(height: 12),
                          _buildTitle(),
                          const SizedBox(height: 36),
                          _buildLoginCard(),
                          const SizedBox(height: 20),
                          _buildFooter(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ── Logo ────────────────────────────────────────────────────────────────────
  Widget _buildLogo() {
    return Transform.translate(
      offset: Offset(0, _logoSlide.value),
      child: Opacity(
        opacity: _logoFade.value,
        child: Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.1),
            border: Border.all(color: Colors.white.withValues(alpha: 0.2), width: 2),
            boxShadow: [
              BoxShadow(
                color: NpupsColors.accent.withValues(alpha: 0.3),
                blurRadius: 30,
                spreadRadius: 2,
              ),
            ],
          ),
          child: const Center(
            child: Icon(
              Icons.account_balance,
              size: 36,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  // ── Title + subtitle ───────────────────────────────────────────────────────
  Widget _buildTitle() {
    return Transform.translate(
      offset: Offset(0, _titleSlide.value),
      child: Opacity(
        opacity: _titleFade.value,
        child: Column(
          children: [
            const Text(
              'NPUPS',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: 6,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Digital System',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: Colors.white.withValues(alpha: 0.7),
                letterSpacing: 3,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              width: 40,
              height: 2,
              decoration: BoxDecoration(
                color: NpupsColors.accent,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'National Programme for the\nUpkeep of Public Spaces',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: Colors.white.withValues(alpha: 0.5),
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Login card ─────────────────────────────────────────────────────────────
  Widget _buildLoginCard() {
    return AnimatedBuilder(
      animation: _shakeController,
      builder: (context, child) {
        // Shake offset on error
        final shakeOffset = _shakeController.isAnimating
            ? math.sin(_shakeAnimation.value * math.pi * 4) * 8 * (1 - _shakeAnimation.value)
            : 0.0;

        return Transform.translate(
          offset: Offset(shakeOffset, _cardSlide.value),
          child: Opacity(
            opacity: _cardFade.value,
            child: child,
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
            BoxShadow(
              color: NpupsColors.accent.withValues(alpha: 0.08),
              blurRadius: 60,
              offset: const Offset(0, 20),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Card header
                Row(
                  children: [
                    Container(
                      width: 4,
                      height: 24,
                      decoration: BoxDecoration(
                        color: NpupsColors.accent,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'Sign In',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: NpupsColors.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    // Demo accounts button
                    TextButton.icon(
                      onPressed: _showDemoAccounts,
                      icon: Icon(Icons.info_outline, size: 16, color: NpupsColors.accent.withValues(alpha: 0.8)),
                      label: Text(
                        'Demo',
                        style: TextStyle(fontSize: 12, color: NpupsColors.accent.withValues(alpha: 0.8)),
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Access your NPUPS dashboard',
                  style: TextStyle(fontSize: 13, color: NpupsColors.textSecondary.withValues(alpha: 0.8)),
                ),
                const SizedBox(height: 24),

                // Error message
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  transitionBuilder: (child, animation) {
                    return SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, -0.3),
                        end: Offset.zero,
                      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
                      child: FadeTransition(opacity: animation, child: child),
                    );
                  },
                  child: _errorMessage != null
                      ? Container(
                          key: ValueKey(_errorMessage),
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: NpupsColors.error.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: NpupsColors.error.withValues(alpha: 0.2)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline, color: NpupsColors.error, size: 18),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: const TextStyle(fontSize: 13, color: NpupsColors.error),
                                ),
                              ),
                            ],
                          ),
                        )
                      : const SizedBox.shrink(key: ValueKey('empty')),
                ),

                // Email field
                _buildFieldLabel('Email Address'),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _emailController,
                  focusNode: _emailFocus,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email],
                  onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
                  decoration: InputDecoration(
                    hintText: 'you@npups.gov.tt',
                    prefixIcon: const Icon(Icons.email_outlined, size: 20, color: NpupsColors.textHint),
                    fillColor: NpupsColors.inputFill,
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Email is required';
                    if (!v.contains('@')) return 'Enter a valid email address';
                    return null;
                  },
                ),
                const SizedBox(height: 18),

                // Password field
                _buildFieldLabel('Password'),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _passwordController,
                  focusNode: _passwordFocus,
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.password],
                  onFieldSubmitted: (_) => _handleLogin(),
                  decoration: InputDecoration(
                    hintText: 'Enter your password',
                    prefixIcon: const Icon(Icons.lock_outline, size: 20, color: NpupsColors.textHint),
                    suffixIcon: IconButton(
                      icon: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        transitionBuilder: (child, animation) =>
                            ScaleTransition(scale: animation, child: child),
                        child: Icon(
                          _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                          key: ValueKey(_obscurePassword),
                          size: 20,
                          color: NpupsColors.textHint,
                        ),
                      ),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                    fillColor: NpupsColors.inputFill,
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Password is required';
                    return null;
                  },
                ),
                const SizedBox(height: 8),

                // Forgot password
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('Password reset will be available in production.'),
                          backgroundColor: NpupsColors.info,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      );
                    },
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      'Forgot password?',
                      style: TextStyle(
                        fontSize: 12,
                        color: NpupsColors.accent.withValues(alpha: 0.8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Login button with pulse glow
                AnimatedBuilder(
                  animation: _pulseAnimation,
                  builder: (context, child) {
                    return Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: _isLoading
                            ? null
                            : [
                                BoxShadow(
                                  color: NpupsColors.accent.withValues(alpha: 0.15 + _pulseAnimation.value * 0.15),
                                  blurRadius: 12 + _pulseAnimation.value * 8,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                      ),
                      child: child,
                    );
                  },
                  child: SizedBox(
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _handleLogin,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: NpupsColors.accent,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: NpupsColors.accent.withValues(alpha: 0.6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        transitionBuilder: (child, animation) {
                          return FadeTransition(
                            opacity: animation,
                            child: ScaleTransition(scale: animation, child: child),
                          );
                        },
                        child: _isLoading
                            ? const SizedBox(
                                key: ValueKey('loading'),
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.white,
                                ),
                              )
                            : const Row(
                                key: ValueKey('signin'),
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text('Sign In', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                                  SizedBox(width: 8),
                                  Icon(Icons.arrow_forward_rounded, size: 20),
                                ],
                              ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // SSO divider (per §5.1 optional SSO via iGovTT)
                Row(
                  children: [
                    Expanded(child: Divider(color: NpupsColors.border, thickness: 1)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text('or', style: TextStyle(fontSize: 12, color: NpupsColors.textHint)),
                    ),
                    Expanded(child: Divider(color: NpupsColors.border, thickness: 1)),
                  ],
                ),
                const SizedBox(height: 16),

                // SSO button placeholder
                OutlinedButton.icon(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('iGovTT SSO integration coming in production.'),
                        backgroundColor: NpupsColors.info,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    );
                  },
                  icon: const Icon(Icons.security, size: 18),
                  label: const Text('Sign in with iGovTT SSO'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: NpupsColors.textSecondary,
                    side: const BorderSide(color: NpupsColors.border),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFieldLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: NpupsColors.textPrimary,
      ),
    );
  }

  // ── Footer ─────────────────────────────────────────────────────────────────
  Widget _buildFooter() {
    return Transform.translate(
      offset: Offset(0, _buttonSlide.value),
      child: Opacity(
        opacity: _footerFade.value,
        child: Column(
          children: [
            Text(
              'Ministry of Rural Development & Local Government',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: Colors.white.withValues(alpha: 0.4),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Republic of Trinidad and Tobago',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: Colors.white.withValues(alpha: 0.3),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'v1.0.0 — ISO 5807 Compliant',
              style: TextStyle(
                fontSize: 10,
                color: Colors.white.withValues(alpha: 0.2),
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Floating Particle Painter — Animated background decoration
// ──────────────────────────────────────────────────────────────────────────────

class _Particle {
  final double x;
  final double y;
  final double radius;
  final double speed;
  final double opacity;
  final double phase;

  _Particle({
    required this.x,
    required this.y,
    required this.radius,
    required this.speed,
    required this.opacity,
    required this.phase,
  });
}

class _ParticlePainter extends CustomPainter {
  final List<_Particle> particles;
  final double animationValue;

  _ParticlePainter({required this.particles, required this.animationValue});

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final dx = p.x * size.width +
          math.sin(animationValue * math.pi * 2 * p.speed + p.phase) * 30;
      final dy = p.y * size.height +
          math.cos(animationValue * math.pi * 2 * p.speed * 0.7 + p.phase) * 20;

      final paint = Paint()
        ..color = Colors.white.withValues(alpha: p.opacity)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, p.radius * 0.5);

      canvas.drawCircle(Offset(dx, dy), p.radius, paint);
    }
  }

  @override
  bool shouldRepaint(_ParticlePainter oldDelegate) =>
      oldDelegate.animationValue != animationValue;
}

// ──────────────────────────────────────────────────────────────────────────────
// Subtle Grid Pattern Painter
// ──────────────────────────────────────────────────────────────────────────────

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 0.5;

    const spacing = 40.0;

    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ──────────────────────────────────────────────────────────────────────────────
// Demo Accounts Bottom Sheet
// ──────────────────────────────────────────────────────────────────────────────

class _DemoAccountsSheet extends StatelessWidget {
  final List<DemoAccountInfo> accounts;
  final ValueChanged<DemoAccountInfo> onSelect;

  const _DemoAccountsSheet({required this.accounts, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          // Drag handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: NpupsColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                Icon(Icons.people_outline, color: NpupsColors.accent, size: 22),
                SizedBox(width: 10),
                Text(
                  'Demo Accounts',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: NpupsColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'Tap an account to auto-fill credentials',
              style: TextStyle(fontSize: 13, color: NpupsColors.textSecondary),
            ),
          ),
          const SizedBox(height: 16),
          ...accounts.map((account) => _buildAccountTile(context, account)),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
        ],
      ),
    );
  }

  Widget _buildAccountTile(BuildContext context, DemoAccountInfo account) {
    final iconData = switch (account.role) {
      'System Admin' => Icons.admin_panel_settings,
      'Regional Coordinator' => Icons.map_outlined,
      'HR Department' => Icons.badge_outlined,
      _ => Icons.person_outline,
    };

    final roleColor = switch (account.role) {
      'System Admin' => NpupsColors.trinidadRed,
      'Regional Coordinator' => NpupsColors.success,
      'HR Department' => NpupsColors.accent,
      _ => NpupsColors.textSecondary,
    };

    return InkWell(
      onTap: () => onSelect(account),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: roleColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(iconData, color: roleColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    account.name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: NpupsColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    account.email,
                    style: const TextStyle(fontSize: 12, color: NpupsColors.textSecondary),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: roleColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                account.role,
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: roleColor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
