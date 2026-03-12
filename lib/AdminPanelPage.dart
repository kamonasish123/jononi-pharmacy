// AdminPanelPage.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

const Color _bgStart = Color(0xFF041A14);
const Color _bgEnd = Color(0xFF0E5A42);
const Color _accent = Color(0xFFFFD166);
const int _defaultProgressDays = 30;
const List<int> _progressRangeOptions = [7, 15, 30, 90];

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

enum _AdminSection { menu, users, progress, companies, history, bkashCustomers, exchangeHistory }

class _DayPoint {
  final DateTime day;
  final double value;
  const _DayPoint(this.day, this.value);
}

class _TopMedicine {
  final String name;
  final int qty;
  final double amount;
  const _TopMedicine(this.name, this.qty, this.amount);
}

class _TopTx {
  final String label;
  final double amount;
  final DateTime? time;
  const _TopTx(this.label, this.amount, this.time);
}

class _ProgressData {
  final List<_DayPoint> salesSeries;
  final double totalSales;
  final List<_TopMedicine> topMedicines;
  final double totalReceive;
  final double totalSend;
  final List<_TopTx> topReceive;
  final List<_TopTx> topSend;
  const _ProgressData({
    required this.salesSeries,
    required this.totalSales,
    required this.topMedicines,
    required this.totalReceive,
    required this.totalSend,
    required this.topReceive,
    required this.topSend,
  });
}

class _SalesSparkline extends StatelessWidget {
  final List<double> values;
  const _SalesSparkline({required this.values});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _SparklinePainter(values: values),
      size: const Size(double.infinity, 140),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<double> values;
  _SparklinePainter({required this.values});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final maxVal = values.reduce((a, b) => a > b ? a : b);
    final paintLine = Paint()
      ..color = _accent.withOpacity(0.9)
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke;

    final paintFill = Paint()
      ..color = _accent.withOpacity(0.18)
      ..style = PaintingStyle.fill;

    final path = Path();
    final fillPath = Path();

    final n = values.length;
    final w = size.width;
    final h = size.height;
    for (var i = 0; i < n; i++) {
      final x = n == 1 ? w / 2 : (w * i / (n - 1));
      final norm = (maxVal <= 0) ? 0.0 : (values[i] / maxVal);
      final y = h - (norm * (h * 0.85)) - 6;
      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, h);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }
    fillPath.lineTo(w, h);
    fillPath.close();

    canvas.drawPath(fillPath, paintFill);
    canvas.drawPath(path, paintLine);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) {
    return oldDelegate.values != values;
  }
}
class AdminPanelPage extends StatefulWidget {
  const AdminPanelPage({super.key});

  @override
  State<AdminPanelPage> createState() => _AdminPanelPageState();
}

class _AdminPanelPageState extends State<AdminPanelPage> {
  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  final currentUser = FirebaseAuth.instance.currentUser;

  final List<String> roles = ['admin', 'manager', 'assistant manager', 'senior seller', 'seller'];

  String _myRole = 'seller';
  bool _loadingRole = true;
  final TextEditingController _promoteEmailController = TextEditingController();
  final TextEditingController _companySearchController = TextEditingController();
  String _companySearchText = '';
  final TextEditingController _bkashCustomerSearchController = TextEditingController();
  String _bkashCustomerSearchText = '';
  final TextEditingController _pharmacySearchController = TextEditingController();
  String _pharmacySearchText = '';
  _AdminSection _section = _AdminSection.menu;
  Future<_ProgressData>? _progressFuture;
  int _selectedProgressDays = _defaultProgressDays;
  final Set<String> _resettingCompanies = {};
  bool _clearingSellHistory = false;
  bool _clearingBkashHistory = false;
  final Set<String> _clearingBkashCustomers = {};
  final Set<String> _resettingBkashCustomers = {};
  final Set<String> _resettingPharmacies = {};

  @override
  void initState() {
    super.initState();
    _loadMyRole();
    _progressFuture = _loadProgressData(days: _selectedProgressDays);
    _companySearchController.addListener(() {
      setState(() {
        _companySearchText = _companySearchController.text.trim().toLowerCase();
      });
    });
    _bkashCustomerSearchController.addListener(() {
      setState(() {
        _bkashCustomerSearchText = _bkashCustomerSearchController.text.trim().toLowerCase();
      });
    });
    _pharmacySearchController.addListener(() {
      setState(() {
        _pharmacySearchText = _pharmacySearchController.text.trim().toLowerCase();
      });
    });
  }

