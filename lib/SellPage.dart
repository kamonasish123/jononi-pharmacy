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

  Future<void> pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2023),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => selectedDate = picked);
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
                            child: merged.isEmpty
                                ? const Center(child: Text("No records for this day.", style: TextStyle(color: Colors.white70)))
                                : ListView.builder(
                                    itemCount: merged.length,
                                    itemBuilder: (_, index) {
                                      final item = merged[index];
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




