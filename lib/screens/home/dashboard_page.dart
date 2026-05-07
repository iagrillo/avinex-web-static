import 'escrow_disclaimer_dialog.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/notification_service.dart';
import 'package:flutter/services.dart';
// import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
// import 'dart:js' as js;
import '../../models/escrow_model.dart';
import '../../models/paystack_checkout_session.dart';
import '../../models/transaction_model.dart';
import '../../models/user_profile_model.dart';
import '../../models/wallet_model.dart';
import '../../models/withdrawal_account_model.dart';
import '../../navigation/app_routes.dart';
import '../../services/auth_service.dart';
import '../../services/dispute_thread_service.dart';
import '../../services/escrow_service.dart';
import '../../services/wallet_service.dart';
import '../dispute/dispute_thread_page.dart';
import '../dispute/raise_dispute_page.dart';
import '../profile/profile_page.dart';
import 'escrow_details_page.dart';
import 'release_escrow_funds_page.dart';

enum UserMode { buyer, seller }

class DashboardPage extends StatefulWidget {
  const DashboardPage({
    super.key,
    required this.userId,
    required this.fullName,
    required this.email,
    this.authService,
    this.walletService,
    this.escrowService,
  });

  const DashboardPage.preview({super.key})
    : userId = 'preview-user',
      fullName = 'Ifeanyi Okeke',
      email = 'ifeanyi@avinex.test',
      authService = null,
      walletService = null,
      escrowService = null;

  final String userId;
  final String fullName;
  final String email;
  final AuthService? authService;
  final WalletService? walletService;
  final EscrowService? escrowService;

  bool get isPreview =>
      authService == null || walletService == null || escrowService == null;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

// Correct class header:
class _DashboardPageState extends State<DashboardPage> with WidgetsBindingObserver {