  Future<void> _loadMyRole() async {
    if (currentUser == null) {
      setState(() {
        _loadingRole = false;
        _myRole = 'seller';
      });
      return;
    }
    try {
      final doc = await firestore.collection('users').doc(currentUser!.uid).get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        setState(() {
          _myRole = (data['role'] ?? 'seller').toString();
          _loadingRole = false;
        });
      } else {
        setState(() {
          _myRole = 'seller';
          _loadingRole = false;
        });
      }
    } catch (e) {
      setState(() {
        _myRole = 'seller';
        _loadingRole = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed loading role: $e')));
    }
  }

  bool get _isAdmin {
    return _myRole.toLowerCase() == 'admin';
  }

  bool get _canEditRoles {
    // only admin and manager can edit roles and approve/reject
    final lr = _myRole.toLowerCase();
    return lr == 'admin' || lr == 'manager';
  }

  Widget _metaPill(String text, {IconData? icon, Color? color}) {
    final c = color ?? Colors.white70;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withOpacity(0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: c),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  String _dateId(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  Future<_ProgressData> _loadProgressData({required int days}) async {
    final now = DateTime.now();
    final dayList = List<DateTime>.generate(
      days,
      (i) => DateTime(now.year, now.month, now.day).subtract(Duration(days: i)),
    ).reversed.toList();

    final Map<String, double> dailySales = {for (final d in dayList) _dateId(d): 0.0};
    final Map<String, _TopMedicine> medAgg = {};
    double totalSales = 0.0;

    for (final d in dayList) {
      final dateId = _dateId(d);
      final snap = await firestore.collection('sales').doc(dateId).collection('bills').get();
      if (snap.docs.isEmpty) continue;
      double dayTotal = 0.0;
      for (final doc in snap.docs) {
        final data = doc.data();
        final paidRaw = data['paid'] ?? data['finalAmount'] ?? data['subTotal'] ?? 0;
        final paid = (paidRaw is num) ? paidRaw.toDouble() : double.tryParse(paidRaw.toString()) ?? 0.0;
        dayTotal += paid;
        totalSales += paid;

        final items = (data['items'] as List?) ?? const [];
        for (final it in items) {
          if (it is! Map) continue;
          final name = (it['name'] ?? it['medicineName'] ?? '').toString().trim();
          if (name.isEmpty) continue;
          final qtyRaw = it['qty'] ?? 0;
          final qty = (qtyRaw is num) ? qtyRaw.toInt() : int.tryParse(qtyRaw.toString()) ?? 0;
          final amountRaw = it['total'] ?? (it['price'] ?? 0) * qty;
          final amount = (amountRaw is num)
              ? amountRaw.toDouble()
              : double.tryParse(amountRaw.toString()) ?? 0.0;
          final existing = medAgg[name];
          if (existing == null) {
            medAgg[name] = _TopMedicine(name, qty, amount);
          } else {
            medAgg[name] = _TopMedicine(
              name,
              existing.qty + qty,
              existing.amount + amount,
            );
          }
        }
      }
      dailySales[dateId] = dayTotal;
    }

    final topMedicines = medAgg.values.toList()
      ..sort((a, b) => b.qty.compareTo(a.qty));

    // bKash totals + top transactions
    double totalReceive = 0.0;
    double totalSend = 0.0;
    final List<_TopTx> receiveList = [];
    final List<_TopTx> sendList = [];

    for (final d in dayList) {
      final dateId = _dateId(d);
      final snap = await firestore.collection('bkash').doc(dateId).collection('transactions').get();
      if (snap.docs.isEmpty) continue;
      for (final doc in snap.docs) {
        final data = doc.data();
        final type = (data['type'] ?? '').toString().toLowerCase();
        final amountRaw = data['amount'] ?? data['finalAmount'] ?? 0;
        final amount = (amountRaw is num) ? amountRaw.toDouble() : double.tryParse(amountRaw.toString()) ?? 0.0;
        final phone = (data['phone'] ?? data['customerPhone'] ?? '').toString();
        final name = (data['name'] ?? data['customerName'] ?? '').toString();
        final label = name.isNotEmpty ? name : (phone.isNotEmpty ? phone : 'Unknown');
        final ts = data['createdAt'];
        final dt = ts is Timestamp ? ts.toDate() : null;

        if (type == 'receive') {
          totalReceive += amount;
          receiveList.add(_TopTx(label, amount, dt));
        } else if (type == 'send') {
          totalSend += amount;
          sendList.add(_TopTx(label, amount, dt));
        }
      }
    }

    receiveList.sort((a, b) => b.amount.compareTo(a.amount));
    sendList.sort((a, b) => b.amount.compareTo(a.amount));

    return _ProgressData(
      salesSeries: dayList
          .map((d) => _DayPoint(d, dailySales[_dateId(d)] ?? 0.0))
          .toList(),
      totalSales: totalSales,
      topMedicines: topMedicines.take(5).toList(),
      totalReceive: totalReceive,
      totalSend: totalSend,
      topReceive: receiveList.take(3).toList(),
      topSend: sendList.take(3).toList(),
    );
  }

  Widget _glassCard({required Widget child, EdgeInsets padding = const EdgeInsets.all(14)}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withOpacity(0.18)),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _menuTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: _glassCard(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: _accent.withOpacity(0.18),
                  shape: BoxShape.circle,
                  border: Border.all(color: _accent.withOpacity(0.45)),
                ),
                child: Icon(icon, color: _accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(subtitle, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white70),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
      ),
    );
  }

  String _money(double v) => v.toStringAsFixed(2);

  String _companyIdFromName(String name) {
    return name.trim().toLowerCase().replaceAll(RegExp(r'\\s+'), '_');
  }

  String _normCompanyKey(String v) {
    return v.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
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

  bool _matchesCompanyOrderDocFor(QueryDocumentSnapshot doc, String companyId, String companyName) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    var cid = (data['companyId'] ?? '').toString().trim();
    if (cid.isEmpty) {
      cid = _companyIdFromOrderPath(doc.reference.path) ?? '';
    }
    if (cid.isNotEmpty && _normCompanyKey(cid) == _normCompanyKey(companyId)) {
      return true;
    }
    final name = (data['companyName'] ?? data['company'] ?? '').toString().trim();
    if (name.isNotEmpty && _normCompanyKey(name) == _normCompanyKey(companyName)) {
      return true;
    }
    return false;
  }

  bool _matchesCompanyPaymentDocFor(QueryDocumentSnapshot doc, String companyId, String companyName) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final mode = (data['mode'] ?? '').toString().trim().toLowerCase();
    if (mode != 'company') return false;
    final cid = (data['companyId'] ?? '').toString().trim();
    if (cid.isNotEmpty && _normCompanyKey(cid) == _normCompanyKey(companyId)) {
      return true;
    }
    final name = (data['name'] ?? data['companyName'] ?? '').toString().trim();
    if (name.isNotEmpty && _normCompanyKey(name) == _normCompanyKey(companyName)) {
      return true;
    }
    return false;
  }

