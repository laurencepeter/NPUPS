import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/locksync_ws.dart';
import '../theme/npups_theme.dart';

// ──────────────────────────────────────────────────────────────────────────────
// LockSync Screen — Pairing + Real-Time Messaging
//
// Flow:
//   1. User taps "Create Code" → gets 6-digit code to share
//   2. Other user enters that code → both get paired
//   3. Once paired, text typed on one screen renders live on the other
// ──────────────────────────────────────────────────────────────────────────────

class LockSyncScreen extends StatefulWidget {
  const LockSyncScreen({super.key});

  @override
  State<LockSyncScreen> createState() => _LockSyncScreenState();
}

class _LockSyncScreenState extends State<LockSyncScreen> with TickerProviderStateMixin {
  // TODO: Replace with your actual server URL
  static const String _serverUrl = 'wss://locksync.yourdomain.com';

  late final LockSyncService _lockSync;
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();
  final FocusNode _messageFocus = FocusNode();

  String _partnerMessage = '';
  StreamSubscription? _messageSub;
  StreamSubscription? _errorSub;

  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();

    _lockSync = LockSyncService(serverUrl: _serverUrl);
    _lockSync.addListener(_onStateChange);

    _messageSub = _lockSync.messages.listen(_onSyncMessage);
    _errorSub = _lockSync.errors.listen(_onError);

    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Auto-connect on screen open
    _lockSync.connect();
  }

  void _onStateChange() {
    if (mounted) setState(() {});
  }

  void _onSyncMessage(SyncMessage msg) {
    final payload = msg.payload;
    if (payload is Map) {
      if (payload['type'] == 'message') {
        setState(() => _partnerMessage = payload['text'] as String? ?? '');
      } else if (payload['type'] == 'keystroke') {
        setState(() {
          final delta = payload['delta'] as String? ?? '';
          _partnerMessage = delta;
        });
      }
    }
  }

  void _onError(String error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error),
        backgroundColor: NpupsColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _createCode() {
    _lockSync.requestPairCode();
  }

  void _joinCode() {
    final code = _codeController.text.trim();
    if (code.length != 6) {
      _onError('Enter a 6-digit code');
      return;
    }
    _lockSync.joinPairCode(code);
  }

  void _onMessageChanged(String text) {
    // Send keystroke delta in real-time
    _lockSync.sendKeystroke(text, _messageController.selection.baseOffset);
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    _lockSync.sendMessage(text);
    _messageController.clear();
  }

  @override
  void dispose() {
    _messageSub?.cancel();
    _errorSub?.cancel();
    _lockSync.removeListener(_onStateChange);
    _lockSync.dispose();
    _codeController.dispose();
    _messageController.dispose();
    _messageFocus.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.lock_outline, size: 20),
            const SizedBox(width: 8),
            const Text('LockSync'),
            const Spacer(),
            _buildStatusChip(),
          ],
        ),
        backgroundColor: const Color(0xFF161B22),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_lockSync.state == LockSyncState.paired)
            IconButton(
              icon: const Icon(Icons.link_off),
              tooltip: 'Unpair',
              onPressed: () {
                _lockSync.unpair();
                _partnerMessage = '';
              },
            ),
        ],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 400),
        child: _buildBody(),
      ),
    );
  }

  Widget _buildStatusChip() {
    final (label, color) = switch (_lockSync.state) {
      LockSyncState.disconnected => ('Offline', Colors.red),
      LockSyncState.connecting => ('Connecting', Colors.orange),
      LockSyncState.connected => ('Ready', Colors.blue),
      LockSyncState.waitingForPair => ('Waiting', Colors.amber),
      LockSyncState.paired => ('Paired', Colors.green),
      LockSyncState.reconnecting => ('Reconnecting', Colors.orange),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildBody() {
    return switch (_lockSync.state) {
      LockSyncState.disconnected => _buildDisconnected(),
      LockSyncState.connecting || LockSyncState.reconnecting => _buildConnecting(),
      LockSyncState.connected => _buildPairingOptions(),
      LockSyncState.waitingForPair => _buildWaitingForPair(),
      LockSyncState.paired => _buildPairedView(),
    };
  }

  Widget _buildDisconnected() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wifi_off, color: Colors.white38, size: 64),
          const SizedBox(height: 16),
          Text(
            _lockSync.lastError ?? 'Disconnected',
            style: const TextStyle(color: Colors.white54, fontSize: 14),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => _lockSync.connect(),
            icon: const Icon(Icons.refresh),
            label: const Text('Reconnect'),
            style: ElevatedButton.styleFrom(
              backgroundColor: NpupsColors.accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnecting() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: NpupsColors.accent),
          SizedBox(height: 16),
          Text('Connecting to relay server...', style: TextStyle(color: Colors.white54)),
        ],
      ),
    );
  }

  Widget _buildPairingOptions() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.devices, color: Colors.white24, size: 80),
            const SizedBox(height: 24),
            const Text(
              'Pair Your Devices',
              style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Generate a code on one device, enter it on the other.',
              style: TextStyle(color: Colors.white54, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),

            // Option 1: Create code
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _createCode,
                icon: const Icon(Icons.qr_code),
                label: const Text('Generate Pairing Code'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: NpupsColors.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 24),

            const Row(
              children: [
                Expanded(child: Divider(color: Colors.white24)),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text('OR', style: TextStyle(color: Colors.white38, fontSize: 12)),
                ),
                Expanded(child: Divider(color: Colors.white24)),
              ],
            ),
            const SizedBox(height: 24),

            // Option 2: Enter code
            TextField(
              controller: _codeController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.bold,
                letterSpacing: 12,
              ),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                hintText: '000000',
                hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.15), letterSpacing: 12),
                counterText: '',
                filled: true,
                fillColor: const Color(0xFF161B22),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white24),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white24),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: NpupsColors.accent, width: 2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _joinCode,
                icon: const Icon(Icons.link),
                label: const Text('Join With Code'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: NpupsColors.accent),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWaitingForPair() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (_, __) => Opacity(
              opacity: _pulseAnimation.value,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                decoration: BoxDecoration(
                  color: const Color(0xFF161B22),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: NpupsColors.accent.withValues(alpha: 0.5)),
                ),
                child: Text(
                  _lockSync.pairCode ?? '------',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 16,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Share this code with your partner',
            style: TextStyle(color: Colors.white70, fontSize: 16),
          ),
          const SizedBox(height: 8),
          const Text(
            'Expires in 5 minutes',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
          const SizedBox(height: 24),
          TextButton.icon(
            onPressed: () {
              if (_lockSync.pairCode != null) {
                Clipboard.setData(ClipboardData(text: _lockSync.pairCode!));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Code copied!'),
                    behavior: SnackBarBehavior.floating,
                    duration: Duration(seconds: 1),
                  ),
                );
              }
            },
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copy Code'),
            style: TextButton.styleFrom(foregroundColor: NpupsColors.accent),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () {
              _lockSync.disconnect();
              _lockSync.connect();
            },
            child: const Text('Cancel', style: TextStyle(color: Colors.white38)),
          ),
        ],
      ),
    );
  }

  Widget _buildPairedView() {
    return Column(
      children: [
        // Partner status bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: const Color(0xFF161B22),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: _lockSync.partnerOnline ? Colors.green : Colors.red,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _lockSync.partnerOnline ? 'Partner Online' : 'Partner Offline',
                style: TextStyle(
                  color: _lockSync.partnerOnline ? Colors.green[300] : Colors.red[300],
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              Text(
                'ID: ${_lockSync.pairId?.substring(0, 8) ?? ""}',
                style: const TextStyle(color: Colors.white24, fontSize: 11, fontFamily: 'monospace'),
              ),
            ],
          ),
        ),

        // Partner's message display (lock screen preview)
        Expanded(
          flex: 3,
          child: Container(
            width: double.infinity,
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF161B22),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: Colors.white10)),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.lock_outline, color: Colors.white38, size: 14),
                      SizedBox(width: 6),
                      Text('LOCK SCREEN PREVIEW', style: TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 2)),
                    ],
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _partnerMessage.isEmpty ? 'Waiting for message...' : _partnerMessage,
                        style: TextStyle(
                          color: _partnerMessage.isEmpty ? Colors.white24 : Colors.white,
                          fontSize: _partnerMessage.isEmpty ? 16 : 22,
                          fontWeight: _partnerMessage.isEmpty ? FontWeight.normal : FontWeight.w300,
                          height: 1.4,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Message input
        Container(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _messageController,
                  focusNode: _messageFocus,
                  onChanged: _onMessageChanged,
                  onSubmitted: (_) => _sendMessage(),
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  maxLines: 3,
                  minLines: 1,
                  decoration: InputDecoration(
                    hintText: 'Type a message...',
                    hintStyle: const TextStyle(color: Colors.white24),
                    filled: true,
                    fillColor: const Color(0xFF161B22),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                decoration: const BoxDecoration(
                  color: NpupsColors.accent,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.send, color: Colors.white, size: 20),
                  onPressed: _sendMessage,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
