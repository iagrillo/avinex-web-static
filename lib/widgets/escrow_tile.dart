import 'package:flutter/material.dart';
import 'dart:js' as js;

import '../core/theme/app_theme.dart';
import '../core/utils/formatters.dart';
import '../models/escrow_model.dart';

class EscrowTile extends StatelessWidget {
  const EscrowTile({
    super.key,
    required this.escrow,
    required this.sellerMode,
    this.onPrimaryTap,
    this.onSecondaryTap,
  });

  final EscrowModel escrow;
  final bool sellerMode;
  final VoidCallback? onPrimaryTap;
  final VoidCallback? onSecondaryTap;

  @override
  Widget build(BuildContext context) {
        // Print to browser console for debug
        // ignore: avoid_print
      // DEBUG: Show the actual values for diagnosis
       // DEBUG: Show the actual values for diagnosis
       final debugText = 'DEBUG: directPayAmount=${escrow.directPayAmount?.toString() ?? 'null'}, escrowAmount=${escrow.escrowAmount?.toString() ?? 'null'}';
      // Print to browser console for debug using JS interop
      js.context.callMethod('console.log', [debugText]);
    final statusColor = _statusColor(escrow.status);
    final statusIcon = _statusIcon(escrow.status);

    // Use robust payment type logic from EscrowModel
    final isMixedPayment = escrow.isMixedPayment;
    final isDirectOnly = escrow.isDirectOnly;
    final isEscrowOnly = escrow.isEscrowOnly;
    // Only show OTP actions for escrow or mixed payments (not pure direct)
    final showOtpActions = !sellerMode && onPrimaryTap != null && !isDirectOnly && !isMixedPayment;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.panelSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
                    // DEBUG: Show the actual values for diagnosis
                    Text(
                      debugText,
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                    ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: statusColor.withAlpha(35),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(statusIcon, color: statusColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      escrow.description,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${sellerMode ? 'Buyer' : 'Seller'}: ${sellerMode ? escrow.buyerName : escrow.sellerName}',
                      style: const TextStyle(color: AppColors.mutedText),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withAlpha(35),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  escrow.status.label,
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Show only relevant info pills for direct pay or escrow
          if (isDirectOnly) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _InfoPill(
                  label: formatCurrency(escrow.directPayAmount ?? escrow.amount),
                  icon: Icons.payments_outlined,
                ),
                _InfoPill(label: escrow.platform, icon: Icons.language_outlined),
                _InfoPill(label: escrow.reference, icon: Icons.tag_outlined),
                _InfoPill(label: 'Direct Pay', icon: Icons.flash_on),
              ],
            ),
          ] else ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _InfoPill(
                  label: formatCurrency(escrow.escrowAmount ?? escrow.amount),
                  icon: Icons.payments_outlined,
                ),
                _InfoPill(label: escrow.platform, icon: Icons.language_outlined),
                _InfoPill(label: escrow.reference, icon: Icons.tag_outlined),
                _InfoPill(
                  label: isMixedPayment
                      ? 'Mixed'
                      : isEscrowOnly
                          ? 'Escrow'
                          : 'Unknown',
                  icon: Icons.payment,
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Text(
            formatDate(escrow.createdAt),
            style: const TextStyle(color: AppColors.mutedText, fontSize: 12),
          ),
          // Show direct payment warning and button ONLY for true direct payments
          if (isDirectOnly)
            Padding(
              padding: const EdgeInsets.only(top: 12.0),
              child: Row(
                children: [
                  Icon(Icons.flash_on, color: AppColors.amber, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'This is a direct payment. No OTP or escrow release is required.',
                      style: const TextStyle(color: AppColors.amber, fontSize: 14),
                    ),
                  ),
                  if (!sellerMode && onPrimaryTap != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 8.0),
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.emerald,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: onPrimaryTap,
                        icon: const Icon(Icons.flash_on),
                        label: const Text('Direct Pay'),
                      ),
                    ),
                ],
              ),
            ),
          // Show OTP actions ONLY for escrow-only (not direct, not mixed)
          if (showOtpActions && isEscrowOnly) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: sellerMode
                          ? AppColors.emerald
                          : AppColors.amber,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: onPrimaryTap,
                    icon: Icon(
                      sellerMode
                          ? Icons.key_outlined
                          : Icons.visibility_outlined,
                    ),
                    label: Text(sellerMode ? 'Enter OTP' : 'View OTP'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Color(0xFF334155)),
                    ),
                    onPressed: onSecondaryTap,
                    child: Text(sellerMode ? 'Request OTP' : 'Save for later'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Color _statusColor(EscrowStatus status) {
    switch (status) {
      case EscrowStatus.pending:
        return AppColors.amber;
      case EscrowStatus.released:
        return AppColors.emerald;
      case EscrowStatus.cancelled:
        return AppColors.rose;
      case EscrowStatus.disputed:
        return Colors.purpleAccent;
    }
  }

  IconData _statusIcon(EscrowStatus status) {
    switch (status) {
      case EscrowStatus.pending:
        return Icons.schedule_outlined;
      case EscrowStatus.released:
        return Icons.check_circle_outline;
      case EscrowStatus.cancelled:
        return Icons.cancel_outlined;
      case EscrowStatus.disputed:
        return Icons.gavel_outlined;
    }
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppColors.mutedText, size: 14),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
