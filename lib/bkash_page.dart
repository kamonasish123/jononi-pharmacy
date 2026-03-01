// bkash_page.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class BkashPage extends StatefulWidget {
  const BkashPage({super.key});

  @override
  State<BkashPage> createState() => _BkashPageState();
}

class _BkashPageState extends State<BkashPage> {
  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  static const Color _bgStart = Color(0xFF041A14);
  static const Color _bgEnd = Color(0xFF0E5A42);
  static const Color _accent = Color(0xFFFFD166);

  DateTime selectedDate = DateTime.now();
  String get dateString => DateFormat('yyyy-MM-dd').format(selectedDate);

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

  Widget _sheetAction({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color? iconColor,
  }) {
    final color = iconColor ?? _accent;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withOpacity(0.18),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white54),
          ],
        ),
      ),
    );
  }

  Widget _sheetSection({
    required String title,
    required String subtitle,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style:
                  const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(subtitle,
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  ThemeData _dialogTheme(BuildContext context) {
    final base = Theme.of(context);
    return base.copyWith(
      dialogBackgroundColor: _bgEnd,
      colorScheme: base.colorScheme.copyWith(
        surface: _bgEnd,
        onSurface: Colors.white,
        primary: _accent,
      ),
      textTheme:
          base.textTheme.apply(bodyColor: Colors.white, displayColor: Colors.white),
      listTileTheme: const ListTileThemeData(
        textColor: Colors.white,
        iconColor: Colors.white70,
      ),
      iconTheme: const IconThemeData(color: Colors.white70),
      inputDecorationTheme: const InputDecorationTheme(
        labelStyle: TextStyle(color: Colors.white70),
        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white30)),
        focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: _accent)),
      ),
      dividerColor: Colors.white24,
    );
  }

  Future<void> pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2023),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => selectedDate = picked);
  }

  Stream<QuerySnapshot> transactionsStream(String date) {
    return firestore
        .collection('bkash')
        .doc(date)
        .collection('transactions')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  /// Select existing Bkash customer or create new (ensures uniqueness).
  /// Returns map {'id': id, 'name': name} or null.
  Future<Map<String, String>?> _selectOrCreateBkashCustomerDialog(BuildContext ctx, {String initial = ''}) async {
    String search = initial.toLowerCase();
    return showDialog<Map<String, String>?>(
      context: ctx,
      builder: (dctx) {
        final controller = TextEditingController(text: initial);
        return StatefulBuilder(builder: (context, setState) {
          return Theme(
            data: _dialogTheme(context),
            child: AlertDialog(
              backgroundColor: _bgEnd,
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: Colors.white24),
              ),
              title: const Text('Select / Create Bkash Customer'),
              content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: controller,
                    decoration: const InputDecoration(labelText: 'Search or type name'),
                    onChanged: (v) => setState(() => search = v.trim().toLowerCase()),
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    child: StreamBuilder<QuerySnapshot>(
                      stream: (search.isEmpty)
                          ? firestore.collection('bkash_customers').orderBy('nameLower').limit(50).snapshots()
                          : firestore
                          .collection('bkash_customers')
                          .orderBy('nameLower')
                          .startAt([search])
                          .endAt([search + '\uf8ff'])
                          .limit(50)
                          .snapshots(),
                      builder: (context, snap) {
                        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                        final docs = snap.data!.docs;
                        if (docs.isEmpty) return const Center(child: Text('No accounts found'));
                        return ListView.separated(
                          shrinkWrap: true,
                          itemCount: docs.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1, color: Colors.white24),
                          itemBuilder: (_, i) {
                            final d = docs[i];
                            final data = d.data() as Map<String, dynamic>;
                            final name = data['name'] ?? '';
                            final addr = data['address'] ?? '';
                            return ListTile(
                              title: Text(name),
                              subtitle: Text(addr.toString()),
                              onTap: () {
                                Navigator.pop(context, {'id': d.id, 'name': name.toString()});
                              },
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('Cancel')),
                TextButton(
                  onPressed: () async {
                    final typed = controller.text.trim();
                    if (typed.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Type a name to create')));
                      return;
                    }
                    final lower = typed.toLowerCase();
                    final existsQ = await firestore.collection('bkash_customers').where('nameLower', isEqualTo: lower).limit(1).get();
                    if (existsQ.docs.isNotEmpty) {
                      // already exists -> return that and inform user
                      final ex = existsQ.docs.first;
                      Navigator.pop(context, {'id': ex.id, 'name': (ex.data() as Map<String, dynamic>)['name']?.toString() ?? typed});
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Customer already exists - selected existing account')));
                      return;
                    }
                    // create new
                    final newRef = firestore.collection('bkash_customers').doc();
                    await newRef.set({
                      'name': typed,
                      'nameLower': lower,
                      'phone': null,
                      'address': null,
                      'balance': 0.0,
                      'createdAt': FieldValue.serverTimestamp(),
                    });
                    Navigator.pop(context, {'id': newRef.id, 'name': typed});
                  },
                  child: const Text('Create / Select'),
                ),
              ],
            ),
          );
        });
      },
    );
  }

  /// Main dialog to create / edit a transaction.
  Future<void> openTransactionDialog({
    Map<String, dynamic>? initial,
    String mode = 'bkash', // 'bkash' or 'transaction'
    required String action, // 'send' or 'receive'
    String? docId,
  }) async {
    final phoneController = TextEditingController(text: initial?['phone'] ?? '');
    final pinController = TextEditingController(text: initial?['pin'] ?? '');
    final amountController = TextEditingController(text: initial?['amount']?.toString() ?? '');
    final percentController = TextEditingController(text: initial?['percent']?.toString() ?? '2');
    final finalAmountController = TextEditingController(text: initial?['finalAmount']?.toString() ?? '');
    final referenceController = TextEditingController(text: initial?['reference'] ?? '');
    final nameController = TextEditingController(text: initial?['name'] ?? (action == 'receive' ? 'Receive' : ''));

    String? selectedCustomerId = initial?['customerId'] as String?;
    String? selectedCustomerName = selectedCustomerId != null ? (initial?['reference'] as String?) : null;

    // if editing, fetch old data for revert
    Map<String, dynamic>? oldDocData;
    if (docId != null) {
      final snap = await firestore.collection('bkash').doc(dateString).collection('transactions').doc(docId).get();
      if (snap.exists) oldDocData = snap.data() as Map<String, dynamic>?;
    }

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (context, setState) {
          void recomputeFinalFromAmount() {
            final a = double.tryParse(amountController.text) ?? 0.0;
            final p = double.tryParse(percentController.text) ?? 0.0;
            final computed = a + a * (p / 100.0);
            finalAmountController.text = computed.toStringAsFixed(2);
          }

          final isBkash = mode == 'bkash';
          final isSend = action == 'send';
          final isReceive = action == 'receive';
          final title = (isBkash ? 'Bkash' : 'Transaction') + ' — ${isSend ? 'Send' : 'Receive'}';

          if (isBkash && isSend && (finalAmountController.text.isEmpty && amountController.text.isNotEmpty)) {
            recomputeFinalFromAmount();
          }

          return Theme(
            data: _dialogTheme(context),
            child: AlertDialog(
              backgroundColor: _bgEnd,
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: Colors.white24),
              ),
              title: Text(title),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                  if (isBkash) ...[
                    TextField(
                      controller: phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(labelText: 'Phone number'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: pinController,
                      keyboardType: TextInputType.number,
                      obscureText: false,
                      decoration: const InputDecoration(labelText: 'PIN (required)'),
                    ),
                    const SizedBox(height: 12),
                  ] else ...[
                    TextField(
                      controller: nameController,
                      decoration: InputDecoration(labelText: 'Name', hintText: action == 'receive' ? 'Receive' : ''),
                    ),
                    const SizedBox(height: 12),
                  ],

                  if (isSend) ...[
                    TextField(
                      controller: amountController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Amount'),
                      onChanged: (_) {
                        if (isBkash && isSend) recomputeFinalFromAmount();
                        setState(() {});
                      },
                    ),
                    const SizedBox(height: 8),
                    if (isBkash && isSend) ...[
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: percentController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(labelText: 'Percentage (%)', hintText: '2'),
                              onChanged: (_) => recomputeFinalFromAmount(),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 3,
                            child: TextField(
                              controller: finalAmountController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(labelText: 'Final amount (editable)'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ] else ...[
                      TextField(
                        controller: finalAmountController..text = (finalAmountController.text.isNotEmpty ? finalAmountController.text : amountController.text),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Final amount (editable)'),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ] else ...[
                    TextField(
                      controller: finalAmountController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Final amount (required)'),
                    ),
                    const SizedBox(height: 8),
                  ],

                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: referenceController,
                          decoration: const InputDecoration(labelText: 'Reference (optional)'),
                          readOnly: false,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Pick / Create Bkash customer',
                        icon: const Icon(Icons.person_search),
                        onPressed: () async {
                          final pick = await _selectOrCreateBkashCustomerDialog(context, initial: referenceController.text);
                          if (pick != null) {
                            selectedCustomerId = pick['id'];
                            selectedCustomerName = pick['name'];
                            referenceController.text = selectedCustomerName ?? '';
                            setState(() {});
                          }
                        },
                      )
                    ],
                  ),
                ],
              ),
            ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                ElevatedButton(
                  onPressed: () async {
                  final finalAmount = double.tryParse(finalAmountController.text.trim()) ??
                      (isSend ? (double.tryParse(amountController.text.trim()) ?? 0.0) : 0.0);
                  final percent = double.tryParse(percentController.text.trim()) ?? (isBkash && isSend ? 2.0 : 0.0);
                  final amount = double.tryParse(amountController.text.trim()) ?? 0.0;

                  if (finalAmount <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid final amount')));
                    return;
                  }
                  if (isBkash && (pinController.text.trim().isEmpty)) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PIN is required for Bkash operations')));
                    return;
                  }

                  final col = firestore.collection('bkash').doc(dateString).collection('transactions');

                  // If editing: revert old customer effect if any
                  if (docId != null && oldDocData != null) {
                    final oldCustomerId = (oldDocData['customerId'] as String?);
                    final oldFinal = ((oldDocData['finalAmount'] ?? oldDocData['amount'] ?? 0) as num).toDouble();
                    final oldAction = (oldDocData['action'] ?? '').toString();

                    if (oldCustomerId != null) {
                      final custRef = firestore.collection('bkash_customers').doc(oldCustomerId);
                      if (oldAction == 'receive') {
                        await custRef.update({'balance': FieldValue.increment(-oldFinal)});
                      } else if (oldAction == 'send') {
                        await custRef.update({'balance': FieldValue.increment(oldFinal)});
                      }
                    }
                  }

                  // Save main transaction (contains reference so Bkash sell page sees it)
                  final txData = <String, dynamic>{
                    'mode': mode,
                    'action': action,
                    'phone': isBkash ? phoneController.text.trim() : null,
                    'pin': isBkash ? pinController.text.trim() : null,
                    'name': !isBkash ? (nameController.text.trim().isNotEmpty ? nameController.text.trim() : null) : null,
                    'amount': isSend ? amount : null,
                    'percent': (isBkash && isSend) ? percent : null,
                    'finalAmount': finalAmount,
                    'reference': referenceController.text.trim().isEmpty ? null : referenceController.text.trim(),
                    'customerId': selectedCustomerId, // may be null
                    'createdAt': FieldValue.serverTimestamp(),
                  };

                  // Save or update main transaction and capture the doc id
                  String originTxId;
                  if (docId != null) {
                    await col.doc(docId).update(txData);
                    originTxId = docId;
                  } else {
                    final docRef = await col.add(txData);
                    originTxId = docRef.id;
                  }

                  // If a customer selected, update customer's balance and add per-customer transaction
                  if (selectedCustomerId != null) {
                    final custRef = firestore.collection('bkash_customers').doc(selectedCustomerId);
                    final amt = finalAmount;

                    // Build per-customer transaction payload containing the useful fields (phone/pin/amount/percent/finalAmount/mode/action/name).
                    // We intentionally omit 'reference' here (account context is implied).
                    final perCustTx = <String, dynamic>{
                      'type': action, // 'receive' or 'send'
                      'mode': mode,
                      'amount': isSend ? amount : null,
                      'finalAmount': amt,
                      'phone': isBkash ? phoneController.text.trim() : null,
                      'pin': isBkash ? pinController.text.trim() : null,
                      'percent': (isBkash && isSend) ? percent : null,
                      'name': !isBkash ? (nameController.text.trim().isNotEmpty ? nameController.text.trim() : null) : null, // <-- ADDED: include name for transaction mode
                      'originTxId': originTxId,
                      'createdAt': FieldValue.serverTimestamp(),
                      'fromDate': dateString,
                      'meta': {'originMode': mode},
                    };

                    if (action == 'receive') {
                      await custRef.update({'balance': FieldValue.increment(amt)});
                      // add per-customer transaction (no 'reference' field)
                      await custRef.collection('transactions').add(perCustTx);
                    } else {
                      await custRef.update({'balance': FieldValue.increment(-amt)});
                      await custRef.collection('transactions').add(perCustTx);
                    }
                  }

                  Navigator.pop(context);
                },
                  child: const Text('Save'),
                ),
              ],
            ),
          );
        });
      },
    );
  }

  Future<void> editTransaction(String id, Map<String, dynamic> data) async {
    final mode = (data['mode'] ?? 'bkash').toString();
    final action = (data['action'] ?? 'send').toString();
    await openTransactionDialog(initial: data, mode: mode, action: action, docId: id);
  }

  Future<void> deleteTransaction(String id, Map<String, dynamic>? data) async {
    final col = firestore.collection('bkash').doc(dateString).collection('transactions');
    final snap = await col.doc(id).get();
    if (!snap.exists) return;
    final d = snap.data() as Map<String, dynamic>? ?? {};
    final custId = d['customerId'] as String?;
    final finalAmt = ((d['finalAmount'] ?? d['amount'] ?? 0) as num).toDouble();
    final action = (d['action'] ?? '').toString();

    final batch = firestore.batch();
    if (custId != null) {
      final custRef = firestore.collection('bkash_customers').doc(custId);
      if (action == 'receive') {
        batch.update(custRef, {'balance': FieldValue.increment(-finalAmt)});
      } else if (action == 'send') {
        batch.update(custRef, {'balance': FieldValue.increment(finalAmt)});
      }
      // we don't attempt to delete per-customer transaction doc(s) here
    }
    batch.delete(col.doc(id));
    await batch.commit();
  }

  Future<void> deleteTransactionUI(String docId, Map<String, dynamic>? data) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => Theme(
        data: _dialogTheme(context),
        child: AlertDialog(
          backgroundColor: _bgEnd,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: Colors.white24),
          ),
          title: const Text('Delete transaction?'),
          content: const Text('This will remove the transaction permanently and revert linked account balance.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
          ],
        ),
      ),
    );
    if (ok == true) {
      await deleteTransaction(docId, data);
    }
  }

    @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: transactionsStream(dateString),
      builder: (context, snap) {
        double totalReceive = 0.0;
        double totalSend = 0.0;
        final docs = snap.data?.docs ?? [];
        for (final d in docs) {
          final data = d.data() as Map<String, dynamic>? ?? {};
          final action = (data['action'] ?? '').toString();
          final finalAmount = ((data['finalAmount'] ?? data['amount'] ?? 0) as num).toDouble();
          if (action == 'receive') totalReceive += finalAmount;
          if (action == 'send') totalSend += finalAmount;
        }

        return Scaffold(
          backgroundColor: Colors.transparent,
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            title: const Text(
              'Bkash',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white),
            ),
            elevation: 0,
            backgroundColor: Colors.transparent,
            actions: [
              IconButton(icon: const Icon(Icons.calendar_today), onPressed: pickDate),
            ],
          ),
          floatingActionButton: FloatingActionButton(
            backgroundColor: _accent,
            child: const Icon(Icons.add, color: Colors.black),
            onPressed: () async {
              await showModalBottomSheet(
                context: context,
                backgroundColor: Colors.transparent,
                isScrollControlled: true,
                builder: (_) {
                  final sheetHeight = MediaQuery.of(context).size.height * 0.72;
                  return SafeArea(
                    child: SizedBox(
                      height: sheetHeight,
                      child: Container(
                        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                        decoration: BoxDecoration(
                          color: _bgEnd,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: Colors.white24),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.45),
                              blurRadius: 18,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: ListView(
                          padding: EdgeInsets.zero,
                          children: [
                            Center(
                              child: Container(
                                width: 44,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: Colors.white24,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                const Text('Quick Actions',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 16)),
                                const Spacer(),
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: _accent.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(Icons.account_balance_wallet,
                                      color: _accent, size: 20),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            const Align(
                              alignment: Alignment.centerLeft,
                              child: Text('Choose a flow to continue',
                                  style: TextStyle(
                                      color: Colors.white70, fontSize: 12)),
                            ),
                            const SizedBox(height: 12),
                            _sheetSection(
                              title: 'Bkash',
                              subtitle: 'Send or receive via Bkash',
                              children: [
                                _sheetAction(
                                  icon: Icons.send,
                                  title: 'Send (Bkash)',
                                  subtitle: 'Send money using Bkash',
                                  onTap: () {
                                    Navigator.pop(context);
                                    openTransactionDialog(
                                        mode: 'bkash', action: 'send');
                                  },
                                ),
                                const SizedBox(height: 10),
                                _sheetAction(
                                  icon: Icons.call_received,
                                  title: 'Receive (Bkash)',
                                  subtitle: 'Receive money from Bkash',
                                  onTap: () {
                                    Navigator.pop(context);
                                    openTransactionDialog(
                                        mode: 'bkash', action: 'receive');
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _sheetSection(
                              title: 'Transaction',
                              subtitle: 'General send/receive',
                              children: [
                                _sheetAction(
                                  icon: Icons.send_to_mobile,
                                  title: 'Send (Transaction)',
                                  subtitle: 'Record a send entry',
                                  iconColor: Colors.cyanAccent,
                                  onTap: () {
                                    Navigator.pop(context);
                                    openTransactionDialog(
                                        mode: 'transaction', action: 'send');
                                  },
                                ),
                                const SizedBox(height: 10),
                                _sheetAction(
                                  icon: Icons.call_received,
                                  title: 'Receive (Transaction)',
                                  subtitle: 'Record a receive entry',
                                  iconColor: Colors.lightGreenAccent,
                                  onTap: () {
                                    Navigator.pop(context);
                                    openTransactionDialog(
                                        mode: 'transaction', action: 'receive');
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
          body: Stack(
            children: [
              _buildBackdrop(),
              SafeArea(
                child: Builder(builder: (ctx) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(color: Colors.white));
                  }
                  if (docs.isEmpty) {
                    return const Center(child: Text('No transactions for this day', style: TextStyle(color: Colors.white70)));
                  }

                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Date: $dateString',
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.white.withOpacity(0.18)),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: _accent.withOpacity(0.18),
                                      shape: BoxShape.circle,
                                      border: Border.all(color: _accent.withOpacity(0.6)),
                                    ),
                                    child: const Icon(Icons.account_balance_wallet, color: _accent),
                                  ),
                                  const SizedBox(width: 12),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Receive: \u09F3 ${totalReceive.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12, color: Colors.white)),
                                      const SizedBox(height: 2),
                                      Text('Send: \u09F3 ${totalSend.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12, color: Colors.white70)),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'Transactions',
                          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 10),
                        Expanded(
                          child: ListView.builder(
                            padding: const EdgeInsets.only(bottom: 120),
                            itemCount: docs.length,
                            itemBuilder: (_, idx) {
                              final doc = docs[idx];
                              final data = doc.data() as Map<String, dynamic>? ?? {};
                              final mode = (data['mode'] ?? 'bkash').toString();
                              final action = (data['action'] ?? 'send').toString();
                              final finalAmount = ((data['finalAmount'] ?? (data['amount'] ?? 0)) as num).toDouble();
                              final phone = data['phone'] as String?;
                              final pin = data['pin'] as String?;
                              final name = data['name'] as String?;
                              final reference = data['reference'] as String?;
                              final time = data['createdAt'] != null ? DateFormat('hh:mm a').format((data['createdAt'] as Timestamp).toDate()) : '';

                              return Container(
                                margin: const EdgeInsets.symmetric(vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: Colors.white.withOpacity(0.16)),
                                ),
                                child: ListTile(
                                  title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text('${mode.toUpperCase()} • ${action.toUpperCase()}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 6),
                                    if (mode == 'bkash') ...[
                                      Text('Phone: ${phone ?? '-'}', style: const TextStyle(color: Colors.white70)),
                                      Text('PIN: ${pin ?? '-'}', style: const TextStyle(color: Colors.white70)),
                                    ] else ...[
                                      Text('Name: ${name ?? '-'}', style: const TextStyle(color: Colors.white70)),
                                    ],
                                    if (reference != null && reference.isNotEmpty) Text('Ref: $reference', style: const TextStyle(color: Colors.white70)),
                                    Text('Final: \u09F3 ${finalAmount.toStringAsFixed(2)}', style: const TextStyle(color: _accent, fontWeight: FontWeight.bold)),
                                    Text('Time: $time', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                                  ]),
                                  onTap: () {
                                    editTransaction(doc.id, data);
                                  },
                                  trailing: PopupMenuButton<String>(
                                    onSelected: (v) async {
                                      if (v == 'edit') {
                                        editTransaction(doc.id, data);
                                      } else if (v == 'delete') {
                                        await deleteTransactionUI(doc.id, data);
                                      }
                                    },
                                    itemBuilder: (_) => const [
                                      PopupMenuItem(value: 'edit', child: Text('Edit')),
                                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ),
            ],
          ),
        );
      },
    );
  }
}


