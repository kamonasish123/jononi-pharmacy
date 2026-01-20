// EditOrderPage.dart
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class EditOrderPage extends StatefulWidget {
  final String companyId;
  final String companyName;
  final String date;
  final String? orderId;
  final Map<String, dynamic>? orderData;

  const EditOrderPage({
    Key? key,
    required this.companyId,
    required this.companyName,
    required this.date,
    this.orderId,
    this.orderData,
  }) : super(key: key);

  @override
  State<EditOrderPage> createState() => _EditOrderPageState();
}

class _EditOrderPageState extends State<EditOrderPage> {
  final FirebaseFirestore firestore = FirebaseFirestore.instance;

  List<Map<String, dynamic>> items = [];
  TextEditingController paidController = TextEditingController(text: "0");
  TextEditingController searchController = TextEditingController();
  Map<String, dynamic>? selectedMedicine;
  String? selectedMedicineId;
  TextEditingController qtyController = TextEditingController();

  // Discount / final amount fields
  // Default discount percent is 10%
  int discountPercent = 10;
  TextEditingController finalAmountController = TextEditingController();

  // UI: which item index is currently "selected" (to show the Receive + Edit controls)
  int selectedItemIndex = -1;

  // Prevent double receive requests for the same index
  final Set<int> _receivingInProgress = {};

  @override
  void initState() {
    super.initState();
    if (widget.orderData != null) {
      // Ensure each item has a 'received' flag (backwards compatible)
      items = List<Map<String, dynamic>>.from(widget.orderData!['items'] ?? []).map((m) {
        final map = Map<String, dynamic>.from(m);
        if (!map.containsKey('received')) map['received'] = false;
        return map;
      }).toList();

      paidController.text = (widget.orderData!['paid'] ?? 0).toString();

      // load discount percent if present; otherwise default to 10
      final dpRaw = widget.orderData!['discountPercent'];
      if (dpRaw != null) {
        if (dpRaw is num) {
          discountPercent = dpRaw.toInt();
        } else {
          discountPercent = int.tryParse(dpRaw.toString()) ?? 10;
        }
      } else {
        discountPercent = 10;
      }

      // load finalAmount if present, otherwise compute from subtotal
      final fa = widget.orderData!['finalAmount'];
      if (fa != null) {
        finalAmountController.text = (fa as num).toStringAsFixed(2);
      } else {
        finalAmountController.text = _computeFinalFromSubtotal().toStringAsFixed(2);
      }
    } else {
      // No orderData -> default discountPercent already 10
      finalAmountController.text = _computeFinalFromSubtotal().toStringAsFixed(2);
    }
  }

  double get subTotal => items.fold(0.0, (sum, i) => sum + ((i['total'] ?? 0) as num).toDouble());
  double get paid => double.tryParse(paidController.text) ?? 0.0;

  double _computeFinalFromSubtotal() {
    final base = subTotal;
    final discount = (discountPercent / 100.0) * base;
    final finalAmt = base - discount;
    return double.parse(finalAmt.toStringAsFixed(2));
  }

  double get finalAmount {
    final parsed = double.tryParse(finalAmountController.text);
    if (parsed == null) return _computeFinalFromSubtotal();
    return parsed;
  }

  double get due => finalAmount - paid;

  /// Apply a percent discount and update finalAmountController
  void _applyDiscountPercent(int p) {
    setState(() {
      discountPercent = p;
      finalAmountController.text = _computeFinalFromSubtotal().toStringAsFixed(2);
    });
  }

