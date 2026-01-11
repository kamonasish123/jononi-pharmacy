// ExchangeDetailPage.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class ExchangeDetailPage extends StatefulWidget {
  final String pharmacyId;
  final String pharmacyName;
  const ExchangeDetailPage({
    super.key,
    required this.pharmacyId,
    required this.pharmacyName,
  });

  @override
  State<ExchangeDetailPage> createState() => _ExchangeDetailPageState();
}

class _ExchangeDetailPageState extends State<ExchangeDetailPage> {
  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  DateTime selectedDate = DateTime.now();
  String get dateString => DateFormat('yyyy-MM-dd').format(selectedDate);

  Future<void> pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2023),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => selectedDate = picked);
  }

  // Query records for the chosen day (createdAt between start and end)
  Stream<QuerySnapshot> recordsForDay() {
    final start = DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
    final end = start.add(const Duration(days: 1));
    return firestore
        .collection('exchanges')
        .doc(widget.pharmacyId)
        .collection('records')
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('createdAt', isLessThan: Timestamp.fromDate(end))
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  // ----------------- Create a borrow/lend transaction (multiple items) -----------------
  Future<void> createBorrowTransaction() async {
    List<Map<String, dynamic>> pickedItems = [];

    final qtyController = TextEditingController();
    final searchController = TextEditingController();
    Map<String, dynamic>? selectedMed;
    String? selectedMedId;
    int latestAvailable = 0; // latest fetched stock for selectedMed

    // direction: true => receive from pharmacy (you receive items -> your stock increases)
    // false => give to pharmacy (you give items -> your stock decreases)
    bool isReceive = true;

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (context, setState) {
          // Helper to fetch the latest doc for a medicine id and update selectedMed & latestAvailable
          Future<void> _fetchLatestMed(String medId) async {
            try {
              final snap = await firestore.collection('medicines').doc(medId).get();
              if (!snap.exists) return;
              final data = snap.data() as Map<String, dynamic>;
              selectedMed = data;
              selectedMedId = medId;
              final stockRaw = data['stock'] ?? data['quantity'] ?? data['qty'] ?? 0;
              latestAvailable = (stockRaw is num) ? stockRaw.toInt() : int.tryParse(stockRaw.toString()) ?? 0;
              // update qtyController hint/clear if needed
              setState(() {});
            } catch (e) {
              debugPrint('fetchLatestMed error: $e');
            }
          }

          void addPicked() {
            final qty = int.tryParse(qtyController.text.trim());
            if (selectedMed == null || qty == null || qty <= 0) return;

            // Robustly parse current available stock from selectedMed (we also fetched latest on selection)
            final stockRaw = selectedMed!['stock'] ?? selectedMed!['quantity'] ?? selectedMed!['qty'] ?? 0;
            final int available = (stockRaw is num) ? stockRaw.toInt() : int.tryParse(stockRaw.toString()) ?? 0;

            // Prevent giving more than available when in "Give" mode
            if (!isReceive && qty > available) {
              showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Insufficient stock'),
                  content: Text('Cannot give $qty items. Available stock: $available.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
                  ],
                ),
              );
              return;
            }

            final price = ((selectedMed!['price'] ?? 0) as num).toDouble();
            final name = (selectedMed!['medicineName'] ?? selectedMed!['medicineNameLower'] ?? '').toString();
            pickedItems.add({
              'medicineId': selectedMedId,
              'medicineName': name,
              'qty': qty,
              'price': price,
              'total': qty * price
            });
            selectedMed = null;
            selectedMedId = null;
            latestAvailable = 0;
            searchController.clear();
            qtyController.clear();
            setState(() {});
          }

          return AlertDialog(
            title: Text('${isReceive ? "Receive from" : "Give to"} — ${widget.pharmacyName}'),
            content: SizedBox(
              width: 360, // constrain width to avoid layout/hitTest issues
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Direction choice
                    Row(
                      children: [
                        Expanded(
                          child: RadioListTile<bool>(
                            value: true,
                            groupValue: isReceive,
                            title: const Text('Receive'),
                            onChanged: (v) => setState(() => isReceive = v ?? true),
                          ),
                        ),
                        Expanded(
                          child: RadioListTile<bool>(
                            value: false,
                            groupValue: isReceive,
                            title: const Text('Give'),
                            onChanged: (v) => setState(() => isReceive = v ?? true),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // search medicine (prefix)
                    TextField(
                      controller: searchController,
                      decoration: const InputDecoration(labelText: 'Search medicine (prefix)'),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 140,
                      child: StreamBuilder<QuerySnapshot>(
                        // Use normalized lower-case field for prefix search so newly updated docs appear
                        stream: firestore
                            .collection('medicines')
                            .orderBy('medicineNameLower')
                            .startAt([searchController.text.toLowerCase()])
                            .endAt([searchController.text.toLowerCase() + '\uf8ff'])
                            .limit(50)
                            .snapshots(),
                        builder: (context, snap) {
                          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                          final docs = snap.data!.docs;

                          // Group by medicineNameLower and pick the best doc per name.
                          final Map<String, QueryDocumentSnapshot> bestByName = {};
                          for (final d in docs) {
                            final data = d.data() as Map<String, dynamic>;
                            final nameLower = (data['medicineNameLower'] ?? (data['medicineName'] ?? '')).toString().toLowerCase();

                            Timestamp? updated = (data['updatedAt'] as Timestamp?) ?? (data['createdAt'] as Timestamp?);
                            final int ts = (updated?.millisecondsSinceEpoch ?? 0);

                            if (!bestByName.containsKey(nameLower)) {
                              bestByName[nameLower] = d;
                            } else {
                              final existing = bestByName[nameLower]!;
                              final existingData = existing.data() as Map<String, dynamic>;
                              Timestamp? exUpdated = (existingData['updatedAt'] as Timestamp?) ?? (existingData['createdAt'] as Timestamp?);
                              final int exTs = (exUpdated?.millisecondsSinceEpoch ?? 0);

                              if (ts > exTs) {
                                bestByName[nameLower] = d;
                              } else if (ts == exTs) {
                                final currQtyRaw = data['quantity'] ?? data['stock'] ?? data['qty'] ?? 0;
                                final existQtyRaw = existingData['quantity'] ?? existingData['stock'] ?? existingData['qty'] ?? 0;
                                final int currQty = (currQtyRaw is num) ? currQtyRaw.toInt() : int.tryParse(currQtyRaw.toString()) ?? 0;
                                final int existQty = (existQtyRaw is num) ? existQtyRaw.toInt() : int.tryParse(existQtyRaw.toString()) ?? 0;
                                if (currQty >= existQty) {
                                  bestByName[nameLower] = d;
                                }
                              }
                            }
                          }

                          final results = bestByName.values.toList()
                            ..sort((a, b) {
                              final an = (a.data() as Map<String, dynamic>)['medicineName'] ?? '';
                              final bn = (b.data() as Map<String, dynamic>)['medicineName'] ?? '';
                              return an.toString().toLowerCase().compareTo(bn.toString().toLowerCase());
                            });

                          if (results.isEmpty) {
                            return const Center(child: Text('No medicines found'));
                          }

                          return ListView.builder(
                            itemCount: results.length,
                            itemBuilder: (context, i) {
                              final d = results[i];
                              final data = d.data() as Map<String, dynamic>;
                              final stockVal = data['quantity'] ?? data['stock'] ?? data['qty'] ?? 0;
                              final stock = (stockVal is num) ? stockVal.toInt() : int.tryParse(stockVal.toString()) ?? 0;
                              final medName = (data['medicineName'] ?? data['medicineNameLower'] ?? '').toString();
                              final price = ((data['price'] ?? 0) as num).toDouble();
                              return ListTile(
                                title: Text(medName),
                                subtitle: Text('Price: ৳$price • Stock: $stock'),
                                onTap: () async {
                                  // Fetch the latest snapshot for this medicine to ensure we have current stock
                                  await _fetchLatestMed(d.id);
                                  // set the search text to the selected medicine name
                                  searchController.text = medName;
                                  qtyController.clear();
                                  setState(() {});
                                },
                              );
                            },
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (selectedMed != null)
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: qtyController,
                              keyboardType: TextInputType.number,
                              onChanged: (_) => setState(() {}), // update button enabled state
                              decoration: InputDecoration(
                                labelText:
                                'Qty (current stock: ${(selectedMed!['quantity'] ?? selectedMed!['stock'] ?? selectedMed!['qty'] ?? 0).toString()})',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Add button: disabled when no selection or when trying to give more than latestAvailable
                          ElevatedButton(
                            onPressed: (selectedMed == null)
                                ? null
                                : () {
                              final qty = int.tryParse(qtyController.text.trim()) ?? 0;
                              if (!isReceive && qty > latestAvailable) {
                                showDialog(
                                  context: context,
                                  builder: (_) => AlertDialog(
                                    title: const Text('Insufficient stock'),
                                    content: Text('Cannot give $qty items. Available stock: $latestAvailable.'),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
                                    ],
                                  ),
                                );
                                return;
                              }
                              addPicked();
                            },
                            child: const Text('Add'),
                          ),
                        ],
                      ),
                    const SizedBox(height: 12),
                    const Divider(),
                    const SizedBox(height: 8),
                    const Text('Picked items:', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 120,
                      child: ListView.builder(
                        itemCount: pickedItems.length,
                        itemBuilder: (context, i) {
                          final it = pickedItems[i];
                          return ListTile(
                            title: Text('${it['medicineName']}'),
                            subtitle: Text('${it['qty']} × ৳${it['price']} = ৳${it['total']}'),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () {
                                setState(() => pickedItems.removeAt(i));
                              },
                            ),
                          );
                        },
                      ),
                    )
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: pickedItems.isEmpty
                    ? null
                    : () async {
                  // calculate subtotal
                  final subTotal = pickedItems.fold<double>(0, (s, e) => s + ((e['total'] ?? 0) as num).toDouble());

                  // gather required quantities by medicineId
                  final Map<String, int> need = {};
                  for (final it in pickedItems) {
                    final idDynamic = it['medicineId'];
                    final id = (idDynamic is String) ? idDynamic : idDynamic?.toString();
                    if (id == null) continue;
                    final q = (it['qty'] is num) ? (it['qty'] as num).toInt() : int.tryParse(it['qty'].toString()) ?? 0;
                    need[id] = (need[id] ?? 0) + q;
                  }

                  try {
                    // Use a transaction to ensure stock cannot go negative between check and update.
                    await firestore.runTransaction((tx) async {
                      // 1) Validate availability for all meds (if giving)
                      if (!isReceive && need.isNotEmpty) {
                        for (final medId in need.keys) {
                          final medRef = firestore.collection('medicines').doc(medId);
                          final medSnap = await tx.get(medRef);
                          if (!medSnap.exists) {
                            throw Exception("Medicine not found (id: $medId).");
                          }
                          final data = medSnap.data()!;
                          final stockVal = data['stock'] ?? data['quantity'] ?? data['qty'] ?? 0;
                          final available = (stockVal is num) ? stockVal.toInt() : int.tryParse(stockVal.toString()) ?? 0;
                          final want = need[medId] ?? 0;
                          if (available < want) {
                            final name = (data['medicineName'] ?? 'Unknown').toString();
                            throw Exception("$name: available $available, required $want");
                          }
                        }
                      }

                      // 2) Create exchange record
                      final recRef = firestore.collection('exchanges').doc(widget.pharmacyId).collection('records').doc();
                      tx.set(recRef, {
                        'type': 'borrow',
                        'direction': isReceive ? 'receive' : 'lend',
                        'items': pickedItems,
                        'subTotal': subTotal,
                        'paid': 0,
                        'due': subTotal,
                        'createdAt': FieldValue.serverTimestamp(),
                      });

                      // 3) Update pharmacy totalDue
                      final pharmRef = firestore.collection('pharmacies').doc(widget.pharmacyId);
                      tx.update(pharmRef, {'totalDue': FieldValue.increment(subTotal)});

                      // 4) Update medicine stocks
                      for (final it in pickedItems) {
                        final medIdDyn = it['medicineId'];
                        final medId = (medIdDyn is String) ? medIdDyn : medIdDyn?.toString();
                        if (medId == null) continue;
                        final qty = (it['qty'] is num) ? (it['qty'] as num).toInt() : int.tryParse(it['qty'].toString()) ?? 0;
                        final medRef = firestore.collection('medicines').doc(medId);

                        // We already validated availability above for give case.
                        final inc = isReceive ? qty : -qty;

                        // Use FieldValue.increment to avoid race conditions on concurrent updates.
                        tx.update(medRef, {
                          'stock': FieldValue.increment(inc),
                          'quantity': FieldValue.increment(inc),
                        });
                      }
                    });

                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('${isReceive ? "Received" : "Given"} saved — subtotal ৳${subTotal.toStringAsFixed(2)}')),
                    );
                  } catch (e) {
                    // If transaction throws due to insufficient stock or other error, show friendly message.
                    final msg = e.toString();
                    await showDialog(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('Operation failed'),
                        content: Text(msg),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
                        ],
                      ),
                    );
                  }
                },
                child: const Text('Save'),
              )
            ],
          );
        });
      },
    );
  }

  // ----------------- Record payment from pharmacy -----------------
  // Payment dialog: if cash -> create a sales bill for today (SellPage will show it and add to daily total).
  // If not cash -> only reduce pharmacy.due; no sales bill created.
  Future<void> recordPayment() async {
    final amountController = TextEditingController();
    bool isCash = true;

    await showDialog(
      context: context,
      builder: (_) {
        return StatefulBuilder(builder: (context, setState) {
          return AlertDialog(
            title: Text('Record Payment — ${widget.pharmacyName}'),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: amountController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Amount'),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Checkbox(value: isCash, onChanged: (v) => setState(() => isCash = v ?? true)),
                      const SizedBox(width: 6),
                      const Expanded(child: Text('Cash payment? (if checked, this will be added to sales)')),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () async {
                  final amount = double.tryParse(amountController.text.trim());
                  if (amount == null || amount <= 0) return;

                  final batch = firestore.batch();

                  // payment record under exchanges
                  final recRef = firestore.collection('exchanges').doc(widget.pharmacyId).collection('records').doc();
                  batch.set(recRef, {
                    'type': 'payment',
                    'amount': amount,
                    'isCash': isCash,
                    'createdAt': FieldValue.serverTimestamp(),
                  });

                  // reduce pharmacy.totalDue
                  final pharmRef = firestore.collection('pharmacies').doc(widget.pharmacyId);
                  batch.update(pharmRef, {'totalDue': FieldValue.increment(-amount)});

                  // If cash payment, also create a sales bill for TODAY so SellPage picks it up
                  if (isCash) {
                    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
                    final billRef = firestore.collection('sales').doc(today).collection('bills').doc();
                    batch.set(billRef, {
                      'items': [],
                      'subTotal': amount,
                      'paid': amount,
                      'due': 0,
                      'createdAt': FieldValue.serverTimestamp(),
                      'fromPharmacyId': widget.pharmacyId,
                      'fromPharmacyName': widget.pharmacyName,
                      'note': 'Payment from pharmacy (cash)',
                    });
                  }

                  await batch.commit();
                  Navigator.pop(context);

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(isCash
                          ? 'Payment recorded and added to sales'
                          : 'Payment recorded (non-cash); no sale created'),
                    ),
                  );
                },
                child: const Text('Submit'),
              ),
            ],
          );
        });
      },
    );
  }

  Future<void> _deleteRecord(DocumentReference recRef) async {
    await recRef.delete();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Record deleted')));
  }

  // ----------------- Show totals dialog (total give / total receive for selected date) -----------------
  Future<void> _showTotalsDialog() async {
    final start = DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
    final end = start.add(const Duration(days: 1));

    // fetch all records for the day once and compute totals locally
    final query = firestore
        .collection('exchanges')
        .doc(widget.pharmacyId)
        .collection('records')
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('createdAt', isLessThan: Timestamp.fromDate(end));

    final snapshot = await query.get();

    double totalReceive = 0.0;
    double totalGive = 0.0;

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final type = (data['type'] ?? '').toString();
      // We only consider borrow-type records that have subTotal
      if (type == 'borrow') {
        final direction = (data['direction'] ?? '').toString(); // 'receive' or 'lend'
        final subTotal = ((data['subTotal'] ?? 0) as num).toDouble();
        if (direction == 'receive') {
          totalReceive += subTotal;
        } else if (direction == 'lend' || direction == 'give' || direction == 'given') {
          // some records may use 'lend' as in your code; accept common variants
          totalGive += subTotal;
        }
      }
    }

    // Show dialog with totals
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Totals — ${widget.pharmacyName}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Expanded(child: Text('Total received (today):', style: TextStyle(fontWeight: FontWeight.w600))),
                Text('৳${totalReceive.toStringAsFixed(2)}'),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Expanded(child: Text('Total given (today):', style: TextStyle(fontWeight: FontWeight.w600))),
                Text('৳${totalGive.toStringAsFixed(2)}'),
              ],
            ),
            const SizedBox(height: 12),
            Text('Date: $dateString', style: const TextStyle(color: Colors.black54)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF01684D),
      appBar: AppBar(
        centerTitle: true,
        backgroundColor: const Color(0xFF01684D),
        title: Text('${widget.pharmacyName} — $dateString'),
        actions: [
          // totals button (top-right) — shows total receive and total give for the selected date
          IconButton(
            icon: const Icon(Icons.bar_chart),
            tooltip: 'Show totals (give / receive) for this date',
            onPressed: _showTotalsDialog,
          ),
          IconButton(icon: const Icon(Icons.calendar_today), onPressed: pickDate),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton(
            heroTag: 'borrow',
            backgroundColor: Colors.orangeAccent,
            child: const Icon(Icons.call_split),
            onPressed: createBorrowTransaction,
            tooltip: 'Borrow / Lend items (adjust stock & due)',
          ),
          const SizedBox(height: 10),
          FloatingActionButton(
            heroTag: 'pay',
            backgroundColor: Colors.yellow[700],
            child: const Icon(Icons.payment, color: Colors.black),
            onPressed: recordPayment,
            tooltip: 'Record payment (cash -> sales + reduce due; non-cash -> reduce due only)',
          ),
        ],
      ),
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot>(
          stream: recordsForDay(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
            final docs = snap.data?.docs ?? [];
            if (docs.isEmpty) return Center(child: Text('No exchange records for this day', style: TextStyle(color: Colors.white70)));
            return ListView.builder(
              itemCount: docs.length,
              itemBuilder: (context, i) {
                final d = docs[i];
                final data = d.data() as Map<String, dynamic>;
                final type = (data['type'] ?? 'borrow').toString();
                final direction = (data['direction'] ?? 'receive').toString();
                final time = data['createdAt'] != null ? DateFormat('hh:mm a').format((data['createdAt'] as Timestamp).toDate()) : '';
                if (type == 'borrow') {
                  final items = (data['items'] as List<dynamic>? ?? []);
                  final subTotal = ((data['subTotal'] ?? 0) as num).toDouble();
                  final dirLabel = direction == 'receive' ? 'Received' : 'Given';
                  return Card(
                    color: Colors.white.withOpacity(0.12),
                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: ListTile(
                      title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('$dirLabel — ${widget.pharmacyName}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 6),
                        ...items.map((it) {
                          final mName = (it['medicineName'] ?? '').toString();
                          final qty = (it['qty'] is num) ? (it['qty'] as num).toInt() : int.tryParse(it['qty'].toString()) ?? 0;
                          final price = ((it['price'] ?? 0) as num).toDouble();
                          final total = ((it['total'] ?? (qty * price)) as num).toDouble();
                          return Text("$mName $qty × ৳$price = ৳$total", style: const TextStyle(color: Colors.white));
                        }).toList(),
                        const Divider(color: Colors.white),
                        Text('Total = ৳$subTotal', style: const TextStyle(color: Colors.yellowAccent, fontWeight: FontWeight.bold)),
                        Text('Time: $time', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      ]),
                      trailing: IconButton(icon: const Icon(Icons.delete, color: Colors.redAccent), onPressed: () => _deleteRecord(d.reference)),
                    ),
                  );
                } else {
                  final amount = ((data['amount'] ?? 0) as num).toDouble();
                  final isCash = (data['isCash'] ?? true) as bool;
                  return Card(
                    color: Colors.white.withOpacity(0.12),
                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: ListTile(
                      title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(isCash ? 'Payment (cash) — ${widget.pharmacyName}' : 'Payment (non-cash) — ${widget.pharmacyName}',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        Text('Amount: ৳$amount', style: const TextStyle(color: Colors.white70)),
                        Text('Time: $time', style: const TextStyle(fontSize: 12)),
                      ]),
                      trailing: IconButton(icon: const Icon(Icons.delete, color: Colors.redAccent), onPressed: () => _deleteRecord(d.reference)),
                    ),
                  );
                }
              },
            );
          },
        ),
      ),
    );
  }
}
