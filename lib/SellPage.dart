// SellPage.dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
                    "${item['name']} ${item['qty']} × ৳${item['price']} = ৳${(item['total'] ?? (item['qty'] ?? 0) * (item['price'] ?? 0))}",
                    style: pw.TextStyle(font: ttf, fontSize: 12),
                  );
                }).toList(),
                pw.Divider(),
                pw.Text("Total = ৳${billData['subTotal'] ?? 0}",
                    style: pw.TextStyle(font: ttf, fontWeight: pw.FontWeight.bold)),
                pw.Text("Paid = ৳${billData['paid'] ?? 0}", style: pw.TextStyle(font: ttf)),
                pw.Text("Due = ৳${billData['due'] ?? 0}", style: pw.TextStyle(font: ttf)),
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
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Transferred ৳${(billData['due'] ?? 0)} to $typedName")));
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
      backgroundColor: const Color(0xFF01684D),
      appBar: AppBar(
        title: Text("Sell Page - $dateString"),
        centerTitle: true,
        backgroundColor: Colors.green,
        actions: [
          IconButton(icon: const Icon(Icons.calendar_today), onPressed: pickDate),
          IconButton(
            icon: const Icon(Icons.attach_money),
            onPressed: () {
              showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text("Daily Total"),
                  content: Text("Total Sell: ৳${dailyTotal.toStringAsFixed(2)}"),
                  actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("Close"))],
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.people),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomerDueListPage())),
            tooltip: "Customer Due List",
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'new_bill',
        backgroundColor: Colors.yellow[700],
        child: const Icon(Icons.add, color: Colors.black),
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => NewBillPage(date: dateString))),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: salesStream(dateString),
        builder: (context, salesSnap) {
          if (salesSnap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          final salesDocs = salesSnap.data?.docs ?? [];

          return StreamBuilder<QuerySnapshot>(
            stream: dueEntriesStream(dateString),
            builder: (context, dueSnap) {
              if (dueSnap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
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

              if (merged.isEmpty) return const Center(child: Text("No records for this day."));

              return ListView.builder(
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

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      color: Colors.white.withOpacity(0.12),
                      child: ListTile(
                        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          // show pharmacy name on top of the card when present
                          if (fromPharmacyName.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6.0),
                              child: Text("Payment from: $fromPharmacyName", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            ),

                          ...items.map((it) => Text("${it['name']} ${it['qty']} × ${it['price']} = ${it['total']}", style: const TextStyle(color: Colors.white))).toList(),
                          const Divider(color: Colors.white),
                          Text("Total = ৳$subTotal", style: const TextStyle(color: Colors.yellowAccent, fontWeight: FontWeight.bold)),
                          Text("Paid = ৳$paid", style: const TextStyle(color: Colors.white70)),
                          Text("Due = ৳$due", style: const TextStyle(color: Colors.white70)),
                          Text("Time: $time", style: const TextStyle(fontSize: 12)),
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

                    // paid entries show as sell-card and contribute to dailyTotal
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      color: type == 'paid' ? Colors.white.withOpacity(0.12) : Colors.orange.withOpacity(0.12),
                      child: ListTile(
                        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(type == 'paid' ? "Payment — $name" : "Due Card — $name", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          Text("Amount: ৳$amount", style: const TextStyle(color: Colors.white70)),
                          if (phone != null && phone != '') Text("Phone: $phone", style: const TextStyle(color: Colors.white70)),
                          if (address != null && address != '') Text("Address: $address", style: const TextStyle(color: Colors.white70)),
                          Text("Time: $time", style: const TextStyle(fontSize: 12)),
                          const SizedBox(height: 4),
                          Text("C Jononi Pharmacy, Shunashar", style: TextStyle(color: Colors.grey[300], fontStyle: FontStyle.italic)),
                        ]),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          if (type == 'due' && transferred == false)
                            IconButton(icon: const Icon(Icons.person_add_alt_1, color: Colors.white), tooltip: "Transfer to customer", onPressed: () => transferDueEntryToCustomer(item['docRef'] as DocumentReference, data)),
                          IconButton(icon: const Icon(Icons.share, color: Colors.white), onPressed: () async {
                            try {
                              // load font for quick pdf
                              final ByteData fontData = await rootBundle.load('assets/fonts/NotoSansBengali-Regular.ttf');
                              final pw.Font ttf = pw.Font.ttf(fontData);

                              final pdf = pw.Document();
                              pdf.addPage(pw.Page(build: (pw.Context context) {
                                return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                                  pw.Text(type == 'paid' ? "Payment - $name" : "Due - $name", style: pw.TextStyle(font: ttf, fontSize: 16, fontWeight: pw.FontWeight.bold)),
                                  pw.SizedBox(height: 6),
                                  pw.Text("Amount: ৳$amount", style: pw.TextStyle(font: ttf)),
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
                      ),
                    );
                  }
                },
              );
            },
          );
        },
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
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Transferred ৳${(entryData['amount'] ?? 0)} to $typedName")));
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
