// NewOrderPage.dart
import 'dart:async';
import 'dart:ui';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'EditOrderPage.dart';

const Color _bgStart = Color(0xFF041A14);
const Color _bgEnd = Color(0xFF0E5A42);
const Color _accent = Color(0xFFFFD166);

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

class NewOrderPage extends StatefulWidget {
  final String companyId;
  final String companyName;

  const NewOrderPage({Key? key, required this.companyId, required this.companyName}) : super(key: key);

  @override
  State<NewOrderPage> createState() => _NewOrderPageState();
}

class _NewOrderPageState extends State<NewOrderPage> {
  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  double totalDue = 0.0;
  bool _isClearing = false;
  bool _isResetting = false;
  List<Map<String, dynamic>> _latestEntries = [];
  String _currentUserRole = 'seller';

  List<Map<String, dynamic>> items = [];
  TextEditingController paidController = TextEditingController(text: "0");

  double get subTotal => items.fold(0.0, (sum, i) => sum + ((i['total'] ?? 0) as num).toDouble());
  double get paid => double.tryParse(paidController.text) ?? 0.0;
  double get due => subTotal - paid;

  String _fmtNum(dynamic v) {
    if (v is num) return v.toStringAsFixed(2);
    final n = double.tryParse(v.toString());
    return (n ?? 0.0).toStringAsFixed(2);
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
      ),
    );
  }

  String _normCompanyKey(String v) {
    return v.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
  }

  String _normalizeRole(String? role) {
    if (role == null) return '';
    return role.toLowerCase().replaceAll(RegExp(r'[\s\-]+'), '_').trim();
  }

  Future<void> _loadMyRole() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final doc = await firestore.collection('users').doc(user.uid).get();
      if (doc.exists) {
        final data = doc.data();
        if (!mounted) return;
        setState(() {
          _currentUserRole = (data?['role'] ?? 'seller').toString();
        });
      }
    } catch (_) {
      // keep default role
    }
  }

  bool get _isAdmin {
    final nr = _normalizeRole(_currentUserRole);
    return nr == 'admin';
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

  bool _matchesCompanyOrderDoc(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    var cid = (data['companyId'] ?? '').toString().trim();
    if (cid.isEmpty) {
      cid = _companyIdFromOrderPath(doc.reference.path) ?? '';
    }
    final companyIdNorm = _normCompanyKey(widget.companyId);
    final cidNorm = _normCompanyKey(cid);
    if (cid.isNotEmpty && (cid == widget.companyId || cidNorm == companyIdNorm)) {
      return true;
    }
    final name = (data['companyName'] ?? data['company'] ?? '').toString().trim();
    if (name.isNotEmpty && _normCompanyKey(name) == _normCompanyKey(widget.companyName)) {
      return true;
    }
    return false;
  }

  bool _matchesCompanyPaymentDoc(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final mode = (data['mode'] ?? '').toString().trim().toLowerCase();
    if (mode != 'company') return false;
    final cid = (data['companyId'] ?? '').toString().trim();
    if (cid.isNotEmpty) {
      if (cid == widget.companyId || _normCompanyKey(cid) == _normCompanyKey(widget.companyId)) {
        return true;
      }
    }
    final name = (data['name'] ?? data['companyName'] ?? '').toString().trim();
    if (name.isNotEmpty && _normCompanyKey(name) == _normCompanyKey(widget.companyName)) {
      return true;
    }
    return false;
  }

  DocumentReference? _entryRef(Map<String, dynamic> entry) {
    final type = entry['type'];
    if (type == 'payment') return entry['ref'] as DocumentReference?;
    final data = entry['data'] as Map<String, dynamic>? ?? {};
    return data['__docRef'] as DocumentReference?;
  }

  String _entryTitle(Map<String, dynamic> entry) {
    final type = entry['type'];
    if (type == 'payment') return 'Payment';
    return 'Order';
  }

  String _entrySubtitle(Map<String, dynamic> entry) {
    final data = entry['data'] as Map<String, dynamic>? ?? {};
    final ts = data['createdAt'];
    final timeLabel =
        (ts is Timestamp) ? DateFormat('dd MMM yyyy, hh:mm a').format(ts.toDate()) : '';
    if (entry['type'] == 'payment') {
      final amountRaw = data['finalAmount'] ?? data['amount'] ?? 0;
      final amount = (amountRaw is num)
          ? amountRaw.toDouble()
          : double.tryParse(amountRaw.toString()) ?? 0.0;
      return 'Amount: ৳ ${amount.toStringAsFixed(2)}${timeLabel.isEmpty ? '' : ' • $timeLabel'}';
    }
    final finalAmt = _computeFinalFromOrderData(data);
    final paid = (data['paid'] is num)
        ? (data['paid'] as num).toDouble()
        : double.tryParse('${data['paid']}') ?? 0.0;
    final due = (data['due'] is num) ? (data['due'] as num).toDouble() : (finalAmt - paid);
    return 'Final: ৳ ${finalAmt.toStringAsFixed(2)} • Due: ৳ ${due.toStringAsFixed(2)}'
        '${timeLabel.isEmpty ? '' : ' • $timeLabel'}';
  }

  Future<void> _hideEntries(List<Map<String, dynamic>> entries) async {
    if (entries.isEmpty) return;
    if (_isClearing) return;
    setState(() => _isClearing = true);
    try {
      WriteBatch batch = firestore.batch();
      int batchCount = 0;
      Future<void> flush() async {
        if (batchCount == 0) return;
        await batch.commit();
        batch = firestore.batch();
        batchCount = 0;
      }

      for (final entry in entries) {
        final ref = _entryRef(entry);
        if (ref == null) continue;
        batch.update(ref, {
          'hidden': true,
          'hiddenAt': FieldValue.serverTimestamp(),
        });
        batchCount++;
        if (batchCount >= 450) {
          await flush();
        }
      }
      await flush();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Chat cleared')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to clear: $e')));
    } finally {
      if (!mounted) return;
      setState(() => _isClearing = false);
    }
  }

  Future<void> _showClearChatOptions() async {
    if (!_isAdmin) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Only admin can clear chat.')));
      }
      return;
    }
    if (_isClearing) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: _bgEnd,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(8)),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.delete_sweep, color: _accent),
              title: const Text('Clear All', style: TextStyle(color: Colors.white)),
              subtitle: const Text('Remove all chat entries', style: TextStyle(color: Colors.white70)),
              onTap: () => Navigator.pop(context, 'all'),
            ),
            ListTile(
              leading: const Icon(Icons.checklist, color: _accent),
              title: const Text('Select Items', style: TextStyle(color: Colors.white)),
              subtitle: const Text('Pick items to clear', style: TextStyle(color: Colors.white70)),
              onTap: () => Navigator.pop(context, 'select'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (action == 'all') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: _bgEnd,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Text('Clear all chat?'),
          content: const Text('This will hide all chat entries. Due will not change.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Clear')),
          ],
        ),
      );
      if (ok == true) {
        await _hideEntries(List<Map<String, dynamic>>.from(_latestEntries));
      }
    } else if (action == 'select') {
      await _showClearChatSelectDialog();
    }
  }

  Future<void> _showClearChatSelectDialog() async {
    final entries = List<Map<String, dynamic>>.from(_latestEntries);
    if (entries.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No chat entries to clear')));
      return;
    }
    final selected = <int>{};
    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: _bgEnd,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Text('Select entries'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: entries.length,
              itemBuilder: (_, i) {
                return CheckboxListTile(
                  value: selected.contains(i),
                  onChanged: (v) {
                    setState(() {
                      if (v == true) {
                        selected.add(i);
                      } else {
                        selected.remove(i);
                      }
                    });
                  },
                  title: Text(_entryTitle(entries[i]), style: const TextStyle(color: Colors.white)),
                  subtitle: Text(_entrySubtitle(entries[i]), style: const TextStyle(color: Colors.white70)),
                  controlAffinity: ListTileControlAffinity.leading,
                );
              },
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: selected.isEmpty
                  ? null
                  : () {
                      Navigator.pop(context, selected.toList());
                    },
              child: const Text('Clear Selected'),
            ),
          ],
        ),
      ),
    ).then((value) async {
      if (value is List && value.isNotEmpty) {
        final toHide = <Map<String, dynamic>>[];
        for (final idx in value) {
          if (idx is int && idx >= 0 && idx < entries.length) {
            toHide.add(entries[idx]);
          }
        }
        await _hideEntries(toHide);
      }
    });
  }

  Future<void> _resetCompanyOrders() async {
    if (!_isAdmin) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Only admin can reset orders.')));
      }
      return;
    }
    if (_isResetting) return;
    final confirmCtrl = TextEditingController();
    bool isConfirming = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: _bgEnd,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Text('Danger: Reset Orders'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'WARNING: This will permanently delete ALL orders and company payment history '
                'for this company from the database. There is NO UNDO. Due will become 0.',
                style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              const Text(
                'Make sure you really want to do this.',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 12),
              const Text('Type RESET to confirm:', style: TextStyle(color: Colors.white70)),
              TextField(
                controller: confirmCtrl,
                decoration: const InputDecoration(hintText: 'RESET'),
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: (confirmCtrl.text.trim() == 'RESET' && !isConfirming)
                  ? () {
                      setState(() => isConfirming = true);
                      Navigator.pop(context, true);
                    }
                  : null,
              child: Text(isConfirming ? 'Resetting...' : 'Reset'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    setState(() => _isResetting = true);
    try {
      // delete matching orders
      final ordersSnap = await firestore.collectionGroup('orders').get();
      final orderRefs = <DocumentReference>[];
      final billRefs = <DocumentReference>{};
      for (final d in ordersSnap.docs) {
        if (!_matchesCompanyOrderDoc(d)) continue;
        orderRefs.add(d.reference);
        final billRef = d.reference.parent.parent;
        if (billRef != null) billRefs.add(billRef);
      }

      Future<void> deleteRefs(List<DocumentReference> refs) async {
        WriteBatch batch = firestore.batch();
        int count = 0;
        Future<void> flush() async {
          if (count == 0) return;
          await batch.commit();
          batch = firestore.batch();
          count = 0;
        }
        for (final r in refs) {
          batch.delete(r);
          count++;
          if (count >= 450) {
            await flush();
          }
        }
        await flush();
      }

      if (orderRefs.isNotEmpty) {
        await deleteRefs(orderRefs);
      }
      if (billRefs.isNotEmpty) {
        await deleteRefs(billRefs.toList());
      }

      // delete company payment transactions
      final txSnap = await firestore.collectionGroup('transactions').get();
      final payRefs = <DocumentReference>[];
      for (final d in txSnap.docs) {
        if (_matchesCompanyPaymentDoc(d)) {
          payRefs.add(d.reference);
        }
      }
      if (payRefs.isNotEmpty) {
        await deleteRefs(payRefs);
      }

      // clear company payments summary
      await firestore.collection('company_payments').doc(widget.companyId).delete();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Company orders reset')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Reset failed: $e')));
    } finally {
      if (!mounted) return;
      setState(() => _isResetting = false);
    }
  }

  Widget _buildPaymentCard(Map<String, dynamic> data) {
    final amountRaw = data['finalAmount'] ?? data['amount'] ?? 0;
    final amount = (amountRaw is num) ? amountRaw.toDouble() : double.tryParse(amountRaw.toString()) ?? 0.0;
    final appliedRaw = data['companyAppliedTotal'] ?? data['companyApplied'] ?? 0;
    final applied = (appliedRaw is num) ? appliedRaw.toDouble() : double.tryParse(appliedRaw.toString()) ?? 0.0;
    final ref = (data['reference'] ?? '').toString().trim();
    final ts = data['createdAt'];
    final timeLabel = (ts is Timestamp) ? DateFormat('dd MMM yyyy, hh:mm a').format(ts.toDate()) : '';

    final source = (data['source'] ?? '').toString().toLowerCase();
    final sourceLabel = source == 'sell' ? 'Sell' : 'bKash';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.18)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: _accent.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.payments, color: _accent, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Text(
                          'Payment • $sourceLabel',
                          style: const TextStyle(color: Colors.white70, fontSize: 10),
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text('Company Payment',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                      Text('Amount: \u09F3 ${amount.toStringAsFixed(2)}',
                          style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      if (applied > 0)
                        Text('Applied: \u09F3 ${applied.toStringAsFixed(2)}',
                            style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      if (ref.isNotEmpty)
                        Text('Ref: $ref', style: const TextStyle(color: Colors.white60, fontSize: 11)),
                      if (timeLabel.isNotEmpty)
                        Text(timeLabel, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> data) {
    final billDate = (data['__billDate'] ?? '').toString();
    final docId = (data['__docId'] ?? '').toString();
    final time = data['createdAt'] != null
        ? DateFormat('hh:mm a').format((data['createdAt'] as Timestamp).toDate())
        : '';
    final displayFinal = (data['finalAmount'] ?? data['subTotal']) as num;
    final paidVal = (data['paid'] is num)
        ? (data['paid'] as num).toDouble()
        : double.tryParse('${data['paid']}') ?? 0.0;
    final dueVal = (displayFinal.toDouble() - paidVal);
    final dueComputed = dueVal < 0 ? 0.0 : dueVal;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withOpacity(0.18)),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => EditOrderPage(
                            companyId: widget.companyId,
                            companyName: widget.companyName,
                            date: billDate,
                            orderId: docId,
                            orderData: data,
                          ),
                        ),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Date: $billDate  Time: $time", style: const TextStyle(color: Colors.white)),
                          const SizedBox(height: 6),
                          ...List.generate(
                            (data['items'] as List).length,
                            (i) {
                              final item = (data['items'] as List)[i];
                              final price = _fmtNum(item['price']);
                              final total = _fmtNum(item['total']);
                              return Text(
                                "${item['name']} ${item['qty']} x $price = $total",
                                style: const TextStyle(color: Colors.white70),
                              );
                            },
                          ),
                          const SizedBox(height: 8),
                          Container(height: 1, color: Colors.white12),
                          const SizedBox(height: 8),
                          Text("Total = \u09F3 ${_fmtNum(data['subTotal'])}", style: const TextStyle(color: Colors.white)),
                          if ((data['finalAmount'] ?? data['subTotal']) != null)
                            Text(
                              "Final amount = \u09F3 ${_fmtNum(displayFinal)}",
                              style: const TextStyle(color: Colors.yellowAccent, fontWeight: FontWeight.bold),
                            ),
                          Text("Paid = \u09F3 ${_fmtNum(paidVal)}", style: const TextStyle(color: Colors.white70)),
                          Text(
                            "Due = \u09F3 ${_fmtNum(dueComputed)}",
                            style: TextStyle(color: dueComputed > 0 ? Colors.redAccent : Colors.greenAccent),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 12,
            right: 12,
            child: InkWell(
              onTap: () => shareOrder(data),
              borderRadius: BorderRadius.circular(18),
              child: Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(
                  color: _accent,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.share, color: Colors.black, size: 18),
              ),
            ),
          ),
        ],
      ),
    );
  }

  final Map<String, List<QueryDocumentSnapshot>> _ordersByBill = {};
  final Map<String, StreamSubscription<QuerySnapshot>> _orderSubs = {};
  StreamSubscription<QuerySnapshot>? _billsSub;
  final StreamController<List<Map<String, dynamic>>> _ordersController = StreamController.broadcast();

  @override
  void initState() {
    super.initState();
    _loadMyRole();
    _startOrdersStream();
  }

  @override
  void dispose() {
    _billsSub?.cancel();
    for (final sub in _orderSubs.values) {
      sub.cancel();
    }
    _ordersController.close();
    super.dispose();
  }

  void _startOrdersStream() {
    final billsRef = firestore.collection('orders').doc(widget.companyId).collection('bills');
    _billsSub = billsRef.orderBy(FieldPath.documentId).snapshots().listen((billSnap) {
      final active = billSnap.docs.map((d) => d.id).toSet();

        if (billSnap.docs.isEmpty) {
          _ordersByBill.clear();
          _ordersController.add(<Map<String, dynamic>>[]);
          if (mounted) setState(() => totalDue = 0.0);
        }

      // remove subscriptions for deleted bills
      final toRemove = _orderSubs.keys.where((k) => !active.contains(k)).toList();
      for (final k in toRemove) {
        _orderSubs[k]?.cancel();
        _orderSubs.remove(k);
        _ordersByBill.remove(k);
      }

      for (final billDoc in billSnap.docs) {
        final billDate = billDoc.id;
        if (_orderSubs.containsKey(billDate)) continue;

        _orderSubs[billDate] = billDoc.reference
            .collection('orders')
            .orderBy('createdAt', descending: true)
            .snapshots()
            .listen((ordersSnap) {
          _ordersByBill[billDate] = ordersSnap.docs;
          _emitCombinedOrders();
        });
      }
    });
  }

  void _emitCombinedOrders() {
    final combined = <Map<String, dynamic>>[];
    totalDue = 0.0;

    _ordersByBill.forEach((billDate, docs) {
      for (final d in docs) {
        final data = d.data() as Map<String, dynamic>? ?? {};
        final paid = (data['paid'] is num) ? (data['paid'] as num).toDouble() : double.tryParse('${data['paid']}') ?? 0.0;
        final finalAmt = _computeFinalFromOrderData(data);
        final dueField = data['due'];
        final due = (dueField is num) ? dueField.toDouble() : double.tryParse('${data['due']}') ?? (finalAmt - paid);
        totalDue += (due < 0 ? 0.0 : due);

        combined.add({
          ...data,
          '__docId': d.id,
          '__billDate': billDate,
          '__docRef': d.reference,
        });
      }
    });

    combined.sort((a, b) {
      final ta = a['createdAt'] is Timestamp ? (a['createdAt'] as Timestamp).toDate() : DateTime(1970);
      final tb = b['createdAt'] is Timestamp ? (b['createdAt'] as Timestamp).toDate() : DateTime(1970);
      return tb.compareTo(ta);
    });

    _ordersController.add(combined);
    if (mounted) setState(() {});
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

  void editItem(int index) {
    final qtyController = TextEditingController(text: items[index]['qty'].toString());
    final priceController = TextEditingController(text: items[index]['price'].toString());

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(items[index]['name']),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: qtyController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: "Quantity"),
            ),
            TextField(
              controller: priceController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: "Price"),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              final qty = int.tryParse(qtyController.text);
              final price = double.tryParse(priceController.text);
              if (qty == null || price == null) return;
              setState(() {
                items[index]['qty'] = qty;
                items[index]['price'] = price;
                items[index]['total'] = qty * price;
              });
              Navigator.pop(context);
            },
            child: const Text("Update"),
          ),
          TextButton(
            onPressed: () {
              setState(() => items.removeAt(index));
              Navigator.pop(context);
            },
            child: const Text("Delete", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> saveOrder() async {
    if (items.isEmpty) return;

    final dateString = DateFormat('yyyy-MM-dd').format(DateTime.now());
    await firestore
        .collection('orders')
        .doc(widget.companyId)
        .collection('bills')
        .doc(dateString)
        .set({'createdAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
    final data = {
      'companyId': widget.companyId,
      'companyName': widget.companyName.trim(),
      'companyNameUpper': widget.companyName.trim().toUpperCase(),
      'items': items,
      'subTotal': subTotal,
      'paid': paid,
      'due': due,
      // finalAmount may be null for new orders; EditOrderPage will set it when used
      'finalAmount': null,
      'createdAt': FieldValue.serverTimestamp(),
    };

    await firestore
        .collection('orders')
        .doc(widget.companyId)
        .collection('bills')
        .doc(dateString)
        .collection('orders')
        .add(data);

    setState(() => items.clear());
    paidController.text = "0";

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Order saved successfully")),
    );
  }

  /// Share order as PDF - uses embedded Bengali-capable font from assets so \u09F3  renders correctly.
  /// Shows fields in the requested order:
  /// Total
  /// Final amount
  /// Paid
  /// Due
  /// Company: <name>
  /// Generated by Jononi Pharmacy, Shunashar.
  Future<void> shareOrder(Map<String, dynamic> orderData) async {
    try {
      // load font from assets (ByteData) and pass ByteData directly to pw.Font.ttf
      final ByteData fontData = await rootBundle.load('assets/fonts/NotoSansBengali-Regular.ttf');
      final pw.Font ttf = pw.Font.ttf(fontData);

      final pdf = pw.Document();
      final itemsList = (orderData['items'] as List?) ?? [];

      String fmt2(dynamic v) {
        if (v is num) return v.toStringAsFixed(2);
        final n = double.tryParse(v.toString());
        return (n ?? 0.0).toStringAsFixed(2);
      }

      // compute a final amount to show:
      // prefer explicit 'finalAmount' when present and non-null,
      // otherwise prefer 'subTotal' if available,
      // otherwise sum items' totals as a last resort.
      double computeFinalAmount() {
        if (orderData.containsKey('finalAmount') && orderData['finalAmount'] != null) {
          final v = orderData['finalAmount'];
          if (v is num) return v.toDouble();
          return double.tryParse(v.toString()) ?? 0.0;
        }
        if (orderData.containsKey('subTotal') && orderData['subTotal'] != null) {
          final v = orderData['subTotal'];
          if (v is num) return v.toDouble();
          return double.tryParse(v.toString()) ?? 0.0;
        }
        // fallback: sum items
        double s = 0.0;
        for (final it in itemsList) {
          try {
            s += ((it['total'] ?? 0) as num).toDouble();
          } catch (_) {}
        }
        return s;
      }

      final double finalAmtToShow = computeFinalAmount();
      final String dateLabel = (orderData['__billDate'] ??
              (orderData['createdAt'] is Timestamp
                  ? DateFormat('yyyy-MM-dd').format((orderData['createdAt'] as Timestamp).toDate())
                  : DateFormat('yyyy-MM-dd').format(DateTime.now())))
          .toString();

      pdf.addPage(
        pw.Page(
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text("Order - $dateLabel",
                    style: pw.TextStyle(font: ttf, fontSize: 18, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 8),
                if (itemsList.isNotEmpty)
                  ...List.generate(itemsList.length, (i) {
                    final item = itemsList[i] as Map<String, dynamic>;
                    final name = item['name'] ?? '';
                    final qty = item['qty'] ?? '';
                    final price = fmt2(item['price'] ?? 0);
                    final total = fmt2(item['total'] ?? 0);
                    return pw.Text(
                      "$name $qty x \u09F3 $price = \u09F3 $total",
                      style: pw.TextStyle(font: ttf, fontSize: 12),
                    );
                  })
                else
                  pw.Text("No items", style: pw.TextStyle(font: ttf)),
                pw.Divider(),

                // ORDERED FIELDS: total, final, paid, due, company, generated by...
                pw.Text("Total = \u09F3 ${fmt2(orderData['subTotal'] ?? 0)}", style: pw.TextStyle(font: ttf, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 4),
                pw.Text("Final amount = \u09F3 ${finalAmtToShow.toStringAsFixed(2)}", style: pw.TextStyle(font: ttf)),
                pw.SizedBox(height: 4),
                pw.Text("Paid = \u09F3 ${fmt2(orderData['paid'] ?? 0)}", style: pw.TextStyle(font: ttf)),
                pw.SizedBox(height: 4),
                pw.Text("Due = \u09F3 ${fmt2(orderData['due'] ?? 0)}", style: pw.TextStyle(font: ttf)),
                pw.SizedBox(height: 10),
                pw.Text("Company: ${widget.companyName}", style: pw.TextStyle(font: ttf, fontStyle: pw.FontStyle.italic)),
                pw.SizedBox(height: 8),
                pw.Text("Generated by Jononi Pharmacy, Shunashar.", style: pw.TextStyle(font: ttf, fontSize: 10)),
              ],
            );
          },
        ),
      );

      final bytes = await pdf.save();

      // Use Printing.sharePdf to open share dialog / save dialog on device.
      await Printing.sharePdf(bytes: bytes, filename: "order.pdf");
    } catch (e, st) {
      // Show error to user so they know why PDF wasn't created
      debugPrint('shareOrder error: $e\n$st');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to create PDF: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final todayString = DateFormat('yyyy-MM-dd').format(DateTime.now());
    return StreamBuilder<QuerySnapshot>(
      stream: firestore.collectionGroup('orders').snapshots(),
      builder: (context, dueSnap) {
        double dueTotal = 0.0;
        if (dueSnap.hasData) {
          for (final d in dueSnap.data!.docs) {
            if (!_matchesCompanyOrderDoc(d)) continue;
            final data = d.data() as Map<String, dynamic>? ?? {};
            final paid = (data['paid'] is num)
                ? (data['paid'] as num).toDouble()
                : double.tryParse('${data['paid']}') ?? 0.0;
            final finalAmt = _computeFinalFromOrderData(data);
            final due = finalAmt - paid;
            if (due > 0) dueTotal += due;
          }
        }

        return Scaffold(
          backgroundColor: Colors.transparent,
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            title: Text(
              "${widget.companyName} - Orders",
              style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white),
            ),
            backgroundColor: Colors.transparent,
            elevation: 0,
            actions: [
              IconButton(
                icon: const Icon(Icons.attach_money, color: Colors.white),
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (_) => Theme(
                      data: Theme.of(context).copyWith(
                        dialogBackgroundColor: _bgEnd,
                        colorScheme: Theme.of(context).colorScheme.copyWith(
                              surface: _bgEnd,
                              onSurface: Colors.white,
                              primary: _accent,
                            ),
                        textTheme: Theme.of(context)
                            .textTheme
                            .apply(bodyColor: Colors.white, displayColor: Colors.white),
                        dividerColor: Colors.white24,
                      ),
                      child: AlertDialog(
                        backgroundColor: _bgEnd,
                        surfaceTintColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                          side: BorderSide(color: Colors.white.withOpacity(0.12)),
                        ),
                        title: const Text("Total Due"),
                        content: Text("Due Amount: \u09F3 ${dueTotal.toStringAsFixed(2)}"),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Close"))
                        ],
                      ),
                    ),
                  );
                },
              ),
              if (_isAdmin)
                PopupMenuButton<String>(
                  enabled: !_isResetting && !_isClearing,
                  icon: const Icon(Icons.more_vert, color: Colors.white),
                  onSelected: (value) {
                    if (value == 'clear') {
                      _showClearChatOptions();
                    } else if (value == 'reset') {
                      _resetCompanyOrders();
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'clear',
                      child: Text('Clear Chat'),
                    ),
                    const PopupMenuItem(
                      value: 'reset',
                      child: Text('Reset Orders'),
                    ),
                  ],
                ),
            ],
          ),
          floatingActionButton: FloatingActionButton(
            backgroundColor: _accent,
            child: const Icon(Icons.add, color: Colors.black),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => EditOrderPage(
                    companyId: widget.companyId,
                    companyName: widget.companyName,
                    date: todayString,
                  ),
                ),
              );
            },
          ),
          body: Stack(
            children: [
              _buildBackdrop(),
              SafeArea(
                child: Column(
                  children: [
                    Expanded(
                      child: StreamBuilder<QuerySnapshot>(
                        stream: firestore.collectionGroup('transactions').snapshots(),
                        builder: (context, paySnap) {
                          if (paySnap.hasError) {
                            return Center(
                              child: Text(
                                'Payments load failed: ${paySnap.error}',
                                style: const TextStyle(color: Colors.white70, fontSize: 12),
                                textAlign: TextAlign.center,
                              ),
                            );
                          }

                          final allDocs =
                              paySnap.hasData ? paySnap.data!.docs : const <QueryDocumentSnapshot>[];
                          final companyNameNorm = _normCompanyKey(widget.companyName);
                          final companyIdNorm = _normCompanyKey(widget.companyId);
                          final paymentDocs = allDocs.where((d) {
                            final data = d.data() as Map<String, dynamic>? ?? {};
                            final mode = (data['mode'] ?? '').toString().trim().toLowerCase();
                            if (mode != 'company') return false;
                            final cid = (data['companyId'] ?? '').toString().trim();
                            final name = (data['name'] ?? data['companyName'] ?? '').toString().trim();
                            final cidNorm = _normCompanyKey(cid);
                            final nameNorm = _normCompanyKey(name);
                            return (cid.isNotEmpty && (cid == widget.companyId || cidNorm == companyIdNorm)) ||
                                (nameNorm.isNotEmpty && nameNorm == companyNameNorm);
                          }).toList()
                            ..sort((a, b) {
                              final da = a.data() as Map<String, dynamic>? ?? {};
                              final db = b.data() as Map<String, dynamic>? ?? {};
                              final ta = da['createdAt'] is Timestamp
                                  ? (da['createdAt'] as Timestamp).toDate()
                                  : DateTime(1970);
                              final tb = db['createdAt'] is Timestamp
                                  ? (db['createdAt'] as Timestamp).toDate()
                                  : DateTime(1970);
                              return tb.compareTo(ta);
                            });
                          return StreamBuilder<List<Map<String, dynamic>>>(
                            stream: _ordersController.stream,
                            builder: (context, snapshot) {
                              if (!snapshot.hasData) {
                                return const Center(child: CircularProgressIndicator(color: Colors.white));
                              }

                              final orders = snapshot.data!;
                              final entries = <Map<String, dynamic>>[];

                              for (final d in paymentDocs) {
                                final data = d.data() as Map<String, dynamic>? ?? {};
                                if ((data['hidden'] ?? false) == true) continue;
                                final ts = data['createdAt'];
                                entries.add({'type': 'payment', 'data': data, 'ts': ts, 'ref': d.reference});
                              }

                              for (final data in orders) {
                                if ((data['hidden'] ?? false) == true) continue;
                                final ts = data['createdAt'];
                                entries.add({'type': 'order', 'data': data, 'ts': ts});
                              }

                              entries.sort((a, b) {
                                DateTime getTime(dynamic ts) {
                                  if (ts is Timestamp) return ts.toDate();
                                  if (ts is DateTime) return ts;
                                  return DateTime(1970);
                                }

                                final ta = getTime(a['ts']);
                                final tb = getTime(b['ts']);
                                return tb.compareTo(ta);
                              });
                              _latestEntries = List<Map<String, dynamic>>.from(entries);

                              if (entries.isEmpty) {
                                return const Center(
                                  child: Text("No orders found.", style: TextStyle(color: Colors.white)),
                                );
                              }

                              return ListView.builder(
                                padding: const EdgeInsets.only(bottom: 120, top: 8),
                                itemCount: entries.length,
                                itemBuilder: (_, index) {
                                  final entry = entries[index];
                                  final type = entry['type'];
                                  final data = entry['data'] as Map<String, dynamic>;
                                  if (type == 'payment') {
                                    return _buildPaymentCard(data);
                                  }
                                  return _buildOrderCard(data);
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
            ],
          ),
        );
      },
    );
  }
}





