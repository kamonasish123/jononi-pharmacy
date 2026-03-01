// CheckStockPage.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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
    final companyController = TextEditingController(text: widget.companyName);
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

          return Theme(
            data: _dialogTheme(context),
            child: AlertDialog(
              backgroundColor: _bgEnd,
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: BorderSide(color: Colors.white.withOpacity(0.12)),
              ),
              title: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: _accent.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.medical_services, color: _accent),
                  ),
                  const SizedBox(width: 10),
                  const Text('Add Medicine'),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: companyController,
                      readOnly: true,
                      decoration: const InputDecoration(
                        labelText: 'Company',
                        prefixIcon: Icon(Icons.business),
                      ),
                    ),
                    const SizedBox(height: 10),
                    StreamBuilder<QuerySnapshot>(
                      stream: firestore.collection('medicines').orderBy('medicineNameLower').limit(500).snapshots(),
                      builder: (context, snap) {
                        final names = <String>{};
                        if (snap.hasData) {
                          for (final doc in snap.data!.docs) {
                            final data = doc.data() as Map<String, dynamic>;
                            final name = (data['medicineName'] ?? data['medicineNameLower'] ?? '').toString().trim();
                            if (name.isNotEmpty) names.add(name);
                          }
                        }
                        final nameList = names.toList()..sort();

                        return Autocomplete<String>(
                          optionsBuilder: (TextEditingValue value) {
                            final query = value.text.trim().toLowerCase();
                            if (query.isEmpty) {
                              return const Iterable<String>.empty();
                            }
                            return nameList.where((n) => n.toLowerCase().startsWith(query)).take(10);
                          },
                          onSelected: (selection) {
                            nameController.text = selection;
                            checkName(selection);
                          },
                          optionsViewBuilder: (context, onSelected, options) {
                            return Align(
                              alignment: Alignment.topLeft,
                              child: Material(
                                color: Colors.transparent,
                                child: Container(
                                  margin: const EdgeInsets.only(top: 8),
                                  constraints: const BoxConstraints(maxHeight: 240),
                                  decoration: BoxDecoration(
                                    color: _bgEnd,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: Colors.white24),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.25),
                                        blurRadius: 12,
                                        offset: const Offset(0, 6),
                                      ),
                                    ],
                                  ),
                                  child: ListView.builder(
                                    padding: const EdgeInsets.symmetric(vertical: 6),
                                    itemCount: options.length,
                                    itemBuilder: (context, index) {
                                      final option = options.elementAt(index);
                                      return InkWell(
                                        onTap: () => onSelected(option),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                          child: Row(
                                            children: [
                                              Container(
                                                width: 28,
                                                height: 28,
                                                decoration: BoxDecoration(
                                                  color: _accent.withOpacity(0.18),
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                child: const Icon(Icons.medical_services, size: 16, color: _accent),
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Text(option, style: const TextStyle(color: Colors.white)),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            );
                          },
                          fieldViewBuilder: (context, textController, focusNode, onSubmit) {
                            return TextField(
                              controller: textController,
                              focusNode: focusNode,
                              style: const TextStyle(color: Colors.white),
                              onChanged: (v) {
                                if (nameController.text != v) {
                                  nameController.text = v;
                                }
                                checkName(v);
                              },
                              decoration: InputDecoration(
                                labelText: 'Medicine name',
                                prefixIcon: const Icon(Icons.medication_outlined),
                                suffixIcon: textController.text.trim().isEmpty
                                    ? null
                                    : IconButton(
                                        icon: const Icon(Icons.close, color: Colors.white70),
                                        onPressed: () {
                                          textController.clear();
                                          nameController.clear();
                                          checkName('');
                                        },
                                      ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: qtyController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Quantity',
                        prefixIcon: Icon(Icons.confirmation_number),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: priceController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Price (\u09F3)',
                        prefixIcon: Icon(Icons.attach_money),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_foundExisting != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Already exists for this company',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              (_foundExisting!['medicineName'] ?? _foundExisting!['medicineNameLower'] ?? '').toString(),
                              style: const TextStyle(color: Colors.white70),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _infoChip(
                                  'Qty',
                                  (_foundExisting!['quantity'] ?? _foundExisting!['stock'] ?? 0).toString(),
                                ),
                                _infoChip(
                                  'Price',
                                  '\u09F3 ${(_foundExisting!['price'] ?? '').toString()}',
                                  color: _accent,
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Increase stock to add quantity to this item.',
                              style: TextStyle(color: Colors.orange),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                if (_foundExisting != null)
                  ElevatedButton.icon(
                    onPressed: _addLoading
                        ? null
                        : () async {
                            // increment existing
                            final qty = int.tryParse(qtyController.text.trim()) ?? 0;
                            final price = double.tryParse(priceController.text.trim()) ??
                                ((_foundExisting!['price'] is num) ? (_foundExisting!['price'] as num).toDouble() : 0.0);
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
                    icon: _addLoading
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.add_circle_outline),
                    label: const Text('Increase stock'),
                  )
                else
                  ElevatedButton.icon(
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
                                setState(() {
                                  _foundExisting = found;
                                });
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Medicine already exists (just created by someone else).')));
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
                    icon: _addLoading
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.check_circle_outline),
                    label: const Text('Add'),
                  ),
              ],
            ),
          );
        });
      },
    );
  }

  // ----------------- build -----------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          "${widget.companyName} - Stock",
          style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Stack(
        children: [
          _buildBackdrop(),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white.withOpacity(0.18)),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: DropdownButton<int>(
                                value: _selectedThreshold,
                                isExpanded: true,
                                underline: const SizedBox.shrink(),
                                dropdownColor: _bgEnd,
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
                            const SizedBox(width: 10),
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(10),
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
                    ),
                  ),
                ),
                Expanded(
                  child: StreamBuilder<List<QueryDocumentSnapshot>>(
                    stream: getCompanyMedicines(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator(color: Colors.white));
                      }

                      if (!snapshot.hasData || snapshot.data!.isEmpty) {
                        return const Center(
                          child: Text(
                            "No medicines found",
                            style: TextStyle(color: Colors.white70, fontSize: 16),
                          ),
                        );
                      }

                      final docs = snapshot.data!;

                      return ListView.builder(
                        padding: const EdgeInsets.only(bottom: 120),
                        itemCount: docs.length,
                        itemBuilder: (context, index) {
                          final data = docs[index].data() as Map<String, dynamic>;
                          final qty = data['quantity'] ?? data['stock'] ?? data['qty'] ?? 0;
                          final price = data['price'] ?? 0;
                          final medName = (data['medicineName'] ?? data['medicineNameLower'] ?? '').toString();

                          /* return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                                    title: Text(
                                      medName.toUpperCase(),
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                    ),
                                    subtitle: Text(
                                      "Quantity: $qty | Price: ৳$price",
                                      style: const TextStyle(color: Colors.white70),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ); */
                          final qtyNum = (qty is num) ? qty.toInt() : int.tryParse(qty.toString()) ?? 0;
                          final qtyColor = qtyNum <= 0
                              ? Colors.redAccent
                              : (_selectedThreshold > 0 && qtyNum <= _selectedThreshold)
                                  ? Colors.orangeAccent
                                  : Colors.white70;

                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            child: ClipRRect(
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
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: 44,
                                        height: 44,
                                        decoration: BoxDecoration(
                                          color: _accent.withOpacity(0.18),
                                          borderRadius: BorderRadius.circular(14),
                                        ),
                                        child: const Icon(Icons.medical_services, color: _accent),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              medName.toUpperCase(),
                                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                            ),
                                            const SizedBox(height: 8),
                                            Wrap(
                                              spacing: 8,
                                              runSpacing: 8,
                                              children: [
                                                _infoChip('Qty', qtyNum.toString(), color: qtyColor),
                                                _infoChip('Price', '\u09F3 $price', color: _accent),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
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
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: _accent,
        child: const Icon(Icons.add, color: Colors.black),
        onPressed: _showAddMedicineDialog,
        tooltip: 'Add medicine for this company',
      ),
    );
  }
}


