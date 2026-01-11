// CheckStockPage.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class CheckStockPage extends StatefulWidget {
  final String companyId;
  final String companyName;

  const CheckStockPage({
    super.key,
    required this.companyId,
    required this.companyName,
  });

  @override
  State<CheckStockPage> createState() => _CheckStockPageState();
}

class _CheckStockPageState extends State<CheckStockPage> {
  final FirebaseFirestore firestore = FirebaseFirestore.instance;

  // Threshold options (0 means "All")
  final List<int> _thresholdOptions = [0, 5, 10, 20, 40, 50, 100];
  int _selectedThreshold = 0;

  // Sort by quantity ascending by default. If false, sort by medicine name.
  bool _sortByQuantity = true;

  // --- Add-medicine state
  bool _isAdding = false;
  bool _addLoading = false;
  Map<String, dynamic>? _foundExisting; // existing doc data if found
  String? _foundDocId;

  // Stream that fetches medicines and filters client-side to tolerate mixed-case fields.
  // Returns a Stream<List<QueryDocumentSnapshot>> so we can filter, threshold and sort easily.
  Stream<List<QueryDocumentSnapshot>> getCompanyMedicines() {
    // We fetch a reasonable number of docs ordered by medicineNameLower.
    // Adjust limit if you expect more than 500 unique medicines.
    return firestore
        .collection('medicines')
        .orderBy('medicineNameLower')
        .limit(1000)
        .snapshots()
        .map((snap) {
      final wantedUpper = widget.companyName.trim().toUpperCase();
      final wantedSlug = widget.companyId.trim().toLowerCase(); // slug passed from CompanyListPage

      // first filter by company (tolerant to different stored fields)
      final matched = snap.docs.where((doc) {
        final data = doc.data() as Map<String, dynamic>;

        final rawCompany = (data['companyName'] ??
            data['companyNameUpper'] ??
            data['companyNameLower'] ??
            '')
            .toString()
            .trim();

        if (rawCompany.isEmpty) return false;

        final compUpper = rawCompany.toUpperCase();
        final compLower = rawCompany.toLowerCase();
        final compSlug = compLower.replaceAll(' ', '_');

        return compUpper == wantedUpper || compLower == wantedSlug || compSlug == wantedSlug;
      }).toList();

      // apply threshold filter
      final threshold = _selectedThreshold;
      final thresholdFiltered = threshold <= 0
          ? matched
          : matched.where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        final qty = (data['quantity'] ?? data['stock'] ?? data['qty'] ?? 0);
        final qnum = (qty is num) ? qty.toInt() : int.tryParse(qty.toString()) ?? 0;
        return qnum <= threshold;
      }).toList();

      // sort results
      thresholdFiltered.sort((a, b) {
        final aData = a.data() as Map<String, dynamic>;
        final bData = b.data() as Map<String, dynamic>;

        if (_sortByQuantity) {
          final aQty = (aData['quantity'] ?? aData['stock'] ?? aData['qty'] ?? 0);
          final bQty = (bData['quantity'] ?? bData['stock'] ?? bData['qty'] ?? 0);
          final aNum = (aQty is num) ? aQty.toInt() : int.tryParse(aQty.toString()) ?? 0;
          final bNum = (bQty is num) ? bQty.toInt() : int.tryParse(bQty.toString()) ?? 0;
          // ascending: smallest quantity first
          final cmp = aNum.compareTo(bNum);
          if (cmp != 0) return cmp;
          // tie-breaker: medicine name
          final aName = (aData['medicineName'] ?? aData['medicineNameLower'] ?? '').toString();
          final bName = (bData['medicineName'] ?? bData['medicineNameLower'] ?? '').toString();
          return aName.toLowerCase().compareTo(bName.toLowerCase());
        } else {
          final aName = (aData['medicineName'] ?? aData['medicineNameLower'] ?? '').toString();
          final bName = (bData['medicineName'] ?? bData['medicineNameLower'] ?? '').toString();
          final cmp = aName.toLowerCase().compareTo(bName.toLowerCase());
          if (cmp != 0) return cmp;
          // tie-breaker: quantity
          final aQty = (aData['quantity'] ?? aData['stock'] ?? aData['qty'] ?? 0);
          final bQty = (bData['quantity'] ?? bData['stock'] ?? bData['qty'] ?? 0);
          final aNum = (aQty is num) ? aQty.toInt() : int.tryParse(aQty.toString()) ?? 0;
          final bNum = (bQty is num) ? bQty.toInt() : int.tryParse(bQty.toString()) ?? 0;
          return aNum.compareTo(bNum);
        }
      });

      return thresholdFiltered;
    });
  }

  String _thresholdLabel(int t) {
    return t <= 0 ? 'All' : '<= $t';
  }

  // ----------------- Helpers for add-medicine -----------------

  /// Find existing medicine doc by (name, company). Sets _foundDocId and returns data or null.
  Future<Map<String, dynamic>?> _findExistingMedicineDoc(String name, String companyUpper) async {
    final nameLower = name.trim().toLowerCase();
    final col = firestore.collection('medicines');

    // Primary: medicineNameLower + companyNameUpper
    try {
      var q = await col
          .where('medicineNameLower', isEqualTo: nameLower)
          .where('companyNameUpper', isEqualTo: companyUpper)
          .limit(1)
          .get();

      if (q.docs.isNotEmpty) {
        _foundDocId = q.docs.first.id;
        return q.docs.first.data();
      }

      // Fallback: medicineNameLower only (rare)
      q = await col.where('medicineNameLower', isEqualTo: nameLower).limit(1).get();
      if (q.docs.isNotEmpty) {
        _foundDocId = q.docs.first.id;
        return q.docs.first.data();
      }
    } catch (e) {
      debugPrint('findExisting error: $e');
    }

    _foundDocId = null;
    return null;
  }

  /// Create new medicine doc for this company
  Future<void> _createMedicine(String name, int qty, double price) async {
    final nameLower = name.trim().toLowerCase();
    final companyUpper = widget.companyName.trim().toUpperCase();
    await firestore.collection('medicines').add({
      'medicineName': name.trim(),
      'medicineNameLower': nameLower,
      'companyName': companyUpper,
      'companyNameUpper': companyUpper,
      'quantity': qty,
      'stock': qty,
      'price': price,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Increment stock/quantity of existing doc
  Future<void> _incrementExisting(String docId, int qty, double price) async {
    final docRef = firestore.collection('medicines').doc(docId);
    final updates = <String, dynamic>{
      'quantity': FieldValue.increment(qty),
      'stock': FieldValue.increment(qty),
      'price': price,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    await docRef.update(updates);
  }

  // ----------------- Add dialog UI -----------------

  Future<void> _showAddMedicineDialog() async {
    final nameController = TextEditingController();
    final qtyController = TextEditingController();
    final priceController = TextEditingController();
    _foundExisting = null;
    _foundDocId = null;

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (c, setState) {
          Future<void> checkName(String v) async {
            if (v.trim().isEmpty) {
              setState(() {
                _foundExisting = null;
                _foundDocId = null;
              });
              return;
            }
            final companyUpper = widget.companyName.trim().toUpperCase();
            final found = await _findExistingMedicineDoc(v, companyUpper);
            setState(() {
              _foundExisting = found;
              // if found, fill qty/price preview
              if (_foundExisting != null) {
                final qtyVal = _foundExisting!['quantity'] ?? _foundExisting!['stock'] ?? 0;
                final priceVal = _foundExisting!['price'] ?? '';
                qtyController.text = qtyVal.toString();
                priceController.text = priceVal.toString();
              } else {
                // keep user-entered values
              }
            });
          }

          return AlertDialog(
            title: const Text('Add Medicine'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Company (readonly)
                  TextField(
                    controller: TextEditingController(text: widget.companyName),
                    readOnly: true,
                    decoration: InputDecoration(labelText: 'Company (pre-filled)'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Medicine name'),
                    onChanged: (v) {
                      // debounce not necessary here
                      checkName(v);
                    },
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: qtyController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Quantity'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: priceController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Price'),
                  ),
                  const SizedBox(height: 12),
                  if (_foundExisting != null)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('This medicine already exists for this company:', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 6),
                        Text('Name: ${(_foundExisting!['medicineName'] ?? _foundExisting!['medicineNameLower'] ?? '').toString()}'),
                        Text('Qty: ${(_foundExisting!['quantity'] ?? _foundExisting!['stock'] ?? 0).toString()}'),
                        Text('Price: ${(_foundExisting!['price'] ?? '').toString()}'),
                        const SizedBox(height: 8),
                        const Text('You can increase stock (adds quantity to existing) or Cancel.', style: TextStyle(color: Colors.orange)),
                      ],
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              if (_foundExisting != null)
                ElevatedButton(
                  onPressed: _addLoading
                      ? null
                      : () async {
                    // increment existing
                    final qty = int.tryParse(qtyController.text.trim()) ?? 0;
                    final price = double.tryParse(priceController.text.trim()) ?? ((_foundExisting!['price'] is num) ? (_foundExisting!['price'] as num).toDouble() : 0.0);
                    if (qty <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a quantity > 0 to add to existing stock')));
                      return;
                    }
                    setState(() => _addLoading = true);
                    try {
                      await _incrementExisting(_foundDocId!, qty, price);
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Stock updated (existing medicine)')));
                    } catch (e) {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to update: $e')));
                    } finally {
                      setState(() => _addLoading = false);
                    }
                  },
                  child: _addLoading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator()) : const Text('Increase stock'),
                )
              else
                ElevatedButton(
                  onPressed: _addLoading
                      ? null
                      : () async {
                    // create new medicine
                    final name = nameController.text.trim();
                    final qty = int.tryParse(qtyController.text.trim()) ?? 0;
                    final price = double.tryParse(priceController.text.trim()) ?? 0.0;
                    if (name.isEmpty || qty <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter name and quantity > 0')));
                      return;
                    }
                    setState(() => _addLoading = true);
                    try {
                      // double-check duplicate right before create
                      final companyUpper = widget.companyName.trim().toUpperCase();
                      final found = await _findExistingMedicineDoc(name, companyUpper);
                      if (found != null) {
                        // If found between UI and server, tell user and show update option instead
                        setState(() {
                          _foundExisting = found;
                        });
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Medicine already exists (just created by someone else).')));
                        // keep dialog open for user to click Increase stock
                        setState(() => _addLoading = false);
                        return;
                      }

                      await _createMedicine(name, qty, price);
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Medicine added')));
                    } catch (e) {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to add: $e')));
                    } finally {
                      setState(() => _addLoading = false);
                    }
                  },
                  child: _addLoading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator()) : const Text('Add'),
                ),
            ],
          );
        });
      },
    );
  }

  // ----------------- build -----------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("${widget.companyName} - Stock"),
        backgroundColor: Colors.green,
      ),
      backgroundColor: const Color(0xFF01684D),
      body: Column(
        children: [
          // Controls: threshold dropdown and sort toggle
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10),
            child: Row(
              children: [
                // Threshold dropdown
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DropdownButton<int>(
                      value: _selectedThreshold,
                      isExpanded: true,
                      underline: const SizedBox.shrink(),
                      dropdownColor: const Color(0xFF01684D),
                      iconEnabledColor: Colors.white70,
                      items: _thresholdOptions
                          .map((t) => DropdownMenuItem<int>(
                        value: t,
                        child: Text(
                          _thresholdLabel(t),
                          style: const TextStyle(color: Colors.white),
                        ),
                      ))
                          .toList(),
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() {
                          _selectedThreshold = v;
                        });
                      },
                    ),
                  ),
                ),

                const SizedBox(width: 10),

                // Sort toggle
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: IconButton(
                    icon: Icon(
                      _sortByQuantity ? Icons.sort_by_alpha : Icons.format_list_numbered,
                      color: Colors.white,
                    ),
                    tooltip: _sortByQuantity ? 'Sort by quantity' : 'Sort by name',
                    onPressed: () {
                      setState(() {
                        _sortByQuantity = !_sortByQuantity;
                      });
                    },
                  ),
                ),
              ],
            ),
          ),

          // List
          Expanded(
            child: StreamBuilder<List<QueryDocumentSnapshot>>(
              stream: getCompanyMedicines(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData) {
                  return Center(
                    child: Text(
                      "No medicines found",
                      style: TextStyle(color: Colors.grey[700], fontSize: 16),
                    ),
                  );
                }

                final docs = snapshot.data!;

                if (docs.isEmpty) {
                  return Center(
                    child: Text(
                      "No medicines found",
                      style: TextStyle(color: Colors.grey[700], fontSize: 16),
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data() as Map<String, dynamic>;
                    final qty = data['quantity'] ?? data['stock'] ?? data['qty'] ?? 0;
                    final price = data['price'] ?? 0;
                    final medName = (data['medicineName'] ?? data['medicineNameLower'] ?? '').toString();

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      color: Colors.white.withOpacity(0.2),
                      child: ListTile(
                        title: Text(
                          medName.toUpperCase(),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          "Quantity: $qty | Price: ৳$price",
                          style: const TextStyle(color: Colors.white70),
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
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.yellow[700],
        child: const Icon(Icons.add, color: Colors.black),
        onPressed: _showAddMedicineDialog,
        tooltip: 'Add medicine for this company',
      ),
    );
  }
}
