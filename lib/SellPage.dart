// SellPage.dart
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'edit_bill_page.dart';
import 'new_bill_page.dart';
import 'CustomerDueListPage.dart';

class SellPage extends StatefulWidget {
  const SellPage({Key? key}) : super(key: key);

  @override
  _SellPageState createState() => _SellPageState();
}

class _SellPageState extends State<SellPage> {
  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  DateTime selectedDate = DateTime.now();
  String get dateString => DateFormat('yyyy-MM-dd').format(selectedDate);
  double dailyTotal = 0.0;
  String _currentUserRole = 'seller';
  bool _clearingSellHistory = false;
  static const Color _bgStart = Color(0xFF041A14);
  static const Color _bgEnd = Color(0xFF0E5A42);
  static const Color _accent = Color(0xFFFFD166);

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

  @override
  void initState() {
    super.initState();
    _loadMyRole();
  }

  Future<void> _loadMyRole() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final doc = await firestore.collection('users').doc(user.uid).get();
      if (doc.exists) {
        final data = doc.data();
        setState(() {
          _currentUserRole = (data?['role'] ?? 'seller').toString();
        });
      }
    } catch (_) {
      // keep default role
    }
  }

  String _normalizeRole(String? role) {
    if (role == null) return '';
    return role.toLowerCase().replaceAll(RegExp(r'[\s\-]+'), '_').trim();
  }

  bool get _canViewDailyTotal {
    final nr = _normalizeRole(_currentUserRole);
    return nr == 'admin' || nr == 'manager';
  }

  Widget _infoChip(String label, String value, {Color? color}) {
    final chipColor = color ?? Colors.white70;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white24),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(color: chipColor, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _glassCard({required Widget child, EdgeInsetsGeometry? padding}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: padding ?? const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.18)),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _actionCard({
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
      child: _glassCard(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white54),
          ],
        ),
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
      textTheme: base.textTheme.apply(bodyColor: Colors.white, displayColor: Colors.white),
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

  List<DateTime> _datesInRange(DateTime start, DateTime end) {
    final s = DateTime(start.year, start.month, start.day);
    final e = DateTime(end.year, end.month, end.day);
    final days = <DateTime>[];
    for (var d = s; !d.isAfter(e); d = d.add(const Duration(days: 1))) {
      days.add(d);
    }
    return days;
  }

  Future<void> _hideCollectionDocs(Query col, {bool Function(QueryDocumentSnapshot)? filter}) async {
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
      if (filter != null && !filter(d)) continue;
      final data = d.data() as Map<String, dynamic>? ?? {};
      if (data['hidden'] == true) continue;
      batch.update(d.reference, {
        'hidden': true,
        'hiddenAt': FieldValue.serverTimestamp(),
      });
      count++;
      if (count >= 450) {
        await flush();
      }
    }
    await flush();
  }

  Future<void> _clearSellHistoryRange() async {
    if (_clearingSellHistory) return;
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2023),
      lastDate: DateTime(2100),
      initialDateRange: DateTimeRange(start: selectedDate, end: selectedDate),
    );
    if (range == null) return;

    setState(() => _clearingSellHistory = true);
    try {
      final dates = _datesInRange(range.start, range.end);
      for (final d in dates) {
        final dateId = DateFormat('yyyy-MM-dd').format(d);
        await _hideCollectionDocs(
          firestore.collection('sales').doc(dateId).collection('bills'),
        );
        await _hideCollectionDocs(
          firestore.collection('due_entries').doc(dateId).collection('entries'),
        );
        // only hide company send transactions created from sell page
        await _hideCollectionDocs(
          firestore.collection('bkash').doc(dateId).collection('transactions'),
          filter: (doc) {
            final data = doc.data() as Map<String, dynamic>? ?? {};
            final mode = (data['mode'] ?? '').toString();
            final action = (data['action'] ?? '').toString();
            final source = (data['source'] ?? '').toString();
            return mode == 'company' && action == 'send' && source == 'sell';
          },
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sales history cleared for selected range')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Clear failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _clearingSellHistory = false);
    }
  }

  Stream<QuerySnapshot> salesStream(String date) {
    return firestore
        .collection('sales')
        .doc(date)
        .collection('bills')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  Stream<QuerySnapshot> dueEntriesStream(String date) {
    return firestore
        .collection('due_entries')
        .doc(date)
        .collection('entries')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  Stream<QuerySnapshot> bkashTxStream(String date) {
    return firestore.collection('bkash').doc(date).collection('transactions').snapshots();
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

  Future<double> _computeCompanyTotalDue(String companyId, {String? companyName}) async {
    // Use collectionGroup to match the same scope as company list
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
                            separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.white24),
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

  Future<void> _openCompanySendDialog() async {
    final companyController = TextEditingController();
    final amountController = TextEditingController();
    final referenceController = TextEditingController();
    String? companyId;
    final submitting = ValueNotifier<bool>(false);

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
                              'Total Due: ৳ ${companyTotalDue!.toStringAsFixed(2)}',
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
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select a company')));
                                return;
                              }
                              if (amount <= 0) {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid amount')));
                                return;
                              }

                              final computedCompanyId = companyId ?? companyName.toLowerCase().replaceAll(' ', '_');
                              final col = firestore.collection('bkash').doc(dateString).collection('transactions');

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
                                  SnackBar(content: Text('Amount exceeds total due (৳ ${totalDue.toStringAsFixed(2)})')),
                                );
                                return;
                              }

                              final txData = <String, dynamic>{
                                'mode': 'company',
                                'action': 'send',
                                'name': companyName,
                                'companyId': computedCompanyId,
                                'amount': amount,
                                'finalAmount': amount,
                                'reference': referenceController.text.trim().isEmpty ? null : referenceController.text.trim(),
                                'source': 'sell',
                                'createdAt': FieldValue.serverTimestamp(),
                              };

                              final docRef = await col.add(txData);

                              final appliedInfo = await _applyCompanyPayment(
                                companyId: computedCompanyId,
                                amount: amount,
                                companyName: companyName,
                              );

                              final appliedTo = (appliedInfo['appliedTo'] as List?) ?? [];
                              final appliedTotal = (appliedInfo['appliedTotal'] as num?)?.toDouble() ?? 0.0;
                              final remaining = (appliedInfo['remaining'] as num?)?.toDouble() ?? 0.0;

                              await col.doc(docRef.id).update({
                                'companyAppliedTotal': appliedTotal,
                                'companyApplied': appliedTotal,
                                'companyAppliedTo': appliedTo,
                                'companyOrderId': appliedTo.isNotEmpty ? (appliedTo.first as Map)['orderId'] : null,
                                'companyBillDate': appliedTo.isNotEmpty ? (appliedTo.first as Map)['billDate'] : null,
                              });

                              await firestore.collection('company_payments').doc(computedCompanyId).set({
                                'companyId': computedCompanyId,
                                'companyName': companyName,
                                'lastPaidAmount': appliedTotal,
                                'lastPaidAt': FieldValue.serverTimestamp(),
                                'lastTxId': docRef.id,
                              }, SetOptions(merge: true));

                              if (appliedTotal <= 0) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('No unpaid orders found for this company')),
                                );
                              } else if (remaining > 0) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Only ৳ ${(amount - remaining).toStringAsFixed(2)} applied. Remaining ৳ ${remaining.toStringAsFixed(2)} not applied.')),
                                );
                              }

                              Navigator.pop(context);
                            } finally {
                              submitting.value = false;
                            }
                          },
                    child: const Text('Send'),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openCustomerDueSendDialog() async {
    final nameController = TextEditingController();
    final amountController = TextEditingController();
    String? selectedCustomerId;
    Map<String, dynamic>? selectedCustomerData;
    String search = '';
    bool addToCustomer = false;
    final submitting = ValueNotifier<bool>(false);

    await showDialog(
      context: context,
      builder: (ctx) {
        return Theme(
          data: _dialogTheme(context),
          child: AlertDialog(
            backgroundColor: _bgEnd,
            surfaceTintColor: Colors.transparent,
            titleTextStyle: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
            contentTextStyle: const TextStyle(color: Colors.white70),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: Colors.white24),
            ),
            title: Row(
              children: const [
                Icon(Icons.person_add_alt_1, color: _accent),
                SizedBox(width: 8),
                Text('Customer Due — Add'),
              ],
            ),
            content: SingleChildScrollView(
              child: StatefulBuilder(
                builder: (context, setState) {
                  return SizedBox(
                    width: double.maxFinite,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                      TextField(
                        controller: nameController,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: 'Customer name',
                          hintText: 'Search or type name',
                          hintStyle: TextStyle(color: Colors.white54),
                        ),
                        onChanged: (v) {
                          setState(() {
                            search = v.trim().toLowerCase();
                            selectedCustomerId = null;
                            selectedCustomerData = null;
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Add to customer list'),
                        subtitle: const Text('If off, it will save only in sales transactions'),
                        value: addToCustomer,
                        onChanged: (v) => setState(() => addToCustomer = v),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        height: 200,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: StreamBuilder<QuerySnapshot>(
                          stream: firestore
                              .collection('customers')
                              .orderBy('nameLower')
                              .startAt([search.isEmpty ? '' : search])
                              .endAt([(search.isEmpty ? '' : search) + '\uf8ff'])
                              .limit(20)
                              .snapshots(),
                          builder: (context, snap) {
                            if (snap.hasError) {
                              return Center(
                                child: Text(
                                  'Failed to load customers',
                                  style: const TextStyle(color: Colors.white70),
                                ),
                              );
                            }
                            if (!snap.hasData) {
                              return const Center(child: CircularProgressIndicator());
                            }
                            final docs = snap.data!.docs;
                            if (docs.isEmpty) {
                              return const Center(child: Text('No customer found. Type to create.'));
                            }
                            return ListView.separated(
                              itemCount: docs.length,
                              separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.white24),
                              itemBuilder: (_, i) {
                                final d = docs[i];
                                final data = d.data() as Map<String, dynamic>;
                                return ListTile(
                                  title: Text(data['name'] ?? ''),
                                  subtitle: Text("${data['address'] ?? 'No address'} • ${data['phone'] ?? 'No phone'}"),
                                  selected: selectedCustomerId == d.id,
                                  onTap: () {
                                    selectedCustomerId = d.id;
                                    selectedCustomerData = data;
                                    nameController.text = data['name'] ?? '';
                                    search = (data['nameLower'] ?? '').toString();
                                    addToCustomer = true;
                                    setState(() {});
                                  },
                                );
                              },
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: amountController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: 'Amount',
                          hintText: 'e.g. 500',
                          hintStyle: TextStyle(color: Colors.white54),
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'If customer is not found, a new one will be created.',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ),
                      ],
                    ),
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
                              final typedName = nameController.text.trim();
                              final amount = double.tryParse(amountController.text.trim()) ?? 0.0;
                              if (amount <= 0) {
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(const SnackBar(content: Text('Enter a valid amount')));
                                return;
                              }

                              final batch = firestore.batch();
                              final now = FieldValue.serverTimestamp();
                              final entryDate = dateString;

                              if (!addToCustomer) {
                                final displayName = typedName.isEmpty ? 'Unknown' : typedName;
                                final entryRef =
                                    firestore.collection('due_entries').doc(entryDate).collection('entries').doc();
                                batch.set(entryRef, {
                                  'type': 'due',
                                  'name': displayName,
                                  'phone': null,
                                  'address': null,
                                  'amount': amount,
                                  'createdAt': now,
                                  'source': 'sell',
                                  'transferred': false,
                                });
                                await batch.commit();
                                if (!mounted) return;
                                Navigator.pop(context);
                                ScaffoldMessenger.of(this.context).showSnackBar(
                                  SnackBar(content: Text('Added due \u09F3 ${amount.toStringAsFixed(2)}')),
                                );
                                return;
                              }

                              if (typedName.isEmpty) {
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(const SnackBar(content: Text('Enter customer name')));
                                return;
                              }

                              DocumentReference<Map<String, dynamic>> custRef;
                              if (selectedCustomerId != null) {
                                custRef = firestore.collection('customers').doc(selectedCustomerId!);
                              } else {
                                custRef = firestore.collection('customers').doc();
                              }
                              final customerId = custRef.id;

                              final snap = await custRef.get();
                              if (!snap.exists) {
                                batch.set(custRef, {
                                  'name': typedName,
                                  'nameLower': typedName.toLowerCase(),
                                  'phone': null,
                                  'address': null,
                                  'totalDue': amount,
                                  'balance': 0,
                                  'createdAt': now,
                                });
                                batch.set(custRef.collection('customer_dues').doc(), {
                                  'type': 'due',
                                  'amount': amount,
                                  'createdAt': now,
                                  'source': 'sell',
                                });
                                final entryRef =
                                    firestore.collection('due_entries').doc(entryDate).collection('entries').doc();
                                batch.set(entryRef, {
                                  'type': 'due',
                                  'customerId': customerId,
                                  'name': typedName,
                                  'phone': null,
                                  'address': null,
                                  'amount': amount,
                                  'createdAt': now,
                                  'source': 'sell',
                                  'transferred': true,
                                  'transferredTo': customerId,
                                });
                                await batch.commit();
                                if (!mounted) return;
                                Navigator.pop(context);
                                ScaffoldMessenger.of(this.context).showSnackBar(
                                  SnackBar(content: Text('Added due \u09F3 ${amount.toStringAsFixed(2)} for $typedName')),
                                );
                                return;
                              }

                              final curr = snap.data() ?? {};
                              final currBalance = ((curr['balance'] ?? 0) as num).toDouble();
                              double remainingDue = amount;
                              double coveredByBalance = 0.0;
                              if (currBalance > 0) {
                                coveredByBalance = currBalance >= amount ? amount : currBalance;
                                remainingDue = amount - coveredByBalance;
                              }

                              if (coveredByBalance > 0) {
                                batch.update(custRef, {'balance': FieldValue.increment(-coveredByBalance)});
                              }

                              if (remainingDue > 0) {
                                batch.update(custRef, {'totalDue': FieldValue.increment(remainingDue)});
                                batch.set(custRef.collection('customer_dues').doc(), {
                                  'type': 'due',
                                  'amount': remainingDue,
                                  'createdAt': now,
                                  'coveredByBalance': coveredByBalance > 0 ? coveredByBalance : null,
                                  'source': 'sell',
                                });

                                final entryRef =
                                    firestore.collection('due_entries').doc(entryDate).collection('entries').doc();
                                batch.set(entryRef, {
                                  'type': 'due',
                                  'customerId': customerId,
                                  'name': curr['name'] ?? typedName,
                                  'phone': curr['phone'] ?? selectedCustomerData?['phone'],
                                  'address': curr['address'] ?? selectedCustomerData?['address'],
                                  'amount': remainingDue,
                                  'createdAt': now,
                                  'coveredByBalance': coveredByBalance > 0 ? coveredByBalance : null,
                                  'source': 'sell',
                                  'transferred': true,
                                  'transferredTo': customerId,
                                });
                              } else {
                                batch.set(custRef.collection('customer_dues').doc(), {
                                  'type': 'due_covered_by_balance',
                                  'amount': amount,
                                  'coveredByBalance': amount,
                                  'createdAt': now,
                                  'source': 'sell',
                                });
                              }

                              await batch.commit();
                              if (!mounted) return;
                              Navigator.pop(context);
                              final message = remainingDue > 0
                                  ? 'Added due \u09F3 ${remainingDue.toStringAsFixed(2)} for $typedName'
                                  : 'Due covered by balance for $typedName';
                              ScaffoldMessenger.of(this.context).showSnackBar(SnackBar(content: Text(message)));
                            } finally {
                              submitting.value = false;
                            }
                          },
                    child: const Text('Send'),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> shareBill(Map<String, dynamic> billData) async {
    try {
      // load font from assets (ByteData) and pass ByteData directly to pw.Font.ttf
      final ByteData fontData = await rootBundle.load('assets/fonts/NotoSansBengali-Regular.ttf');
      final pw.Font ttf = pw.Font.ttf(fontData);

      final pdf = pw.Document();
      pdf.addPage(
        pw.Page(
          build: (pw.Context context) {
            final items = (billData['items'] as List? ?? []);
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text("Bill - $dateString",
                    style: pw.TextStyle(font: ttf, fontSize: 18, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 8),
                ...items.map((item) {
                  return pw.Text(
                    "${item['name']} ${item['qty']} × \u09F3 ${item['price']} = \u09F3 ${(item['total'] ?? (item['qty'] ?? 0) * (item['price'] ?? 0))}",
                    style: pw.TextStyle(font: ttf, fontSize: 12),
                  );
                }).toList(),
                pw.Divider(),
                pw.Text("Total = \u09F3 ${billData['subTotal'] ?? 0}",
                    style: pw.TextStyle(font: ttf, fontWeight: pw.FontWeight.bold)),
                pw.Text("Paid = \u09F3 ${billData['paid'] ?? 0}", style: pw.TextStyle(font: ttf)),
                pw.Text("Due = \u09F3 ${billData['due'] ?? 0}", style: pw.TextStyle(font: ttf)),
                pw.SizedBox(height: 10),
                pw.Text("C Jononi Pharmacy, Shunashar",
                    style: pw.TextStyle(font: ttf, fontStyle: pw.FontStyle.italic)),
              ],
            );
          },
        ),
      );

      await Printing.sharePdf(bytes: await pdf.save(), filename: "bill.pdf");
    } catch (e, st) {
      debugPrint('shareBill error: $e\n$st');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to create PDF: $e")));
    }
  }

  // Transfer a sale's due to a customer (sale -> customer)
  Future<void> transferBillDueToCustomer(DocumentReference billRef, Map<String, dynamic> billData) async {
    final searchController = TextEditingController(text: (billData['customerName'] ?? ''));
    String? selectedCustomerId;
    Map<String, dynamic>? selectedCustomerData;

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text("Transfer Due to Customer"),
              content: SizedBox(
                width: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(controller: searchController, decoration: const InputDecoration(labelText: "Search or type name"), onChanged: (_) => setState(() {})),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 220,
                      child: StreamBuilder<QuerySnapshot>(
                        stream: firestore
                            .collection('customers')
                            .orderBy('nameLower')
                            .startAt([searchController.text.trim().toLowerCase()])
                            .endAt([searchController.text.trim().toLowerCase() + '\uf8ff'])
                            .limit(20)
                            .snapshots(),
                        builder: (context, snap) {
                          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                          final docs = snap.data!.docs;
                          if (docs.isEmpty) return const Center(child: Text("No customer found. Type a new name to create."));
                          return ListView.builder(
                            itemCount: docs.length,
                            itemBuilder: (_, i) {
                              final d = docs[i];
                              final data = d.data() as Map<String, dynamic>;
                              return ListTile(
                                title: Text(data['name'] ?? ''),
                                subtitle: Text("${data['address'] ?? 'No address'} • ${data['phone'] ?? 'No phone'}"),
                                onTap: () {
                                  selectedCustomerId = d.id;
                                  selectedCustomerData = data;
                                  searchController.text = data['name'] ?? '';
                                  setState(() {});
                                },
                                selected: selectedCustomerId == d.id,
                              );
                            },
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text("If customer not found, the typed name will be created."),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
                ElevatedButton(
                  onPressed: () async {
                    final typedName = searchController.text.trim();
                    if (typedName.isEmpty) return;

                    final batch = firestore.batch();
                    String customerId;
                    Map<String, dynamic> customerDataToUse = {};

                    if (selectedCustomerId != null) {
                      customerId = selectedCustomerId!;
                      customerDataToUse = selectedCustomerData ?? {};
                      final custRef = firestore.collection('customers').doc(customerId);
                      batch.update(custRef, {'totalDue': FieldValue.increment((billData['due'] ?? 0))});
                      batch.set(custRef.collection('customer_dues').doc(), {
                        'type': 'due',
                        'amount': (billData['due'] ?? 0),
                        'createdAt': FieldValue.serverTimestamp(),
                      });
                    } else {
                      final newCustRef = firestore.collection('customers').doc();
                      customerId = newCustRef.id;
                      customerDataToUse = {
                        'name': typedName,
                        'nameLower': typedName.toLowerCase(),
                        'phone': billData['customerPhone'] ?? null,
                        'address': billData['customerAddress'] ?? null,
                        'totalDue': (billData['due'] ?? 0),
                        'createdAt': FieldValue.serverTimestamp(),
                      };
                      batch.set(newCustRef, customerDataToUse);
                      batch.set(newCustRef.collection('customer_dues').doc(), {
                        'type': 'due',
                        'amount': (billData['due'] ?? 0),
                        'createdAt': FieldValue.serverTimestamp(),
                      });
                    }

                    // set sale due to 0 and mark as transferred
                    batch.update(billRef, {
                      'due': 0,
                      'dueTransferred': true,
                      'transferredTo': customerId,
                      'transferredAt': FieldValue.serverTimestamp(),
                    });

                    await batch.commit();
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Transferred \u09F3 ${(billData['due'] ?? 0)} to $typedName")));
                  },
                  child: const Text("Transfer"),
                ),
              ],
            );
          },
        );
      },
    );
  }

    @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          "Sales",
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white),
        ),
        elevation: 0,
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(icon: const Icon(Icons.calendar_today), onPressed: pickDate),
          IconButton(
            icon: const Icon(Icons.people),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomerDueListPage())),
            tooltip: "Customer Due List",
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'new_bill',
        backgroundColor: _accent,
        child: const Icon(Icons.add, color: Colors.black),
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => NewBillPage(date: dateString))),
      ),
      body: Stack(
        children: [
          _buildBackdrop(),
          SafeArea(
            child: StreamBuilder<QuerySnapshot>(
              stream: salesStream(dateString),
              builder: (context, salesSnap) {
                if (salesSnap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: Colors.white));
                }
                final salesDocs = salesSnap.data?.docs ?? [];

                return StreamBuilder<QuerySnapshot>(
                  stream: dueEntriesStream(dateString),
                  builder: (context, dueSnap) {
                    if (dueSnap.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator(color: Colors.white));
                    }
                    final dueDocs = dueSnap.data?.docs ?? [];

                    // Merge sales + due_entries
                    final List<Map<String, dynamic>> merged = [];

                    for (final s in salesDocs) {
                      final data = s.data() as Map<String, dynamic>;
                      merged.add({
                        'kind': 'sale',
                        'id': s.id,
                        'docRef': s.reference,
                        'createdAt': (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
                        'data': data,
                      });
                    }

                    for (final d in dueDocs) {
                      final data = d.data() as Map<String, dynamic>;
                      merged.add({
                        'kind': 'due',
                        'id': d.id,
                        'docRef': d.reference,
                        'createdAt': (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
                        'data': data,
                      });
                    }

                    merged.sort((a, b) => (b['createdAt'] as DateTime).compareTo(a['createdAt'] as DateTime));

                    // Calculate daily total as sum of paid amounts only:
                    // - For sales: add the 'paid' field (not subTotal)
                    // - For due_entries: add 'amount' when type == 'paid'
                    dailyTotal = 0.0;
                    for (final item in merged) {
                      if (item['kind'] == 'sale') {
                        final data = item['data'] as Map<String, dynamic>;
                        dailyTotal += ((data['paid'] ?? 0) as num).toDouble();
                      } else {
                        final data = item['data'] as Map<String, dynamic>;
                        if ((data['type'] ?? '') == 'paid') {
                          dailyTotal += ((data['amount'] ?? 0) as num).toDouble();
                        }
                      }
                    }

                    return StreamBuilder<QuerySnapshot>(
                      stream: bkashTxStream(dateString),
                      builder: (context, bkashSnap) {
                        final bkashDocs = bkashSnap.data?.docs ?? [];
                        double totalSend = 0.0;
                        double customerDueSend = 0.0;

                        for (final d in dueDocs) {
                          final data = d.data() as Map<String, dynamic>? ?? {};
                          final type = (data['type'] ?? '').toString();
                          final source = (data['source'] ?? '').toString();
                          if (type == 'due' && source == 'sell') {
                            final amt = data['amount'];
                            double amount = 0.0;
                            if (amt is num) {
                              amount = amt.toDouble();
                            } else if (amt != null) {
                              amount = double.tryParse(amt.toString()) ?? 0.0;
                            }
                            customerDueSend += amount;
                          }
                        }

                        for (final d in bkashDocs) {
                          final data = d.data() as Map<String, dynamic>? ?? {};
                          final mode = (data['mode'] ?? '').toString();
                          final action = (data['action'] ?? '').toString();
                          final source = (data['source'] ?? '').toString();
                          if (mode == 'company' && action == 'send' && source == 'sell') {
                            final amount = ((data['finalAmount'] ?? data['amount'] ?? 0) as num).toDouble();
                            totalSend += amount;
                          }
                        }
                        totalSend += customerDueSend;

                        final List<Map<String, dynamic>> mergedAll = List<Map<String, dynamic>>.from(merged);
                        for (final d in bkashDocs) {
                          final data = d.data() as Map<String, dynamic>? ?? {};
                          final mode = (data['mode'] ?? '').toString();
                          final action = (data['action'] ?? '').toString();
                          final source = (data['source'] ?? '').toString();
                          if (mode == 'company' && action == 'send' && source == 'sell') {
                            mergedAll.add({
                              'kind': 'company_send',
                              'id': d.id,
                              'docRef': d.reference,
                              'createdAt': (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
                              'data': data,
                            });
                          }
                        }
                        mergedAll.sort((a, b) => (b['createdAt'] as DateTime).compareTo(a['createdAt'] as DateTime));

                        final mergedAllDisplay = mergedAll.where((item) {
                          final data = item['data'] as Map<String, dynamic>? ?? {};
                          return data['hidden'] != true;
                        }).toList();

                        return Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 6),
                              Text(
                                "Date: $dateString",
                                style: const TextStyle(color: Colors.white70, fontSize: 12),
                              ),
                              if (_canViewDailyTotal) ...[
                                const SizedBox(height: 10),
                                _glassCard(
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
                                        child: const Icon(Icons.attach_money, color: _accent),
                                      ),
                                      const SizedBox(width: 12),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text("Daily Total", style: TextStyle(color: Colors.white70, fontSize: 12)),
                                          Text(
                                            "\u09F3 ${dailyTotal.toStringAsFixed(2)}",
                                            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                                          ),
                                        ],
                                      ),
                                      const Spacer(),
                                      TextButton.icon(
                                        onPressed: pickDate,
                                        icon: const Icon(Icons.calendar_today, size: 18, color: Colors.white70),
                                        label: const Text(
                                          "Change",
                                          style: TextStyle(color: Colors.white70, fontSize: 12),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              if (_canViewDailyTotal) ...[
                                const SizedBox(height: 10),
                                _glassCard(
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 40,
                                        height: 40,
                                        decoration: BoxDecoration(
                                          color: Colors.orangeAccent.withOpacity(0.2),
                                          shape: BoxShape.circle,
                                          border: Border.all(color: Colors.orangeAccent.withOpacity(0.6)),
                                        ),
                                        child: const Icon(Icons.send, color: Colors.orangeAccent),
                                      ),
                                      const SizedBox(width: 12),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text("Total Send", style: TextStyle(color: Colors.white70, fontSize: 12)),
                                          Text(
                                            "\u09F3 ${totalSend.toStringAsFixed(2)}",
                                            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              const SizedBox(height: 14),
                              const Text(
                                "Transactions",
                                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 10),
                              Expanded(
                                child: mergedAllDisplay.isEmpty
                                    ? const Center(child: Text("No records for this day.", style: TextStyle(color: Colors.white70)))
                                    : ListView.builder(
                                      itemCount: mergedAllDisplay.length,
                                      itemBuilder: (_, index) {
                                        final item = mergedAllDisplay[index];
                                        if (item['kind'] == 'company_send') {
                                        final Map<String, dynamic> data = item['data'];
                                        final name = (data['name'] ?? data['companyName'] ?? 'Unknown').toString();
                                        final amount = ((data['finalAmount'] ?? data['amount'] ?? 0) as num).toDouble();
                                        final ref = (data['reference'] ?? '').toString();
                                        final time = (data['createdAt'] as Timestamp?) != null
                                            ? DateFormat('dd MMM yyyy, hh:mm a')
                                                .format((data['createdAt'] as Timestamp).toDate())
                                            : '';

                                        return Container(
                                          margin: const EdgeInsets.symmetric(vertical: 6),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withOpacity(0.08),
                                            borderRadius: BorderRadius.circular(16),
                                            border: Border.all(color: Colors.white.withOpacity(0.16)),
                                          ),
                                          child: Padding(
                                            padding: const EdgeInsets.all(12),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                      decoration: BoxDecoration(
                                                        color: Colors.redAccent.withOpacity(0.2),
                                                        borderRadius: BorderRadius.circular(999),
                                                      ),
                                                      child: const Text(
                                                        'Company Send',
                                                        style: TextStyle(
                                                          color: Colors.redAccent,
                                                          fontWeight: FontWeight.w700,
                                                          fontSize: 12,
                                                        ),
                                                      ),
                                                    ),
                                                    const Spacer(),
                                                    if (time.isNotEmpty)
                                                      Text(time, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                                                  ],
                                                ),
                                                const SizedBox(height: 8),
                                                Text('Company: $name', style: const TextStyle(color: Colors.white)),
                                                Text('Amount: \u09F3 ${amount.toStringAsFixed(2)}',
                                                    style: const TextStyle(color: Colors.white70)),
                                                if (ref.isNotEmpty)
                                                  Text('Ref: $ref', style: const TextStyle(color: Colors.white60, fontSize: 11)),
                                              ],
                                            ),
                                          ),
                                        );
                                        }
                                        if (item['kind'] == 'sale') {
                                        final Map<String, dynamic> data = item['data'];
                                        final items = (data['items'] as List?) ?? [];
                                        final subTotal = ((data['subTotal'] ?? 0) as num).toDouble();
                                        final paid = ((data['paid'] ?? 0) as num).toDouble();
                                        final due = ((data['due'] ?? 0) as num).toDouble();
                                        final dueTransferred = (data['dueTransferred'] ?? false) as bool;
                                        final time = (data['createdAt'] as Timestamp?) != null ? DateFormat('hh:mm a').format((data['createdAt'] as Timestamp).toDate()) : '';
                                        final fromPharmacyName = (data['fromPharmacyName'] ?? '').toString();
                                        final dueColor = due > 0 ? Colors.orangeAccent : Colors.white70;

                                        return Container(
                                          margin: const EdgeInsets.symmetric(vertical: 6),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withOpacity(0.08),
                                            borderRadius: BorderRadius.circular(16),
                                            border: Border.all(color: Colors.white.withOpacity(0.16)),
                                          ),
                                          /* child: ListTile(
                                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                            title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                              if (fromPharmacyName.isNotEmpty)
                                                Padding(
                                                  padding: const EdgeInsets.only(bottom: 6.0),
                                                  child: Text("Payment from: $fromPharmacyName", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                                ),
                                              ...items.map((it) => Text("${it['name']} ${it['qty']} × ${it['price']} = ${it['total']}", style: const TextStyle(color: Colors.white))).toList(),
                                              const SizedBox(height: 8),
                                              Wrap(
                                                spacing: 8,
                                                runSpacing: 8,
                                                children: [
                                                  _infoChip('Total', '\u09F3 $subTotal', color: _accent),
                                                  _infoChip('Paid', '\u09F3 $paid', color: Colors.greenAccent),
                                                  _infoChip('Due', '\u09F3 $due', color: dueColor),
                                                ],
                                              ),
                                              const SizedBox(height: 6),
                                              Text("Time: $time", style: const TextStyle(fontSize: 12, color: Colors.white60)),
                                              const SizedBox(height: 4),
                                              Text("C Jononi Pharmacy, Shunashar", style: TextStyle(color: Colors.grey[300], fontStyle: FontStyle.italic)),
                                            ]),
                                            onTap: () {
                                              Navigator.push(context, MaterialPageRoute(builder: (_) => EditBillPage(date: dateString, billId: item['id'], billData: data)));
                                            },
                                            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                              IconButton(icon: const Icon(Icons.share, color: Colors.white), onPressed: () => shareBill(data)),
                                              if (due > 0 && !dueTransferred)
                                                IconButton(icon: const Icon(Icons.person_add_alt_1, color: Colors.white), tooltip: "Transfer due to customer", onPressed: () => transferBillDueToCustomer(item['docRef'] as DocumentReference, data)),
                                              if (dueTransferred) const Icon(Icons.check_circle, color: Colors.greenAccent),
                                            ]),
                                          ), */
                                          child: InkWell(
                                            borderRadius: BorderRadius.circular(16),
                                            onTap: () {
                                              Navigator.push(context, MaterialPageRoute(builder: (_) => EditBillPage(date: dateString, billId: item['id'], billData: data)));
                                            },
                                            child: Padding(
                                              padding: const EdgeInsets.all(12),
                                              child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                      decoration: BoxDecoration(
                                                        color: _accent.withOpacity(0.18),
                                                        borderRadius: BorderRadius.circular(999),
                                                      ),
                                                      child: const Text(
                                                        'Sale',
                                                        style: TextStyle(color: _accent, fontWeight: FontWeight.w700, fontSize: 12),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    if (fromPharmacyName.isNotEmpty)
                                                      Expanded(
                                                        child: Text(
                                                          "From: $fromPharmacyName",
                                                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                                                          overflow: TextOverflow.ellipsis,
                                                        ),
                                                      )
                                                    else
                                                      const Spacer(),
                                                    Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        IconButton(
                                                          icon: const Icon(Icons.share, color: Colors.white),
                                                          onPressed: () => shareBill(data),
                                                        ),
                                                        if (due > 0 && !dueTransferred)
                                                          IconButton(
                                                            icon: const Icon(Icons.person_add_alt_1, color: Colors.white),
                                                            tooltip: "Transfer due to customer",
                                                            onPressed: () => transferBillDueToCustomer(item['docRef'] as DocumentReference, data),
                                                          ),
                                                        if (dueTransferred)
                                                          const Icon(Icons.check_circle, color: Colors.greenAccent),
                                                      ],
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 8),
                                                ...List.generate(items.length, (i) {
                                                  final it = items[i] as Map<String, dynamic>;
                                                  return Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text(
                                                        "${it['name']} ${it['qty']} x \u09F3 ${((it['price'] ?? 0) as num).toDouble().toStringAsFixed(2)} = \u09F3 ${((it['total'] ?? 0) as num).toDouble().toStringAsFixed(2)}",
                                                        style: const TextStyle(color: Colors.white70),
                                                      ),
                                                      if (i != items.length - 1)
                                                        const Divider(color: Colors.white24, height: 12),
                                                    ],
                                                  );
                                                }),
                                                const Divider(color: Colors.white24, height: 12),
                                                Wrap(
                                                  spacing: 8,
                                                  runSpacing: 8,
                                                  children: [
                                                    _infoChip('Total', '\u09F3 $subTotal', color: _accent),
                                                    _infoChip('Paid', '\u09F3 $paid', color: Colors.greenAccent),
                                                    _infoChip('Due', '\u09F3 $due', color: dueColor),
                                                  ],
                                                ),
                                                const SizedBox(height: 8),
                                                Row(
                                                  children: [
                                                    Text("Time: $time", style: const TextStyle(fontSize: 12, color: Colors.white60)),
                                                    const Spacer(),
                                                    Text(
                                                      "C Jononi Pharmacy",
                                                      style: TextStyle(color: Colors.grey[300], fontStyle: FontStyle.italic, fontSize: 12),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                              ),
                                            ),
                                          ),
                                        );
                                      } else {
                                        final Map<String, dynamic> data = item['data'];
                                        final amount = ((data['amount'] ?? 0) as num).toDouble();
                                        final type = (data['type'] ?? 'due') as String;
                                        final name = data['name'] ?? 'Unknown';
                                        final phone = data['phone'] ?? '';
                                        final address = data['address'] ?? '';
                                        final transferred = (data['transferred'] ?? false) as bool;
                                        final time = (data['createdAt'] as Timestamp?) != null ? DateFormat('hh:mm a').format((data['createdAt'] as Timestamp).toDate()) : '';
                                        final isPaid = type == 'paid';

                                        return Container(
                                          margin: const EdgeInsets.symmetric(vertical: 6),
                                          decoration: BoxDecoration(
                                            color: type == 'paid' ? Colors.white.withOpacity(0.08) : Colors.orange.withOpacity(0.12),
                                            borderRadius: BorderRadius.circular(16),
                                            border: Border.all(color: Colors.white.withOpacity(0.16)),
                                          ),
                                          /* child: ListTile(
                                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                            title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                              Row(
                                                children: [
                                                  Container(
                                                    width: 26,
                                                    height: 26,
                                                    decoration: BoxDecoration(
                                                      color: isPaid ? Colors.greenAccent.withOpacity(0.18) : Colors.orange.withOpacity(0.2),
                                                      borderRadius: BorderRadius.circular(8),
                                                    ),
                                                    child: Icon(isPaid ? Icons.call_received : Icons.call_made, size: 16, color: isPaid ? Colors.greenAccent : Colors.orangeAccent),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: Text(
                                                      isPaid ? "Payment - $name" : "Due Card - $name",
                                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 8),
                                              Wrap(
                                                spacing: 8,
                                                runSpacing: 8,
                                                children: [
                                                  _infoChip('Amount', '\u09F3 $amount', color: isPaid ? Colors.greenAccent : Colors.orangeAccent),
                                                ],
                                              ),
                                              if (phone != null && phone != '') Text("Phone: $phone", style: const TextStyle(color: Colors.white70)),
                                              if (address != null && address != '') Text("Address: $address", style: const TextStyle(color: Colors.white70)),
                                              Text("Time: $time", style: const TextStyle(fontSize: 12, color: Colors.white60)),
                                              const SizedBox(height: 4),
                                              Text("C Jononi Pharmacy, Shunashar", style: TextStyle(color: Colors.grey[300], fontStyle: FontStyle.italic)),
                                            ]),
                                            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                              if (type == 'due' && transferred == false)
                                                IconButton(icon: const Icon(Icons.person_add_alt_1, color: Colors.white), tooltip: "Transfer to customer", onPressed: () => transferDueEntryToCustomer(item['docRef'] as DocumentReference, data)),
                                              IconButton(icon: const Icon(Icons.share, color: Colors.white), onPressed: () async {
                                                try {
                                                  final ByteData fontData = await rootBundle.load('assets/fonts/NotoSansBengali-Regular.ttf');
                                                  final pw.Font ttf = pw.Font.ttf(fontData);

                                                  final pdf = pw.Document();
                                                  pdf.addPage(pw.Page(build: (pw.Context context) {
                                                    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                                                      pw.Text(type == 'paid' ? "Payment - $name" : "Due - $name", style: pw.TextStyle(font: ttf, fontSize: 16, fontWeight: pw.FontWeight.bold)),
                                                      pw.SizedBox(height: 6),
                                                      pw.Text("Amount: \u09F3 $amount", style: pw.TextStyle(font: ttf)),
                                                      if (phone != null && phone != '') pw.Text("Phone: $phone", style: pw.TextStyle(font: ttf)),
                                                      if (address != null && address != '') pw.Text("Address: $address", style: pw.TextStyle(font: ttf)),
                                                      pw.SizedBox(height: 12),
                                                      pw.Text("C Jononi Pharmacy, Shunashar", style: pw.TextStyle(font: ttf, fontStyle: pw.FontStyle.italic)),
                                                    ]);
                                                  }));
                                                  await Printing.sharePdf(bytes: await pdf.save(), filename: "${type}_$name.pdf");
                                                } catch (e, st) {
                                                  debugPrint('share quick pdf error: $e\n$st');
                                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to create PDF: $e")));
                                                }
                                              }),
                                            ]),
                                          ), */
                                          child: Padding(
                                            padding: const EdgeInsets.all(12),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Container(
                                                      width: 28,
                                                      height: 28,
                                                      decoration: BoxDecoration(
                                                        color: isPaid ? Colors.greenAccent.withOpacity(0.18) : Colors.orange.withOpacity(0.2),
                                                        borderRadius: BorderRadius.circular(8),
                                                      ),
                                                      child: Icon(isPaid ? Icons.call_received : Icons.call_made, size: 16, color: isPaid ? Colors.greenAccent : Colors.orangeAccent),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Expanded(
                                                      child: Text(
                                                        isPaid ? "Payment - $name" : "Due Card - $name",
                                                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                                      ),
                                                    ),
                                                    Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        if (type == 'due' && transferred == false)
                                                          IconButton(
                                                            icon: const Icon(Icons.person_add_alt_1, color: Colors.white),
                                                            tooltip: "Transfer to customer",
                                                            onPressed: () => transferDueEntryToCustomer(item['docRef'] as DocumentReference, data),
                                                          ),
                                                        IconButton(
                                                          icon: const Icon(Icons.share, color: Colors.white),
                                                          onPressed: () async {
                                                            try {
                                                              final ByteData fontData = await rootBundle.load('assets/fonts/NotoSansBengali-Regular.ttf');
                                                              final pw.Font ttf = pw.Font.ttf(fontData);

                                                              final pdf = pw.Document();
                                                              pdf.addPage(pw.Page(build: (pw.Context context) {
                                                                return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                                                                  pw.Text(type == 'paid' ? "Payment - $name" : "Due - $name", style: pw.TextStyle(font: ttf, fontSize: 16, fontWeight: pw.FontWeight.bold)),
                                                                  pw.SizedBox(height: 6),
                                                                  pw.Text("Amount: \u09F3 $amount", style: pw.TextStyle(font: ttf)),
                                                                  if (phone != null && phone != '') pw.Text("Phone: $phone", style: pw.TextStyle(font: ttf)),
                                                                  if (address != null && address != '') pw.Text("Address: $address", style: pw.TextStyle(font: ttf)),
                                                                  pw.SizedBox(height: 12),
                                                                  pw.Text("C Jononi Pharmacy, Shunashar", style: pw.TextStyle(font: ttf, fontStyle: pw.FontStyle.italic)),
                                                                ]);
                                                              }));
                                                              await Printing.sharePdf(bytes: await pdf.save(), filename: "${type}_$name.pdf");
                                                            } catch (e, st) {
                                                              debugPrint('share quick pdf error: $e\n$st');
                                                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to create PDF: $e")));
                                                            }
                                                          },
                                                        ),
                                                      ],
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 8),
                                                Wrap(
                                                  spacing: 8,
                                                  runSpacing: 8,
                                                  children: [
                                                    _infoChip('Amount', '\u09F3 $amount', color: isPaid ? Colors.greenAccent : Colors.orangeAccent),
                                                  ],
                                                ),
                                                if (phone != null && phone != '') Text("Phone: $phone", style: const TextStyle(color: Colors.white70)),
                                                if (address != null && address != '') Text("Address: $address", style: const TextStyle(color: Colors.white70)),
                                                const SizedBox(height: 6),
                                                Row(
                                                  children: [
                                                    Text("Time: $time", style: const TextStyle(fontSize: 12, color: Colors.white60)),
                                                    const Spacer(),
                                                    Text(
                                                      "C Jononi Pharmacy",
                                                      style: TextStyle(color: Colors.grey[300], fontStyle: FontStyle.italic, fontSize: 12),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      }
                                    },
                                  ),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
          Positioned(
            left: 16,
            bottom: 16,
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FloatingActionButton(
                    heroTag: 'customer_due_send',
                    mini: true,
                    backgroundColor: Colors.orangeAccent,
                    onPressed: _openCustomerDueSendDialog,
                    tooltip: 'Customer Due',
                    child: const Icon(Icons.person_add_alt_1, color: Colors.black),
                  ),
                  const SizedBox(height: 10),
                  FloatingActionButton(
                    heroTag: 'company_send',
                    mini: true,
                    backgroundColor: Colors.redAccent,
                    onPressed: _openCompanySendDialog,
                    tooltip: 'Company Send',
                    child: const Icon(Icons.add, color: Colors.black),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Helper to transfer a due-entry (created from SellPage) to a customer
  Future<void> transferDueEntryToCustomer(DocumentReference entryRef, Map<String, dynamic> entryData) async {
    // reuse logic similar to transferBillDueToCustomer but simpler (entry -> customer)
    final searchController = TextEditingController(text: (entryData['name'] ?? ''));
    String? selectedCustomerId;
    Map<String, dynamic>? selectedCustomerData;

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (context, setState) {
          return AlertDialog(
            title: const Text("Transfer Due Card to Customer"),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: searchController, decoration: const InputDecoration(labelText: "Search or type name"), onChanged: (_) => setState(() {})),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 220,
                    child: StreamBuilder<QuerySnapshot>(
                      stream: firestore
                          .collection('customers')
                          .orderBy('nameLower')
                          .startAt([searchController.text.trim().toLowerCase()])
                          .endAt([searchController.text.trim().toLowerCase() + '\uf8ff'])
                          .limit(20)
                          .snapshots(),
                      builder: (context, snap) {
                        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                        final docs = snap.data!.docs;
                        if (docs.isEmpty) return const Center(child: Text("No customer found. Type a new name to create."));
                        return ListView.builder(
                          itemCount: docs.length,
                          itemBuilder: (_, i) {
                            final d = docs[i];
                            final data = d.data() as Map<String, dynamic>;
                            return ListTile(
                              title: Text(data['name'] ?? ''),
                              subtitle: Text("${data['address'] ?? 'No address'} • ${data['phone'] ?? 'No phone'}"),
                              onTap: () {
                                selectedCustomerId = d.id;
                                selectedCustomerData = data;
                                searchController.text = data['name'] ?? '';
                                setState(() {});
                              },
                              selected: selectedCustomerId == d.id,
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
              TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
              ElevatedButton(
                onPressed: () async {
                  final typedName = searchController.text.trim();
                  if (typedName.isEmpty) return;
                  final batch = firestore.batch();
                  String customerId;
                  if (selectedCustomerId != null) {
                    customerId = selectedCustomerId!;
                    final custRef = firestore.collection('customers').doc(customerId);
                    batch.update(custRef, {'totalDue': FieldValue.increment((entryData['amount'] ?? 0))});
                    batch.set(custRef.collection('customer_dues').doc(), {
                      'type': 'due',
                      'amount': (entryData['amount'] ?? 0),
                      'createdAt': FieldValue.serverTimestamp(),
                    });
                  } else {
                    final newCustRef = firestore.collection('customers').doc();
                    customerId = newCustRef.id;
                    batch.set(newCustRef, {
                      'name': typedName,
                      'nameLower': typedName.toLowerCase(),
                      'phone': entryData['phone'] ?? null,
                      'address': entryData['address'] ?? null,
                      'totalDue': (entryData['amount'] ?? 0),
                      'createdAt': FieldValue.serverTimestamp(),
                    });
                    batch.set(newCustRef.collection('customer_dues').doc(), {
                      'type': 'due',
                      'amount': (entryData['amount'] ?? 0),
                      'createdAt': FieldValue.serverTimestamp(),
                    });
                  }

                  batch.update(entryRef, {'transferred': true, 'transferredTo': customerId, 'transferredAt': FieldValue.serverTimestamp()});
                  await batch.commit();
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Transferred \u09F3 ${(entryData['amount'] ?? 0)} to $typedName")));
                },
                child: const Text("Transfer"),
              ),
            ],
          );
        });
      },
    );
  }
}