  Future<void> _showGenerateOtpPrompt(EscrowModel escrow) async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF1D2840),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Escrow Created!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'You must generate a release code (OTP) and give it to the seller to release funds.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.mutedText),
                ),
                const SizedBox(height: 18),
                Container(height: 1, color: const Color(0xFF334155)),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () async {
                    Navigator.of(context).pop();
                    await _showReleaseCodeDialog(escrow);
                  },
                  child: const Text('Generate OTP'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
  late WalletModel _wallet;
  List<WalletTransaction> _transactions = const [];
  List<EscrowModel> _escrows = const [];
  UserProfileModel? _profile;
  WithdrawalAccountModel? _withdrawalAccount;
  UserMode _mode = UserMode.buyer;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _pendingDepositReference;
  RealtimeChannel? _walletChannel;
  bool _verifyDialogOpen = false;
  bool _depositDialogOpen = false;
  int _buyerUnreadNotifications = 0;
  int _sellerUnreadNotifications = 0;

  @override
  void initState() {
    super.initState();
    _wallet = WalletModel.empty(userId: widget.userId);
    // NotificationService is initialized in main.dart with navigatorKey.
    _load();
    _subscribeToWalletUpdates();
    WidgetsBinding.instance.addObserver(this);
  }

  void _subscribeToWalletUpdates() {
    final client = Supabase.instance.client;
    _walletChannel = client
        .channel('wallet_updates_${widget.userId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'wallet_transactions',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: widget.userId,
          ),
          callback: (_) {
            if (mounted) _refreshWallet();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'wallets',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: widget.userId,
          ),
          callback: (_) {
            if (mounted) _refreshWallet();
          },
        )
        .subscribe();
  }

  Future<void> _refreshWallet() async {
    if (widget.walletService == null) return;
    try {
      final results = await Future.wait([
        widget.walletService!.fetchOrCreateWallet(widget.userId),
        widget.walletService!.fetchTransactions(widget.userId),
      ]);
      if (mounted) {
        setState(() {
          _wallet = results[0] as WalletModel;
          _transactions = results[1] as List<WalletTransaction>;
        });
      }
    } catch (_) {
      // Silently ignore refresh errors
    }
  }

  Future<void> _refreshNotificationCounts() async {
    if (widget.isPreview) {
      if (!mounted) return;
      setState(() {
        _buyerUnreadNotifications = 0;
        _sellerUnreadNotifications = 0;
      });
      return;
    }

    try {
      final userId = widget.userId;
      final rows = await Supabase.instance.client
          .from('notifications')
          .select('role')
          .eq('user_id', userId)
          .eq('read', false);

      if (!mounted) return;

      var buyerCount = 0;
      var sellerCount = 0;
      for (final row in rows as List) {
        final role = '${(row as Map)['role'] ?? ''}'.trim().toLowerCase();
        if (role == 'seller') {
          sellerCount++;
        } else {
          buyerCount++;
        }
      }

      setState(() {
        _buyerUnreadNotifications = buyerCount;
        _sellerUnreadNotifications = sellerCount;
      });
    } catch (_) {
      // Keep existing counts if notifications fetch fails.
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _walletChannel?.unsubscribe();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed &&
        _pendingDepositReference != null &&
        mounted &&
        !_busy &&
        !_verifyDialogOpen &&
        !_depositDialogOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            _pendingDepositReference != null &&
            !_busy &&
            !_verifyDialogOpen &&
            !_depositDialogOpen) {
          _showVerifyDepositDialog();
        }
      });
    }
  }

  bool get _isVerified => _profile?.isVerified ?? widget.isPreview;

  String get _firstName {
    final parts = widget.fullName.trim().split(RegExp(r'\s+'));
    return parts.isEmpty ? 'User' : parts.first;
  }

  List<EscrowModel> get _buyerEscrows =>
      _escrows.where((escrow) => escrow.buyerId == widget.userId).toList();

  List<EscrowModel> get _sellerEscrows =>
      _escrows.where((escrow) => escrow.sellerId == widget.userId).toList();

  List<EscrowModel> get _pendingBuyerEscrows => _buyerEscrows
      .where((escrow) => escrow.status == EscrowStatus.pending)
      .toList();

  List<EscrowModel> get _pendingSellerEscrows => _sellerEscrows
      .where((escrow) => escrow.status == EscrowStatus.pending)
      .toList();

  List<EscrowModel> get _completedBuyerEscrows => _buyerEscrows
      .where((escrow) => escrow.status != EscrowStatus.pending)
      .toList();

  List<EscrowModel> get _completedSellerEscrows => _sellerEscrows
      .where((escrow) => escrow.status != EscrowStatus.pending)
      .toList();

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      if (widget.isPreview) {
        _wallet = const WalletModel(
          id: 'wallet-preview',
          userId: 'preview-user',
          availableBalance: 13850000,
          pendingBalance: 0,
          totalBalance: 13850000,
        );
        _profile = const UserProfileModel(
          id: 'preview-user',
          email: 'ifeanyi@avinex.test',
          fullName: 'Ifeanyi Okeke',
          phone: '08030000000',
          verificationStatus: 'verified',
        );
        _withdrawalAccount = null;
        _transactions = _previewTransactions;
        _escrows = _previewEscrows;
        _pendingDepositReference = 'PSK-AVX-482913';
        _buyerUnreadNotifications = 0;
        _sellerUnreadNotifications = 0;
      } else {
        final results = await Future.wait<dynamic>([
          widget.walletService!.fetchOrCreateWallet(widget.userId),
          widget.walletService!.fetchTransactions(widget.userId),
          widget.escrowService!.fetchEscrows(widget.userId),
          widget.authService!.getCurrentProfile(),
          widget.authService!.getSavedWithdrawalAccount(),
          Supabase.instance.client
              .from('notifications')
              .select('role')
              .eq('user_id', widget.userId)
              .eq('read', false),
        ]);

        _wallet = results[0] as WalletModel;
        _transactions = results[1] as List<WalletTransaction>;
        _escrows = results[2] as List<EscrowModel>;
        _profile = results[3] as UserProfileModel?;
        _withdrawalAccount = results[4] as WithdrawalAccountModel?;

        var buyerCount = 0;
        var sellerCount = 0;
        for (final row in results[5] as List) {
          final role = '${(row as Map)['role'] ?? ''}'.trim().toLowerCase();
          if (role == 'seller') {
            sellerCount++;
          } else {
            buyerCount++;
          }
        }
        _buyerUnreadNotifications = buyerCount;
        _sellerUnreadNotifications = sellerCount;

        // Show notification if user has active escrows.
        final activeEscrowCount = _escrows
            .where((escrow) => escrow.status == EscrowStatus.pending)
            .length;
        if (activeEscrowCount > 0 && mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            if (!mounted) return;
            _showMessage(
              'You have $activeEscrowCount active escrow${activeEscrowCount == 1 ? '' : 's'} in progress.',
              accent: AppColors.emerald,
            );
            await NotificationService.showActiveEscrowNotification(
              activeEscrowCount,
            );
          });
        }

        // Role-based admin redirect logic
        if (widget.authService != null) {
          final isSuperAdmin = await widget.authService!.hasSuperAdminAccess();
          if (isSuperAdmin && mounted) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              Navigator.of(context).pushNamedAndRemoveUntil(
                AppRoutes.adminDashboard,
                (route) => false,
              );
            });
            return;
          }

          final hasAdminAccess = await widget.authService!.hasAdminAccess();
          if (hasAdminAccess && mounted) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              Navigator.of(context).pushNamedAndRemoveUntil(
                AppRoutes.regularAdminDashboard,
                (route) => false,
              );
            });
            return;
          }
        }

        final queuedNotice = widget.authService?.consumeUserNotice();
        if (queuedNotice != null && mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final activeEscrowCount = _escrows
                .where((escrow) => escrow.status == EscrowStatus.pending)
                .length;
            if (activeEscrowCount > 0 && mounted) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                _showMessage(
                  'You have $activeEscrowCount active escrow${activeEscrowCount == 1 ? '' : 's'} in progress.',
                  accent: AppColors.emerald,
                );
              });
            }
            if (!mounted) return;
            _showMessage(queuedNotice, accent: AppColors.emerald);
          });
        }
      }
    } catch (error) {
      _error = _formatError(error);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  List<WalletTransaction> get _buyerTransactions =>
      _transactions.take(4).toList();

  String _formatError(Object error) {
    final message = '$error'.replaceFirst('Exception: ', '').trim();
    return message.replaceFirst('Bad state: ', '');
  }

  void _showMessage(String message, {Color? accent}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: accent == null
              ? AppColors.panelSoft
              : accent.withOpacity(0.18),
          content: Text(message),
        ),
      );
  }

  Future<void> _runBusyAction(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      _showMessage(_formatError(error), accent: AppColors.rose);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<String?> _showEscrowConfirmationWithPin({
    required bool directPay,
    required String sellerEmail,
    required String description,
    required double amount,
    double directPayAmount = 0,
    double escrowAmount = 0,
  }) async {

    final buyerFee = amount * 0.005;
    final totalDebit = amount + buyerFee;

    // Step 1: Show payment review dialog (Direct Pay: only amount, no escrow fields)
    final reviewConfirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: AppColors.panel,
          title: const Text(
            'Confirm Payment',
            style: TextStyle(color: Colors.white),
          ),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _FeeRow(
                    label: 'Payment type',
                    value: directPay ? 'Direct Pay' : 'Escrow only',
                  ),
                  _FeeRow(label: 'Seller', value: sellerEmail),
                  _FeeRow(label: 'Purpose', value: description),
                  _FeeRow(
                    label: 'Total amount',
                    value: '₦ ${amount.toStringAsFixed(2)}',
                  ),
                  if (!directPay) ...[
                    _FeeRow(
                      label: 'Escrow amount',
                      value: '₦ ${escrowAmount.toStringAsFixed(2)}',
                    ),
                  ],
                  _FeeRow(
                    label: 'Buyer fee (0.5%)',
                    value: '₦ ${buyerFee.toStringAsFixed(2)}',
                  ),
                  const Divider(color: Colors.white10),
                  _FeeRow(
                    label: 'Total debit',
                    value: '₦ ${totalDebit.toStringAsFixed(2)}',
                    highlight: true,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Please confirm these details before proceeding.',
                    style: TextStyle(color: AppColors.mutedText),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.emerald,
              ),
              child: const Text('Continue'),
            ),
          ],
        );
      },
    );

    if (reviewConfirmed != true) return null;
    if (!mounted) return null;

    // Step 2: Show disclaimer dialog
    final disclaimerAccepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const EscrowDisclaimerDialog(),
    );
    if (disclaimerAccepted != true) return null;
    if (!mounted) return null;

    String? errorText;
    final pinController = TextEditingController();
    try {
      while (mounted) {
        pinController.clear();
        final pin = await showDialog<String>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) {
            return AlertDialog(
              backgroundColor: AppColors.panel,
              title: const Text(
                'Enter Security PIN',
                style: TextStyle(color: Colors.white),
              ),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'For security, enter your 4-digit transaction PIN to create this payment.',
                      style: TextStyle(color: AppColors.mutedText),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: pinController,
                      obscureText: true,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      maxLength: 4,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(4),
                      ],
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Security PIN',
                        counterText: '',
                      ),
                    ),
                    if (errorText != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        errorText!,
                        style: const TextStyle(color: AppColors.rose),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop(pinController.text.trim());
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.emerald,
                  ),
                  child: const Text('Confirm & Create'),
                ),
              ],
            );
          },
        );

        if (pin == null) return null;
        if (RegExp(r'^\d{4}$').hasMatch(pin)) {
          return pin;
        }
        errorText = 'Enter your 4-digit PIN to continue.';
      }
    } finally {
      pinController.dispose();
    }

    return null;
  }

  Future<String?> _showSetupTransactionPinDialog() async {
    String? errorText;
    final pinController = TextEditingController();
    final confirmPinController = TextEditingController();

    try {
    while (mounted) {
      pinController.clear();
      confirmPinController.clear();

      final values = await showDialog<Map<String, String>>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return AlertDialog(
            backgroundColor: AppColors.panel,
            title: const Text(
              'Set Transaction PIN',
              style: TextStyle(color: Colors.white),
            ),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'First-time setup: create a 4-digit PIN for escrow and direct payments.',
                    style: TextStyle(color: AppColors.mutedText),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: pinController,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(4),
                    ],
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'New PIN',
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: confirmPinController,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(4),
                    ],
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Confirm PIN',
                      counterText: '',
                    ),
                  ),
                  if (errorText != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      errorText,
                      style: const TextStyle(color: AppColors.rose),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.emerald,
                ),
                onPressed: () {
                  Navigator.of(dialogContext).pop({
                    'pin': pinController.text.trim(),
                    'confirmPin': confirmPinController.text.trim(),
                  });
                },
                child: const Text('Save PIN'),
              ),
            ],
          );
        },
      );

      if (values == null) {
        return null;
      }
      final pin = values['pin'] ?? '';
      final confirmPin = values['confirmPin'] ?? '';

      if (!RegExp(r'^\d{4}$').hasMatch(pin)) {
        errorText = 'PIN must be exactly 4 digits.';
        continue;
      }

      if (pin != confirmPin) {
        errorText = 'PIN confirmation does not match.';
        continue;
      }

      return pin;
    }
    } finally {
      pinController.dispose();
      confirmPinController.dispose();
    }

    return null;
  }

  Future<void> _showVerificationSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          decoration: const BoxDecoration(
            color: AppColors.panel,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 56,
                    height: 5,
                    decoration: BoxDecoration(
                      color: const Color(0xFF334155),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Verify Account',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _isVerified
                      ? 'Your Avinex account is already verified and ready for payments.'
                      : 'Verify your email and complete your profile verification to enable withdrawals, escrow creation, and direct payouts.',
                  style: const TextStyle(
                    color: AppColors.mutedText,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 18),
                _InfoBullet(
                  icon: Icons.mark_email_read_outlined,
                  text:
                      'Use the email verification link sent to ${widget.email}.',
                ),
                const SizedBox(height: 12),
                const _InfoBullet(
                  icon: Icons.verified_user_outlined,
                  text:
                      'Only verified buyer and seller accounts can create Avinex escrow payments.',
                ),
                const SizedBox(height: 12),
                const _InfoBullet(
                  icon: Icons.account_balance_outlined,
                  text:
                      'A verified account with a saved payout bank unlocks withdrawals and seller payouts.',
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.emerald,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(54),
                    ),
                    onPressed: () async {
                      Navigator.of(context).pop();
                      await _load();
                    },
                    child: Text(
                      _isVerified
                          ? 'Refresh Status'
                          : 'I\'ve Verified My Account',
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showDepositDialog() async {
    if (_busy || _depositDialogOpen || _verifyDialogOpen) return;
    _depositDialogOpen = true;
    final amountController = TextEditingController();
    String? _depositError;
    bool _depositLoading = false;

    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (ctx, setS) {
            return AlertDialog(
              backgroundColor: AppColors.panel,
              title: const Text(
                'Deposit to Wallet',
                style: TextStyle(color: Colors.white),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: amountController,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        hintText: 'Amount',
                        prefixText: '₦ ',
                      ),
                    ),
                    if (_depositError != null) ...[
                      const SizedBox(height: 8),
                      Text(_depositError!,
                          style: const TextStyle(color: AppColors.rose)),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed:
                      _depositLoading ? null : () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: _depositLoading
                      ? null
                      : () async {
                          final amount = double.tryParse(
                                amountController.text
                                    .replaceAll(',', '')
                                    .trim(),
                              ) ??
                              0;
                          if (amount <= 0) {
                            setS(() => _depositError =
                                'Enter a valid deposit amount.');
                            return;
                          }
                          setS(() {
                            _depositLoading = true;
                            _depositError = null;
                          });
                          try {
                            if (widget.isPreview) {
                              if (mounted) {
                                setState(() {
                                  _wallet = _wallet.copyWith(
                                    availableBalance:
                                        _wallet.availableBalance + amount,
                                    totalBalance:
                                        _wallet.totalBalance + amount,
                                  );
                                  _pendingDepositReference =
                                      'PSK-AVX-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
                                });
                              }
                              Navigator.of(ctx).pop();
                              _showMessage(
                                'Preview deposit initialized. Use Verify Deposit to complete it.',
                              );
                              return;
                            }
                            final session = await widget.walletService!
                                .initializePaystackDeposit(
                              email: widget.email,
                              amount: amount,
                            );
                            _pendingDepositReference = session.reference;
                            if (ctx.mounted) Navigator.of(ctx).pop();
                            await _launchCheckout(session);
                            _showMessage(
                              'Paystack checkout opened. Verify the deposit after payment.',
                            );
                            if (mounted) setState(() {});
                          } catch (e) {
                            if (!ctx.mounted) return;
                            setS(() {
                              _depositLoading = false;
                              _depositError = _formatError(e);
                            });
                          }
                        },
                  child: _depositLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Continue'),
                ),
              ],
            );
          },
        ),
      );
    } finally {
      _depositDialogOpen = false;
    }
  }

  Future<void> _launchCheckout(PaystackCheckoutSession session) async {
    final url = Uri.tryParse(session.authorizationUrl);
    if (url == null) {
      throw StateError('The Paystack checkout URL is invalid.');
    }

    final launched = await launchUrl(url, mode: LaunchMode.externalApplication);
    if (!launched) {
      throw StateError(
        'Unable to open the Paystack checkout link on this device.',
      );
    }
  }

  Future<void> _showVerifyDepositDialog() async {
    if (_busy || _verifyDialogOpen || _depositDialogOpen) return;
    _verifyDialogOpen = true;
    final controller = TextEditingController(
      text: _pendingDepositReference ?? '',
    );
    String? _verifyError;
    bool _verifyLoading = false;

    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (ctx, setS) {
            return AlertDialog(
              backgroundColor: AppColors.panel,
              title: const Text(
                'Verify Deposit',
                style: TextStyle(color: Colors.white),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: controller,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        hintText: 'Enter Paystack reference',
                      ),
                    ),
                    if (_verifyError != null) ...[
                      const SizedBox(height: 8),
                      Text(_verifyError!,
                          style: const TextStyle(color: AppColors.rose)),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed:
                      _verifyLoading ? null : () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: _verifyLoading
                      ? null
                      : () async {
                          final ref = controller.text.trim();
                          if (ref.isEmpty) {
                            setS(() => _verifyError =
                                'Enter the payment reference to verify.');
                            return;
                          }
                          setS(() {
                            _verifyLoading = true;
                            _verifyError = null;
                          });
                          try {
                            if (widget.isPreview) {
                              _pendingDepositReference = null;
                              Navigator.of(ctx).pop();
                              _showMessage(
                                'Preview deposit marked as verified.',
                              );
                              if (mounted) setState(() {});
                              return;
                            }
                            await widget.walletService!
                                .verifyPaystackDeposit(reference: ref);
                            _pendingDepositReference = null;
                            if (ctx.mounted) Navigator.of(ctx).pop();
                            await _load();
                            _showMessage(
                              'Deposit verification complete. Wallet refreshed.',
                            );
                          } catch (e) {
                            if (!ctx.mounted) return;
                            setS(() {
                              _verifyLoading = false;
                              _verifyError = _formatError(e);
                            });
                          }
                        },
                  child: _verifyLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Verify'),
                ),
              ],
            );
          },
        ),
      );
    } finally {
      _verifyDialogOpen = false;
    }
  }

  Future<void> _showWithdrawalDialog() async {
    final controller = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: AppColors.panel,
          title: const Text(
            'Withdraw Funds',
            style: TextStyle(color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_withdrawalAccount != null)
                Text(
                  'Payout account: ${_withdrawalAccount!.bankName} • ${_withdrawalAccount!.maskedAccountNumber}',
                  style: const TextStyle(color: AppColors.mutedText),
                ),
              if (_withdrawalAccount != null) const SizedBox(height: 14),
              TextField(
                controller: controller,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  prefixText: '₦ ',
                  hintText: 'Enter amount',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final amount =
                    double.tryParse(
                      controller.text.replaceAll(',', '').trim(),
                    ) ??
                    0;
                if (amount <= 0) {
                  _showMessage(
                    'Enter a valid withdrawal amount.',
                    accent: AppColors.rose,
                  );
                  return;
                }
                Navigator.of(dialogContext).pop();
                await _runBusyAction(() async {
                  if (!_isVerified) {
                    throw StateError(
                      'Verify your account before requesting a withdrawal.',
                    );
                  }
                  if (_withdrawalAccount == null) {
                    throw StateError(
                      'Add a payout account before requesting withdrawals.',
                    );
                  }
                  // PATCH: Enforce PIN setup and prompt before withdrawal
                  final hasPin = await widget.authService!.hasTransactionPin();
                  if (!hasPin) {
                    final newPin = await _showSetupTransactionPinDialog();
                    if (newPin == null) {
                      _showMessage('Withdrawal cancelled: PIN setup required.', accent: AppColors.rose);
                      return;
                    }
                    await widget.authService!.setTransactionPin(pin: newPin);
                    _showMessage(
                      'Transaction PIN setup complete.',
                      accent: AppColors.emerald,
                    );
                  }
                  final pin = await _showEscrowConfirmationWithPin(
                    directPay: false,
                    sellerEmail: '',
                    description: 'Withdrawal',
                    amount: amount,
                    directPayAmount: 0,
                    escrowAmount: 0,
                  );
                  if (pin == null) {
                    _showMessage('Withdrawal cancelled: PIN required.', accent: AppColors.rose);
                    return;
                  }
                  await widget.authService!.verifySecurityPin(pin: pin);
                  if (widget.isPreview) {
                    setState(() {
                      _wallet = _wallet.copyWith(
                        availableBalance: (_wallet.availableBalance - amount)
                            .clamp(0, double.infinity)
                            .toDouble(),
                        totalBalance: (_wallet.totalBalance - amount)
                            .clamp(0, double.infinity)
                            .toDouble(),
                      );
                    });
                    _showMessage(
                      'Preview withdrawal queued to ${_withdrawalAccount!.bankName}.',
                    );
                    return;
                  }
                  await widget.authService!.ensureVerifiedAccount(
                    action: 'withdraw funds',
                  );
                  await widget.walletService!.withdraw(
                    userId: widget.userId,
                    amount: amount,
                    withdrawalAccount: _withdrawalAccount!,
                    description:
                        'Withdrawal to ${_withdrawalAccount!.bankName}',
                  );
                  await _load();
                  _showMessage('Withdrawal recorded successfully.');
                });
              },
              child: const Text('Withdraw'),
            ),
          ],
        );
      },
    );
    controller.dispose();
  }

  Future<void> _showPayoutAccountDialog() async {
    if (widget.isPreview) {
      _showMessage(
        'Payout setup is only available when signed in to a live account.',
      );
      return;
    }

    final accountNumberController = TextEditingController();
    String? selectedBankCode;
    String? selectedBankName;
    bool loadingBanks = true;
    bool saving = false;
    String? errorText;
    List<Map<String, String>> banks = const [];

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        Future<void> fetchBanks(BuildContext builderCtx, StateSetter setSheetState) async {
          try {
            final response = await widget.walletService!.fetchPaystackBanks();
            if (!builderCtx.mounted) return;
            setSheetState(() {
              banks = response;
              loadingBanks = false;
              if (banks.isNotEmpty) {
                selectedBankCode = banks.first['code'];
                selectedBankName = banks.first['name'];
              }
            });
          } catch (error) {
            if (!builderCtx.mounted) return;
            setSheetState(() {
              loadingBanks = false;
              errorText = _formatError(error);
            });
          }
        }

        return StatefulBuilder(
          builder: (context, setSheetState) {
            if (loadingBanks && banks.isEmpty && errorText == null) {
              fetchBanks(context, setSheetState);
            }
            return Container(
              padding: EdgeInsets.fromLTRB(
                20,
                20,
                20,
                20 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              decoration: const BoxDecoration(
                color: AppColors.panel,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Set Up Payout Account',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Add a Paystack-verified bank account to enable withdrawals and seller payouts.',
                      style: TextStyle(color: AppColors.mutedText),
                    ),
                    const SizedBox(height: 18),
                    if (loadingBanks)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else ...[
                      DropdownButtonFormField<String>(
                        key: ValueKey(selectedBankCode),
                        initialValue: selectedBankCode,
                        decoration: const InputDecoration(labelText: 'Bank'),
                        dropdownColor: AppColors.panelSoft,
                        items: banks
                            .map(
                              (bank) => DropdownMenuItem<String>(
                                value: bank['code'],
                                child: Text(
                                  bank['name'] ?? '',
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          setSheetState(() {
                            selectedBankCode = value;
                            selectedBankName = banks.firstWhere(
                              (bank) => bank['code'] == value,
                            )['name'];
                          });
                        },
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: accountNumberController,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: 'Account Number',
                        ),
                      ),
                    ],
                    if (errorText != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        errorText!,
                        style: const TextStyle(color: AppColors.rose),
                      ),
                    ],
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.emerald,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(54),
                        ),
                        onPressed: loadingBanks || saving
                            ? null
                            : () async {
                                final accountNumber = accountNumberController
                                    .text
                                    .trim();
                                if (selectedBankCode == null ||
                                    selectedBankName == null ||
                                    accountNumber.length < 10) {
                                  setSheetState(() {
                                    errorText =
                                        'Choose a bank and enter a valid account number.';
                                  });
                                  return;
                                }
                                setSheetState(() {
                                  saving = true;
                                  errorText = null;
                                });
                                try {
                                  final account = await widget.walletService!
                                      .verifyWithdrawalAccount(
                                        bankCode: selectedBankCode!,
                                        bankName: selectedBankName!,
                                        accountNumber: accountNumber,
                                      );
                                  await widget.authService!
                                      .saveWithdrawalAccount(account);
                                  if (!context.mounted) return;
                                  final nav = Navigator.of(context);
                                  nav.pop();
                                  await _load();
                                  _showMessage(
                                    'Payout account saved successfully.',
                                  );
                                } catch (error) {
                                  if (!context.mounted) return;
                                  setSheetState(() {
                                    saving = false;
                                    errorText = _formatError(error);
                                  });
                                }
                              },
                        child: saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Verify & Save Account'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    accountNumberController.dispose();
  }

  Future<void> _showCreateEscrowDialog({required bool directPay}) async {
    final sellerEmailController = TextEditingController();
    final sellerNameController = TextEditingController();
    final sellerPhoneController = TextEditingController();
    final buyerPhoneController = TextEditingController(
      text: _profile?.phone ?? '',
    );
    final descriptionController = TextEditingController();
    final amountController = TextEditingController();
    final directPayController = TextEditingController();

    final errorNotifier = ValueNotifier<String?>(null);

    final draft = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _CreateEscrowSheetBody(
        directPay: directPay,
        sellerEmailController: sellerEmailController,
        sellerNameController: sellerNameController,
        sellerPhoneController: sellerPhoneController,
        buyerPhoneController: buyerPhoneController,
        descriptionController: descriptionController,
        amountController: amountController,
        directPayController: directPayController,
        errorNotifier: errorNotifier,
        onSubmit: (data) => Navigator.of(sheetContext).pop(data),
        currentUserEmail: widget.email,
        authService: widget.authService,
      ),
    );

    errorNotifier.dispose();

    if (draft != null && mounted) {
      await _submitEscrowFromDashboard(
        directPay: draft['directPay'] as bool,
        sellerName: draft['sellerName'] as String,
        sellerEmail: draft['sellerEmail'] as String,
        sellerPhone: draft['sellerPhone'] as String,
        buyerPhone: draft['buyerPhone'] as String,
        description: draft['description'] as String,
        amount: (draft['amount'] as num).toDouble(),
        directPayAmount: (draft['directPayAmount'] as num).toDouble(),
        escrowAmount: (draft['escrowAmount'] as num).toDouble(),
      );
    }

    sellerEmailController.dispose();
    sellerNameController.dispose();
    sellerPhoneController.dispose();
    buyerPhoneController.dispose();
    descriptionController.dispose();
    amountController.dispose();
    directPayController.dispose();
  }



  Future<void> _submitEscrowFromDashboard({
    required bool directPay,
    required String sellerName,
    required String sellerEmail,
    required String sellerPhone,
    required String buyerPhone,
    required String description,
    required double amount,
    required double directPayAmount,
    required double escrowAmount,
  }) async {
    try {
      if (!_isVerified && !widget.isPreview) {
        await widget.authService!.ensureVerifiedAccount(
          action: 'create payments',
        );
      }

      if (widget.isPreview) {
        _showMessage(
          '${directPay ? 'Direct payment' : 'Escrow payment'} created in preview mode.',
        );
        return;
      }

      final verifiedSeller = await widget.authService!
          .lookupVerifiedCounterparty(email: sellerEmail);

      final resolvedSellerName =
          '${verifiedSeller['full_name'] ?? ''}'.trim().isNotEmpty
          ? '${verifiedSeller['full_name'] ?? ''}'.trim()
          : sellerName;
      final resolvedSellerPhone =
          '${verifiedSeller['phone'] ?? ''}'.trim().isNotEmpty
          ? '${verifiedSeller['phone'] ?? ''}'.trim()
          : sellerPhone;

      final hasPin = await widget.authService!.hasTransactionPin();
      if (!hasPin) {
        final newPin = await _showSetupTransactionPinDialog();
        if (newPin == null) {
          return;
        }
        await widget.authService!.setTransactionPin(pin: newPin);
        _showMessage(
          'Transaction PIN setup complete.',
          accent: AppColors.emerald,
        );
      }

      final pin = await _showEscrowConfirmationWithPin(
        directPay: directPay,
        sellerEmail: sellerEmail,
        description: description,
        amount: amount,
        directPayAmount: directPayAmount,
        escrowAmount: escrowAmount,
      );
      if (pin == null) {
        return;
      }

      if (_busy) return;
      setState(() => _busy = true);
      try {
        await widget.authService!.verifySecurityPin(pin: pin);

        final escrow = await widget.escrowService!.createEscrow(
          buyerId: widget.userId,
          buyerName: widget.fullName,
          sellerName: resolvedSellerName,
          sellerEmail: sellerEmail,
          sellerPhone: resolvedSellerPhone,
          buyerPhone: buyerPhone,
          description: description,
          platform: 'Avinex',
          amount: amount,
          directPay: directPay,
          directPayAmount: directPayAmount,
          escrowAmount: escrowAmount,
        );

        await _load();
        _showMessage(
          directPay
              ? 'Direct payment created successfully.'
              : 'Escrow created successfully.',
        );

        // Prompt buyer to generate OTP after escrow creation
        if (!directPay && mounted) {
          await _showGenerateOtpPrompt(escrow);
        }
      } finally {
        if (mounted) {
          setState(() => _busy = false);
        }
      }

      // Move this function above _submitEscrowFromDashboard
    } catch (error) {
      _showMessage(_formatError(error), accent: AppColors.rose);
    }
  }

  Future<void> _openDisputeFlow(EscrowModel escrow) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) =>
            RaiseDisputePage(escrow: escrow, onDisputeRaised: _load),
      ),
    );

    if (result == true) {
      await _load();
      _showMessage('Dispute submitted. Our team will review it.');
    }
  }

  Future<void> _openReleaseFlow(EscrowModel escrow) async {
    if (widget.escrowService == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ReleaseEscrowFundsPage(
          escrow: escrow,
          onConfirmRelease: (otp) async {
            await widget.escrowService!.releaseEscrow(
              escrowId: escrow.id,
              otp: otp,
            );
            await _load();
            _showMessage('Funds released successfully.');
          },
        ),
      ),
    );
  }

  Future<void> _showReleaseCodeDialog(EscrowModel escrow) async {
    if (_busy) return;

    if (escrow.isDirectPayment) {
      _showMessage(
        'This payment is direct and does not use a release OTP.',
        accent: AppColors.amber,
      );
      return;
    }

    String code;
    setState(() => _busy = true);
    try {
      code = widget.isPreview
          ? (escrow.otp.isEmpty ? generateOtp() : escrow.otp)
          : await widget.escrowService!.generateReleaseCode(
              escrowId: escrow.id,
            );
    } catch (error) {
      _showMessage(_formatError(error), accent: AppColors.rose);
      return;
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF1D2840),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Escrow Release Code Generated',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Share this code with the seller to confirm release.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.mutedText),
                ),
                const SizedBox(height: 18),
                Container(height: 1, color: const Color(0xFF334155)),
                const SizedBox(height: 20),
                Text(
                  code,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 42,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 4,
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(52),
                    ),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: code));
                      if (!context.mounted) return;
                      final nav = Navigator.of(context);
                      nav.pop();
                      _showMessage('Release code copied to clipboard.');
                    },
                    child: const Text(
                      'Copy Code',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Container(height: 1, color: const Color(0xFF334155)),
                const SizedBox(height: 14),
                const Text(
                  'Seller must enter this code to unlock funds.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.mutedText),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openEscrowDetails(EscrowModel escrow) async {
    final sellerMode = _mode == UserMode.seller;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => EscrowDetailsPage(
          escrow: escrow,
          sellerMode: sellerMode,
          onReleaseFunds: sellerMode && escrow.status == EscrowStatus.pending
              ? () => _openReleaseFlow(escrow)
              : null,
          onRaiseDispute: () => _openDisputeFlow(escrow),
          onGenerateReleaseCode:
              !sellerMode &&
                  escrow.status == EscrowStatus.pending &&
                  !escrow.isDirectPayment
              ? () => _showReleaseCodeDialog(escrow)
              : null,
          onOpenChat: () {
            final userId = widget.authService?.currentUser?.id ?? '';
            final role = sellerMode ? 'seller' : 'buyer';
            Navigator.of(context).pushNamed(
              AppRoutes.escrowChat,
              arguments: {
                'escrowId': escrow.id,
                'userId': userId,
                'role': role,
                'buyerId': escrow.buyerId,
                'sellerId': escrow.sellerId,
              },
            );
          },
          onOpenDisputeThread: () => _openDisputeThread(escrow),
        ),
      ),
    );
    await _load();
  }

  Future<void> _openDisputeThread(EscrowModel escrow) async {
    final currentUserId = widget.authService?.currentUser?.id ?? '';
    if (currentUserId.isEmpty) {
      _showMessage('Sign in again to open dispute thread.');
      return;
    }

    final role = currentUserId == escrow.buyerId ? 'buyer' : 'seller';
    final service = DisputeThreadService(Supabase.instance.client);

    try {
      final dispute = await service.getLatestDisputeForEscrow(escrow.id);
      if (dispute == null) {
        _showMessage('No dispute thread exists for this escrow yet.');
        return;
      }

      final disputeId = '${dispute['id'] ?? ''}'.trim();
      if (disputeId.isEmpty) {
        _showMessage('Unable to open dispute thread right now.');
        return;
      }

      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => DisputeThreadPage(
            disputeId: disputeId,
            escrowId: escrow.id,
            currentUserId: currentUserId,
            currentRole: role,
          ),
        ),
      );
    } catch (e) {
      _showMessage('Unable to open dispute thread: $e');
    }
  }

  Future<void> _openProfilePage() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ProfilePage(
          fullName: widget.fullName,
          email: widget.email,
          profile: _profile,
          withdrawalAccount: _withdrawalAccount,
          authService: widget.authService,
          previewMode: widget.isPreview,
        ),
      ),
    );
    await _load();
  }

  Future<void> _openNotificationCenter() async {
    final route = _mode == UserMode.seller
        ? AppRoutes.sellerNotificationCenter
        : AppRoutes.buyerNotificationCenter;
    await Navigator.of(context).pushNamed(route);
    await _refreshNotificationCounts();
  }

  String _releaseAvailability(EscrowModel escrow) {
    final readyAt = escrow.createdAt.add(const Duration(days: 1));
    final diff = readyAt.difference(DateTime.now());
    if (diff.isNegative || diff.inHours <= 0) {
      return 'Release available now';
    }
    return 'Release available in ${diff.inHours}h';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: _buildBottomCta(),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF070E24), Color(0xFF08132D), Color(0xFF0A1C46)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 140),
              children: [
                _buildHeader(),
                const SizedBox(height: 14),
                if (_error != null) _buildErrorBanner(),
                _buildModeSwitcher(),
                const SizedBox(height: 14),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 120),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else ...[
                  if (_mode == UserMode.buyer) ...[
                    _buildBalanceCard(),
                    const SizedBox(height: 14),
                    _buildBuyerActionCard(),
                    if (_pendingBuyerEscrows.isNotEmpty) ...[
                      const SizedBox(height: 22),
                      _buildSectionHeader('Pending Escrows'),
                      const SizedBox(height: 12),
                      _buildBuyerPendingEscrowsList(),
                    ],
                    const SizedBox(height: 22),
                    _buildSectionHeader('Recent Transactions'),
                    const SizedBox(height: 12),
                    _buildBuyerTransactionsList(),
                  ] else ...[
                    if (_pendingSellerEscrows.length == 1) ...[
                      _buildFeaturedSellerEscrow(_pendingSellerEscrows.first),
                      const SizedBox(height: 18),
                    ],
                    _buildSectionHeader('Pending Sales'),
                    const SizedBox(height: 12),
                    _buildPendingSalesCard(),
                    const SizedBox(height: 18),
                    _buildSectionHeader('Funds Overview'),
                    const SizedBox(height: 12),
                    _buildFundsOverview(),
                    const SizedBox(height: 18),
                    _buildSectionHeader('Recent Payouts'),
                    const SizedBox(height: 12),
                    _buildSellerTransactions(),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final badgeCount =
      _mode == UserMode.buyer ? _buyerUnreadNotifications : _sellerUnreadNotifications;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      _BrandMark(),
                      SizedBox(width: 10),
                      Text(
                        'Avinex Escrow',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Supabase auth + wallet',
                    style: TextStyle(color: AppColors.mutedText, fontSize: 15),
                  ),
                ],
              ),
            ),
            _HeaderBell(count: badgeCount, onTap: _openNotificationCenter),
            Container(width: 1, height: 30, color: const Color(0xFF334155)),
            const SizedBox(width: 12),
            Column(
              children: [
                InkWell(
                  onTap: _openProfilePage,
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: const BoxDecoration(
                      color: Color(0xFF083344),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _firstName.substring(0, 1).toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.fullName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 14),
        Container(height: 1, color: const Color(0xFF1E293B)),
      ],
    );
  }

  Widget _buildModeSwitcher() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF151F35),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        children: UserMode.values.map((mode) {
          final selected = _mode == mode;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _mode = mode),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: BoxDecoration(
                  color: selected ? AppColors.emerald : Colors.transparent,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Text(
                  mode == UserMode.buyer ? 'Buyer' : 'Seller',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildBalanceCard() {
    return Container(
      padding: const EdgeInsets.only(top: 22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          colors: [Color(0xFF18C76F), Color(0xFF1F8BFF)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
      ),
      child: Column(
        children: [
          const Text(
            'Available Balance',
            style: TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            formatCurrency(_wallet.availableBalance),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0x33020617),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _BalanceMetric(
                    label: 'In Escrow',
                    value: formatCurrency(_wallet.pendingBalance),
                  ),
                ),
                const _MetricDivider(),
                Expanded(
                  child: _BalanceMetric(
                    label: 'Active Escrows',
                    value: '${_pendingBuyerEscrows.length}',
                  ),
                ),
                const _MetricDivider(),
                Expanded(
                  child: _BalanceMetric(
                    label: 'Completed',
                    value: '${_completedBuyerEscrows.length}',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBuyerActionCard() {
    final hasPayoutAccount = _withdrawalAccount != null;
    final showVerifyDeposit =
        _pendingDepositReference != null &&
        _pendingDepositReference!.isNotEmpty;
    final showVerificationRow = !_isVerified || showVerifyDeposit;
    final verificationLabel = !_isVerified
        ? 'Verify Account'
        : 'Verify Deposit';
    final verificationIcon = !_isVerified
        ? Icons.verified_user_outlined
        : Icons.shield_outlined;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF17233B),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(child: Divider(color: Color(0xFF475569))),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'Wallet Actions',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Expanded(child: Divider(color: Color(0xFF475569))),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _ActionTile(
                  color: AppColors.emerald,
                  icon: Icons.account_balance_wallet_outlined,
                  label: 'Deposit',
                  onTap: _busy ? null : _showDepositDialog,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ActionTile(
                  color: hasPayoutAccount
                      ? const Color(0xFF5B6B82)
                      : const Color(0xFF5B6B82),
                  icon: Icons.check_circle_outline_rounded,
                  label: 'Withdraw',
                  subtitle: hasPayoutAccount ? null : 'No payout account added',
                  onTap: _busy
                      ? null
                      : hasPayoutAccount
                      ? _showWithdrawalDialog
                      : _showPayoutAccountDialog,
                ),
              ),
            ],
          ),
          if (showVerificationRow) ...[
            const SizedBox(height: 12),
            _ActionTile(
              color: const Color(0xFF2563EB),
              icon: verificationIcon,
              label: verificationLabel,
              wide: true,
              onTap: _busy
                  ? null
                  : !_isVerified
                  ? _showVerificationSheet
                  : _showVerifyDepositDialog,
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _ActionTile(
                  color: const Color(0xFF16A34A),
                  icon: Icons.shield_outlined,
                  label: 'Create Escrow',
                  onTap: _busy
                      ? null
                      : () => _showCreateEscrowDialog(directPay: false),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ActionTile(
                  color: AppColors.amber,
                  icon: Icons.send_outlined,
                  label: 'Pay Direct',
                  onTap: _busy
                      ? null
                      : () => _showCreateEscrowDialog(directPay: true),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const SizedBox(width: 4, child: Divider(color: Color(0xFF475569))),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  hasPayoutAccount
                      ? 'Verified payout account ready for withdrawals.'
                      : 'Set up a payout account to enable withdrawals.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFD1D5DB),
                    fontSize: 12.5,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const SizedBox(width: 4, child: Divider(color: Color(0xFF475569))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBuyerPendingEscrowsList() {
    if (_pendingBuyerEscrows.isEmpty) {
      return _buildEmptyCard(
        'No pending escrows yet. Escrows and direct payments will appear here.',
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF16213A),
        borderRadius: BorderRadius.circular(26),
      ),
      child: Column(
        children: _pendingBuyerEscrows.map((escrow) {
          // DEBUG: Print directPayAmount and escrowAmount for every escrow in the list
          // ignore: avoid_print
          final debugText = 'LIST DEBUG: escrowId=${escrow.id}, directPayAmount=${escrow.directPayAmount?.toString() ?? 'null'}, escrowAmount=${escrow.escrowAmount?.toString() ?? 'null'}';
          // Print to browser console for debug using JS interop
          try {
            // ignore: undefined_prefixed_name
            // ignore: unnecessary_statements
            // js.context.callMethod('console.log', [debugText]);
          } catch (_) {}

          final isDirect = escrow.isDirectPayment;
          return InkWell(
            onTap: _busy ? null : () => _openEscrowDetails(escrow),
            borderRadius: BorderRadius.circular(18),
            child: Stack(
              children: [
                _ListCardRow(
                  iconBackground: isDirect ? const Color(0xFF1E40AF) : const Color(0xFF1E3A5F),
                  icon: isDirect ? Icons.flash_on_outlined : Icons.shield_outlined,
                  iconColor: isDirect ? AppColors.amber : AppColors.cyan,
                  title: escrow.description,
                  subtitle:
                      'Seller: ${escrow.sellerName} • ${formatCurrency(escrow.amount)}',
                  amount: isDirect ? 'Direct Pay' : 'View OTP',
                  amountColor: isDirect ? AppColors.amber : AppColors.cyan,
                  badgeLabel: isDirect ? 'Direct' : 'Pending',
                  badgeColor: isDirect ? AppColors.amber : AppColors.amber,
                ),
                if (!isDirect)
                  Positioned(
                    right: 12,
                    top: 18,
                    child: IconButton(
                      icon: const Icon(Icons.vpn_key_outlined, color: AppColors.cyan),
                      tooltip: 'View OTP',
                      onPressed: _busy ? null : () => _showReleaseCodeDialog(escrow),
                    ),
                  ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildBuyerTransactionsList() {
    final items = _buyerTransactions;
    if (items.isEmpty) {
      return _buildEmptyCard(
        'No recent transactions yet. Your deposits, escrow activity, and withdrawals will appear here.',
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF16213A),
        borderRadius: BorderRadius.circular(26),
      ),
      child: Column(
        children: items
            .map(
              (transaction) => _ListCardRow(
                iconBackground: transaction.type.isPositive
                    ? const Color(0xFF0C4A3B)
                    : const Color(0xFF4C1D2F),
                icon: transaction.type.isPositive
                    ? Icons.south_west_rounded
                    : Icons.north_east_rounded,
                iconColor: transaction.type.isPositive
                    ? const Color(0xFF22C55E)
                    : const Color(0xFFF43F5E),
                title: transaction.description,
                subtitle: formatDate(transaction.createdAt),
                amount:
                    '${transaction.type.isPositive ? '+' : '-'}${formatCurrency(transaction.amount)}',
                amountColor: transaction.type.isPositive
                    ? const Color(0xFF22C55E)
                    : const Color(0xFFF43F5E),
                badgeLabel: _titleCase(transaction.status),
                badgeColor: transaction.status.toLowerCase() == 'completed'
                    ? AppColors.emerald
                    : const Color(0xFFF43F5E),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildFeaturedSellerEscrow(EscrowModel escrow) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF16213A),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ProductThumb(label: escrow.description),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        escrow.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Buyer: ${escrow.buyerName}',
                        style: const TextStyle(
                          color: Color(0xFFD1D5DB),
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Amount in Escrow: ${formatCurrency(escrow.resolvedEscrowAmount)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (escrow.hasDirectPayComponent) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Directly Paid: ${formatCurrency(escrow.resolvedDirectPayAmount)}',
                          style: const TextStyle(
                            color: AppColors.amber,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
            decoration: const BoxDecoration(color: Color(0xFF116E44)),
            child: const Row(
              children: [
                Icon(Icons.check_circle_outline, color: Color(0xFF86EFAC)),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Delivered - Awaiting Buyer Confirmation',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.schedule_outlined,
                      color: AppColors.mutedText,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _releaseAvailability(escrow),
                      style: const TextStyle(
                        color: Color(0xFFD1D5DB),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _FullWidthActionButton(
                  color: AppColors.emerald,
                  label: 'Release Funds',
                  onTap: _busy ? null : () => _openReleaseFlow(escrow),
                ),
                const SizedBox(height: 12),
                _FullWidthActionButton(
                  color: AppColors.rose,
                  label: 'Raise Dispute',
                  onTap: _busy ? null : () => _openDisputeFlow(escrow),
                ),
                const SizedBox(height: 12),
                _FullWidthActionButton(
                  color: const Color(0xFF2563EB),
                  label: 'View Details',
                  onTap: _busy ? null : () => _openEscrowDetails(escrow),
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    vertical: 14,
                    horizontal: 16,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1D2840),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Text(
                    'Tip: Only confirm release once you have received and checked the item.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFFD1D5DB), fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingSalesCard() {
    if (_pendingSellerEscrows.isEmpty) {
      return _buildEmptyCard('No pending seller escrows yet.');
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF16213A),
        borderRadius: BorderRadius.circular(26),
      ),
      child: Column(
        children: [
          for (var i = 0; i < _pendingSellerEscrows.length; i++) ...[
            _PendingSaleRow(
              escrow: _pendingSellerEscrows[i],
              onTap: () => _openEscrowDetails(_pendingSellerEscrows[i]),
            ),
            if (i != _pendingSellerEscrows.length - 1)
              Container(height: 1, color: const Color(0xFF23314F)),
          ],
          if (_withdrawalAccount == null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              child: const Text(
                'Set up a payout account to enable withdrawals.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFFD1D5DB), fontSize: 14),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFundsOverview() {
    final inEscrow = _pendingSellerEscrows.fold<double>(
      0,
      (sum, item) => sum + item.resolvedEscrowAmount,
    );
    final released = _completedSellerEscrows
        .where((e) => e.status == EscrowStatus.released)
        .fold<double>(0, (sum, item) => sum + item.amount);
    final awaiting = _pendingSellerEscrows
        .where((e) => !e.isDirectPayment)
        .fold<double>(0, (sum, item) => sum + item.resolvedEscrowAmount);

    return Row(
      children: [
        Expanded(
          child: _OverviewCard(
            label: 'In Escrow',
            value: formatCurrency(inEscrow),
            accent: AppColors.emerald,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _OverviewCard(
            label: 'Awaiting Release',
            value: formatCurrency(awaiting),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _OverviewCard(
            label: 'Total Sales',
            value: formatCurrency(released + inEscrow),
            accent: AppColors.emerald,
          ),
        ),
      ],
    );
  }

  Widget _buildSellerTransactions() {
    final sellerTransactions = _transactions
        .where(
          (transaction) =>
              transaction.type == WalletTransactionType.release ||
              transaction.type == WalletTransactionType.withdraw,
        )
        .take(5)
        .toList();

    if (sellerTransactions.isEmpty) {
      return _buildEmptyCard('No seller payout activity yet.');
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF16213A),
        borderRadius: BorderRadius.circular(26),
      ),
      child: Column(
        children: sellerTransactions.map((transaction) {
          final positive = transaction.type.isPositive;
          return _ListCardRow(
            iconBackground: positive
                ? const Color(0xFF0C4A3B)
                : const Color(0xFF4C1D2F),
            icon: positive
                ? Icons.arrow_outward_rounded
                : Icons.north_east_rounded,
            iconColor: positive
                ? const Color(0xFF22C55E)
                : const Color(0xFFF43F5E),
            title: transaction.description,
            subtitle: transaction.type == WalletTransactionType.release
                ? 'Escrow settlement'
                : 'Bank withdrawal',
            amount:
                '${positive ? '+' : '-'}${formatCurrency(transaction.amount)}',
            amountColor: positive
                ? const Color(0xFF22C55E)
                : const Color(0xFFF43F5E),
            badgeLabel: _titleCase(transaction.status),
            badgeColor: positive ? AppColors.emerald : AppColors.rose,
          );
        }).toList(),
      ),
    );
  }

  Widget _buildEmptyCard(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFF16213A),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Text(
        message,
        style: const TextStyle(color: AppColors.mutedText, fontSize: 15),
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.rose.withOpacity(0.14),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.rose.withOpacity(0.35)),
      ),
      child: Text(_error!, style: const TextStyle(color: Colors.white)),
    );
  }

  Widget _buildBottomCta() {
    if (_loading) return const SizedBox.shrink();

    final needsVerification = !_isVerified;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
        child: SizedBox(
          height: 58,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.emerald,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            onPressed: _busy
                ? null
                : needsVerification
                ? _showVerificationSheet
                : () => _showCreateEscrowDialog(directPay: false),
            icon: Icon(
              needsVerification
                  ? Icons.verified_user_outlined
                  : Icons.add_circle_outline_rounded,
            ),
            label: Text(
              needsVerification ? 'Verify Account' : 'Create Escrow',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ),
    );
  }

  String _titleCase(String value) {
    if (value.isEmpty) return value;
    return value[0].toUpperCase() + value.substring(1).toLowerCase();
  }
}

class _HeaderBell extends StatelessWidget {
  const _HeaderBell({required this.count, this.onTap});

  final int count;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            child: const Icon(
              Icons.notifications_none_rounded,
              color: Colors.white,
              size: 34,
            ),
          ),
        ),
        if (count > 0)
          Positioned(
            right: 3,
            top: 2,
            child: Container(
              width: 22,
              height: 22,
              decoration: const BoxDecoration(
                color: Color(0xFFFBBF24),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                '$count',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 20,
      decoration: BoxDecoration(
        color: const Color(0xFF16A34A),
        borderRadius: BorderRadius.circular(6),
      ),
      alignment: Alignment.center,
      child: const Icon(
        Icons.change_history_rounded,
        color: Colors.white,
        size: 16,
      ),
    );
  }
}

class _BalanceMetric extends StatelessWidget {
  const _BalanceMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12.5),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14.5,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _MetricDivider extends StatelessWidget {
  const _MetricDivider();

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 32, color: Colors.white24);
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.color,
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.wide = false,
  });

  final Color color;
  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Ink(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: wide ? 16 : 14),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(15),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 28),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: wide
                    ? CrossAxisAlignment.center
                    : CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: wide ? TextAlign.center : TextAlign.start,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      textAlign: wide ? TextAlign.center : TextAlign.start,
                      style: const TextStyle(
                        color: Color(0xFFE5E7EB),
                        fontSize: 10.5,
                        height: 1.1,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ListCardRow extends StatelessWidget {
  const _ListCardRow({
    required this.iconBackground,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.amountColor,
    this.badgeLabel,
    this.badgeColor,
  });

  final Color iconBackground;
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String amount;
  final Color amountColor;
  final String? badgeLabel;
  final Color? badgeColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF23314F))),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: iconBackground,
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: iconColor, size: 26),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFFD1D5DB),
                    fontSize: 12,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                amount,
                style: TextStyle(
                  color: amountColor,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (badgeLabel != null && badgeColor != null) ...[
                const SizedBox(height: 5),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: badgeColor!.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    badgeLabel!,
                    style: TextStyle(
                      color: badgeColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _PendingSaleRow extends StatelessWidget {
  const _PendingSaleRow({required this.escrow, required this.onTap});

  final EscrowModel escrow;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  escrow.buyerName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  escrow.sellerEmail,
                  style: const TextStyle(
                    color: Color(0xFFD1D5DB),
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${escrow.description}: Escrow ${formatCurrency(escrow.resolvedEscrowAmount)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (escrow.hasDirectPayComponent) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Direct paid: ${formatCurrency(escrow.resolvedDirectPayAmount)}',
                    style: const TextStyle(
                      color: AppColors.amber,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: onTap,
            child: const Text('View Details'),
          ),
        ],
      ),
    );
  }
}

class _OverviewCard extends StatelessWidget {
  const _OverviewCard({required this.label, required this.value, this.accent});

  final String label;
  final String value;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
      decoration: BoxDecoration(
        color: const Color(0xFF16213A),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFFD1D5DB),
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            value,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: accent ?? Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _FullWidthActionButton extends StatelessWidget {
  const _FullWidthActionButton({
    required this.color,
    required this.label,
    required this.onTap,
  });

  final Color color;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        onPressed: onTap,
        child: Text(
          label,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

class _ProductThumb extends StatelessWidget {
  const _ProductThumb({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 104,
      height: 88,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          colors: [Color(0xFF111827), Color(0xFF1D4ED8), Color(0xFFF97316)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      alignment: Alignment.center,
      child: Icon(
        label.toLowerCase().contains('phone')
            ? Icons.smartphone_rounded
            : label.toLowerCase().contains('laptop') ||
                  label.toLowerCase().contains('macbook')
            ? Icons.laptop_mac_rounded
            : Icons.inventory_2_outlined,
        color: Colors.white,
        size: 42,
      ),
    );
  }
}

class _InfoBullet extends StatelessWidget {
  const _InfoBullet({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppColors.cyan, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: Color(0xFFD1D5DB),
              fontSize: 15,
            ),
          ),
        ),
      ],
    );
  }
}

Widget _buildSectionHeader(String title) {
  return Row(
    children: [
      Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w900,
        ),
      ),
      const SizedBox(width: 10),
      const Expanded(child: Divider(color: Color(0xFF334155), thickness: 1.2)),
    ],
  );
}


class _CreateEscrowSheetBody extends StatefulWidget {
  const _CreateEscrowSheetBody({
    required this.directPay,
    required this.sellerEmailController,
    required this.sellerNameController,
    required this.sellerPhoneController,
    required this.buyerPhoneController,
    required this.descriptionController,
    required this.amountController,
    required this.directPayController,
    required this.errorNotifier,
    required this.onSubmit,
    required this.currentUserEmail,
    required this.authService,
  });

  final bool directPay;
  final TextEditingController sellerEmailController;
  final TextEditingController sellerNameController;
  final TextEditingController sellerPhoneController;
  final TextEditingController buyerPhoneController;
  final TextEditingController descriptionController;
  final TextEditingController amountController;
  final TextEditingController directPayController;
  final ValueNotifier<String?> errorNotifier;
  final void Function(Map<String, dynamic> data) onSubmit;
  final String currentUserEmail;
  final AuthService? authService;

  @override
  State<_CreateEscrowSheetBody> createState() => _CreateEscrowSheetBodyState();
}

class _CreateEscrowSheetBodyState extends State<_CreateEscrowSheetBody> {
  bool _sellerNameReadOnly = false;
  bool _sellerEmailVerified = false;

  @override
  void initState() {
    super.initState();
    widget.sellerEmailController.addListener(_onSellerEmailChanged);
  }

  @override
  void dispose() {
    widget.sellerEmailController.removeListener(_onSellerEmailChanged);
    super.dispose();
  }

  Future<void> _onSellerEmailChanged() async {
    final email = widget.sellerEmailController.text.trim();
    final currentUserEmail = widget.currentUserEmail.trim().toLowerCase();
    print('[DEBUG] Seller email entered: "$email"');
    if (email.isEmpty) {
      print('[DEBUG] Early return: email is empty');
      setState(() {
        widget.sellerNameController.text = '';
        _sellerNameReadOnly = false;
        _sellerEmailVerified = false;
      });
      return;
    }
    if (email.toLowerCase() == currentUserEmail) {
      print('[DEBUG] Early return: self-escrow detected');
      setState(() {
        widget.sellerNameController.text = '';
        _sellerNameReadOnly = false;
        _sellerEmailVerified = false;
        widget.errorNotifier.value = 'You cannot escrow to yourself. Please enter a different seller email.';
      });
      return;
    }
    final authService = widget.authService;
    if (authService == null) {
      print('[DEBUG] Early return: authService is null');
      return;
    }
    try {
      print('[DEBUG] Calling lookupVerifiedCounterparty for: $email');
      final verifiedSeller = await authService.lookupVerifiedCounterparty(email: email);
      print('[DEBUG] lookupVerifiedCounterparty returned: $verifiedSeller');
      final status = verifiedSeller['verification_status'];
      if (status == 'verified') {
        setState(() {
          widget.sellerNameController.text = verifiedSeller['full_name'];
          _sellerNameReadOnly = true;
          _sellerEmailVerified = true;
          widget.errorNotifier.value = null;
        });
      } else if (status == 'not_verified') {
        setState(() {
          widget.sellerNameController.text = verifiedSeller['full_name'] ?? '';
          _sellerNameReadOnly = true;
          _sellerEmailVerified = false;
          widget.errorNotifier.value = 'Seller exists but is not verified.';
        });
      } else {
        setState(() {
          widget.sellerNameController.text = '';
          _sellerNameReadOnly = false;
          _sellerEmailVerified = false;
          widget.errorNotifier.value = 'Seller email not found or not verified.';
        });
      }
    } catch (e, stack) {
      print('[DEBUG] lookupVerifiedCounterparty ERROR: $e');
      print('[DEBUG] Stack trace: $stack');
      setState(() {
        widget.sellerNameController.text = '';
        _sellerNameReadOnly = false;
        _sellerEmailVerified = false;
        widget.errorNotifier.value = 'Error verifying seller: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Safe to read MediaQuery here — this widget's own Element is the dependent,
    // so Flutter's scheduler can rebuild it at the right time (not during IME frames).
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomInset),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.panel,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.directPay ? 'Pay Direct' : 'Create Escrow',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  widget.directPay
                      ? 'Create a direct payment for a verified seller account.'
                      : 'Create a protected escrow transaction for a verified seller account.',
                  style: const TextStyle(color: AppColors.mutedText),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: widget.sellerEmailController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(labelText: 'Seller Email'),
                ),
                const SizedBox(height: 6),
                if (widget.sellerEmailController.text.isNotEmpty)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (_sellerEmailVerified)
                            ...[
                              Icon(Icons.check_circle, color: Colors.green, size: 20),
                              const SizedBox(width: 6),
                              const Text('Seller verified', style: TextStyle(color: Colors.green)),
                            ]
                          else
                            ...[
                              Icon(Icons.error_outline, color: Colors.red, size: 20),
                              const SizedBox(width: 6),
                              const Text('Seller not verified', style: TextStyle(color: Colors.red)),
                            ]
                        ],
                      ),
                      if (_sellerEmailVerified && widget.sellerNameController.text.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4.0, left: 2.0),
                          child: Row(
                            children: [
                              const Text('Name:', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
                              const SizedBox(width: 6),
                              Text(
                                widget.sellerNameController.text,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                const SizedBox(height: 12),
                TextField(
                  controller: widget.sellerNameController,
                  readOnly: _sellerNameReadOnly,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(labelText: 'Seller Name'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: widget.sellerPhoneController,
                  keyboardType: TextInputType.phone,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(labelText: 'Seller Phone'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: widget.buyerPhoneController,
                  keyboardType: TextInputType.phone,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(labelText: 'Buyer Phone'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: widget.descriptionController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'What are you paying for?',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: widget.amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Total Amount',
                    prefixText: '₦ ',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: widget.directPayController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Direct Pay Amount',
                    prefixText: '₦ ',
                    helperText:
                        'Amount to pay directly (rest goes to escrow)',
                  ),
                ),
                // Fee breakdown — reacts only to amountController changes
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: widget.amountController,
                  builder: (_, amtValue, __) {
                    final raw = amtValue.text.replaceAll(',', '').trim();
                    final amt = double.tryParse(raw) ?? 0;
                    if (amt <= 0) return const SizedBox.shrink();
                    final buyerFee = (amt * 0.005).toStringAsFixed(2);
                    final totalCharge = (amt * 1.005).toStringAsFixed(2);
                    final sellerReceives = (amt * 0.995).toStringAsFixed(2);
                    return Container(
                      margin: const EdgeInsets.only(top: 12),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.emerald.withAlpha(18),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.emerald.withAlpha(50),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Fee Breakdown',
                            style: TextStyle(
                              color: AppColors.emerald,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 8),
                          _FeeRow(
                            label: 'Transaction amount',
                            value: '₦ ${amt.toStringAsFixed(2)}',
                          ),
                          _FeeRow(
                            label: 'Your platform fee (0.5%)',
                            value: '₦ $buyerFee',
                          ),
                          const Divider(color: Colors.white10, height: 16),
                          _FeeRow(
                            label: 'Total debited from your wallet',
                            value: '₦ $totalCharge',
                            highlight: true,
                          ),
                          const SizedBox(height: 4),
                          _FeeRow(
                            label: 'Seller receives (after 0.5% fee)',
                            value: '₦ $sellerReceives',
                          ),
                        ],
                      ),
                    );
                  },
                ),
                // Error text
                ValueListenableBuilder<String?>(
                  valueListenable: widget.errorNotifier,
                  builder: (_, err, __) {
                    if (err == null) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        err,
                        style: const TextStyle(color: AppColors.rose),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: widget.directPay
                          ? AppColors.amber
                          : AppColors.emerald,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(54),
                    ),
                    onPressed: _sellerEmailVerified
                        ? () {
                            final amount =
                                double.tryParse(
                                  widget.amountController.text
                                      .replaceAll(',', '')
                                      .trim(),
                                ) ??
                                0;
                            final directPayAmount =
                                double.tryParse(
                                  widget.directPayController.text
                                      .replaceAll(',', '')
                                      .trim(),
                                ) ??
                                0;
                            final escrowAmount = amount - directPayAmount;
                            if (widget.sellerEmailController.text.trim().isEmpty ||
                                widget.sellerNameController.text.trim().isEmpty ||
                                widget.sellerPhoneController.text.trim().isEmpty ||
                                widget.buyerPhoneController.text.trim().isEmpty ||
                                widget.descriptionController.text.trim().isEmpty ||
                                amount <= 0) {
                              widget.errorNotifier.value =
                                  'Complete all fields with valid information.';
                              return;
                            }
                            if (directPayAmount < 0) {
                              widget.errorNotifier.value =
                                  'Direct pay amount must be positive.';
                              return;
                            }
                            if (directPayAmount > amount) {
                              widget.errorNotifier.value =
                                  'Direct pay cannot exceed total amount.';
                              return;
                            }
                            widget.onSubmit({
                              'directPay': widget.directPay,
                              'sellerName': widget.sellerNameController.text.trim(),
                              'sellerEmail': widget.sellerEmailController.text.trim(),
                              'sellerPhone': widget.sellerPhoneController.text.trim(),
                              'buyerPhone': widget.buyerPhoneController.text.trim(),
                              'description': widget.descriptionController.text.trim(),
                              'amount': amount,
                              'directPayAmount': directPayAmount,
                              'escrowAmount': escrowAmount,
                            });
                          }
                      : null,
                    child: const Text('Create Escrow'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FeeRow extends StatelessWidget {
  const _FeeRow({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: highlight ? Colors.white : AppColors.mutedText,
              fontSize: 12,
              fontWeight: highlight ? FontWeight.w700 : FontWeight.normal,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: highlight ? AppColors.emerald : Colors.white,
              fontSize: 12,
              fontWeight: highlight ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

final List<WalletTransaction> _previewTransactions = [
  WalletTransaction(
    id: 'tx-1',
    type: WalletTransactionType.withdraw,
    amount: 600000,
    description: 'Withdrawal to Moniepoint MFB',
    status: 'pending',
    createdAt: DateTime(2026, 4, 8, 18, 45),
  ),
  WalletTransaction(
    id: 'tx-2',
    type: WalletTransactionType.withdraw,
    amount: 300000,
    description: 'Withdrawal to Moniepoint MFB',
    status: 'pending',
    createdAt: DateTime(2026, 4, 8, 18, 45),
  ),
  WalletTransaction(
    id: 'tx-3',
    type: WalletTransactionType.deposit,
    amount: 5000000,
    description: 'Paystack Wallet Funding',
    status: 'completed',
    createdAt: DateTime(2026, 4, 8, 18, 41),
  ),
  WalletTransaction(
    id: 'tx-4',
    type: WalletTransactionType.deposit,
    amount: 200000,
    description: 'Paystack Wallet Funding',
    status: 'completed',
    createdAt: DateTime(2026, 4, 8, 18, 32),
  ),
  WalletTransaction(
    id: 'tx-5',
    type: WalletTransactionType.release,
    amount: 150000,
    description: 'Payout to Bank Account',
    status: 'completed',
    createdAt: DateTime(2026, 4, 6, 17, 10),
  ),
];

final List<EscrowModel> _previewEscrows = [
  EscrowModel(
    id: 'esc-1',
    buyerId: 'preview-user',
    buyerName: 'Ifeanyi Okeke',
    sellerId: 'seller-1',
    sellerName: 'Elcun Int.',
    sellerEmail: 'elcun@avinex.test',
    sellerPhone: '08011111111',
    buyerPhone: '08030000000',
    description: 'MacBook Pro 2025',
    platform: 'Avinex',
    amount: 250000,
    otp: '482913',
    reference: 'AVN-2026-482913',
    status: EscrowStatus.pending,
    createdAt: DateTime(2026, 4, 14, 10, 0),
  ),
  EscrowModel(
    id: 'esc-2',
    buyerId: 'buyer-2',
    buyerName: 'John Doe',
    sellerId: 'preview-user',
    sellerName: 'Ifeanyi Okeke',
    sellerEmail: 'johndoe@gmail.com',
    sellerPhone: '08022222222',
    buyerPhone: '08040000000',
    description: 'Gaming Laptop',
    platform: 'Avinex',
    amount: 250000,
    otp: '621404',
    reference: 'AVN-2026-250000',
    status: EscrowStatus.pending,
    createdAt: DateTime(2026, 4, 14, 9, 0),
  ),
  EscrowModel(
    id: 'esc-3',
    buyerId: 'buyer-3',
    buyerName: 'Sarah Jones',
    sellerId: 'preview-user',
    sellerName: 'Ifeanyi Okeke',
    sellerEmail: 'sarahjones123@mail.com',
    sellerPhone: '08023334444',
    buyerPhone: '08041111111',
    description: 'Smartphone',
    platform: 'Avinex',
    amount: 120000,
    otp: '819223',
    reference: 'AVN-2026-120000',
    status: EscrowStatus.pending,
    createdAt: DateTime(2026, 4, 14, 8, 0),
  ),
  EscrowModel(
    id: 'esc-4',
    buyerId: 'buyer-4',
    buyerName: 'Michael Smith',
    sellerId: 'preview-user',
    sellerName: 'Ifeanyi Okeke',
    sellerEmail: 'mike.smith456@yahoo.com',
    sellerPhone: '08025556666',
    buyerPhone: '08042222222',
    description: 'Wireless Headphones',
    platform: 'Avinex',
    amount: 75000,
    otp: '720418',
    reference: 'AVN-2026-075000',
    status: EscrowStatus.pending,
    createdAt: DateTime(2026, 4, 13, 16, 0),
  ),
  EscrowModel(
    id: 'esc-5',
    buyerId: 'preview-user',
    buyerName: 'Ifeanyi Okeke',
    sellerId: 'seller-2',
    sellerName: 'Prime Devices',
    sellerEmail: 'prime@avinex.test',
    sellerPhone: '08010000001',
    buyerPhone: '08030000000',
    description: 'Office Printer',
    platform: 'Avinex',
    amount: 180000,
    otp: 'DIRECT',
    reference: 'AVN-2026-180000',
    status: EscrowStatus.released,
    createdAt: DateTime(2026, 4, 8, 13, 0),
  ),
];
