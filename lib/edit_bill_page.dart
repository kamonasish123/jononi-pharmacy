// EditBillPage.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class EditBillPage extends StatefulWidget {
  final String date;
  final String billId;
  final Map<String, dynamic> billData;

  EditBillPage({
    required this.date,
    required this.billId,
    required this.billData,
  });

  @override
  State<EditBillPage> createState() => _EditBillPageState();
}

class _EditBillPageState extends State<EditBillPage> {
  late List<Map<String, dynamic>> items;
  late List<Map<String, dynamic>> originalItems; // keep original for diff
  late TextEditingController paidController;
  final FirebaseFirestore firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    // defensive deep copy
    originalItems = (widget.billData['items'] as List? ?? []).map<Map<String, dynamic>>((e) {
      return Map<String, dynamic>.from(e as Map<String, dynamic>);
    }).toList();

    items = originalItems.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e)).toList();

    paidController = TextEditingController(text: (widget.billData['paid'] ?? 0).toString());
  }

  @override
  void dispose() {
    paidController.dispose();
    super.dispose();
  }

  double get subTotal =>
      items.fold(0.0, (sum, i) => sum + ((i['qty'] ?? 0) as num) * ((i['price'] ?? 0) as num));

  double get paid => double.tryParse(paidController.text) ?? 0;
  double get due => subTotal - paid;

  String? _medIdOf(Map<String, dynamic> it) {
    if (it.containsKey('medicineId') && it['medicineId'] != null) return it['medicineId'].toString();
    if (it.containsKey('medId') && it['medId'] != null) return it['medId'].toString();
    if (it.containsKey('id') && it['id'] != null) return it['id'].toString();
    return null;
  }

  /// Try to read intuitive stock fields in order: stock -> quantity -> qty
  int _parseStockFromData(Map<String, dynamic> data) {
    final raw = data['stock'] ?? data['quantity'] ?? data['qty'] ?? 0;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw.toString()) ?? 0;
  }

  void editItem(int index) {
    final qtyController =
    TextEditingController(text: items[index]['qty'].toString());
    final priceController =
    TextEditingController(text: items[index]['price'].toString());

    final int oldQty = (items[index]['qty'] ?? 0) is num ? (items[index]['qty'] as num).toInt() : int.tryParse(items[index]['qty'].toString()) ?? 0;
    final String? medId = _medIdOf(items[index]);

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(items[index]['name'] ?? ''),
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
            onPressed: () async {
              final qty = int.tryParse(qtyController.text);
              final price = double.tryParse(priceController.text);

              if (qty == null || price == null) return;

              // If qty increased, ensure stock is sufficient BEFORE applying the change.
              if (qty > oldQty && medId != null) {
                try {
                  final medSnap = await firestore.collection('medicines').doc(medId).get();
                  if (!medSnap.exists) {
                    await showDialog(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('Medicine not found'),
                        content: const Text('Medicine document not found in database. Cannot adjust stock.'),
                        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
                      ),
                    );
                    return;
                  }
                  final medData = medSnap.data() as Map<String, dynamic>;
                  final currStock = _parseStockFromData(medData);
                  final need = qty - oldQty;
                  if (currStock < need) {
                    // Not enough stock. Offer to set to maximum allowed (oldQty + currStock)
                    final allowedExtra = currStock;
                    final maxPossible = oldQty + allowedExtra;
                    final wantContinue = await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('Not enough stock'),
                        content: Text(
                          'You tried to increase quantity by $need but only $currStock available.\n\n'
                              'Do you want to set the quantity to the maximum possible ($maxPossible)?',
                        ),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Set to max')),
                        ],
                      ),
                    );
                    if (wantContinue == true) {
                      setState(() {
                        items[index]['qty'] = maxPossible;
                        items[index]['price'] = price;
                        items[index]['total'] = maxPossible * price;
                      });
                      Navigator.pop(context);
                    } else {
                      // user cancelled — do nothing
                    }
                    return;
                  }
                } catch (e) {
                  // if check fails for some reason, show message and block update
                  await showDialog(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('Stock check failed'),
                      content: Text('Could not verify stock: $e'),
                      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
                    ),
                  );
                  return;
                }
              }

              // If here, either qty <= oldQty (returning stock) or qty increased and we had enough stock.
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
              setState(() {
                items.removeAt(index);
              });
              Navigator.pop(context);
            },
            child: const Text(
              "Delete",
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> saveChanges() async {
    // Build map of medId -> delta (newQty - oldQty)
    final Map<String, int> deltaByMed = {};

    // accumulate new items by medId (sum qty if duplicates)
    final Map<String, int> newQtyByMed = {};
    for (final it in items) {
      final medId = _medIdOf(it);
      if (medId == null) continue; // skip items without medicine id (can't update stock)
      final q = (it['qty'] ?? 0) is num ? (it['qty'] as num).toInt() : int.tryParse(it['qty'].toString()) ?? 0;
      newQtyByMed[medId] = (newQtyByMed[medId] ?? 0) + q;
    }

    // accumulate old/original qty by medId
    final Map<String, int> oldQtyByMed = {};
    for (final it in originalItems) {
      final medId = _medIdOf(it);
      if (medId == null) continue;
      final q = (it['qty'] ?? 0) is num ? (it['qty'] as num).toInt() : int.tryParse(it['qty'].toString()) ?? 0;
      oldQtyByMed[medId] = (oldQtyByMed[medId] ?? 0) + q;
    }

    // collect deltas: new - old for each med present in either map
    final allMedIds = <String>{}..addAll(newQtyByMed.keys)..addAll(oldQtyByMed.keys);
    for (final medId in allMedIds) {
      final newQ = newQtyByMed[medId] ?? 0;
      final oldQ = oldQtyByMed[medId] ?? 0;
      final delta = newQ - oldQ;
      if (delta != 0) deltaByMed[medId] = delta;
    }

    final saleRef = firestore.collection('sales').doc(widget.date).collection('bills').doc(widget.billId);

    // If there are stock-increasing deltas, pre-check current stock to fail fast (avoid negative)
    try {
      if (deltaByMed.isNotEmpty) {
        // fetch all required medicine docs in one go
        final medsToFetch = deltaByMed.keys.toList();
        final List<DocumentSnapshot> medSnaps = await Future.wait(
            medsToFetch.map((id) => firestore.collection('medicines').doc(id).get()));

        // collect shortages
        final List<String> shortages = [];
        for (int i = 0; i < medsToFetch.length; ++i) {
          final id = medsToFetch[i];
          final snap = medSnaps[i];
          final delta = deltaByMed[id]!;
          if (!snap.exists) {
            shortages.add('Medicine (id: $id) not found');
            continue;
          }
          final data = snap.data() as Map<String, dynamic>;
          final currStock = _parseStockFromData(data);
          if (delta > 0 && currStock < delta) {
            final medName = (data['medicineName'] ?? data['name'] ?? id).toString();
            shortages.add('$medName — need $delta, available $currStock');
          }
        }

        if (shortages.isNotEmpty) {
          // Show a friendly dialog listing shortages
          final message = 'Cannot save: insufficient stock for:\n\n' + shortages.join('\n');
          await showDialog(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Insufficient stock'),
              content: Text(message),
              actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
            ),
          );
          return;
        }
      }

      // All good — run transaction to update meds + sale atomically
      await firestore.runTransaction((tx) async {
        // Validate again inside transaction and apply updates
        for (final entry in deltaByMed.entries) {
          final medId = entry.key;
          final delta = entry.value;

          final medRef = firestore.collection('medicines').doc(medId);
          final medSnap = await tx.get(medRef);
          if (!medSnap.exists) {
            throw Exception('Medicine document not found (id: $medId). Aborting save.');
          }
          final data = medSnap.data() as Map<String, dynamic>;
          final currStock = _parseStockFromData(data);

          if (delta > 0 && currStock < delta) {
            final medName = (data['medicineName'] ?? data['name'] ?? medId).toString();
            throw Exception('Not enough stock for "$medName". Need $delta, available $currStock.');
          }

          // Apply increment: use -delta so that positive delta decreases stock, negative delta increases stock
          final int incrementValue = -delta;
          final updateData = <String, dynamic>{
            'updatedAt': FieldValue.serverTimestamp(),
            'stock': FieldValue.increment(incrementValue),
            'quantity': FieldValue.increment(incrementValue),
          };
          tx.update(medRef, updateData);
        }

        // Finally update sale doc
        tx.update(saleRef, {
          'items': items,
          'subTotal': subTotal,
          'paid': paid,
          'due': due,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Bill saved successfully")),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      final errMsg = e.toString();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Save failed: $errMsg")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Edit Bill"),
        backgroundColor: Colors.green,
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                itemCount: items.length,
                itemBuilder: (_, index) {
                  final item = items[index];
                  return Card(
                    child: ListTile(
                      title: Text(item['name'] ?? ''),
                      subtitle: Text(
                          "${item['qty']} × ৳${item['price']} = ৳${(item['qty'] ?? 0) * (item['price'] ?? 0)}"),
                      trailing: const Icon(Icons.edit),
                      onTap: () => editItem(index),
                    ),
                  );
                },
              ),
            ),
            const Divider(),
            Text("Total = ৳${subTotal.toStringAsFixed(2)}",
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            TextField(
              controller: paidController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: "Paid"),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 4),
            Text("Due = ৳${due.toStringAsFixed(2)}",
                style: TextStyle(
                    color: due > 0 ? Colors.red : Colors.green)),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: saveChanges,
              child: const Text("Save Changes"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.yellow[700],
                foregroundColor: Colors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