  /// Allow custom percent input
  Future<void> _askCustomDiscount() async {
    final ctrl = TextEditingController(text: discountPercent.toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Set discount %'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Percent (e.g., 12)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Apply')),
        ],
      ),
    );

    if (ok == true) {
      final p = int.tryParse(ctrl.text.trim()) ?? 0;
      _applyDiscountPercent(p.clamp(0, 100));
    }
  }

  /// Robust search: fetch recent docs (ordered by updatedAt) so we also include docs
  /// that don't have medicineNameLower, then client-filter and dedupe (pick best).
  Stream<List<QueryDocumentSnapshot>> searchMedicinesStream(String query) {
    final col = firestore.collection('medicines');

    // fetch by updatedAt (recent first) — this ensures docs missing medicineNameLower appear
    final base = col.orderBy('updatedAt', descending: true).limit(800).snapshots();

    return base.map((snap) {
      final q = query.trim().toLowerCase();
      final docs = snap.docs;
      if (q.isEmpty) return docs;

      // client-side prefix match using best-available name fields
      final filtered = docs.where((d) {
        final data = d.data() as Map<String, dynamic>;
        final nameLower = (data['medicineNameLower'] ?? data['medicineName'] ?? data['name'] ?? '').toString().toLowerCase();
        return nameLower.startsWith(q);
      }).toList();

      // Group by normalized name and pick the best doc per name.
      final Map<String, QueryDocumentSnapshot> bestByName = {};
      for (final d in filtered) {
        final data = d.data() as Map<String, dynamic>;
        final nameLower = (data['medicineNameLower'] ?? data['medicineName'] ?? data['name'] ?? '').toString().toLowerCase();

        // prefer updatedAt then createdAt
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
            // tie-breaker: prefer higher quantity/stock
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

      return results;
    });
  }

  Future<void> _selectMedicineAndFetchLatest(String docId) async {
    try {
      // fetch latest snapshot for this medicine id to ensure current stock/price
      final snap = await firestore.collection('medicines').doc(docId).get();
      if (!snap.exists) return;
      final data = snap.data() as Map<String, dynamic>;
      setState(() {
        selectedMedicine = data;
        selectedMedicineId = docId;
      });
    } catch (e) {
      debugPrint('Failed to fetch latest medicine doc: $e');
    }
  }

  void addToOrder() {
    if (selectedMedicine == null || qtyController.text.isEmpty) return;
    final qty = int.tryParse(qtyController.text);
    final price = double.tryParse(selectedMedicine!['price'].toString()) ?? 0.0;
    if (qty == null || qty <= 0) return;

    setState(() {
      items.add({
        'medicineId': selectedMedicineId,
        'name': selectedMedicine!['medicineName'],
        'qty': qty,
        'price': price,
        'total': qty * price,
        'received': false,
      });
      finalAmountController.text = _computeFinalFromSubtotal().toStringAsFixed(2);
      selectedMedicine = null;
      selectedMedicineId = null;
      searchController.clear();
      qtyController.clear();
    });
  }

  void editItem(int index) {
    if ((items[index]['received'] ?? false) == true) return;

    final qtyControllerLocal = TextEditingController(text: items[index]['qty'].toString());
    final priceController = TextEditingController(text: items[index]['price'].toString());

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(items[index]['name']),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: qtyControllerLocal,
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
              final qty = int.tryParse(qtyControllerLocal.text);
              final price = double.tryParse(priceController.text);
              if (qty == null || price == null) return;
              setState(() {
                items[index]['qty'] = qty;
                items[index]['price'] = price;
                items[index]['total'] = qty * price;
                finalAmountController.text = _computeFinalFromSubtotal().toStringAsFixed(2);
              });
              Navigator.pop(context);
            },
            child: const Text("Update"),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                items.removeAt(index);
                finalAmountController.text = _computeFinalFromSubtotal().toStringAsFixed(2);
              });
              Navigator.pop(context);
            },
            child: const Text("Delete", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  /// Receive a single item: increment medicine stock and quantity in Firestore atomically,
  /// mark item as received locally and persist the order items array (if order exists).
  Future<void> _receiveItem(int index) async {
    final item = items[index];
    final medId = item['medicineId']?.toString();
    final qty = (item['qty'] is num) ? (item['qty'] as num).toInt() : int.tryParse(item['qty'].toString()) ?? 0;
    if (medId == null || qty <= 0) return;

    if (_receivingInProgress.contains(index)) return;
    if ((item['received'] ?? false) == true) return;

    _receivingInProgress.add(index);
    setState(() {
      items[index]['received'] = true;
      selectedItemIndex = -1;
    });

    try {
      final medRef = firestore.collection('medicines').doc(medId);

      await firestore.runTransaction((tx) async {
        final medSnap = await tx.get(medRef);
        if (!medSnap.exists) {
          throw Exception('Medicine document not found');
        }

        // Use FieldValue.increment to avoid overwriting concurrent updates
        tx.update(medRef, {
          'stock': FieldValue.increment(qty),
          'quantity': FieldValue.increment(qty),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });
    } catch (e) {
      setState(() {
        items[index]['received'] = false;
      });
      _receivingInProgress.remove(index);

      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Receive failed'),
          content: Text('Could not update stock for this medicine: $e'),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
        ),
      );
      return;
    }

    if (widget.orderId != null) {
      try {
        await firestore
            .collection('orders')
            .doc(widget.companyId)
            .collection('bills')
            .doc(widget.date)
            .collection('orders')
            .doc(widget.orderId)
            .update({'items': items, 'updatedAt': FieldValue.serverTimestamp()});
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Warning: could not persist received state: $e')));
      }
    }

    _receivingInProgress.remove(index);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Item received and stock updated')));
  }

  Future<void> saveOrder() async {
    if (items.isEmpty) return;

    final finalAmt = finalAmount;
    final paidVal = paid;
    final dueVal = double.parse((finalAmt - paidVal).toStringAsFixed(2));

    final data = {
      'items': items,
      'subTotal': subTotal,
      'finalAmount': finalAmt,
      'paid': paidVal,
      'due': dueVal,
      'discountPercent': discountPercent,
      'createdAt': FieldValue.serverTimestamp(),
    };

    if (widget.orderId != null) {
      await firestore
          .collection('orders')
          .doc(widget.companyId)
          .collection('bills')
          .doc(widget.date)
          .collection('orders')
          .doc(widget.orderId)
          .update(data);
    } else {
      await firestore
          .collection('orders')
          .doc(widget.companyId)
          .collection('bills')
          .doc(widget.date)
          .collection('orders')
          .add(data);
    }

    setState(() {
      items.clear();
      paidController.text = "0";
    });

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Order saved")));
    Navigator.pop(context);
  }

  /// Optional: share current order as PDF (keeps same font fix as NewOrderPage)
  Future<void> shareOrder(Map<String, dynamic> orderData) async {
    try {
      final ByteData fontData = await rootBundle.load('assets/fonts/NotoSansBengali-Regular.ttf');
      final pw.Font ttf = pw.Font.ttf(fontData);

      final pdf = pw.Document();
      final itemsList = (orderData['items'] as List?) ?? [];

      // compute final amount to show in PDF: prefer orderData['finalAmount'], fallback to current finalAmount getter
      double finalAmtToShow;
      if (orderData.containsKey('finalAmount') && orderData['finalAmount'] != null) {
        finalAmtToShow = ((orderData['finalAmount'] ?? 0) as num).toDouble();
      } else {
        finalAmtToShow = finalAmount;
      }

      pdf.addPage(
        pw.Page(
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text("Order - ${widget.date}", style: pw.TextStyle(font: ttf, fontSize: 18, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 8),
                if (itemsList.isNotEmpty)
                  ...List.generate(itemsList.length, (i) {
                    final item = itemsList[i] as Map<String, dynamic>;
                    final name = item['name'] ?? '';
                    final qty = item['qty'] ?? '';
                    final price = item['price'] ?? '';
                    final total = item['total'] ?? '';
                    return pw.Text("$name $qty × ৳$price = ৳$total", style: pw.TextStyle(font: ttf, fontSize: 12));
                  })
                else
                  pw.Text("No items", style: pw.TextStyle(font: ttf)),
                pw.Divider(),
                pw.Text("Total = ৳${orderData['subTotal'] ?? 0}", style: pw.TextStyle(font: ttf, fontWeight: pw.FontWeight.bold)),
                pw.Text("Paid = ৳${orderData['paid'] ?? 0}", style: pw.TextStyle(font: ttf)),
                // <-- Added final amount line so PDF shows final amount
                pw.Text("Final = ৳${finalAmtToShow.toStringAsFixed(2)}", style: pw.TextStyle(font: ttf)),
                pw.Text("Due = ৳${orderData['due'] ?? 0}", style: pw.TextStyle(font: ttf)),
                pw.SizedBox(height: 10),
                pw.Text("${widget.companyName}", style: pw.TextStyle(font: ttf, fontStyle: pw.FontStyle.italic)),
              ],
            );
          },
        ),
      );

      final bytes = await pdf.save();
      await Printing.sharePdf(bytes: bytes, filename: "order.pdf");
    } catch (e, st) {
      debugPrint('shareOrder (Edit) error: $e\n$st');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to create PDF: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("${widget.companyName} Order"),
        backgroundColor: Colors.green,
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            // 🔹 Search Medicine
            TextField(
              controller: searchController,
              decoration: const InputDecoration(
                labelText: "Search Medicine",
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (searchController.text.isNotEmpty)
              SizedBox(
                height: 150,
                child: StreamBuilder<List<QueryDocumentSnapshot>>(
                  stream: searchMedicinesStream(searchController.text),
                  builder: (_, snapshot) {
                    if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                    final docs = snapshot.data!;
                    if (docs.isEmpty) return const Center(child: Text('No medicines found'));
                    // Grouping already handled in searchMedicinesStream; results are the best per name
                    return ListView.builder(
                      itemCount: docs.length,
                      itemBuilder: (_, i) {
                        final d = docs[i];
                        final data = d.data() as Map<String, dynamic>;

                        // <-- IMPORTANT: prefer 'quantity' first, then 'stock', then 'qty'
                        final stockVal = data['quantity'] ?? data['stock'] ?? data['qty'] ?? 0;
                        final stock = (stockVal is num) ? stockVal.toString() : stockVal.toString();

                        final medName = (data['medicineName'] ?? data['medicineNameLower'] ?? '').toString();
                        final price = ((data['price'] ?? 0) as num).toString();
                        return ListTile(
                          title: Text(medName),
                          subtitle: Text('Price: ৳$price • Stock: $stock'),
                          onTap: () async {
                            // fetch latest snapshot for this medicine id to ensure current stock/price
                            await _selectMedicineAndFetchLatest(d.id);
                            // set search text to selected name for clarity
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
            if (selectedMedicine != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: qtyController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: "Quantity"),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(onPressed: addToOrder, child: const Text("Add")),
                ],
              ),
            ],

            const SizedBox(height: 12),

            // Discount controls
            Row(
              children: [
                const Text("Discount:", style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                // SINGLE custom button (shows current percent). User taps to edit.
                ElevatedButton(
                  onPressed: _askCustomDiscount,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey[700],
                    foregroundColor: Colors.white,
                  ),
                  child: Text("Custom (${discountPercent}%)"),
                ),
                const Spacer(),
                Text("Applied: $discountPercent%", style: const TextStyle(color: Colors.white70)),
              ],
            ),

            const SizedBox(height: 8),

            // Final amount (editable)
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: finalAmountController,
                    keyboardType: TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: "Final Amount"),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: paidController,
                    keyboardType: TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: "Paid"),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Due display
            Row(
              children: [
                const Text("Due: ", style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(width: 6),
                Text(
                  "৳${due.toStringAsFixed(2)}",
                  style: TextStyle(color: due > 0 ? Colors.red : Colors.green, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                ElevatedButton(
                  onPressed: saveOrder,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.yellow[700], foregroundColor: Colors.black),
                  child: const Text("Save Order"),
                ),
              ],
            ),

            const Divider(),

            // Items list with per-item Edit + Receive controls
            Expanded(
              child: items.isEmpty
                  ? const Center(child: Text("No items", style: TextStyle(fontSize: 16)))
                  : ListView.builder(
                itemCount: items.length,
                itemBuilder: (_, index) {
                  final item = items[index];
                  final bool received = (item['received'] ?? false) == true;
                  final bool inProgress = _receivingInProgress.contains(index);

                  Widget trailingWidget;
                  if (received) {
                    trailingWidget = const Text(
                      'Received',
                      style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                    );
                  } else if (selectedItemIndex == index) {
                    trailingWidget = Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, color: Colors.blue),
                          tooltip: 'Edit',
                          onPressed: () => editItem(index),
                        ),
                        const SizedBox(width: 6),
                        ElevatedButton(
                          onPressed: inProgress ? null : () => _receiveItem(index),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                          child: inProgress
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Text('Receive'),
                        ),
                      ],
                    );
                  } else {
                    trailingWidget = const Icon(Icons.more_vert);
                  }

                  return Card(
                    child: ListTile(
                      title: Text(item['name'] ?? ''),
                      subtitle: Text("${item['qty']} × ৳${item['price']} = ৳${(item['total']).toStringAsFixed(2)}"),
                      trailing: trailingWidget,
                      onTap: () {
                        if (received) return;
                        setState(() {
                          selectedItemIndex = (selectedItemIndex == index) ? -1 : index;
                        });
                      },
                      onLongPress: () {
                        if (received) return;
                        editItem(index);
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
