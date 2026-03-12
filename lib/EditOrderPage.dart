// EditOrderPage.dart
import 'dart:ui';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

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
  bool _isSaving = false;

  List<Map<String, dynamic>> items = [];
  TextEditingController paidController = TextEditingController(text: "0");
  TextEditingController searchController = TextEditingController();
  Map<String, dynamic>? selectedMedicine;
  String? selectedMedicineId;
  TextEditingController qtyController = TextEditingController();
  bool _isAdding = false;

  // Discount / final amount fields
  // Default discount percent is 10%
  int discountPercent = 10;
  TextEditingController finalAmountController = TextEditingController();

  // UI: which item index is currently "selected" (to show the Receive + Edit controls)
  int selectedItemIndex = -1;

  // Prevent double receive requests for the same index
  final Set<int> _receivingInProgress = {};

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

  String _fmtNum(dynamic v) {
    if (v is num) return v.toStringAsFixed(2);
    final n = double.tryParse(v.toString());
    return (n ?? 0.0).toStringAsFixed(2);
  }

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

    // fetch by updatedAt (recent first) â€” this ensures docs missing medicineNameLower appear
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

  Future<void> addToOrder() async {
    if (_isAdding) return;
    setState(() => _isAdding = true);
    try {
      if (selectedMedicine == null || qtyController.text.isEmpty) return;
      final qty = int.tryParse(qtyController.text);
      final price = double.tryParse(selectedMedicine!['price'].toString()) ?? 0.0;
      if (qty == null || qty <= 0) return;

      setState(() {
        final existingIndex = items.indexWhere((it) => it['medicineId'] == selectedMedicineId);
        if (existingIndex >= 0) {
          // replace qty with new value (allow increase or decrease)
          items[existingIndex]['qty'] = qty;
          items[existingIndex]['price'] = price;
          items[existingIndex]['total'] = qty * price;
          items[existingIndex]['received'] = items[existingIndex]['received'] ?? false;
        } else {
          items.add({
            'medicineId': selectedMedicineId,
            'name': selectedMedicine!['medicineName'],
            'qty': qty,
            'price': price,
            'total': qty * price,
            'received': false,
          });
        }
        finalAmountController.text = _computeFinalFromSubtotal().toStringAsFixed(2);
        selectedMedicine = null;
        selectedMedicineId = null;
        searchController.clear();
        qtyController.clear();
      });
    } finally {
      await Future.delayed(const Duration(milliseconds: 300));
      if (mounted) setState(() => _isAdding = false);
    }
  }

  void editItem(int index) {
    if ((items[index]['received'] ?? false) == true) return;

    final qtyControllerLocal = TextEditingController(text: items[index]['qty'].toString());
    final priceController = TextEditingController(text: items[index]['price'].toString());

    showDialog(
      context: context,
      builder: (_) => Theme(
        data: _dialogTheme(context),
        child: StatefulBuilder(
          builder: (context, setStateDialog) {
            bool isUpdating = false;
            return AlertDialog(
              backgroundColor: _bgEnd,
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: BorderSide(color: Colors.white.withOpacity(0.12)),
              ),
              title: Text(items[index]['name'], style: const TextStyle(color: Colors.white)),
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
              TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
              TextButton(
                onPressed: isUpdating
                    ? null
                    : () {
                        setStateDialog(() => isUpdating = true);
                        final qty = int.tryParse(qtyControllerLocal.text);
                        final price = double.tryParse(priceController.text);
                        if (qty == null || price == null) {
                          setStateDialog(() => isUpdating = false);
                          return;
                        }
                        setState(() {
                          items[index]['qty'] = qty;
                          items[index]['price'] = price;
                          items[index]['total'] = qty * price;
                          finalAmountController.text = _computeFinalFromSubtotal().toStringAsFixed(2);
                        });
                        Navigator.pop(context);
                      },
                child: isUpdating
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text("Update"),
              ),
              TextButton(
                onPressed: isUpdating
                    ? null
                    : () {
                        setStateDialog(() => isUpdating = true);
                        setState(() {
                          items.removeAt(index);
                          finalAmountController.text = _computeFinalFromSubtotal().toStringAsFixed(2);
                        });
                        Navigator.pop(context);
                      },
                child: isUpdating
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.redAccent),
                      )
                    : const Text("Delete", style: TextStyle(color: Colors.red)),
              ),
            ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _promptReceiveWithPrice(int index) async {
    final item = items[index];
    if ((item['received'] ?? false) == true) return;
    final currentPrice = (item['price'] is num)
        ? (item['price'] as num).toDouble()
        : double.tryParse(item['price'].toString()) ?? 0.0;
    final controller = TextEditingController(text: currentPrice.toString());

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setStateDialog) {
          bool isSubmitting = false;
          return AlertDialog(
            backgroundColor: _bgEnd,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(color: Colors.white.withOpacity(0.12)),
            ),
            title: const Text('Receive & Update Price', style: TextStyle(color: Colors.white)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item['name'] ?? '', style: const TextStyle(color: Colors.white70)),
                const SizedBox(height: 10),
                TextField(
                  controller: controller,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Price (৳)'),
                ),
                const SizedBox(height: 6),
                const Text('This updates stock price only (bill price stays same).', style: TextStyle(color: Colors.white54, fontSize: 12)),
              ],
            ),
            actions: [
              TextButton(
                onPressed: isSubmitting ? null : () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: isSubmitting
                    ? null
                    : () {
                        setStateDialog(() => isSubmitting = true);
                        Navigator.pop(context, true);
                      },
                style: ElevatedButton.styleFrom(backgroundColor: _accent, foregroundColor: Colors.black),
                child: isSubmitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                      )
                    : const Text('Receive'),
              ),
            ],
          );
        },
      ),
    );

    if (ok != true) return;
    final text = controller.text.trim();
    final newPrice = text.isEmpty ? currentPrice : double.tryParse(text);
    if (newPrice == null || newPrice < 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid price (>= 0)')));
      return;
    }

    await _receiveItem(index, priceOverride: newPrice);
  }

  /// Receive a single item: increment medicine stock and quantity in Firestore atomically,
  /// mark item as received locally and persist the order items array (if order exists).
  Future<void> _receiveItem(int index, {double? priceOverride}) async {
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
        final updates = <String, dynamic>{
          'stock': FieldValue.increment(qty),
          'quantity': FieldValue.increment(qty),
          'updatedAt': FieldValue.serverTimestamp(),
        };
        if (priceOverride != null) {
          updates['price'] = priceOverride;
        }
        tx.update(medRef, updates);
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
    if (_isSaving) return;
    if (items.isEmpty) return;

    setState(() => _isSaving = true);
    try {
      final finalAmt = finalAmount;
      final paidVal = paid;
      final dueVal = double.parse((finalAmt - paidVal).toStringAsFixed(2));

    final data = {
      'companyId': widget.companyId,
      'companyName': widget.companyName.trim(),
      'companyNameUpper': widget.companyName.trim().toUpperCase(),
      'items': items,
      'subTotal': subTotal,
      'finalAmount': finalAmt,
      'paid': paidVal,
      'due': dueVal,
      'discountPercent': discountPercent,
      'createdAt': FieldValue.serverTimestamp(),
    };

      await firestore
          .collection('orders')
          .doc(widget.companyId)
          .collection('bills')
          .doc(widget.date)
          .set({'createdAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));

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
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
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
                    final price = _fmtNum(item['price']);
                    final total = _fmtNum(item['total']);
                    return pw.Text("$name $qty x \u09F3 $price = \u09F3 $total", style: pw.TextStyle(font: ttf, fontSize: 12));
                  })
                else
                  pw.Text("No items", style: pw.TextStyle(font: ttf)),
                pw.Divider(),
                pw.Text("Total = \u09F3 ${_fmtNum(orderData['subTotal'])}", style: pw.TextStyle(font: ttf, fontWeight: pw.FontWeight.bold)),
                pw.Text("Paid = \u09F3 ${_fmtNum(orderData['paid'])}", style: pw.TextStyle(font: ttf)),
                // <-- Added final amount line so PDF shows final amount
                pw.Text("Final = \u09F3 ${_fmtNum(finalAmtToShow)}", style: pw.TextStyle(font: ttf)),
                pw.Text("Due = \u09F3 ${_fmtNum(orderData['due'])}", style: pw.TextStyle(font: ttf)),
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

  Widget _glassBox({required Widget child, EdgeInsets padding = const EdgeInsets.all(12)}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: padding,
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

  Widget _glassTextField({
    TextEditingController? controller,
    required String label,
    TextInputType? keyboardType,
    IconData? icon,
    ValueChanged<String>? onChanged,
  }) {
    return _glassBox(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        onChanged: onChanged,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white70),
          prefixIcon: icon != null ? Icon(icon, color: Colors.white) : null,
          border: InputBorder.none,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          "${widget.companyName} Order",
          style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Stack(
        children: [
          _buildBackdrop(),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _glassTextField(
                    controller: searchController,
                    label: "Search Medicine",
                    icon: Icons.search,
                    onChanged: (_) => setState(() {}),
                  ),
                  if (searchController.text.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _glassBox(
                      padding: EdgeInsets.zero,
                      child: SizedBox(
                        height: 150,
                        child: StreamBuilder<List<QueryDocumentSnapshot>>(
                          stream: searchMedicinesStream(searchController.text),
                          builder: (_, snapshot) {
                            if (!snapshot.hasData) {
                              return const Center(child: CircularProgressIndicator(color: Colors.white));
                            }
                            final docs = snapshot.data!;
                            if (docs.isEmpty) return const Center(child: Text('No medicines found', style: TextStyle(color: Colors.white70)));
                            return ListView.builder(
                              itemCount: docs.length,
                              itemBuilder: (_, i) {
                                final d = docs[i];
                                final data = d.data() as Map<String, dynamic>;

                                final stockVal = data['quantity'] ?? data['stock'] ?? data['qty'] ?? 0;
                                final stock = (stockVal is num) ? stockVal.toString() : stockVal.toString();

                                final medName = (data['medicineName'] ?? data['medicineNameLower'] ?? '').toString();
                                final price = ((data['price'] ?? 0) as num).toString();
                                return ListTile(
                                  title: Text(medName, style: const TextStyle(color: Colors.white)),
                                  subtitle: Text('Price: \u09F3 $price | Stock: $stock', style: const TextStyle(color: Colors.white70)),
                                  onTap: () async {
                                    await _selectMedicineAndFetchLatest(d.id);
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
                    ),
                  ],
                  if (selectedMedicine != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _glassTextField(
                            controller: qtyController,
                            label: "Quantity",
                            keyboardType: TextInputType.number,
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: _isAdding ? null : addToOrder,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _accent,
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: _isAdding
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                                )
                              : const Text("Add"),
                        ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 12),

                  _glassBox(
                    child: Row(
                      children: [
                        const Text("Discount:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: _askCustomDiscount,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _accent,
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: Text("Custom (${discountPercent}%)"),
                        ),
                        const Spacer(),
                        Text("Applied: $discountPercent%", style: const TextStyle(color: Colors.white70)),
                      ],
                    ),
                  ),

                  const SizedBox(height: 8),

                  Row(
                    children: [
                      Expanded(
                        child: _glassTextField(
                          controller: finalAmountController,
                          label: "Final Amount",
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _glassTextField(
                          controller: paidController,
                          label: "Paid",
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  _glassBox(
                    child: Row(
                      children: [
                        const Text("Due:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                        const SizedBox(width: 6),
                        Text(
                          "\u09F3 ${due.toStringAsFixed(2)}",
                          style: TextStyle(
                            color: due > 0 ? Colors.redAccent : Colors.greenAccent,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        ElevatedButton(
                          onPressed: _isSaving ? null : saveOrder,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _accent,
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: _isSaving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                                )
                              : const Text("Save Order"),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  Expanded(
                    child: items.isEmpty
                        ? const Center(child: Text("No items", style: TextStyle(fontSize: 16, color: Colors.white70)))
                        : ListView.builder(
                            itemCount: items.length,
                            itemBuilder: (_, index) {
                              final bool canEditSavedOrder = widget.orderId != null;
                              final item = items[index];
                              final bool received = (item['received'] ?? false) == true;
                              final bool inProgress = _receivingInProgress.contains(index);

                              Widget trailingWidget;
                              if (!canEditSavedOrder) {
                                trailingWidget = const SizedBox.shrink();
                              } else if (received) {
                                trailingWidget = const Text(
                                  'Received',
                                  style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold),
                                );
                              } else if (selectedItemIndex == index) {
                                trailingWidget = Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.edit, color: Colors.lightBlueAccent),
                                      tooltip: 'Edit',
                                      onPressed: () => editItem(index),
                                    ),
                                    const SizedBox(width: 6),
                                    ElevatedButton(
                                      onPressed: inProgress ? null : () => _promptReceiveWithPrice(index),
                                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                                      child: inProgress
                                          ? const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                            )
                                          : const Text('Receive'),
                                    ),
                                  ],
                                );
                              } else {
                                trailingWidget = const Icon(Icons.more_vert, color: Colors.white70);
                              }

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
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
                                      child: ListTile(
                                        title: Text(item['name'] ?? '', style: const TextStyle(color: Colors.white)),
                                        subtitle: Text(
                                          "${item['qty']} x \u09F3 ${_fmtNum(item['price'])} = \u09F3 ${_fmtNum(item['total'])}",
                                          style: const TextStyle(color: Colors.white70),
                                        ),
                                        trailing: trailingWidget,
                                        onTap: () {
                                          if (!canEditSavedOrder || received) return;
                                          setState(() {
                                            selectedItemIndex = (selectedItemIndex == index) ? -1 : index;
                                          });
                                        },
                                        onLongPress: () {
                                          if (!canEditSavedOrder || received) return;
                                          editItem(index);
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
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







