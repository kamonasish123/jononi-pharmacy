import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';

class NewBillPage extends StatefulWidget {
  final String date;

  const NewBillPage({super.key, required this.date});

  @override
  State<NewBillPage> createState() => _NewBillPageState();
}

class _NewBillPageState extends State<NewBillPage> {
  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  bool _isSaving = false;
  bool _isAdding = false;

  final TextEditingController searchController = TextEditingController();
  final TextEditingController qtyController = TextEditingController();
  final TextEditingController paidController = TextEditingController();

  List<Map<String, dynamic>> billItems = [];
  Map<String, dynamic>? selectedMedicine;
  String? selectedMedicineId;
  static const Color _bgStart = Color(0xFF041A14);
  static const Color _bgEnd = Color(0xFF0E5A42);
  static const Color _accent = Color(0xFFFFD166);
  double _round2(double v) => double.parse(v.toStringAsFixed(2));

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

  // ---------- SEARCH ----------
  Stream<QuerySnapshot> searchMedicines(String query) {
    final col = firestore.collection('medicines');

    // If query is empty, return most recently created/updated medicines so new items show up
    if (query.isEmpty) {
      // order by updatedAt (fallback to createdAt) to surface latest items
      return col
          .orderBy('updatedAt', descending: true)
          .limit(10)
          .snapshots();
    }

    // Use the normalized lower-case field for prefix search
    final qLower = query.toLowerCase();
    return col
        .orderBy('medicineNameLower')
        .startAt([qLower])
        .endAt([qLower + '\uf8ff'])
        .limit(50)
        .snapshots();
  }

  // ---------- CALCULATIONS ----------
  double get subTotal =>
      _round2(billItems.fold(0.0, (sum, item) => sum + (item['total'] as num).toDouble()));

  double get paid => _round2(double.tryParse(paidController.text) ?? 0.0);
  double get due => _round2(subTotal - paid);

