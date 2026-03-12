// BkashMobileAccountPage.dart
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class BkashMobileAccountPage extends StatefulWidget {
  final String accountId;
  final Map<String, dynamic> accountData;

  const BkashMobileAccountPage({
    super.key,
    required this.accountId,
    required this.accountData,
  });

  @override
  State<BkashMobileAccountPage> createState() => _BkashMobileAccountPageState();
}

class _BkashMobileAccountPageState extends State<BkashMobileAccountPage> {
  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  static const Color _bgStart = Color(0xFF041A14);
  static const Color _bgEnd = Color(0xFF0E5A42);
  static const Color _accent = Color(0xFFFFD166);

  bool _isSubmitting = false;
  bool _isDialogOpen = false;
  bool _isClearing = false;

  ThemeData _dialogTheme(BuildContext context) {
    final base = Theme.of(context);
    return base.copyWith(
      dialogBackgroundColor: _bgEnd,
      colorScheme: base.colorScheme.copyWith(
        surface: _bgEnd,
        onSurface: Colors.white,
        primary: _accent,
      ),
      textTheme: base.textTheme.apply(bodyColor: Colors.white, displayColor: Colors.white),
      inputDecorationTheme: const InputDecorationTheme(
        labelStyle: TextStyle(color: Colors.white70),
        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white30)),
        focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: _accent)),
      ),
      dividerColor: Colors.white24,
    );
  }

  Widget _buildBackdrop() {
    return Stack(
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_bgStart, _bgEnd],
            ),
          ),
        ),
        Positioned(
          top: -120,
          right: -80,
          child: Container(
            width: 240,
            height: 240,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [_accent.withOpacity(0.35), Colors.transparent],
              ),
            ),
          ),
        ),
        Positioned(
          bottom: -140,
          left: -90,
          child: Container(
            width: 260,
            height: 260,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [Colors.white.withOpacity(0.18), Colors.transparent],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> _accountStream() {
    return firestore.collection('bkash_mobile_accounts').doc(widget.accountId).snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _transactionsStream() {
    return firestore
        .collection('bkash_mobile_accounts')
        .doc(widget.accountId)
        .collection('transactions')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  Future<void> _submitTransaction(String type, double amount, {String? note}) async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);
    try {
      final accRef = firestore.collection('bkash_mobile_accounts').doc(widget.accountId);
      final txRef = accRef.collection('transactions').doc();
      await firestore.runTransaction((tx) async {
        final snap = await tx.get(accRef);
        if (!snap.exists) {
          throw Exception('Account not found');
        }
        final data = snap.data() as Map<String, dynamic>? ?? {};
        final balRaw = data['balance'] ?? 0;
        final current = (balRaw is num) ? balRaw.toDouble() : double.tryParse(balRaw.toString()) ?? 0.0;
        if (type == 'send' && amount > current) {
          throw Exception('Amount exceeds current balance');
        }
        final newBalance = type == 'receive' ? current + amount : current - amount;
        tx.update(accRef, {
          'balance': newBalance,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        tx.set(txRef, {
          'type': type,
          'amount': amount,
          'note': (note == null || note.trim().isEmpty) ? null : note.trim(),
          'balanceAfter': newBalance,
          'createdAt': FieldValue.serverTimestamp(),
        });
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(type == 'receive' ? 'Received successfully' : 'Sent successfully')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    } finally {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
    }
  }

  Future<void> _openAmountDialog(String type, double currentBalance) async {
    if (_isDialogOpen) return;
    _isDialogOpen = true;
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    bool isSaving = false;

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setState) => Theme(
          data: _dialogTheme(context),
          child: AlertDialog(
            backgroundColor: _bgEnd,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(color: Colors.white.withOpacity(0.12)),
            ),
            title: Text(type == 'receive' ? 'Receive Money' : 'Send Money'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: amountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Amount'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: noteCtrl,
                    decoration: const InputDecoration(labelText: 'Note (optional)'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSaving ? null : () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: isSaving
                    ? null
                    : () async {
                        if (isSaving) return;
                        setState(() => isSaving = true);
                        try {
                          final amt = double.tryParse(amountCtrl.text.trim()) ?? 0.0;
                          if (amt <= 0) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter valid amount')));
                            return;
                          }
                          if (type == 'send' && amt > currentBalance) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Amount exceeds current balance')));
                            return;
                          }
                          await _submitTransaction(type, amt, note: noteCtrl.text.trim());
                          if (!context.mounted) return;
                          Navigator.pop(context);
                        } finally {
                          if (!context.mounted) return;
                          setState(() => isSaving = false);
                        }
                      },
                child: Text(isSaving ? 'Saving...' : 'Save'),
              ),
            ],
          ),
        ),
      ),
    );
    _isDialogOpen = false;
  }

  Future<void> _clearTransactions() async {
    if (_isClearing) return;
    bool isConfirming = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setState) => Theme(
          data: _dialogTheme(context),
          child: AlertDialog(
            backgroundColor: _bgEnd,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(color: Colors.white.withOpacity(0.12)),
            ),
            title: const Text('Clear transactions?'),
            content: const Text('This will remove all transaction history. Balance will not change.'),
            actions: [
              TextButton(
                onPressed: isConfirming ? null : () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: isConfirming
                    ? null
                    : () {
                        if (isConfirming) return;
                        setState(() => isConfirming = true);
                        Navigator.pop(context, true);
                      },
                child: Text(isConfirming ? 'Clearing...' : 'Clear'),
              ),
            ],
          ),
        ),
      ),
    );
    if (ok != true) return;
    setState(() => _isClearing = true);
    try {
      final txCol = firestore.collection('bkash_mobile_accounts').doc(widget.accountId).collection('transactions');
      final snap = await txCol.get();
      if (snap.docs.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No transactions to clear')));
        return;
      }
      const chunkSize = 400;
      final refs = snap.docs.map((d) => d.reference).toList();
      for (var i = 0; i < refs.length; i += chunkSize) {
        final batch = firestore.batch();
        final end = (i + chunkSize) > refs.length ? refs.length : (i + chunkSize);
        for (var j = i; j < end; j++) {
          batch.delete(refs[j]);
        }
        await batch.commit();
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Transactions cleared')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to clear: $e')));
    } finally {
      if (!mounted) return;
      setState(() => _isClearing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final initialMobile = (widget.accountData['mobile'] ?? widget.accountData['mobileDigits'] ?? '').toString();
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: Text(
          initialMobile.isEmpty ? 'Bkash Mobile' : initialMobile,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18),
        ),
        actions: [
          IconButton(
            tooltip: 'Clear transactions',
            onPressed: _isClearing ? null : _clearTransactions,
            icon: _isClearing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.delete_sweep, color: Colors.white),
          ),
        ],
      ),
      body: Stack(
        children: [
          _buildBackdrop(),
          SafeArea(
            child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: _accountStream(),
              builder: (context, snap) {
                final data = snap.data?.data() ?? widget.accountData;
                final mobile = (data['mobile'] ?? data['mobileDigits'] ?? '').toString();
                final balRaw = data['balance'] ?? 0;
                final balance = (balRaw is num) ? balRaw.toDouble() : double.tryParse(balRaw.toString()) ?? 0.0;
                final balColor = balance >= 0 ? Colors.greenAccent : Colors.redAccent;
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.white.withOpacity(0.18)),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: _accent.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  alignment: Alignment.center,
                                  child: const Icon(Icons.phone_android, color: _accent),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        mobile.isEmpty ? 'Bkash Mobile' : mobile,
                                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
                                      ),
                                      const SizedBox(height: 4),
                                      Text('Balance', style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12)),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: balColor.withOpacity(0.18),
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(color: balColor.withOpacity(0.45)),
                                  ),
                                  child: Text(
                                    "\u09F3${balance.toStringAsFixed(2)}",
                                    style: TextStyle(color: balColor, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.06),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.white.withOpacity(0.16)),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: _isSubmitting ? null : () => _openAmountDialog('receive', balance),
                                    icon: const Icon(Icons.call_received),
                                    label: const Text('Receive'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: _isSubmitting ? null : () => _openAmountDialog('send', balance),
                                    icon: const Icon(Icons.call_made),
                                    label: const Text('Send'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.orange,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Transactions',
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                          stream: _transactionsStream(),
                          builder: (context, txSnap) {
                            if (txSnap.connectionState == ConnectionState.waiting) {
                              return const Center(child: CircularProgressIndicator(color: Colors.white));
                            }
                            final docs = txSnap.data?.docs ?? [];
                            if (docs.isEmpty) {
                              return const Center(
                                child: Text('No transactions yet', style: TextStyle(color: Colors.white70)),
                              );
                            }
                            return ListView.separated(
                              itemCount: docs.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 6),
                              itemBuilder: (_, i) {
                                final m = docs[i].data();
                                final type = (m['type'] ?? '').toString();
                                final amountRaw = m['amount'] ?? 0;
                                final amount = (amountRaw is num) ? amountRaw.toDouble() : double.tryParse(amountRaw.toString()) ?? 0.0;
                                final createdAt = m['createdAt'] as Timestamp?;
                                final timeStr = createdAt != null ? DateFormat('hh:mm a, dd MMM yyyy').format(createdAt.toDate()) : '';
                                final note = (m['note'] ?? '').toString();
                                final isReceive = type == 'receive';
                                final color = isReceive ? Colors.greenAccent : Colors.redAccent;
                                return Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.08),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: Colors.white.withOpacity(0.16)),
                                  ),
                                  child: ListTile(
                                    title: Text(
                                      isReceive ? 'Receive' : 'Send',
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                                    ),
                                    subtitle: Text(
                                      note.isEmpty ? timeStr : '$note\n$timeStr',
                                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                                    ),
                                    trailing: Text(
                                      "${isReceive ? '+' : '-'}\u09F3${amount.toStringAsFixed(2)}",
                                      style: TextStyle(color: color, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
