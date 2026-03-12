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
  bool _clearingBkashHistory = false;

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

  String _normalizeMobile(String input) {
    final digits = input.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('880') && digits.length == 13) {
      return '0${digits.substring(3)}';
    }
    return digits;
  }

  String _normCompanyKey(String v) {
    return v.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
  }

  bool _matchesCompanyOrderDoc(
    QueryDocumentSnapshot doc,
    String companyId, {
    String? companyName,
  }) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final path = doc.reference.path;
    final dataCid = (data['companyId'] ?? '').toString().trim();
    final dataName = (data['companyName'] ?? data['company'] ?? '').toString().trim();
    final byPath = path.contains('/orders/$companyId/bills/');
    final byId = dataCid.isNotEmpty && dataCid == companyId;
    final byName = companyName != null &&
        dataName.isNotEmpty &&
        _normCompanyKey(dataName) == _normCompanyKey(companyName);
    return byPath || byId || byName;
  }

  Future<QueryDocumentSnapshot<Map<String, dynamic>>?> _getMobileAccountByDigits(String digits) async {
    if (digits.isEmpty) return null;
    final snap = await firestore
        .collection('bkash_mobile_accounts')
        .where('mobileDigits', isEqualTo: digits)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return snap.docs.first;
  }

  Future<void> _revertMobileTransaction({
    required DocumentReference<Map<String, dynamic>> accountRef,
    required String originTxId,
    required String oldAction,
    required double oldFinalAmount,
  }) async {
    if (oldFinalAmount <= 0) return;
    final revertDelta = oldAction == 'receive' ? -oldFinalAmount : oldFinalAmount;
    final txRef = accountRef.collection('transactions').doc(originTxId);
    await firestore.runTransaction((tx) async {
      final snap = await tx.get(accountRef);
      if (!snap.exists) return;
      final data = snap.data() as Map<String, dynamic>? ?? {};
      final balRaw = data['balance'] ?? 0;
      final current = (balRaw is num) ? balRaw.toDouble() : double.tryParse(balRaw.toString()) ?? 0.0;
      final newBalance = current + revertDelta;
      tx.update(accountRef, {'balance': newBalance, 'updatedAt': FieldValue.serverTimestamp()});
      tx.delete(txRef);
    });
  }

  Future<void> _applyMobileTransaction({
    required DocumentReference<Map<String, dynamic>> accountRef,
    required String originTxId,
    required String action,
    required double finalAmount,
    required String phone,
  }) async {
    if (finalAmount <= 0) return;
    final delta = action == 'receive' ? finalAmount : -finalAmount;
    final txRef = accountRef.collection('transactions').doc(originTxId);
    await firestore.runTransaction((tx) async {
      final snap = await tx.get(accountRef);
      if (!snap.exists) throw Exception('Mobile account not found');
      final data = snap.data() as Map<String, dynamic>? ?? {};
      final balRaw = data['balance'] ?? 0;
      final current = (balRaw is num) ? balRaw.toDouble() : double.tryParse(balRaw.toString()) ?? 0.0;
      final newBalance = current + delta;
      if (newBalance < 0) {
        throw Exception('Amount exceeds current balance');
      }
      tx.update(accountRef, {'balance': newBalance, 'updatedAt': FieldValue.serverTimestamp()});
      tx.set(txRef, {
        'type': action, // receive/send
        'amount': finalAmount,
        'phone': phone,
        'balanceAfter': newBalance,
        'originTxId': originTxId,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
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

  List<DateTime> _datesInRange(DateTime start, DateTime end) {
    final s = DateTime(start.year, start.month, start.day);
    final e = DateTime(end.year, end.month, end.day);
    final days = <DateTime>[];
    for (var d = s; !d.isAfter(e); d = d.add(const Duration(days: 1))) {
      days.add(d);
    }
    return days;
  }

  Future<void> _hideBkashDocs(String dateId) async {
    final col = firestore.collection('bkash').doc(dateId).collection('transactions');
    final snap = await col.get();
    if (snap.docs.isEmpty) return;
    WriteBatch batch = firestore.batch();
    int count = 0;
    Future<void> flush() async {
      if (count == 0) return;
      await batch.commit();
      batch = firestore.batch();
      count = 0;
    }
    for (final d in snap.docs) {
      final data = d.data();
      if (data['hidden'] == true) continue;
      batch.update(d.reference, {
        'hidden': true,
        'hiddenAt': FieldValue.serverTimestamp(),
      });
      count++;
      if (count >= 450) await flush();
    }
    await flush();
  }

  Future<void> _clearBkashHistoryRange() async {
    if (_clearingBkashHistory) return;
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2023),
      lastDate: DateTime(2100),
      initialDateRange: DateTimeRange(start: selectedDate, end: selectedDate),
    );
    if (range == null) return;
    setState(() => _clearingBkashHistory = true);
    try {
      final dates = _datesInRange(range.start, range.end);
      for (final d in dates) {
        final dateId = DateFormat('yyyy-MM-dd').format(d);
        await _hideBkashDocs(dateId);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('bKash history cleared for selected range')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Clear failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _clearingBkashHistory = false);
    }
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
    final submitting = ValueNotifier<bool>(false);
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
                ValueListenableBuilder<bool>(
                  valueListenable: submitting,
                  builder: (context, isSubmitting, _) {
                    return TextButton(
                      onPressed: isSubmitting
                          ? null
                          : () async {
                              submitting.value = true;
                              try {
                                final typed = controller.text.trim();
                                if (typed.isEmpty) {
                                  ScaffoldMessenger.of(context)
                                      .showSnackBar(const SnackBar(content: Text('Type a name to create')));
                                  return;
                                }
                                final lower = typed.toLowerCase();
                                final existsQ = await firestore
                                    .collection('bkash_customers')
                                    .where('nameLower', isEqualTo: lower)
                                    .limit(1)
                                    .get();
                                if (existsQ.docs.isNotEmpty) {
                                  // already exists -> return that and inform user
                                  final ex = existsQ.docs.first;
                                  Navigator.pop(context, {
                                    'id': ex.id,
                                    'name': (ex.data() as Map<String, dynamic>)['name']?.toString() ?? typed
                                  });
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Customer already exists - selected existing account')));
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
                              } finally {
                                submitting.value = false;
                              }
                            },
                      child: const Text('Create / Select'),
                    );
                  },
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
    final submitting = ValueNotifier<bool>(false);

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
                ValueListenableBuilder<bool>(
                  valueListenable: submitting,
                  builder: (context, isSubmitting, _) {
                    return ElevatedButton(
                      onPressed: isSubmitting
                          ? null
                          : () async {
                              submitting.value = true;
                              try {
                                final finalAmount = double.tryParse(finalAmountController.text.trim()) ??
                                    (isSend ? (double.tryParse(amountController.text.trim()) ?? 0.0) : 0.0);
                                final percent = double.tryParse(percentController.text.trim()) ?? (isBkash && isSend ? 2.0 : 0.0);
                                final amount = double.tryParse(amountController.text.trim()) ?? 0.0;
                                final phoneRaw = phoneController.text.trim();

                                if (finalAmount <= 0) {
                                  ScaffoldMessenger.of(context)
                                      .showSnackBar(const SnackBar(content: Text('Enter a valid final amount')));
                                  return;
                                }
                                if (isBkash && (pinController.text.trim().isEmpty)) {
                                  ScaffoldMessenger.of(context)
                                      .showSnackBar(const SnackBar(content: Text('PIN is required for Bkash operations')));
                                  return;
                                }

                                // Mobile account match (by exact digits)
                                QueryDocumentSnapshot<Map<String, dynamic>>? newMobileDoc;
                                QueryDocumentSnapshot<Map<String, dynamic>>? oldMobileDoc;
                                String newMobileDigits = '';
                                String oldMobileDigits = '';
                                double oldFinal = 0.0;
                                String oldAction = '';

                                if (isBkash) {
                                  newMobileDigits = _normalizeMobile(phoneRaw);
                                  if (newMobileDigits.isNotEmpty) {
                                    newMobileDoc = await _getMobileAccountByDigits(newMobileDigits);
                                  }
                                  if (docId != null && oldDocData != null) {
                                    final oldPhone = (oldDocData['phone'] ?? '').toString();
                                    oldMobileDigits = _normalizeMobile(oldPhone);
                                    if (oldMobileDigits.isNotEmpty) {
                                      if (newMobileDoc != null && oldMobileDigits == newMobileDigits) {
                                        oldMobileDoc = newMobileDoc;
                                      } else {
                                        oldMobileDoc = await _getMobileAccountByDigits(oldMobileDigits);
                                      }
                                    }
                                  }
                                  if (oldDocData != null) {
                                    oldFinal =
                                        ((oldDocData['finalAmount'] ?? oldDocData['amount'] ?? 0) as num).toDouble();
                                    oldAction = (oldDocData['action'] ?? '').toString();
                                  }

                                  // Prevent send exceeding mobile balance (if matched)
                                  if (newMobileDoc != null && action == 'send') {
                                    final mobData = newMobileDoc.data();
                                    final balRaw = mobData['balance'] ?? 0;
                                    final current =
                                        (balRaw is num) ? balRaw.toDouble() : double.tryParse(balRaw.toString()) ?? 0.0;
                                    double effective = current;
                                    if (oldMobileDoc != null &&
                                        oldMobileDoc.id == newMobileDoc.id &&
                                        oldAction.isNotEmpty) {
                                      // revert old effect for accurate check
                                      if (oldAction == 'receive') {
                                        effective -= oldFinal;
                                      } else if (oldAction == 'send') {
                                        effective += oldFinal;
                                      }
                                    }
                                    if (finalAmount > effective) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('Amount exceeds mobile balance')));
                                      return;
                                    }
                                  }
                                }

                                final col = firestore.collection('bkash').doc(dateString).collection('transactions');

                                // If editing: revert old customer effect if any
                                if (docId != null && oldDocData != null) {
                                  final oldCustomerId = (oldDocData['customerId'] as String?);
                                  final oldFinal =
                                      ((oldDocData['finalAmount'] ?? oldDocData['amount'] ?? 0) as num).toDouble();
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
                                  'name': !isBkash
                                      ? (nameController.text.trim().isNotEmpty ? nameController.text.trim() : null)
                                      : null,
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

                                // Update matched mobile account (exact phone match only)
                                if (isBkash) {
                                  final mobileUnchanged = docId != null &&
                                      oldMobileDoc != null &&
                                      newMobileDoc != null &&
                                      oldMobileDoc.id == newMobileDoc.id &&
                                      oldAction == action &&
                                      oldFinal == finalAmount;

                                  if (!mobileUnchanged) {
                                    if (docId != null && oldMobileDoc != null && oldAction.isNotEmpty && oldFinal > 0) {
                                      await _revertMobileTransaction(
                                        accountRef: oldMobileDoc.reference,
                                        originTxId: originTxId,
                                        oldAction: oldAction,
                                        oldFinalAmount: oldFinal,
                                      );
                                    }
                                    if (newMobileDoc != null) {
                                      await _applyMobileTransaction(
                                        accountRef: newMobileDoc.reference,
                                        originTxId: originTxId,
                                        action: action,
                                        finalAmount: finalAmount,
                                        phone: phoneRaw,
                                      );
                                    }
                                  }
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
                                    'name': !isBkash
                                        ? (nameController.text.trim().isNotEmpty ? nameController.text.trim() : null)
                                        : null, // <-- ADDED: include name for transaction mode
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
                              } finally {
                                submitting.value = false;
                              }
                            },
                      child: const Text('Save'),
                    );
                  },
                ),
              ],
            ),
          );
        });
      },
    );
  }

  double _computeFinalFromOrderData(Map<String, dynamic> data) {
    final fa = data['finalAmount'];
    if (fa is num) return fa.toDouble();
    if (fa != null) {
      final v = double.tryParse(fa.toString());
      if (v != null) return v;
    }

    final st = data['subTotal'];
    if (st is num) return st.toDouble();
    if (st != null) {
      final v = double.tryParse(st.toString());
      if (v != null) return v;
    }

    final items = data['items'];
    if (items is List) {
      double sum = 0.0;
      for (final it in items) {
        if (it is Map) {
          final t = it['total'];
          if (t is num) sum += t.toDouble();
        }
      }
      if (sum > 0) return sum;
    }

    final paid = (data['paid'] is num) ? (data['paid'] as num).toDouble() : double.tryParse('${data['paid']}') ?? 0.0;
    final due = (data['due'] is num) ? (data['due'] as num).toDouble() : double.tryParse('${data['due']}') ?? 0.0;
    return paid + due;
  }

  String? _companyIdFromOrderPath(String path) {
    final parts = path.split('/');
    for (var i = 0; i < parts.length - 1; i++) {
      if (parts[i] == 'orders') {
        return parts[i + 1];
      }
    }
    return null;
  }

  Future<Map<String, dynamic>> _applyCompanyPayment({
    required String companyId,
    required double amount,
    String? companyName,
  }) async {
    // Use collectionGroup matching to ensure we apply to the same orders used for total due.
    return _applyCompanyPaymentFromCollectionGroup(
      companyId: companyId,
      amount: amount,
      companyName: companyName,
    );
  }

  Future<Map<String, dynamic>> _applyCompanyPaymentFromCollectionGroup({
    required String companyId,
    required double amount,
    String? companyName,
  }) async {
    final ordersSnap = await firestore.collectionGroup('orders').get();
    if (ordersSnap.docs.isEmpty) {
      return {'appliedTotal': 0.0, 'remaining': amount, 'appliedTo': <Map<String, dynamic>>[]};
    }

    final matched = <QueryDocumentSnapshot>[];
    for (final d in ordersSnap.docs) {
      if (_matchesCompanyOrderDoc(d, companyId, companyName: companyName)) {
        matched.add(d);
      }
    }

    if (matched.isEmpty) {
      return {'appliedTotal': 0.0, 'remaining': amount, 'appliedTo': <Map<String, dynamic>>[]};
    }

    matched.sort((a, b) {
      final da = (a.data() as Map<String, dynamic>);
      final db = (b.data() as Map<String, dynamic>);
      final ta = da['createdAt'] is Timestamp ? (da['createdAt'] as Timestamp).toDate() : DateTime(1970);
      final tb = db['createdAt'] is Timestamp ? (db['createdAt'] as Timestamp).toDate() : DateTime(1970);
      return ta.compareTo(tb);
    });

    double remaining = amount;
    final appliedTo = <Map<String, dynamic>>[];

    WriteBatch batch = firestore.batch();
    int batchCount = 0;

    Future<void> flushBatch() async {
      if (batchCount == 0) return;
      await batch.commit();
      batch = firestore.batch();
      batchCount = 0;
    }

    for (final orderDoc in matched) {
      if (remaining <= 0) break;
      final data = orderDoc.data() as Map<String, dynamic>? ?? {};
      final paid = (data['paid'] is num) ? (data['paid'] as num).toDouble() : double.tryParse('${data['paid']}') ?? 0.0;
      final finalAmt = _computeFinalFromOrderData(data);
      final due = (data['due'] is num) ? (data['due'] as num).toDouble() : (finalAmt - paid);
      if (due <= 0) continue;

      final applyNow = remaining > due ? due : remaining;
      final newPaid = double.parse((paid + applyNow).toStringAsFixed(2));
      final newDue = double.parse((finalAmt - newPaid).toStringAsFixed(2));

      final updates = <String, dynamic>{
        'paid': newPaid,
        'due': newDue < 0 ? 0.0 : newDue,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if ((data['companyId'] ?? '').toString().isEmpty) {
        updates['companyId'] = companyId;
      }
      if ((data['companyName'] ?? '').toString().isEmpty && companyName != null) {
        updates['companyName'] = companyName;
        updates['companyNameUpper'] = companyName.trim().toUpperCase();
      }

      batch.update(orderDoc.reference, updates);
      batchCount++;

      final billDate = orderDoc.reference.parent.parent?.id ?? '';
      appliedTo.add({'orderId': orderDoc.id, 'billDate': billDate, 'amount': applyNow});
      remaining = double.parse((remaining - applyNow).toStringAsFixed(2));

      if (batchCount >= 450) {
        await flushBatch();
      }
    }

    await flushBatch();
    final appliedTotal = double.parse((amount - remaining).toStringAsFixed(2));
    return {'appliedTotal': appliedTotal, 'remaining': remaining, 'appliedTo': appliedTo};
  }

  Future<void> _revertCompanyPayment(Map<String, dynamic> oldData) async {
    final companyId = oldData['companyId'] as String?;
    if (companyId == null) return;

    final appliedToRaw = oldData['companyAppliedTo'];
    final items = <Map<String, dynamic>>[];

    if (appliedToRaw is List) {
      for (final it in appliedToRaw) {
        if (it is Map) {
          items.add(Map<String, dynamic>.from(it));
        }
      }
    } else {
      final orderId = oldData['companyOrderId'] as String?;
      final billDate = (oldData['companyBillDate'] ?? dateString).toString();
      final applied = (oldData['companyApplied'] is num)
          ? (oldData['companyApplied'] as num).toDouble()
          : double.tryParse('${oldData['companyApplied']}') ?? 0.0;
      if (orderId != null && applied > 0) {
        items.add({'orderId': orderId, 'billDate': billDate, 'amount': applied});
      }
    }

    if (items.isEmpty) return;

    WriteBatch batch = firestore.batch();
    int batchCount = 0;

    Future<void> flushBatch() async {
      if (batchCount == 0) return;
      await batch.commit();
      batch = firestore.batch();
      batchCount = 0;
    }

    for (final it in items) {
      final orderId = it['orderId']?.toString();
      final billDate = it['billDate']?.toString();
      final applied = (it['amount'] is num) ? (it['amount'] as num).toDouble() : double.tryParse('${it['amount']}') ?? 0.0;
      if (orderId == null || billDate == null || applied <= 0) continue;

      final orderRef = firestore
          .collection('orders')
          .doc(companyId)
          .collection('bills')
          .doc(billDate)
          .collection('orders')
          .doc(orderId);

      final snap = await orderRef.get();
      if (!snap.exists) continue;
      final data = snap.data() as Map<String, dynamic>? ?? {};
      final paid = (data['paid'] is num) ? (data['paid'] as num).toDouble() : double.tryParse('${data['paid']}') ?? 0.0;
      final finalAmt = _computeFinalFromOrderData(data);
      final due = (data['due'] is num) ? (data['due'] as num).toDouble() : (finalAmt - paid);

      final newPaid = double.parse((paid - applied).clamp(0.0, double.infinity).toStringAsFixed(2));
      final newDue = double.parse((finalAmt - newPaid).toStringAsFixed(2));
      final cappedDue = newDue > finalAmt ? finalAmt : newDue;

      batch.update(orderRef, {
        'paid': newPaid,
        'due': cappedDue < 0 ? 0.0 : cappedDue,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      batchCount++;
      if (batchCount >= 450) {
        await flushBatch();
      }
    }

    await flushBatch();
  }

  Future<double> _computeCompanyTotalDue(String companyId, {String? companyName}) async {
    final snap = await firestore.collectionGroup('orders').get();
    if (snap.docs.isEmpty) return 0.0;
    double total = 0.0;
    for (final d in snap.docs) {
      if (!_matchesCompanyOrderDoc(d, companyId, companyName: companyName)) continue;
      final data = d.data() as Map<String, dynamic>? ?? {};
      final paid = (data['paid'] is num) ? (data['paid'] as num).toDouble() : double.tryParse('${data['paid']}') ?? 0.0;
      final finalAmt = _computeFinalFromOrderData(data);
      final due = (data['due'] is num) ? (data['due'] as num).toDouble() : (finalAmt - paid);
      if (due > 0) total += due;
    }
    return double.parse(total.toStringAsFixed(2));
  }

  Future<double> _computeCompanyTotalDueFromCollectionGroup(String companyId) async {
    final snap = await firestore.collectionGroup('orders').get();
    if (snap.docs.isEmpty) return 0.0;
    double total = 0.0;
    for (final d in snap.docs) {
      if (!_matchesCompanyOrderDoc(d, companyId)) continue;
      final data = d.data() as Map<String, dynamic>? ?? {};
      final paid = (data['paid'] is num) ? (data['paid'] as num).toDouble() : double.tryParse('${data['paid']}') ?? 0.0;
      final finalAmt = _computeFinalFromOrderData(data);
      final due = (data['due'] is num) ? (data['due'] as num).toDouble() : (finalAmt - paid);
      if (due > 0) total += due;
    }
    return double.parse(total.toStringAsFixed(2));
  }

  /// Send money to company order (uses existing company list).
  Future<void> openCompanyOrderDialog({
    Map<String, dynamic>? initial,
    String action = 'send',
    String? docId,
  }) async {
    final companyController = TextEditingController(text: initial?['name']?.toString() ?? '');
    final amountController = TextEditingController(
      text: (initial?['finalAmount'] ?? initial?['amount'] ?? '').toString(),
    );
    final referenceController = TextEditingController(text: initial?['reference']?.toString() ?? '');
    final submitting = ValueNotifier<bool>(false);

    String? companyId = initial?['companyId'] as String?;
    Map<String, dynamic>? oldDocData;
    if (docId != null) {
      final snap = await firestore.collection('bkash').doc(dateString).collection('transactions').doc(docId).get();
      if (snap.exists) oldDocData = snap.data() as Map<String, dynamic>?;
    }

    double? companyTotalDue;
    bool dueLoading = false;
    bool didInit = false;

    await showDialog(
      context: context,
      builder: (ctx) {
        return Theme(
          data: _dialogTheme(context),
          child: AlertDialog(
            backgroundColor: _bgEnd,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: Colors.white24),
          ),
          title: const Text('Company Order — Send'),
          content: SingleChildScrollView(
              child: StatefulBuilder(
                builder: (context, setState) {
                  if (!didInit) {
                    didInit = true;
                    if (companyId != null) {
                      dueLoading = true;
                      _computeCompanyTotalDue(companyId!, companyName: companyController.text.trim()).then((v) {
                        if (!context.mounted) return;
                        setState(() {
                          companyTotalDue = v;
                          dueLoading = false;
                        });
                      });
                    }
                  }

                  Future<void> refreshDue() async {
                    if (companyId == null) return;
                    setState(() => dueLoading = true);
                    final v = await _computeCompanyTotalDue(companyId!, companyName: companyController.text.trim());
                    if (!context.mounted) return;
                    setState(() {
                      companyTotalDue = v;
                      dueLoading = false;
                    });
                  }

                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: companyController,
                              readOnly: true,
                              decoration: const InputDecoration(
                                labelText: 'Company',
                                hintText: 'Select company',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            tooltip: 'Pick company',
                            icon: const Icon(Icons.business),
                            onPressed: () async {
                              final pick = await _selectCompanyDialog(context, initial: companyController.text);
                              if (pick != null) {
                                companyController.text = pick['name'] ?? '';
                                companyId = pick['id'];
                                await refreshDue();
                              }
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (dueLoading)
                        Row(
                          children: const [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: 8),
                            Text('Calculating total due...', style: TextStyle(color: Colors.white70, fontSize: 12)),
                          ],
                        )
                      else if (companyTotalDue != null)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: Colors.white24),
                            ),
                            child: Text(
                              'Total Due: \u09F3 ${companyTotalDue!.toStringAsFixed(2)}',
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                          ),
                        ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: amountController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Amount'),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: referenceController,
                        decoration: const InputDecoration(labelText: 'Reference (optional)'),
                      ),
                    ],
                  );
                },
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              ValueListenableBuilder<bool>(
                valueListenable: submitting,
                builder: (context, isSubmitting, _) {
                  return ElevatedButton(
                    onPressed: isSubmitting
                        ? null
                        : () async {
                            submitting.value = true;
                            try {
                              final companyName = companyController.text.trim();
                              final amount = double.tryParse(amountController.text.trim()) ?? 0.0;

                              if (companyName.isEmpty) {
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(const SnackBar(content: Text('Select a company')));
                                return;
                              }
                              if (amount <= 0) {
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(const SnackBar(content: Text('Enter a valid amount')));
                                return;
                              }

                              final computedCompanyId = companyId ?? companyName.toLowerCase().replaceAll(' ', '_');
                              final col = firestore.collection('bkash').doc(dateString).collection('transactions');

                              // Validate against total due across all orders (oldest to latest).
                              final totalDue = companyTotalDue ??
                                  await _computeCompanyTotalDue(computedCompanyId, companyName: companyName);
                              if (totalDue <= 0) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('No due found for this company')),
                                );
                                return;
                              }
                              if (amount > totalDue) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Amount exceeds total due (\u09F3 ${totalDue.toStringAsFixed(2)})')),
                                );
                                return;
                              }

                              // If editing: revert old company payment effect first
                              if (oldDocData != null && (oldDocData?['mode'] == 'company')) {
                                await _revertCompanyPayment(oldDocData!);
                              }

                              final txData = <String, dynamic>{
                                'mode': 'company',
                                'action': action,
                                'name': companyName,
                                'companyId': computedCompanyId,
                                'amount': amount,
                                'finalAmount': amount,
                                'reference': referenceController.text.trim().isEmpty ? null : referenceController.text.trim(),
                                'createdAt': FieldValue.serverTimestamp(),
                              };

                              String originTxId;
                              if (docId != null) {
                                await col.doc(docId).update(txData);
                                originTxId = docId;
                              } else {
                                final docRef = await col.add(txData);
                                originTxId = docRef.id;
                              }

                              final appliedInfo = await _applyCompanyPayment(
                                companyId: computedCompanyId,
                                amount: amount,
                                companyName: companyName,
                              );

                              final appliedTo = (appliedInfo['appliedTo'] as List?) ?? [];
                              final appliedTotal = (appliedInfo['appliedTotal'] as num?)?.toDouble() ?? 0.0;
                              final remaining = (appliedInfo['remaining'] as num?)?.toDouble() ?? 0.0;

                              await col.doc(originTxId).update({
                                'companyAppliedTotal': appliedTotal,
                                'companyApplied': appliedTotal, // backward compatible
                                'companyAppliedTo': appliedTo,
                                'companyOrderId': appliedTo.isNotEmpty ? (appliedTo.first as Map)['orderId'] : null,
                                'companyBillDate': appliedTo.isNotEmpty ? (appliedTo.first as Map)['billDate'] : null,
                              });

                              await firestore.collection('company_payments').doc(computedCompanyId).set({
                                'companyId': computedCompanyId,
                                'companyName': companyName,
                                'lastPaidAmount': appliedTotal,
                                'lastPaidAt': FieldValue.serverTimestamp(),
                                'lastTxId': originTxId,
                              }, SetOptions(merge: true));

                              if (appliedTotal <= 0) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('No unpaid orders found for this company')),
                                );
                              } else if (remaining > 0) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content: Text(
                                          'Only \u09F3 ${(amount - remaining).toStringAsFixed(2)} applied. Remaining \u09F3 ${remaining.toStringAsFixed(2)} not applied.')),
                                );
                              }

                              Navigator.pop(context);
                            } finally {
                              submitting.value = false;
                            }
                          },
                    child: const Text('Save'),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> editTransaction(String id, Map<String, dynamic> data) async {
    final mode = (data['mode'] ?? 'bkash').toString();
    final action = (data['action'] ?? 'send').toString();
    if (mode == 'company') {
      await openCompanyOrderDialog(initial: data, action: action, docId: id);
      return;
    }
    await openTransactionDialog(initial: data, mode: mode, action: action, docId: id);
  }

  Future<void> deleteTransaction(String id, Map<String, dynamic>? data) async {
    final col = firestore.collection('bkash').doc(dateString).collection('transactions');
    final snap = await col.doc(id).get();
    if (!snap.exists) return;
    final d = snap.data() as Map<String, dynamic>? ?? {};
    final mode = (d['mode'] ?? 'bkash').toString();

    if (mode == 'company') {
      await _revertCompanyPayment(d);
      final companyId = d['companyId'] as String?;
      if (companyId != null) {
        try {
          final payRef = firestore.collection('company_payments').doc(companyId);
          final paySnap = await payRef.get();
          if (paySnap.exists) {
            final data = paySnap.data() as Map<String, dynamic>? ?? {};
            if (data['lastTxId'] == id) {
              await payRef.set({
                'lastPaidAmount': FieldValue.delete(),
                'lastPaidAt': FieldValue.delete(),
                'lastTxId': FieldValue.delete(),
              }, SetOptions(merge: true));
            }
          }
        } catch (_) {}
      }
      await col.doc(id).delete();
      return;
    }
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
    bool isDeleting = false;
    await showDialog<bool>(
      context: context,
      builder: (_) => Theme(
        data: _dialogTheme(context),
        child: StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: _bgEnd,
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: Colors.white24),
              ),
              title: const Text('Delete transaction?'),
              content: const Text('This will remove the transaction permanently and revert linked account balance.'),
              actions: [
                TextButton(onPressed: isDeleting ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
                ElevatedButton(
                  onPressed: isDeleting
                      ? null
                      : () async {
                          setState(() => isDeleting = true);
                          try {
                            await deleteTransaction(docId, data);
                          } finally {
                            if (context.mounted) {
                              Navigator.pop(context, true);
                            }
                          }
                        },
                  child: isDeleting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                        )
                      : const Text('Delete'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

    @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: transactionsStream(dateString),
      builder: (context, snap) {
        double totalReceive = 0.0;
        double totalSend = 0.0;
        final docs = snap.data?.docs ?? [];
        final visibleDocs = docs.where((d) {
          final data = d.data() as Map<String, dynamic>? ?? {};
          final source = (data['source'] ?? '').toString();
          if (source == 'sell') return false; // keep sell page company sends only in Sell page
          return data['hidden'] != true;
        }).toList();
        for (final d in visibleDocs) {
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
                              title: 'Company Order',
                              subtitle: 'Pay supplier/company',
                              children: [
                                _sheetAction(
                                  icon: Icons.business_center,
                                  title: 'Send (Company Order)',
                                  subtitle: 'Send payment to company',
                                  iconColor: Colors.orangeAccent,
                                  onTap: () {
                                    Navigator.pop(context);
                                    openCompanyOrderDialog(action: 'send');
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
                          child: visibleDocs.isEmpty
                              ? const Center(child: Text('No transactions for this day', style: TextStyle(color: Colors.white70)))
                              : ListView.builder(
                            padding: const EdgeInsets.only(bottom: 120),
                            itemCount: visibleDocs.length,
                            itemBuilder: (_, idx) {
                              final doc = visibleDocs[idx];
                              final data = doc.data() as Map<String, dynamic>? ?? {};
                              final mode = (data['mode'] ?? 'bkash').toString();
                              final action = (data['action'] ?? 'send').toString();
                              final modeLabel = mode == 'company' ? 'COMPANY ORDER' : mode.toUpperCase();
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
                                    Text('$modeLabel • ${action.toUpperCase()}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 6),
                                    if (mode == 'company') ...[
                                      Text('Company: ${name ?? '-'}', style: const TextStyle(color: Colors.white70)),
                                    ] else if (mode == 'bkash') ...[
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

  /// Select a company from existing medicine list (no creation here).
  /// Returns map {'id': id, 'name': name} or null.
  Future<Map<String, String>?> _selectCompanyDialog(BuildContext ctx, {String initial = ''}) async {
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
                side: const BorderSide(color: Colors.white24),
              ),
              title: const Text('Select Company'),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: controller,
                      decoration: const InputDecoration(labelText: 'Search company'),
                      onChanged: (v) => setState(() => search = v.trim().toLowerCase()),
                    ),
                    const SizedBox(height: 8),
                    Flexible(
                      child: StreamBuilder<QuerySnapshot>(
                        stream: firestore.collection('medicines').orderBy('companyName').snapshots(),
                        builder: (context, snap) {
                          if (!snap.hasData) {
                            return const Center(child: CircularProgressIndicator());
                          }

                          final docs = snap.data!.docs;
                          final set = <String>{};

                          for (final d in docs) {
                            final data = d.data() as Map<String, dynamic>? ?? {};
                            final raw = (data['companyName'] ??
                                    data['companyNameUpper'] ??
                                    data['companyNameLower'] ??
                                    '')
                                .toString()
                                .trim();
                            if (raw.isNotEmpty) set.add(raw.toUpperCase());
                          }

                          final companies = set.toList()..sort();
                          final filtered = search.isEmpty
                              ? companies
                              : companies.where((c) => c.toLowerCase().contains(search)).toList();

                          if (filtered.isEmpty) {
                            return const Center(child: Text('No companies found'));
                          }

                          return ListView.separated(
                            shrinkWrap: true,
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1, color: Colors.white24),
                            itemBuilder: (_, i) {
                              final name = filtered[i];
                              final id = name.toLowerCase().replaceAll(' ', '_');
                              return ListTile(
                                title: Text(name),
                                onTap: () => Navigator.pop(context, {'id': id, 'name': name}),
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
              ],
            ),
          );
        });
      },
    );
  }
}


