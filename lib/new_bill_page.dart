import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class NewBillPage extends StatefulWidget {
  final String date;

  const NewBillPage({super.key, required this.date});

  @override
  State<NewBillPage> createState() => _NewBillPageState();
}

class _NewBillPageState extends State<NewBillPage> {
  final FirebaseFirestore firestore = FirebaseFirestore.instance;

  final TextEditingController searchController = TextEditingController();
  final TextEditingController qtyController = TextEditingController();
  final TextEditingController paidController = TextEditingController();

  List<Map<String, dynamic>> billItems = [];
  Map<String, dynamic>? selectedMedicine;
  String? selectedMedicineId;

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
      billItems.fold(0.0, (sum, item) => sum + (item['total'] as num).toDouble());

  double get paid => double.tryParse(paidController.text) ?? 0.0;
  double get due => subTotal - paid;

  // ---------- ADD ITEM ----------
  void addToBill() {
    if (selectedMedicine == null || qtyController.text.isEmpty) return;

    final qty = int.tryParse(qtyController.text);
    if (qty == null || qty <= 0) return;

    // SAFE STOCK DEFAULT = 0 and tolerant parsing
    final rawStock = selectedMedicine!['quantity'] ?? selectedMedicine!['stock'] ?? selectedMedicine!['qty'] ?? 0;
    final int stock = (rawStock is num) ? rawStock.toInt() : int.tryParse(rawStock.toString()) ?? 0;

    if (qty > stock) {
      showDialog(
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
    final double price = (rawPrice is num) ? rawPrice.toDouble() : double.tryParse(rawPrice.toString()) ?? 0.0;

    setState(() {
      billItems.add({
        'medicineId': selectedMedicineId,
        'name': selectedMedicine!['medicineName'] ?? (selectedMedicine!['medicineNameLower'] ?? ''),
        'qty': qty,
        'price': price,
        'total': qty * price,
      });

      selectedMedicine = null;
      selectedMedicineId = null;
      searchController.clear();
      qtyController.clear();
    });
  }

  // ---------- SAVE BILL ----------
  Future<void> saveBill() async {
    if (billItems.isEmpty) return;

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
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final timeString = DateFormat('hh:mm a').format(DateTime.now());

    return Scaffold(
      appBar: AppBar(
        title: Text("New Bill - ${widget.date}"),
        backgroundColor: Colors.green,
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            // Search medicine
            TextField(
              controller: searchController,
              decoration: const InputDecoration(
                labelText: "Search Medicine",
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 6),

            // Search results
            if (searchController.text.isNotEmpty)
              SizedBox(
                height: 160,
                child: StreamBuilder<QuerySnapshot>(
                  stream: searchMedicines(searchController.text),
                  builder: (_, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final docs = snapshot.data!.docs;
                    return ListView.builder(
                      itemCount: docs.length,
                      itemBuilder: (_, i) {
                        final data = docs[i].data() as Map<String, dynamic>;

                        // tolerant parsing for stock and price
                        final rawStock = data['quantity'] ?? data['stock'] ?? data['qty'] ?? 0;
                        final int stock = (rawStock is num) ? rawStock.toInt() : int.tryParse(rawStock.toString()) ?? 0;
                        final rawPrice = data['price'] ?? 0;
                        final double price = (rawPrice is num) ? rawPrice.toDouble() : double.tryParse(rawPrice.toString()) ?? 0.0;

                        final displayName = (data['medicineName'] ?? data['medicineNameLower'] ?? '').toString();

                        return ListTile(
                          title: Text(displayName),
                          subtitle: Text("৳$price | Stock: $stock"),
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

            // If query is empty, still show recent items so user can pick latest medicines
            if (searchController.text.isEmpty)
              SizedBox(
                height: 160,
                child: StreamBuilder<QuerySnapshot>(
                  stream: searchMedicines(''),
                  builder: (_, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final docs = snapshot.data!.docs;
                    return ListView.builder(
                      itemCount: docs.length,
                      itemBuilder: (_, i) {
                        final data = docs[i].data() as Map<String, dynamic>;
                        final rawStock = data['quantity'] ?? data['stock'] ?? data['qty'] ?? 0;
                        final int stock = (rawStock is num) ? rawStock.toInt() : int.tryParse(rawStock.toString()) ?? 0;
                        final rawPrice = data['price'] ?? 0;
                        final double price = (rawPrice is num) ? rawPrice.toDouble() : double.tryParse(rawPrice.toString()) ?? 0.0;
                        final displayName = (data['medicineName'] ?? data['medicineNameLower'] ?? '').toString();

                        return ListTile(
                          title: Text(displayName),
                          subtitle: Text("৳$price | Stock: $stock"),
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

            // Quantity input
            if (selectedMedicine != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: qtyController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText:
                        "Quantity (Stock: ${selectedMedicine!['quantity'] ?? selectedMedicine!['stock'] ?? 0})",
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(onPressed: addToBill, child: const Text("Add")),
                ],
              ),
            ],

            // Bill items list
            Expanded(
              child: ListView.builder(
                itemCount: billItems.length,
                itemBuilder: (_, index) {
                  final item = billItems[index];
                  return ListTile(
                    title: Text(item['name']),
                    subtitle: Text("${item['qty']} × ৳${item['price']}"),
                    trailing: Text("৳${item['total']}"),
                  );
                },
              ),
            ),

            const Divider(),

            // Total, Paid, Due
            Text("Total = ৳${subTotal.toStringAsFixed(2)}", style: const TextStyle(fontWeight: FontWeight.bold)),
            TextField(
              controller: paidController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: "Paid"),
            ),
            Text("Due = ৳${due.toStringAsFixed(2)}", style: TextStyle(color: due > 0 ? Colors.red : Colors.green)),
            const SizedBox(height: 6),
            Text("Time: $timeString"),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: saveBill,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.yellow[700],
                foregroundColor: Colors.black,
              ),
              child: const Text("Save Bill"),
            ),
          ],
        ),
      ),
    );
  }
}
