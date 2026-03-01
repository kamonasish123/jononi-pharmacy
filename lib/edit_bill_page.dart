// EditBillPage.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';

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
  static const Color _bgStart = Color(0xFF041A14);
  static const Color _bgEnd = Color(0xFF0E5A42);
  static const Color _accent = Color(0xFFFFD166);
  double _round2(double v) => double.parse(v.toStringAsFixed(2));

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
    // defensive deep copy
    originalItems = (widget.billData['items'] as List? ?? []).map<Map<String, dynamic>>((e) {
      return Map<String, dynamic>.from(e as Map<String, dynamic>);
    }).toList();

    items = originalItems.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e)).toList();

    for (final it in originalItems) {
      final qty = (it['qty'] ?? 0) is num ? (it['qty'] as num).toDouble() : double.tryParse(it['qty'].toString()) ?? 0.0;
      final price = _round2((it['price'] ?? 0) is num ? (it['price'] as num).toDouble() : double.tryParse(it['price'].toString()) ?? 0.0);
      it['price'] = price;
      it['total'] = _round2(qty * price);
    }
    for (final it in items) {
      final qty = (it['qty'] ?? 0) is num ? (it['qty'] as num).toDouble() : double.tryParse(it['qty'].toString()) ?? 0.0;
      final price = _round2((it['price'] ?? 0) is num ? (it['price'] as num).toDouble() : double.tryParse(it['price'].toString()) ?? 0.0);
      it['price'] = price;
      it['total'] = _round2(qty * price);
    }

    paidController = TextEditingController(
      text: _round2((widget.billData['paid'] ?? 0) is num ? (widget.billData['paid'] as num).toDouble() : double.tryParse((widget.billData['paid'] ?? 0).toString()) ?? 0.0).toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    paidController.dispose();
    super.dispose();
  }

  double get subTotal => _round2(
      items.fold(0.0, (sum, i) => sum + ((i['qty'] ?? 0) as num) * ((i['price'] ?? 0) as num)));

  double get paid => _round2(double.tryParse(paidController.text) ?? 0.0);
  double get due => _round2(subTotal - paid);

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
      builder: (_) => Theme(
        data: _dialogTheme(context),
        child: AlertDialog(
          backgroundColor: _bgEnd,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: Colors.white.withOpacity(0.12)),
          ),
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
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}$')),
                ],
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
                      final roundedPrice = _round2(price);
                      setState(() {
                        items[index]['qty'] = maxPossible;
                        items[index]['price'] = roundedPrice;
                        items[index]['total'] = _round2(maxPossible * roundedPrice);
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
                final roundedPrice = _round2(price);
                items[index]['qty'] = qty;
                items[index]['price'] = roundedPrice;
                items[index]['total'] = _round2(qty * roundedPrice);
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
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          "Edit Bill",
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white),
        ),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: Stack(
        children: [
          _buildBackdrop(),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Bill ID: ${widget.billId}",
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: items.isEmpty
                        ? const Center(child: Text("No items", style: TextStyle(color: Colors.white70)))
                        : ListView.builder(
                            itemCount: items.length,
                            itemBuilder: (_, index) {
                              final item = items[index];
                              return Container(
                                margin: const EdgeInsets.symmetric(vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: Colors.white.withOpacity(0.16)),
                                ),
                                child: ListTile(
                                  title: Text(item['name'] ?? '', style: const TextStyle(color: Colors.white)),
                                  /* subtitle: Text(
                                    "${item['qty']} × ?${item['price']} = ?${(item['qty'] ?? 0) * (item['price'] ?? 0)}",
                                    style: const TextStyle(color: Colors.white70),
                                  ), */
                                  subtitle: Text(
                                    "${item['qty']} x \u09F3 ${((item['price'] ?? 0) as num).toDouble().toStringAsFixed(2)} = \u09F3 ${(((item['qty'] ?? 0) as num).toDouble() * ((item['price'] ?? 0) as num).toDouble()).toStringAsFixed(2)}",
                                    style: const TextStyle(color: Colors.white70),
                                  ),
                                  trailing: const Icon(Icons.edit, color: Colors.white70),
                                  onTap: () => editItem(index),
                                ),
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withOpacity(0.18)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Total = \u09F3 ${subTotal.toStringAsFixed(2)}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 6),
                            TextField(
                              controller: paidController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}$')),
                              ],
                              style: const TextStyle(color: Colors.white),
                              decoration: const InputDecoration(
                                labelText: "Paid",
                                labelStyle: TextStyle(color: Colors.white70),
                                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white30)),
                                focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: _accent)),
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                            const SizedBox(height: 6),
                            Text("Due = \u09F3 ${due.toStringAsFixed(2)}", style: TextStyle(color: due > 0 ? Colors.orangeAccent : Colors.greenAccent)),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: saveChanges,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _accent,
                                  foregroundColor: Colors.black,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                child: const Text("Save Changes"),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}