  // ---------- ADD ITEM ----------
  Future<void> addToBill() async {
    if (_isAdding) return;
    setState(() => _isAdding = true);
    try {
      if (selectedMedicine == null || qtyController.text.isEmpty) return;

      final qty = int.tryParse(qtyController.text);
      if (qty == null || qty <= 0) return;

      // SAFE STOCK DEFAULT = 0 and tolerant parsing
      final rawStock = selectedMedicine!['quantity'] ?? selectedMedicine!['stock'] ?? selectedMedicine!['qty'] ?? 0;
      final int stock = (rawStock is num) ? rawStock.toInt() : int.tryParse(rawStock.toString()) ?? 0;

      int existingQty = 0;
      final existingIndex = billItems.indexWhere((it) => it['medicineId'] == selectedMedicineId);
      if (existingIndex >= 0) {
        final existingRaw = billItems[existingIndex]['qty'];
        existingQty = (existingRaw is num) ? existingRaw.toInt() : int.tryParse(existingRaw.toString()) ?? 0;
      }

      if (qty > stock) {
        await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text("Stock Error"),
            content: Text(
                "Quantity must be less than or equal to stock.\nAvailable stock: $stock"),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("OK"))
            ],
          ),
        );
        return;
      }

      final rawPrice = selectedMedicine!['price'] ?? 0;
      final double price = _round2((rawPrice is num) ? rawPrice.toDouble() : double.tryParse(rawPrice.toString()) ?? 0.0);

      setState(() {
        if (existingIndex >= 0) {
          // Replace qty with the latest entered value (so user can increase or reduce)
          billItems[existingIndex]['qty'] = qty;
          billItems[existingIndex]['price'] = price;
          billItems[existingIndex]['total'] = _round2(qty * price);
        } else {
          billItems.add({
            'medicineId': selectedMedicineId,
            'name': selectedMedicine!['medicineName'] ?? (selectedMedicine!['medicineNameLower'] ?? ''),
            'qty': qty,
            'price': price,
            'total': _round2(qty * price),
          });
        }

        selectedMedicine = null;
        selectedMedicineId = null;
        searchController.clear();
        qtyController.clear();
      });
    } finally {
      if (mounted) setState(() => _isAdding = false);
    }
  }

  // ---------- SAVE BILL ----------
  Future<void> saveBill() async {
    if (_isSaving) return;
    if (billItems.isEmpty) return;

    setState(() => _isSaving = true);
    try {
      final batch = firestore.batch();

      final billRef = firestore
          .collection('sales')
          .doc(widget.date)
          .collection('bills')
          .doc();

      batch.set(billRef, {
        'items': billItems,
        'subTotal': subTotal,
        'paid': paid,
        'due': due,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // REDUCE STOCK SAFELY: update BOTH 'quantity' and 'stock' so all pages stay consistent
      for (var item in billItems) {
        final medRef = firestore.collection('medicines').doc(item['medicineId']);
        batch.update(medRef, {
          'quantity': FieldValue.increment(-item['qty']),
          'stock': FieldValue.increment(-item['qty']),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Save failed: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

    @override
  Widget build(BuildContext context) {
    final timeString = DateFormat('hh:mm a').format(DateTime.now());

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          "New Bill",
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
                    "Date: ${widget.date}",
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                      child: Container(
                        height: 52,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withOpacity(0.18)),
                        ),
                        child: Row(
                          children: [
                            const SizedBox(width: 12),
                            const Icon(Icons.search, color: Colors.white70),
                            const SizedBox(width: 6),
                            Expanded(
                              child: TextField(
                                controller: searchController,
                                style: const TextStyle(color: Colors.white, fontSize: 14),
                                decoration: const InputDecoration(
                                  hintText: "Search medicine",
                                  hintStyle: TextStyle(color: Colors.white54),
                                  border: InputBorder.none,
                                ),
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                            if (searchController.text.isNotEmpty)
                              IconButton(
                                icon: const Icon(Icons.clear, color: Colors.white70),
                                onPressed: () => setState(() => searchController.clear()),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                      child: Container(
                        height: 160,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withOpacity(0.18)),
                        ),
                        child: StreamBuilder<QuerySnapshot>(
                          stream: searchMedicines(searchController.text),
                          builder: (_, snapshot) {
                            if (!snapshot.hasData) {
                              return const Center(child: CircularProgressIndicator(color: Colors.white));
                            }
                            final docs = snapshot.data!.docs;
                            if (docs.isEmpty) {
                              return const Center(child: Text("No medicines found", style: TextStyle(color: Colors.white70)));
                            }
                            return ListView.builder(
                              itemCount: docs.length,
                              itemBuilder: (_, i) {
                                final data = docs[i].data() as Map<String, dynamic>;

                                final rawStock = data['quantity'] ?? data['stock'] ?? data['qty'] ?? 0;
                                final int stock = (rawStock is num) ? rawStock.toInt() : int.tryParse(rawStock.toString()) ?? 0;
                                final rawPrice = data['price'] ?? 0;
                                final double price = _round2((rawPrice is num) ? rawPrice.toDouble() : double.tryParse(rawPrice.toString()) ?? 0.0);

                                final displayName = (data['medicineName'] ?? data['medicineNameLower'] ?? '').toString();

                                return ListTile(
                                  title: Text(displayName, style: const TextStyle(color: Colors.white)),
                                  subtitle: Text("\u09F3 ${price.toStringAsFixed(2)} | Stock: $stock", style: const TextStyle(color: Colors.white70)),
                                  onTap: () {
                                    setState(() {
                                      selectedMedicine = data;
                                      selectedMedicineId = docs[i].id;
                                      searchController.text = displayName;
                                    });
                                  },
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                  if (selectedMedicine != null) ...[
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white.withOpacity(0.18)),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: qtyController,
                                  keyboardType: TextInputType.number,
                                  style: const TextStyle(color: Colors.white),
                                  decoration: InputDecoration(
                                    labelText: "Quantity (Stock: ${selectedMedicine!['quantity'] ?? selectedMedicine!['stock'] ?? 0})",
                                    labelStyle: const TextStyle(color: Colors.white70),
                                    border: const OutlineInputBorder(),
                                    enabledBorder: OutlineInputBorder(
                                      borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderSide: const BorderSide(color: _accent, width: 1.4),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton(
                                onPressed: _isAdding ? null : addToBill,
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
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Expanded(
                    child: billItems.isEmpty
                        ? const Center(child: Text("No items yet", style: TextStyle(color: Colors.white70)))
                        : ListView.builder(
                            itemCount: billItems.length,
                            itemBuilder: (_, index) {
                              final item = billItems[index];
                              return Container(
                                margin: const EdgeInsets.symmetric(vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: Colors.white.withOpacity(0.16)),
                                ),
                                child: ListTile(
                                  title: Text(item['name'], style: const TextStyle(color: Colors.white)),
                                  subtitle: Text("${item['qty']} × \u09F3 ${item['price']}", style: const TextStyle(color: Colors.white70)),
                                  trailing: Text("\u09F3 ${item['total']}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
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
                            const SizedBox(height: 6),
                            Text("Time: $timeString", style: const TextStyle(color: Colors.white60, fontSize: 12)),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _isSaving ? null : saveBill,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _accent,
                                  foregroundColor: Colors.black,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                child: _isSaving
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                                      )
                                    : const Text("Save Bill"),
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



