import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class EscrowDisclaimerDialog extends StatefulWidget {
  const EscrowDisclaimerDialog({super.key});

  @override
  State<EscrowDisclaimerDialog> createState() => _EscrowDisclaimerDialogState();
}

class _EscrowDisclaimerDialogState extends State<EscrowDisclaimerDialog> {
  bool _agreed = false;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 520,
        constraints: const BoxConstraints(maxHeight: 600),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.panel,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFF334155)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'PAYMENT & ESCROW DISCLAIMER',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: SingleChildScrollView(
                child: Text(
                  'AVINEX\nSecure Escrow & Payment Platform\n\n'
                  'PAYMENT & ESCROW DISCLAIMER\n'
                  'Terms Acknowledged Prior to Fund Commitment\n'
                  'Version 1.0  |  Effective Date: 7 May 2026\n\n'
                  '⚠  IMPORTANT NOTICE: You are about to commit funds on the Avinex platform. Read this document carefully and completely before proceeding. By clicking "Confirm & Pay," you confirm that you have read, understood, and agreed to every term stated herein.\n\n'
                  '1.  PARTIES TO THIS TRANSACTION\n\n'
                  'This disclaimer governs the relationship between:\n'
                  '• Avinex Technologies ("Avinex," "Platform," "we," "us") — the neutral technology intermediary facilitating payment processing and escrow holding services;\n'
                  '• The Buyer ("you," "Payer") — the party initiating and funding this transaction;\n'
                  '• The Seller ("Counterparty," "Recipient") — the party receiving payment upon fulfilment of agreed conditions.\n'
                  'Avinex is not a party to the underlying commercial transaction between Buyer and Seller.\n\n'
                  '2.  PAYMENT TYPES AND HOW THEY WORK\n\n'
                  '2A.  Direct Payment\n'
                  'When you select Direct Payment, your funds are transferred immediately and irrevocably to the Seller upon your confirmation. You expressly acknowledge that:\n'
                  '• Funds credited to the Seller under a Direct Payment cannot be recalled, reversed, or refunded by Avinex under any circumstances;\n'
                  '• Avinex bears no liability for goods or services not delivered following a Direct Payment;\n'
                  '• Direct Payment is appropriate only where you have an existing, established trust relationship with the Seller and do not require Avinex\'s escrow protection.\n\n'
                  '2B.  Escrow Payment\n'
                  'When you select Escrow Payment, your funds are held securely by Avinex in a ring-fenced escrow balance on your behalf. You acknowledge that:\n'
                  '• Funds remain in escrow and are not accessible to the Seller until a valid One-Time Password (OTP) is presented;\n'
                  '• The OTP is generated exclusively by Avinex and delivered only to the Buyer (the party who created and funded the escrow);\n'
                  '• You, as Buyer, must share the OTP with the Seller only after you are personally satisfied that the agreed goods, services, or deliverables have been received to your satisfaction;\n'
                  '• Sharing the OTP constitutes your irrevocable authorisation to release the escrow funds to the Seller;\n'
                  '• Avinex will process the release upon valid OTP submission and cannot reverse a completed release.\n\n'
                  '3.  ONE-TIME PASSWORD (OTP) — CRITICAL OBLIGATIONS\n\n'
                  '⚠  IMPORTANT NOTICE: The OTP is the sole mechanism for releasing escrow funds. Treat it with the same care as your bank PIN. Never share it until you have confirmed satisfactory delivery.\n\n'
                  'You further agree that:\n'
                  '• If you share the OTP with the Seller and subsequently claim that delivery was not made, Avinex shall not be obligated to reverse the transaction, as OTP submission constitutes conclusive release authorisation;\n'
                  '• You must not share the OTP via unsecured channels (e.g., unverified phone numbers, social media) without due care;\n'
                  '• Avinex will never ask you for your OTP via phone, email, or chat support. Any person requesting your OTP claiming to be an Avinex representative is engaging in fraud — report immediately to support@avinex.com.\n\n'
                  '4.  AVINEX\'S ROLE — SCOPE AND LIMITATIONS\n\n'
                  'Avinex provides technology infrastructure for payment and escrow processing. You expressly acknowledge and agree that:\n'
                  '• Avinex is NOT a party to the commercial agreement between Buyer and Seller and does not verify, warrant, inspect, or guarantee the quality, quantity, authenticity, legality, or fitness of any goods, services, digital products, or deliverables forming the subject of any transaction;\n'
                  '• Avinex is NOT liable for product defects, misrepresentation, non-delivery, delays, or any dispute arising from the underlying commercial transaction between the parties;\n'
                  '• Avinex does NOT provide insurance, indemnity, or guarantee of any transaction outcome;\n'
                  '• Avinex\'s sole obligation is to hold escrow funds securely and release them in accordance with OTP validation or a concluded dispute resolution process.\n\n'
                  '5.  DISPUTE RESOLUTION — BUYER AND SELLER OBLIGATIONS\n\n'
                  '5A.  Buyer\'s Right to Raise a Dispute\n'
                  'If you are the Buyer and you have concerns regarding non-delivery, partial delivery, or misrepresentation, you may raise a formal dispute through the Avinex platform before sharing the OTP. Avinex will acknowledge your complaint and facilitate communication between the parties.\n\n'
                  '5B.  Seller\'s 24-Hour Response Obligation\n'
                  '24-HOUR RESPONSE WINDOW — SELLER\'S OBLIGATION\n'
                  'Where a Buyer raises a complaint or dispute — including a complaint that the OTP has not been provided — the Seller (the party who created the escrow) has a mandatory window of twenty-four (24) hours from the time of notification to respond, file a counter-complaint, or provide evidence of fulfilment through the Avinex platform. Failure to respond within this window shall entitle Avinex to commence dispute adjudication in favour of the Buyer as a default position, which may result in the escrow funds being returned to the Buyer\'s wallet.\n\n'
                  'Both parties acknowledge that:\n'
                  '• Avinex acts as a neutral facilitator and not as an arbitrator or court of law;\n'
                  '• Avinex\'s dispute resolution mechanism is commercially reasonable but not legally binding beyond the scope of fund release decisions on the platform;\n'
                  '• Avinex reserves the right to request evidence, documentation, and communications from both parties during the dispute process;\n'
                  '• Where evidence is inconclusive, Avinex may at its sole discretion split the escrow funds, extend the dispute window, or escalate to external mediation;\n'
                  '• Avinex is not responsible for losses arising from fraudulent activity perpetrated by either party and reserves the right to report such activity to the Nigeria Financial Intelligence Unit (NFIU) and other relevant authorities.\n\n'
                  '6.  PLATFORM FEES\n\n'
                  'By proceeding, you acknowledge and consent to the following non-refundable platform service fees:\n'
                  'Fee Type\tRate\tCharged To\n'
                  'Buyer Platform Fee\t0.5% of transaction amount\tBuyer (deducted on payment)\n'
                  'Seller Platform Fee\t0.5% of transaction amount\tSeller (deducted on release)\n\n'
                  'Platform fees are non-refundable once a transaction has been initiated, regardless of the outcome of any dispute.\n\n'
                  '7.  PROHIBITED TRANSACTIONS\n\n'
                  'You certify that this transaction does not involve any of the following:\n'
                  '• Proceeds of unlawful activity, money laundering, or terrorism financing contrary to the Money Laundering (Prevention and Prohibition) Act 2022 and the Terrorism (Prevention and Prohibition) Act 2022;\n'
                  '• Purchase or sale of prohibited goods, controlled substances, weapons, counterfeit items, or any commodity illegal under Nigerian law;\n'
                  '• Any transaction designed to defraud, deceive, or manipulate the counterparty or the Avinex platform.\n'
                  'Violation of this clause constitutes grounds for immediate account suspension, fund freezing, and mandatory referral to law enforcement authorities.\n\n'
                  '8.  GOVERNING LAW & JURISDICTION\n\n'
                  'This disclaimer and all transactions conducted on the Avinex platform are governed exclusively by the laws of the Federal Republic of Nigeria, including but not limited to:\n'
                  '• Federal Competition and Consumer Protection Act (FCCPA) 2018;\n'
                  '• Central Bank of Nigeria (CBN) Payment Systems Management Act 2020;\n'
                  '• Nigeria Data Protection Act (NDPA) 2023;\n'
                  '• Electronic Transactions Bill (as applicable).\n'
                  'Any dispute arising from the use of the Avinex platform that cannot be resolved internally shall be submitted to the courts of the Federal Capital Territory, Abuja, Nigeria, or by mutual written agreement, to arbitration under the Arbitration and Mediation Act 2023.\n\n'
                  '9.  BUYER\'S DECLARATION & ACKNOWLEDGEMENT\n\n'
                  'By proceeding past this screen and confirming your payment, you irrevocably declare that:\n'
                  '(a) You have read and understood this entire disclaimer; (b) You are at least 18 years of age and legally competent to enter into binding commitments; (c) You are acting on your own behalf or have lawful authority to act on behalf of a registered entity; (d) The funds being committed are lawfully obtained and owned by you; (e) You accept the terms herein without duress, coercion, or misrepresentation; (f) You understand the distinction between Direct Payment and Escrow Payment and have chosen your payment type knowingly; (g) You understand that Avinex is not liable for the quality or delivery of goods and services but will assist in dispute resolution in good faith.\n\n'
                  '10.  EXECUTION\n\n'
                  'For in-app transactions, acceptance is recorded electronically upon clicking "Confirm & Pay." For manually executed agreements, sign below:\n\n'
                  'Buyer Full Name:  ________________________________________________\n\n'
                  'Buyer Signature:  ________________________________________________\n\n'
                  'Date:  ________________________________________________\n\n'
                  'Avinex Reference / Escrow ID:  ________________________________________________\n\n'
                  'Avinex Technologies  |  support@avinex.com  |  www.avinex.com\n'
                  'This disclaimer does not constitute legal advice. Parties are encouraged to seek independent legal counsel for complex transactions.\n',
                  style: TextStyle(color: Colors.white, fontSize: 14, height: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Checkbox(
                  value: _agreed,
                  onChanged: (v) => setState(() => _agreed = v ?? false),
                  activeColor: AppColors.emerald,
                ),
                const Expanded(
                  child: Text(
                    'I have read and agree to the above terms and disclaimer.',
                    style: TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: _agreed ? () => Navigator.of(context).pop(true) : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.emerald,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: const Text('Confirm & Pay', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Color(0xFF334155)),
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