  Future<void> _confirmResetCompany(String companyName) async {
    if (!_isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Only admin can reset company data.')));
      return;
    }
    final ctrl = TextEditingController();
    bool isBusy = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Danger: Reset Company'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This will permanently delete ALL orders and company payment history for "$companyName". '
                'Due will become 0. There is NO UNDO.',
                style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              const Text('Type RESET to confirm:', style: TextStyle(color: Colors.white70)),
              TextField(
                controller: ctrl,
                decoration: const InputDecoration(hintText: 'RESET'),
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: (ctrl.text.trim() == 'RESET' && !isBusy)
                  ? () {
                      setState(() => isBusy = true);
                      Navigator.pop(ctx, true);
                    }
                  : null,
              child: Text(isBusy ? 'Resetting...' : 'Reset'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await _resetCompanyForever(companyName);
  }

  Future<void> _resetCompanyForever(String companyName) async {
    final companyId = _companyIdFromName(companyName);
    if (_resettingCompanies.contains(companyId)) return;
    setState(() => _resettingCompanies.add(companyId));
    try {
      // delete orders + bills for this company
      final ordersSnap = await firestore.collectionGroup('orders').get();
      final orderRefs = <DocumentReference>[];
      final billRefs = <DocumentReference>{};
      for (final d in ordersSnap.docs) {
        if (!_matchesCompanyOrderDocFor(d, companyId, companyName)) continue;
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

      if (orderRefs.isNotEmpty) await deleteRefs(orderRefs);
      if (billRefs.isNotEmpty) await deleteRefs(billRefs.toList());

      // delete company payment transactions
      final txSnap = await firestore.collectionGroup('transactions').get();
      final payRefs = <DocumentReference>[];
      for (final d in txSnap.docs) {
        if (_matchesCompanyPaymentDocFor(d, companyId, companyName)) {
          payRefs.add(d.reference);
        }
      }
      if (payRefs.isNotEmpty) await deleteRefs(payRefs);

      // clear company payments summary
      await firestore.collection('company_payments').doc(companyId).delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Reset completed for $companyName')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Reset failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _resettingCompanies.remove(companyId));
    }
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
      batch.update(d.reference, {'hidden': true, 'hiddenAt': FieldValue.serverTimestamp()});
      count++;
      if (count >= 450) await flush();
    }
    await flush();
  }

  Future<void> _clearSellHistoryRangeAdmin() async {
    if (!_isAdmin) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Only admin can clear history.')));
      return;
    }
    if (_clearingSellHistory) return;
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2023),
      lastDate: DateTime(2100),
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
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Sell history cleared for selected range')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Clear failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _clearingSellHistory = false);
    }
  }

  Future<void> _clearBkashHistoryRangeAdmin() async {
    if (!_isAdmin) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Only admin can clear history.')));
      return;
    }
    if (_clearingBkashHistory) return;
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2023),
      lastDate: DateTime(2100),
    );
    if (range == null) return;
    setState(() => _clearingBkashHistory = true);
    try {
      final dates = _datesInRange(range.start, range.end);
      for (final d in dates) {
        final dateId = DateFormat('yyyy-MM-dd').format(d);
        await _hideCollectionDocs(
          firestore.collection('bkash').doc(dateId).collection('transactions'),
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('bKash history cleared for selected range')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Clear failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _clearingBkashHistory = false);
    }
  }

  Future<void> _confirmClearBkashCustomerHistory(String id, String name) async {
    if (!_isAdmin) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Only admin can clear history.')));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear history?'),
        content: Text('Clear all transactions for "$name"? Balance will stay unchanged.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Clear')),
        ],
      ),
    );
    if (ok == true) {
      await _clearBkashCustomerHistory(id, name);
    }
  }

  Future<void> _clearBkashCustomerHistory(String id, String name) async {
    if (_clearingBkashCustomers.contains(id)) return;
    setState(() => _clearingBkashCustomers.add(id));
    try {
      final txCol = firestore.collection('bkash_customers').doc(id).collection('transactions');
      final snap = await txCol.get();
      if (snap.docs.isNotEmpty) {
        WriteBatch batch = firestore.batch();
        int count = 0;
        Future<void> flush() async {
          if (count == 0) return;
          await batch.commit();
          batch = firestore.batch();
          count = 0;
        }
        for (final d in snap.docs) {
          batch.delete(d.reference);
          count++;
          if (count >= 450) await flush();
        }
        await flush();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('History cleared for $name')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Clear failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _clearingBkashCustomers.remove(id));
    }
  }

  Future<void> _confirmResetBkashCustomer(String id, String name) async {
    if (!_isAdmin) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Only admin can reset accounts.')));
      return;
    }
    final ctrl = TextEditingController();
    bool busy = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Danger: Reset Account'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This will permanently delete ALL transactions for "$name" and set balance to 0. '
                'There is NO UNDO.',
                style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              const Text('Type RESET to confirm:', style: TextStyle(color: Colors.white70)),
              TextField(
                controller: ctrl,
                decoration: const InputDecoration(hintText: 'RESET'),
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: (ctrl.text.trim() == 'RESET' && !busy)
                  ? () {
                      setState(() => busy = true);
                      Navigator.pop(ctx, true);
                    }
                  : null,
              child: Text(busy ? 'Resetting...' : 'Reset'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      await _resetBkashCustomer(id, name);
    }
  }

  Future<void> _resetBkashCustomer(String id, String name) async {
    if (_resettingBkashCustomers.contains(id)) return;
    setState(() => _resettingBkashCustomers.add(id));
    try {
      final custRef = firestore.collection('bkash_customers').doc(id);
      final txCol = custRef.collection('transactions');
      final snap = await txCol.get();
      if (snap.docs.isNotEmpty) {
        WriteBatch batch = firestore.batch();
        int count = 0;
        Future<void> flush() async {
          if (count == 0) return;
          await batch.commit();
          batch = firestore.batch();
          count = 0;
        }
        for (final d in snap.docs) {
          batch.delete(d.reference);
          count++;
          if (count >= 450) await flush();
        }
        await flush();
      }
      await custRef.update({
        'balance': 0.0,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Reset completed for $name')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Reset failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _resettingBkashCustomers.remove(id));
    }
  }

  Future<void> _confirmResetExchangeRange(String pharmacyId, String pharmacyName) async {
    if (!_isAdmin) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Only admin can reset exchange history.')));
      return;
    }
    if (_resettingPharmacies.contains(pharmacyId)) return;

    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2023),
      lastDate: DateTime(2100),
    );
    if (range == null) return;

    final ctrl = TextEditingController();
    bool busy = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Danger: Reset Exchange History'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This will permanently delete ALL exchange records for "$pharmacyName" '
                'between ${DateFormat('dd MMM yyyy').format(range.start)} and '
                '${DateFormat('dd MMM yyyy').format(range.end)}. '
                'Receive/Send totals for those dates will become 0. There is NO UNDO.',
                style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              const Text('Type RESET to confirm:', style: TextStyle(color: Colors.white70)),
              TextField(
                controller: ctrl,
                decoration: const InputDecoration(hintText: 'RESET'),
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: (ctrl.text.trim() == 'RESET' && !busy)
                  ? () {
                      setState(() => busy = true);
                      Navigator.pop(ctx, true);
                    }
                  : null,
              child: Text(busy ? 'Resetting...' : 'Reset'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;

    await _resetExchangeRange(pharmacyId, pharmacyName, range.start, range.end);
  }

  Future<void> _resetExchangeRange(
      String pharmacyId, String pharmacyName, DateTime start, DateTime end) async {
    setState(() => _resettingPharmacies.add(pharmacyId));
    try {
      final s = DateTime(start.year, start.month, start.day);
      final e = DateTime(end.year, end.month, end.day).add(const Duration(days: 1));
      final recCol = firestore.collection('exchanges').doc(pharmacyId).collection('records');
      final snap = await recCol
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(s))
          .where('createdAt', isLessThan: Timestamp.fromDate(e))
          .get();

      double sumBorrow = 0.0;
      double sumPayment = 0.0;

      if (snap.docs.isNotEmpty) {
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
          final type = (data['type'] ?? '').toString();
          if (type == 'borrow') {
            final st = data['subTotal'];
            final v = (st is num) ? st.toDouble() : double.tryParse(st.toString()) ?? 0.0;
            sumBorrow += v;
          } else if (type == 'payment') {
            final amt = data['amount'];
            final v = (amt is num) ? amt.toDouble() : double.tryParse(amt.toString()) ?? 0.0;
            sumPayment += v;
          }
          batch.delete(d.reference);
          count++;
          if (count >= 450) await flush();
        }
        await flush();
      }

      // Adjust pharmacy totalDue to remain consistent with deleted records.
      final delta = (-sumBorrow) + (sumPayment);
      if (delta.abs() > 0.0001) {
        final pharmRef = firestore.collection('pharmacies').doc(pharmacyId);
        await firestore.runTransaction((tx) async {
          final snap = await tx.get(pharmRef);
          final current = (snap.data()?['totalDue'] ?? 0);
          final currentDue = (current is num) ? current.toDouble() : double.tryParse(current.toString()) ?? 0.0;
          double newDue = currentDue + delta;
          if (newDue < 0) newDue = 0.0;
          tx.update(pharmRef, {'totalDue': newDue, 'updatedAt': FieldValue.serverTimestamp()});
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Exchange history reset for $pharmacyName')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Reset failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _resettingPharmacies.remove(pharmacyId));
    }
  }

  /// Helper to check whether the current user (editor) may change target user's role to `newRole`,
  /// and whether editor may change target user's current role at all.
  /// Returns null when allowed, otherwise an error message.
  Future<String?> _checkPermissionForRoleChange(String targetUid, String newRole) async {
    final editorRole = _myRole.toLowerCase();
    // refresh editor role from server to be safe
    try {
      final meDoc = await firestore.collection('users').doc(currentUser!.uid).get();
      if (meDoc.exists) {
        final meRole = (meDoc.data() as Map<String, dynamic>)['role'] ?? editorRole;
        // use updated
        // (we won't force setState here â€” we'll still use _myRole for UI)
      }
    } catch (_) {}

    // fetch target user's role
    String targetRole = '';
    try {
      final tdoc = await firestore.collection('users').doc(targetUid).get();
      if (tdoc.exists) {
        targetRole = ((tdoc.data() as Map<String, dynamic>)['role'] ?? '').toString().toLowerCase();
      }
    } catch (_) {
      // if fetch fails, be conservative and disallow changing admin
      targetRole = '';
    }

    // admin can do anything
    if (_isAdmin) return null;

    // manager rules:
    // - cannot change admins (targetRole == 'admin')
    // - cannot assign 'admin' role
    if (editorRole == 'manager') {
      if (targetRole == 'admin') return 'Manager cannot modify an Admin user.';
      if (newRole.toLowerCase() == 'admin') return 'Only an Admin can assign the admin role.';
      return null; // allowed otherwise
    }

    // anyone else cannot change roles
    return 'Only Admin or Manager can change roles.';
  }

  Future<void> _updateRole(String uid, String newRole, String userEmail) async {
    // Permission checks before attempting update
    final permErr = await _checkPermissionForRoleChange(uid, newRole);
    if (permErr != null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(permErr)));
      return;
    }

    try {
      final batch = firestore.batch();
      final userRef = firestore.collection('users').doc(uid);
      batch.update(userRef, {'role': newRole, 'updatedAt': FieldValue.serverTimestamp()});
      // optional: audit log for role changes
      final auditRef = firestore.collection('admin_audit').doc();
      batch.set(auditRef, {
        'type': 'role_change',
        'targetUid': uid,
        'targetEmail': userEmail,
        'newRole': newRole,
        'changedByUid': currentUser?.uid,
        'changedByEmail': currentUser?.email,
        'ts': FieldValue.serverTimestamp(),
      });
      await batch.commit();

      // reload our role if we changed our own role
      if (currentUser != null && currentUser!.uid == uid) {
        await _loadMyRole();
      }

      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Role updated to "$newRole" for $userEmail')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to update role: $e')));
    }
  }

  /// Find user by email and set their role (used for quick set admin)
  Future<void> _setRoleByEmail(String email, String roleToSet) async {
    if (email.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Type an email first')));
      return;
    }
    try {
      final q = await firestore.collection('users').where('email', isEqualTo: email).limit(1).get();
      if (q.docs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No user document found for that email. Create user first.')));
        return;
      }
      final doc = q.docs.first;

      // permission check
      final permErr = await _checkPermissionForRoleChange(doc.id, roleToSet);
      if (permErr != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(permErr)));
        return;
      }

      await _updateRole(doc.id, roleToSet, email);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  Future<void> _approveUser(String uid, String email, String roleToSet) async {
    if (!_canEditRoles) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('You do not have permission to approve users.')));
      return;
    }

    // check permissions for assigning a role
    final permErr = await _checkPermissionForRoleChange(uid, roleToSet);
    if (permErr != null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(permErr)));
      return;
    }

    try {
      final me = currentUser;
      final userRef = firestore.collection('users').doc(uid);
      final auditRef = firestore.collection('admin_audit').doc();

      await firestore.runTransaction((tx) async {
        tx.update(userRef, {
          'approved': true,
          'status': 'approved', // mark approved
          'approvedAt': FieldValue.serverTimestamp(),
          'approvedBy': me?.uid,
          'role': roleToSet,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        tx.set(auditRef, {
          'type': 'approve_user',
          'targetUid': uid,
          'targetEmail': email,
          'assignedRole': roleToSet,
          'byUid': me?.uid,
          'byEmail': me?.email,
          'ts': FieldValue.serverTimestamp(),
        });
      });

      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('User approved')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Approve failed: $e')));
    }
  }

  Future<void> _rejectUser(String uid, String email) async {
    if (!_canEditRoles) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('You do not have permission to reject users.')));
      return;
    }

    try {
      final me = currentUser;
      final userRef = firestore.collection('users').doc(uid);
      final auditRef = firestore.collection('admin_audit').doc();

      await firestore.runTransaction((tx) async {
        // Important: remove 'status' and 'approvalRequestedAt' so user doesn't persist in pending.
        // When the user re-requests approval they should write `approvalRequestedAt` and `status: 'pending'`.
        tx.update(userRef, {
          'approved': false,
          'rejectedAt': FieldValue.serverTimestamp(),
          'rejectedBy': me?.uid,
          'approvalRequestedAt': FieldValue.delete(), // optional cleanup
          'status': FieldValue.delete(), // remove status so user can re-request later
          'updatedAt': FieldValue.serverTimestamp(),
        });
        tx.set(auditRef, {
          'type': 'reject_user',
          'targetUid': uid,
          'targetEmail': email,
          'byUid': me?.uid,
          'byEmail': me?.email,
          'ts': FieldValue.serverTimestamp(),
        });
      });

      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('User rejected')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Reject failed: $e')));
    }
  }

  Future<void> _revokeApprovedUser(String uid, String email) async {
    if (!_canEditRoles) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('You do not have permission to revoke approvals.')));
      return;
    }

    // Do not allow revoking an Admin's approval unless current user is admin
    try {
      final tdoc = await firestore.collection('users').doc(uid).get();
      final targetRole = (tdoc.exists ? (tdoc.data() as Map<String, dynamic>)['role'] : null)?.toString().toLowerCase() ?? '';
      if (targetRole == 'admin' && !_isAdmin) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Only an Admin may revoke another Admin.')));
        return;
      }
    } catch (_) {
      // proceed conservatively
    }

    try {
      final me = currentUser;
      final userRef = firestore.collection('users').doc(uid);
      final auditRef = firestore.collection('admin_audit').doc();

      await firestore.runTransaction((tx) async {
        tx.update(userRef, {
          'approved': false,
          'status': 'pending', // put back in pending so admin must re-approve
          'approvalRequestedAt': FieldValue.serverTimestamp(),
          'revokedAt': FieldValue.serverTimestamp(),
          'revokedBy': me?.uid,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        tx.set(auditRef, {
          'type': 'revoke_approval',
          'targetUid': uid,
          'targetEmail': email,
          'byUid': me?.uid,
          'byEmail': me?.email,
          'ts': FieldValue.serverTimestamp(),
        });
      });

      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('User approval revoked')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Revoke failed: $e')));
    }
  }

  Future<void> _confirmApproveDialog(String uid, String email, String currentRole) async {
    String chosen = currentRole.isNotEmpty ? currentRole : 'seller';
    await showDialog(
      context: context,
      builder: (ctx) {
        bool loading = false;
        return StatefulBuilder(builder: (c, setState) {
          return AlertDialog(
            title: const Text('Approve user'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Approve: $email'),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: chosen,
                  items: roles.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => chosen = v);
                  },
                ),
                if (loading) const Padding(padding: EdgeInsets.only(top: 12), child: CircularProgressIndicator()),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: loading
                    ? null
                    : () async {
                  setState(() => loading = true);
                  await _approveUser(uid, email, chosen);
                  if (mounted) Navigator.pop(ctx);
                },
                child: const Text('Approve'),
              ),
            ],
          );
        });
      },
    );
  }

  Future<void> _confirmRejectDialog(String uid, String email) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject user'),
        content: Text('Reject account for $email ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reject')),
        ],
      ),
    );

    if (ok == true) {
      await _rejectUser(uid, email);
    }
  }

  Future<void> _confirmRevokeDialog(String uid, String email) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Revoke approval'),
        content: Text('Revoke approval for $email ? This will require them to be approved again.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Revoke')),
        ],
      ),
    );

    if (ok == true) {
      await _revokeApprovedUser(uid, email);
    }
  }

  @override
  void dispose() {
    _promoteEmailController.dispose();
    _companySearchController.dispose();
    _bkashCustomerSearchController.dispose();
    _pharmacySearchController.dispose();
    super.dispose();
  }

  Widget _buildMenuScaffold() {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Admin Panel', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (_loadingRole)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Center(child: CircularProgressIndicator(color: Colors.white)),
            ),
          if (!_loadingRole)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.verified_user, size: 14, color: _accent),
                    const SizedBox(width: 6),
                    Text(
                      _myRole.toUpperCase(),
                      style: const TextStyle(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      body: Stack(
        children: [
          _buildBackdrop(),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.only(top: 8, bottom: 24),
              children: [
                _menuTile(
                  icon: Icons.group,
                  title: 'Users',
                  subtitle: 'Approve users, manage roles and access',
                  onTap: () => setState(() => _section = _AdminSection.users),
                ),
                _menuTile(
                  icon: Icons.business,
                  title: 'Companies',
                  subtitle: 'Reset company order & payment history',
                  onTap: () => setState(() => _section = _AdminSection.companies),
                ),
                _menuTile(
                  icon: Icons.delete_sweep,
                  title: 'Clear History',
                  subtitle: 'Clear sell or bKash chat history by date range',
                  onTap: () => setState(() => _section = _AdminSection.history),
                ),
                _menuTile(
                  icon: Icons.account_balance_wallet,
                  title: 'Bkash Customer History',
                  subtitle: 'Clear or reset customer transactions',
                  onTap: () => setState(() => _section = _AdminSection.bkashCustomers),
                ),
                _menuTile(
                  icon: Icons.handshake,
                  title: 'Exchange History',
                  subtitle: 'Reset exchange records by pharmacy & date range',
                  onTap: () => setState(() => _section = _AdminSection.exchangeHistory),
                ),
                _menuTile(
                  icon: Icons.insights,
                  title: 'Pharmacy Progress',
                  subtitle: 'Growth graph, best sales and bKash stats',
                  onTap: () {
                    setState(() {
                      _section = _AdminSection.progress;
                      _progressFuture = _loadProgressData(days: _selectedProgressDays);
                    });
                  },
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                  child: Text(
                    'More sections coming soon...',
                    style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressScaffold() {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Pharmacy Progress', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => setState(() => _section = _AdminSection.menu),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white70),
            onPressed: () {
              setState(() {
                _progressFuture = _loadProgressData(days: _selectedProgressDays);
              });
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          _buildBackdrop(),
          SafeArea(
            child: RefreshIndicator(
              color: _accent,
              backgroundColor: _bgEnd,
              onRefresh: () async {
                setState(() {
                  _progressFuture = _loadProgressData(days: _selectedProgressDays);
                });
                await _progressFuture;
              },
              child: FutureBuilder<_ProgressData>(
                future: _progressFuture,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(color: Colors.white));
                  }
                  if (snap.hasError || !snap.hasData) {
                    return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        SizedBox(height: 120),
                        Center(child: Text('Failed to load progress', style: TextStyle(color: Colors.white70))),
                      ],
                    );
                  }
                  final data = snap.data!;
                  final values = data.salesSeries.map((e) => e.value).toList();
                  return ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                    children: [
                      _sectionTitle('Time Range'),
                      _glassCard(
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _progressRangeOptions.map((d) {
                            final selected = _selectedProgressDays == d;
                            return ChoiceChip(
                              label: Text('$d Days'),
                              selected: selected,
                              selectedColor: _accent,
                              backgroundColor: Colors.white.withOpacity(0.08),
                              labelStyle: TextStyle(
                                color: selected ? Colors.black : Colors.white70,
                                fontWeight: FontWeight.w600,
                              ),
                              onSelected: (v) {
                                if (!v) return;
                                setState(() {
                                  _selectedProgressDays = d;
                                  _progressFuture = _loadProgressData(days: d);
                                });
                              },
                            );
                          }).toList(),
                        ),
                      ),
                      _sectionTitle('Sales Growth (last $_selectedProgressDays days)'),
                      _glassCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Total Sales', style: TextStyle(color: Colors.white70)),
                            const SizedBox(height: 6),
                            Text(
                              '\u09F3 ${_money(data.totalSales)}',
                              style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(height: 140, child: _SalesSparkline(values: values)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _glassCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('bKash Receive', style: TextStyle(color: Colors.white70)),
                                  const SizedBox(height: 6),
                                  Text('\u09F3 ${_money(data.totalReceive)}',
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _glassCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('bKash Send', style: TextStyle(color: Colors.white70)),
                                  const SizedBox(height: 6),
                                  Text('\u09F3 ${_money(data.totalSend)}',
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      _sectionTitle('Best Selling Medicines'),
                      _glassCard(
                        child: data.topMedicines.isEmpty
                            ? const Text('No sales yet', style: TextStyle(color: Colors.white70))
                            : Column(
                                children: data.topMedicines.map((m) {
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 6),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            m.name,
                                            style: const TextStyle(color: Colors.white),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        _metaPill('Qty: ${m.qty}', color: _accent),
                                        const SizedBox(width: 6),
                                        _metaPill('\u09F3 ${_money(m.amount)}'),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ),
                      ),
                      _sectionTitle('Best bKash Receive'),
                      _glassCard(
                        child: data.topReceive.isEmpty
                            ? const Text('No receive transactions', style: TextStyle(color: Colors.white70))
                            : Column(
                                children: data.topReceive.map((t) {
                                  final time = t.time != null ? DateFormat('dd MMM, hh:mm a').format(t.time!) : '';
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 6),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(t.label, style: const TextStyle(color: Colors.white)),
                                        ),
                                        if (time.isNotEmpty)
                                          Text(time, style: const TextStyle(color: Colors.white60, fontSize: 11)),
                                        const SizedBox(width: 8),
                                        _metaPill('\u09F3 ${_money(t.amount)}', color: Colors.greenAccent),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ),
                      ),
                      _sectionTitle('Best bKash Send'),
                      _glassCard(
                        child: data.topSend.isEmpty
                            ? const Text('No send transactions', style: TextStyle(color: Colors.white70))
                            : Column(
                                children: data.topSend.map((t) {
                                  final time = t.time != null ? DateFormat('dd MMM, hh:mm a').format(t.time!) : '';
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 6),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(t.label, style: const TextStyle(color: Colors.white)),
                                        ),
                                        if (time.isNotEmpty)
                                          Text(time, style: const TextStyle(color: Colors.white60, fontSize: 11)),
                                        const SizedBox(width: 8),
                                        _metaPill('\u09F3 ${_money(t.amount)}', color: Colors.redAccent),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompaniesScaffold() {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Company Control', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => setState(() => _section = _AdminSection.menu),
        ),
      ),
      body: Stack(
        children: [
          _buildBackdrop(),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                  child: _glassCard(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: TextField(
                      controller: _companySearchController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        hintText: 'Search company',
                        hintStyle: TextStyle(color: Colors.white70),
                        prefixIcon: Icon(Icons.search, color: Colors.white70),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: firestore.collection('medicines').snapshots(),
                    builder: (context, snap) {
                      if (!snap.hasData) {
                        return const Center(child: CircularProgressIndicator(color: Colors.white));
                      }
                      final docs = snap.data!.docs;
                      final companySet = <String>{};
                      for (final d in docs) {
                        final data = d.data() as Map<String, dynamic>;
                        final name = (data['companyName'] ?? '').toString().trim();
                        if (name.isNotEmpty) {
                          companySet.add(name.toUpperCase());
                        }
                      }
                      final companies = companySet.toList()..sort();
                      final filtered = _companySearchText.isEmpty
                          ? companies
                          : companies.where((c) => c.contains(_companySearchText.toUpperCase())).toList();

                      if (filtered.isEmpty) {
                        return const Center(child: Text('No companies found', style: TextStyle(color: Colors.white70)));
                      }

                      return ListView.separated(
                        padding: const EdgeInsets.only(bottom: 120, top: 8),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 6),
                        itemBuilder: (_, i) {
                          final company = filtered[i];
                          final companyId = _companyIdFromName(company);
                          final isResetting = _resettingCompanies.contains(companyId);
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: _glassCard(
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      company,
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton(
                                    onPressed: (!_isAdmin || isResetting) ? null : () => _confirmResetCompany(company),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.redAccent,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                    child: Text(isResetting ? 'Resetting...' : 'Reset'),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
                if (!_isAdmin)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text('Only admin can reset company data.', style: TextStyle(color: Colors.white60, fontSize: 12)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryScaffold() {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Clear History', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => setState(() => _section = _AdminSection.menu),
        ),
      ),
      body: Stack(
        children: [
          _buildBackdrop(),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                _sectionTitle('Sell Page'),
                _glassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Clear sell page chat/transaction history by date range. '
                        'Totals remain unchanged.',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      const SizedBox(height: 10),
                      ElevatedButton.icon(
                        onPressed: (_isAdmin && !_clearingSellHistory) ? _clearSellHistoryRangeAdmin : null,
                        icon: const Icon(Icons.delete_sweep),
                        label: Text(_clearingSellHistory ? 'Clearing...' : 'Clear Sell History'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _sectionTitle('bKash Page'),
                _glassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Clear bKash transaction history by date range. '
                        'Totals remain unchanged.',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      const SizedBox(height: 10),
                      ElevatedButton.icon(
                        onPressed: (_isAdmin && !_clearingBkashHistory) ? _clearBkashHistoryRangeAdmin : null,
                        icon: const Icon(Icons.delete_sweep),
                        label: Text(_clearingBkashHistory ? 'Clearing...' : 'Clear bKash History'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!_isAdmin)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text('Only admin can clear history.', style: TextStyle(color: Colors.white60, fontSize: 12)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBkashCustomerHistoryScaffold() {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Bkash Customer History', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => setState(() => _section = _AdminSection.menu),
        ),
      ),
      body: Stack(
        children: [
          _buildBackdrop(),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                  child: _glassCard(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: TextField(
                      controller: _bkashCustomerSearchController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        hintText: 'Search customer',
                        hintStyle: TextStyle(color: Colors.white70),
                        prefixIcon: Icon(Icons.search, color: Colors.white70),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: firestore.collection('bkash_customers').orderBy('nameLower').snapshots(),
                    builder: (context, snap) {
                      if (!snap.hasData) {
                        return const Center(child: CircularProgressIndicator(color: Colors.white));
                      }
                      final docs = snap.data!.docs;
                      if (docs.isEmpty) {
                        return const Center(child: Text('No customers found', style: TextStyle(color: Colors.white70)));
                      }
                      final filtered = docs.where((d) {
                        if (_bkashCustomerSearchText.isEmpty) return true;
                        final data = d.data() as Map<String, dynamic>? ?? {};
                        final name = (data['name'] ?? '').toString().toLowerCase();
                        final phone = (data['phone'] ?? '').toString().toLowerCase();
                        return name.contains(_bkashCustomerSearchText) || phone.contains(_bkashCustomerSearchText);
                      }).toList();

                      if (filtered.isEmpty) {
                        return const Center(child: Text('No customers match', style: TextStyle(color: Colors.white70)));
                      }

                      return ListView.separated(
                        padding: const EdgeInsets.only(bottom: 120, top: 8),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 6),
                        itemBuilder: (_, i) {
                          final doc = filtered[i];
                          final data = doc.data() as Map<String, dynamic>? ?? {};
                          final id = doc.id;
                          final name = (data['name'] ?? 'Unknown').toString();
                          final phone = (data['phone'] ?? '').toString();
                          final balanceRaw = data['balance'] ?? 0;
                          final balance = (balanceRaw is num)
                              ? balanceRaw.toDouble()
                              : double.tryParse(balanceRaw.toString()) ?? 0.0;
                          final isClearing = _clearingBkashCustomers.contains(id);
                          final isResetting = _resettingBkashCustomers.contains(id);

                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: _glassCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                                  if (phone.isNotEmpty)
                                    Text(phone, style: const TextStyle(color: Colors.white60, fontSize: 12)),
                                  const SizedBox(height: 6),
                                  Text('Balance: \u09F3 ${balance.toStringAsFixed(2)}',
                                      style: const TextStyle(color: Colors.white70, fontSize: 12)),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: ElevatedButton(
                                          onPressed: (!_isAdmin || isClearing || isResetting)
                                              ? null
                                              : () => _confirmClearBkashCustomerHistory(id, name),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.blueGrey,
                                            foregroundColor: Colors.white,
                                          ),
                                          child: Text(isClearing ? 'Clearing...' : 'Clear Chat'),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: ElevatedButton(
                                          onPressed: (!_isAdmin || isClearing || isResetting)
                                              ? null
                                              : () => _confirmResetBkashCustomer(id, name),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.redAccent,
                                            foregroundColor: Colors.white,
                                          ),
                                          child: Text(isResetting ? 'Resetting...' : 'Reset'),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
                if (!_isAdmin)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text('Only admin can clear or reset customers.', style: TextStyle(color: Colors.white60, fontSize: 12)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExchangeHistoryScaffold() {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Exchange History', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => setState(() => _section = _AdminSection.menu),
        ),
      ),
      body: Stack(
        children: [
          _buildBackdrop(),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                  child: _glassCard(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: TextField(
                      controller: _pharmacySearchController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        hintText: 'Search pharmacy',
                        hintStyle: TextStyle(color: Colors.white70),
                        prefixIcon: Icon(Icons.search, color: Colors.white70),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: firestore.collection('pharmacies').orderBy('nameLower').snapshots(),
                    builder: (context, snap) {
                      if (!snap.hasData) {
                        return const Center(child: CircularProgressIndicator(color: Colors.white));
                      }
                      final docs = snap.data!.docs;
                      if (docs.isEmpty) {
                        return const Center(child: Text('No pharmacies found', style: TextStyle(color: Colors.white70)));
                      }
                      final filtered = docs.where((d) {
                        if (_pharmacySearchText.isEmpty) return true;
                        final data = d.data() as Map<String, dynamic>? ?? {};
                        final name = (data['name'] ?? '').toString().toLowerCase();
                        return name.contains(_pharmacySearchText);
                      }).toList();

                      if (filtered.isEmpty) {
                        return const Center(child: Text('No pharmacies match', style: TextStyle(color: Colors.white70)));
                      }

                      return ListView.separated(
                        padding: const EdgeInsets.only(bottom: 120, top: 8),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 6),
                        itemBuilder: (_, i) {
                          final doc = filtered[i];
                          final data = doc.data() as Map<String, dynamic>? ?? {};
                          final id = doc.id;
                          final name = (data['name'] ?? 'Unknown').toString();
                          final dueRaw = data['totalDue'] ?? 0;
                          final due = (dueRaw is num) ? dueRaw.toDouble() : double.tryParse(dueRaw.toString()) ?? 0.0;
                          final isResetting = _resettingPharmacies.contains(id);

                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: _glassCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 4),
                                  Text('Current Due: \u09F3 ${due.toStringAsFixed(2)}',
                                      style: const TextStyle(color: Colors.white70, fontSize: 12)),
                                  const SizedBox(height: 10),
                                  ElevatedButton.icon(
                                    onPressed: (!_isAdmin || isResetting)
                                        ? null
                                        : () => _confirmResetExchangeRange(id, name),
                                    icon: const Icon(Icons.delete_sweep),
                                    label: Text(isResetting ? 'Resetting...' : 'Reset by Date Range'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.redAccent,
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
                if (!_isAdmin)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text('Only admin can reset exchange history.', style: TextStyle(color: Colors.white60, fontSize: 12)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).copyWith(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: Colors.transparent,
      colorScheme: Theme.of(context).colorScheme.copyWith(
            brightness: Brightness.dark,
            primary: _accent,
            secondary: _accent,
          ),
      dividerColor: Colors.white12,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withOpacity(0.12),
        labelStyle: const TextStyle(color: Colors.white70),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.28)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: _accent.withOpacity(0.7)),
        ),
      ),
    );

    if (_section == _AdminSection.menu) {
      return Theme(data: theme, child: _buildMenuScaffold());
    }
    if (_section == _AdminSection.progress) {
      return Theme(data: theme, child: _buildProgressScaffold());
    }
    if (_section == _AdminSection.companies) {
      return Theme(data: theme, child: _buildCompaniesScaffold());
    }
    if (_section == _AdminSection.history) {
      return Theme(data: theme, child: _buildHistoryScaffold());
    }
    if (_section == _AdminSection.bkashCustomers) {
      return Theme(data: theme, child: _buildBkashCustomerHistoryScaffold());
    }
    if (_section == _AdminSection.exchangeHistory) {
      return Theme(data: theme, child: _buildExchangeHistoryScaffold());
    }

    return Theme(
      data: theme,
      child: DefaultTabController(
        length: 2,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => setState(() => _section = _AdminSection.menu),
            ),
            title: const Text(
              'Admin Panel - Users',
              style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white),
            ),
            centerTitle: true,
            backgroundColor: Colors.transparent,
            elevation: 0,
            actions: [
              if (_loadingRole)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Center(child: CircularProgressIndicator(color: Colors.white)),
                ),
              if (!_loadingRole)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white.withOpacity(0.2)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.verified_user, size: 14, color: _accent),
                        const SizedBox(width: 6),
                        Text(
                          _myRole.toUpperCase(),
                          style: const TextStyle(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
            bottom: const TabBar(
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              indicatorColor: _accent,
              tabs: [
                Tab(text: 'Pending'),
                Tab(text: 'All Users'),
              ],
            ),
          ),
          body: Stack(
            children: [
              _buildBackdrop(),
              SafeArea(
                top: false,
                child: Padding(
              padding: const EdgeInsets.only(top: kToolbarHeight + kTextTabBarHeight + 16),
              child: TabBarView(
                    children: [
            // ---------------------------
            // Pending tab
            // ---------------------------
            Column(
              children: [
                // Keep your quick promote UI consistent (as above). It remains visible here.
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withOpacity(0.18)),
                        ),
                        child: Column(
                          children: [
                            LayoutBuilder(
                              builder: (ctx, constraints) {
                                final field = TextField(
                                  controller: _promoteEmailController,
                                  decoration: const InputDecoration(
                                    labelText: 'Email to change role (e.g. rkamonasish@gmail.com)',
                                  ),
                                );
                                final button = ElevatedButton(
                                  onPressed: _canEditRoles
                                      ? () async {
                                          final email = _promoteEmailController.text.trim();
                                          if (email.isEmpty) {
                                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Type an email first')));
                                            return;
                                          }
                                          final chosen = await showDialog<String?>(
                                            context: context,
                                            builder: (ctx) => AlertDialog(
                                              title: const Text('Choose role'),
                                              content: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: roles.map((r) {
                                                  return ListTile(
                                                    title: Text(r),
                                                    onTap: () => Navigator.pop(ctx, r),
                                                  );
                                                }).toList(),
                                              ),
                                            ),
                                          );
                                          if (chosen == null) return;
                                          await _setRoleByEmail(email, chosen);
                                        }
                                      : null,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _accent,
                                    foregroundColor: Colors.black,
                                  ),
                                  child: const Text('Set Role'),
                                );

                                final isNarrow = constraints.maxWidth < 420;
                                if (isNarrow) {
                                  return Column(
                                    children: [
                                      field,
                                      const SizedBox(height: 8),
                                      SizedBox(width: double.infinity, child: button),
                                    ],
                                  );
                                }
                                return Row(
                                  children: [
                                    Expanded(child: field),
                                    const SizedBox(width: 8),
                                    button,
                                  ],
                                );
                              },
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                icon: const Icon(Icons.star, size: 18, color: _accent),
                                label: const Text('Set rkamonasish@gmail.com as admin'),
                                onPressed: _canEditRoles
                                    ? () async {
                                        final ok = await showDialog<bool>(
                                          context: context,
                                          builder: (ctx) => AlertDialog(
                                            title: const Text('Confirm'),
                                            content: const Text('Set rkamonasish@gmail.com as admin?'),
                                            actions: [
                                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                              ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Yes')),
                                            ],
                                          ),
                                        );
                                        if (ok == true) {
                                          await _setRoleByEmail('rkamonasish@gmail.com', 'admin');
                                        }
                                      }
                                    : null,
                              ),
                            ),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text('Only Admin / Manager can change roles.', style: TextStyle(color: Colors.grey.shade300)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // Pending approvals list (query users where approved == false)
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: firestore.collection('users').where('approved', isEqualTo: false).snapshots(),
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

                      final allDocs = snap.data?.docs ?? [];

                      // Client-side filter: show entries that are actually "pending"
                      // Show if:
                      //  - status == 'pending' or 'requested'
                      //  - OR approvalRequestedAt exists (user re-requested)
                      final pendingDocs = allDocs.where((d) {
                        final data = d.data() as Map<String, dynamic>;
                        final status = (data['status'] ?? '').toString().toLowerCase();
                        final hasRequest = data.containsKey('approvalRequestedAt') && data['approvalRequestedAt'] != null;
                        return status == 'pending' || status == 'requested' || hasRequest;
                      }).toList();

                      // optional: sort by approvalRequestedAt desc if available
                      pendingDocs.sort((a, b) {
                        final ad = (a.data() as Map<String, dynamic>)['approvalRequestedAt'] as Timestamp?;
                        final bd = (b.data() as Map<String, dynamic>)['approvalRequestedAt'] as Timestamp?;
                        final at = ad?.millisecondsSinceEpoch ?? 0;
                        final bt = bd?.millisecondsSinceEpoch ?? 0;
                        return bt.compareTo(at);
                      });

                      if (pendingDocs.isEmpty) {
                        return const Center(child: Text('No pending approval requests', style: TextStyle(color: Colors.white70)));
                      }

                      return ListView.separated(
                        padding: const EdgeInsets.only(bottom: 120),
                        itemCount: pendingDocs.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final doc = pendingDocs[i];
                          final data = doc.data() as Map<String, dynamic>;
                          final uid = doc.id;
                          final name = (data['displayName'] ?? data['name'] ?? '').toString();
                          final email = (data['email'] ?? '').toString();
                          final role = (data['role'] ?? 'seller').toString();
                          final ts = data['approvalRequestedAt'] as Timestamp?;
                          final requestedAt = ts != null ? ts.toDate() : null;
                          final requestedAtStr = requestedAt != null
                              ? '${requestedAt.year}-${requestedAt.month.toString().padLeft(2, '0')}-${requestedAt.day.toString().padLeft(2, '0')} ${requestedAt.hour.toString().padLeft(2, '0')}:${requestedAt.minute.toString().padLeft(2, '0')}'
                              : null;

                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
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
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        CircleAvatar(
                                          child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?'),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                name.isNotEmpty ? name : email,
                                                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              if (name.isNotEmpty)
                                                Text(
                                                  email,
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: const TextStyle(fontSize: 13, color: Colors.white70),
                                                ),
                                              const SizedBox(height: 6),
                                              Wrap(
                                                spacing: 8,
                                                runSpacing: 6,
                                                children: [
                                                  _metaPill('Role: $role'),
                                                  if (requestedAtStr != null) _metaPill(requestedAtStr, icon: Icons.access_time),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              tooltip: 'Approve',
                                              icon: const Icon(Icons.check_circle, color: Colors.greenAccent),
                                              onPressed: _canEditRoles ? () => _confirmApproveDialog(uid, email, role) : null,
                                            ),
                                            IconButton(
                                              tooltip: 'Reject',
                                              icon: const Icon(Icons.cancel, color: Colors.redAccent),
                                              onPressed: _canEditRoles ? () => _confirmRejectDialog(uid, email) : null,
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
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

            // ---------------------------
            // All Users tab (only approved users shown)
            // ---------------------------
            Column(
              children: [
                // Keep same quick promote UI here as well
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withOpacity(0.18)),
                        ),
                        child: Column(
                          children: [
                            LayoutBuilder(
                              builder: (ctx, constraints) {
                                final field = TextField(
                                  controller: _promoteEmailController,
                                  decoration: const InputDecoration(
                                    labelText: 'Email to change role (e.g. rkamonasish@gmail.com)',
                                  ),
                                );
                                final button = ElevatedButton(
                                  onPressed: _canEditRoles
                                      ? () async {
                                          final email = _promoteEmailController.text.trim();
                                          if (email.isEmpty) {
                                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Type an email first')));
                                            return;
                                          }
                                          final chosen = await showDialog<String?>(
                                            context: context,
                                            builder: (ctx) => AlertDialog(
                                              title: const Text('Choose role'),
                                              content: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: roles.map((r) {
                                                  return ListTile(
                                                    title: Text(r),
                                                    onTap: () => Navigator.pop(ctx, r),
                                                  );
                                                }).toList(),
                                              ),
                                            ),
                                          );
                                          if (chosen == null) return;
                                          await _setRoleByEmail(email, chosen);
                                        }
                                      : null,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _accent,
                                    foregroundColor: Colors.black,
                                  ),
                                  child: const Text('Set Role'),
                                );

                                final isNarrow = constraints.maxWidth < 420;
                                if (isNarrow) {
                                  return Column(
                                    children: [
                                      field,
                                      const SizedBox(height: 8),
                                      SizedBox(width: double.infinity, child: button),
                                    ],
                                  );
                                }
                                return Row(
                                  children: [
                                    Expanded(child: field),
                                    const SizedBox(width: 8),
                                    button,
                                  ],
                                );
                              },
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                icon: const Icon(Icons.star, size: 18, color: _accent),
                                label: const Text('Set rkamonasish@gmail.com as admin'),
                                onPressed: _canEditRoles
                                    ? () async {
                                        final ok = await showDialog<bool>(
                                          context: context,
                                          builder: (ctx) => AlertDialog(
                                            title: const Text('Confirm'),
                                            content: const Text('Set rkamonasish@gmail.com as admin?'),
                                            actions: [
                                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                              ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Yes')),
                                            ],
                                          ),
                                        );
                                        if (ok == true) {
                                          await _setRoleByEmail('rkamonasish@gmail.com', 'admin');
                                        }
                                      }
                                    : null,
                              ),
                            ),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text('Only Admin / Manager can change roles.', style: TextStyle(color: Colors.grey.shade300)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // All users list (only approved users shown)
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: firestore.collection('users').where('approved', isEqualTo: true).snapshots(), // show only approved users
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                      final docs = snap.data?.docs ?? [];
                      if (docs.isEmpty) return const Center(child: Text('No user records', style: TextStyle(color: Colors.white70)));

                      return ListView.separated(
                        padding: const EdgeInsets.only(bottom: 120),
                        itemCount: docs.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final doc = docs[i];
                          final data = doc.data() as Map<String, dynamic>;
                          final uid = doc.id;
                          final name = (data['displayName'] ?? data['name'] ?? '').toString();
                          final email = (data['email'] ?? '').toString();
                          final role = (data['role'] ?? 'seller').toString();

                          final isMe = currentUser != null && currentUser!.uid == uid;
                          String selectedRole = role;
                          final roleNorm = role.toLowerCase();

                          final tileColor = isMe ? Colors.white.withOpacity(0.12) : Colors.white.withOpacity(0.08);

                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: BackdropFilter(
                                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: tileColor,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: Colors.white.withOpacity(0.18)),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            CircleAvatar(child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?')),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    name.isNotEmpty ? name : email,
                                                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                  if (name.isNotEmpty)
                                                    Text(
                                                      email,
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: const TextStyle(fontSize: 13, color: Colors.white70),
                                                    ),
                                                ],
                                              ),
                                            ),
                                            IconButton(
                                              icon: const Icon(Icons.copy, size: 20, color: Colors.white70),
                                              tooltip: 'Copy UID',
                                              onPressed: () {
                                                Clipboard.setData(ClipboardData(text: uid));
                                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('UID copied')));
                                              },
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 6,
                                          children: [
                                            _metaPill('Role: $role'),
                                            if (isMe) _metaPill('You', icon: Icons.person),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: AbsorbPointer(
                                                absorbing: !_canEditRoles,
                                                child: DropdownButtonFormField<String>(
                                                  isExpanded: true,
                                                  value: selectedRole,
                                                  dropdownColor: _bgEnd,
                                                  style: const TextStyle(color: Colors.white),
                                                  items: roles.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                                                  onChanged: (val) {
                                                    if (val == null) return;
                                                    showDialog<bool>(
                                                      context: context,
                                                      builder: (ctx) => AlertDialog(
                                                        title: const Text('Confirm role change'),
                                                        content: Text('Change role for $email to \"$val\"?'),
                                                        actions: [
                                                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                                          ElevatedButton(
                                                            onPressed: () => Navigator.pop(ctx, true),
                                                            child: const Text('Yes'),
                                                          ),
                                                        ],
                                                      ),
                                                    ).then((confirmed) {
                                                      if (confirmed == true) {
                                                        _updateRole(uid, val, email);
                                                      }
                                                    });
                                                  },
                                                  decoration: InputDecoration(
                                                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                                    isDense: true,
                                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            IconButton(
                                              icon: const Icon(Icons.block, size: 20, color: Colors.redAccent),
                                              tooltip: roleNorm == 'admin'
                                                  ? 'Cannot revoke an admin (unless you are Admin)'
                                                  : 'Revoke approval (user will need approval again)',
                                              onPressed: (_canEditRoles && roleNorm != 'admin')
                                                  ? () => _confirmRevokeDialog(uid, email)
                                                  : (!_canEditRoles ? null : (_isAdmin ? () => _confirmRevokeDialog(uid, email) : null)),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
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
          ],
          ),
        ),
      ),
    ],
  ),
),
),
);
  }
}



