// MedicineAddPage.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

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

class MedicineAddPage extends StatefulWidget {
  @override
  _MedicineAddPageState createState() => _MedicineAddPageState();
}

class _MedicineAddPageState extends State<MedicineAddPage> {
  final TextEditingController companyController = TextEditingController();
  final TextEditingController nameController = TextEditingController();
  final TextEditingController qtyController = TextEditingController();
  final TextEditingController priceController = TextEditingController();
  final TextEditingController searchController = TextEditingController();
  final TextEditingController companySearchController = TextEditingController();

  bool isLoading = false;
  Map<String, dynamic>? existingMedicine;
  String? existingDocId;

  String searchText = "";
  String companySearchText = "";

  final FirebaseFirestore firestore = FirebaseFirestore.instance;

  // current user's role (used to control delete visibility)
  String currentUserRole = 'seller';

  @override
  void initState() {
    super.initState();
    _loadMyRole();
  }

  Future<void> _loadMyRole() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final doc = await firestore.collection('users').doc(user.uid).get();
      if (doc.exists) {
        final data = doc.data();
        setState(() {
          currentUserRole = (data?['role'] ?? 'seller').toString();
        });
      }
    } catch (e) {
      // ignore — default role will be 'seller'
    }
  }

  @override
  void dispose() {
    companyController.dispose();
    nameController.dispose();
    qtyController.dispose();
    priceController.dispose();
    searchController.dispose();
    companySearchController.dispose();
    super.dispose();
  }

  // normalize role helper
  String _normalizeRole(String? role) {
    if (role == null) return '';
    return role.toLowerCase().replaceAll(RegExp(r'[\s\-]+'), '_').trim();
  }

  bool get _canDelete {
    final nr = _normalizeRole(currentUserRole);
    return nr == 'admin' || nr == 'manager';
  }

  // ---------------- HELPERS ----------------
  Widget _glassCard({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(12),
    EdgeInsetsGeometry? margin,
  }) {
    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: ClipRRect(
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
      ),
    );
  }

  Widget _sectionHeader(String title, String subtitle, IconData icon) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: _accent.withOpacity(0.18),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: _accent),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(subtitle, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          ),
        ),
      ],
    );
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

  /// Find an existing medicine document matching (case-insensitive) name + company.
  /// Returns doc snapshot data and sets existingDocId when found.
  Future<Map<String, dynamic>?> _findExistingMedicineDoc(String name, String company) async {
    final nameLower = name.trim().toLowerCase();
    final companyUpper = company.trim().toUpperCase();

    final col = firestore.collection('medicines');

    // Try normalized fields first (preferred)
    var q = await col
        .where('medicineNameLower', isEqualTo: nameLower)
        .where('companyNameUpper', isEqualTo: companyUpper)
        .limit(1)
        .get();

    if (q.docs.isNotEmpty) {
      existingDocId = q.docs.first.id;
      return q.docs.first.data();
    }

    // Fallback: older docs might have medicineName/companyName stored differently
    q = await col
        .where('medicineName', isEqualTo: nameLower)
        .where('companyName', isEqualTo: companyUpper)
        .limit(1)
        .get();

    if (q.docs.isNotEmpty) {
      existingDocId = q.docs.first.id;
      return q.docs.first.data();
    }

    // Another fallback: maybe company not provided originally — try only medicine name matches
    q = await col.where('medicineNameLower', isEqualTo: nameLower).limit(1).get();
    if (q.docs.isNotEmpty) {
      existingDocId = q.docs.first.id;
      return q.docs.first.data();
    }

    q = await col.where('medicineName', isEqualTo: nameLower).limit(1).get();
    if (q.docs.isNotEmpty) {
      existingDocId = q.docs.first.id;
      return q.docs.first.data();
    }

    existingDocId = null;
    return null;
  }

  // ---------------- CHECK EXISTING MEDICINE ----------------
  Future<void> checkMedicineExists(String name, String company) async {
    if (name.trim().isEmpty) {
      setState(() {
        existingMedicine = null;
        existingDocId = null;
      });
      return;
    }

    try {
      final data = await _findExistingMedicineDoc(
        name,
        company.isEmpty ? "UNKNOWN" : company,
      );

      if (data != null) {
        setState(() {
          existingMedicine = data;
          // fill qty and price from whichever field exists
          final qtyVal = data['quantity'] ?? data['stock'] ?? data['qty'];
          qtyController.text = (qtyVal ?? '').toString();
          priceController.text = (data['price'] ?? '').toString();
        });
      } else {
        setState(() {
          existingMedicine = null;
          existingDocId = null;
          qtyController.clear();
          priceController.clear();
        });
      }
    } catch (e) {
      // don't break UI on lookup error
      debugPrint("checkMedicineExists error: $e");
      setState(() {
        existingMedicine = null;
        existingDocId = null;
      });
    }
  }

  // ---------------- SAVE MEDICINE ----------------
  Future<void> saveMedicine() async {
    final rawName = nameController.text.trim();
    final name = rawName;
    final nameLower = name.toLowerCase();
    final companyRaw = companyController.text.trim();
    final company = companyRaw.isEmpty ? "UNKNOWN" : companyRaw;
    final companyUpper = company.toUpperCase();

    if (name.isEmpty || qtyController.text.isEmpty || priceController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Fill all required fields")));
      return;
    }

    final qty = int.tryParse(qtyController.text);
    final price = double.tryParse(priceController.text);

    if (qty == null || price == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Invalid quantity or price")));
      return;
    }

    setState(() => isLoading = true);

    try {
      // Try to find an existing document (robust against old/new field names)
      final existing = await _findExistingMedicineDoc(name, company);

      if (existingDocId != null) {
        // Update the existing doc: increment quantity & stock, set price and normalized fields
        final docRef = firestore.collection('medicines').doc(existingDocId);

        // We'll increment both 'quantity' and 'stock' (so legacy code reading either works)
        final updates = <String, dynamic>{
          'quantity': FieldValue.increment(qty),
          'stock': FieldValue.increment(qty),
          'price': price,
          // store company in uppercase and keep normalized fields
          'medicineName': name,
          'medicineNameLower': nameLower,
          'companyName': companyUpper,
          'companyNameUpper': companyUpper,
          'updatedAt': FieldValue.serverTimestamp(),
        };

        await docRef.update(updates);
      } else {
        // create new normalized document (write both stock+quantity and nameLower fields)
        await firestore.collection('medicines').add({
          'medicineName': name,
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

      // clear fields and UI state
      companyController.clear();
      nameController.clear();
      qtyController.clear();
      priceController.clear();
      existingMedicine = null;
      existingDocId = null;

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Medicine saved")));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
      debugPrint("saveMedicine error: $e");
    } finally {
      setState(() => isLoading = false);
    }
  }

  // ---------------- DELETE ----------------
  Future<void> _confirmAndDelete(DocumentReference docRef, String displayName) async {
    // Confirm user still has permission before performing deletion (extra safety)
    if (!_canDelete) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('You do not have permission to delete medicines')));
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete medicine?'),
        content: Text('Permanently delete "$displayName" from database? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await docRef.delete();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Deleted')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    }
  }

  // ---------------- STREAM (PREFIX SEARCH FIXED) ----------------
  Stream<QuerySnapshot> getMedicines() {
    final col = firestore.collection('medicines');

    // If user is searching by company, fetch a broad set and filter client-side
    if (companySearchText.isNotEmpty) {
      // fetch by medicineNameLower so we get a large set; increase limit if you expect more docs
      return col.orderBy('medicineNameLower').limit(1000).snapshots();
    }

    if (searchText.isNotEmpty) {
      final prefix = searchText.toLowerCase();
      return col
          .orderBy('medicineNameLower')
          .startAt([prefix])
          .endAt([prefix + '\uf8ff'])
          .limit(200)
          .snapshots();
    }

    return col.orderBy('medicineNameLower').snapshots();
  }

  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
    final bool isSearching = searchText.trim().isNotEmpty || companySearchText.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text("Medicine Manager", style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: Stack(
        children: [
          _buildBackdrop(),
          SafeArea(
            child: Column(
              children: [
                // INPUT AREA (only show add/update fields when NOT searching)
                /* if (!isSearching)
                  Expanded(
                    flex: 0,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          field(companyController, "Company Name (optional)", Icons.business),
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
                                  return nameList
                                      .where((n) => n.toLowerCase().startsWith(query))
                                      .take(10);
                                },
                                onSelected: (selection) {
                                  nameController.text = selection;
                                  checkMedicineExists(
                                    selection,
                                    companyController.text.isEmpty ? "UNKNOWN" : companyController.text,
                                  );
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
                                                      child: Text(
                                                        option,
                                                        style: const TextStyle(color: Colors.white),
                                                      ),
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
                                      checkMedicineExists(
                                        v,
                                        companyController.text.isEmpty ? "UNKNOWN" : companyController.text,
                                      );
                                    },
                                    decoration: InputDecoration(
                                      labelText: "Medicine Name",
                                      labelStyle: const TextStyle(color: Colors.white70),
                                      prefixIcon: const Icon(Icons.medical_services, color: Colors.white),
                                      suffixIcon: textController.text.trim().isEmpty
                                          ? null
                                          : IconButton(
                                              icon: const Icon(Icons.close, color: Colors.white70),
                                              onPressed: () {
                                                textController.clear();
                                                nameController.clear();
                                                checkMedicineExists('', companyController.text);
                                              },
                                            ),
                                      border: InputBorder.none,
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                          if (existingMedicine != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                "Existing → Qty: ${(existingMedicine!['quantity'] ?? existingMedicine!['stock'] ?? '')} | ৳${(existingMedicine!['price'] ?? '')}",
                                style: const TextStyle(color: Colors.yellowAccent),
                              ),
                            ),
                          const SizedBox(height: 10),
                          field(qtyController, "Quantity", Icons.confirmation_number, number: true),
                          const SizedBox(height: 10),
                          field(priceController, "Price", Icons.attach_money, number: true),
                          const SizedBox(height: 15),
                          ElevatedButton(
                            onPressed: isLoading ? null : saveMedicine,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _accent,
                              foregroundColor: Colors.black,
                              minimumSize: const Size(double.infinity, 48),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            child: isLoading
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : Text(existingMedicine != null ? "Update" : "Add"),
                          ),
                          const SizedBox(height: 15),
                        ],
                      ),
                    ),
                  ), */

                if (!isSearching)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                    child: _glassCard(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionHeader('Add Medicine', 'Create or update stock', Icons.medical_services),
                          const SizedBox(height: 14),
                          field(companyController, "Company Name (optional)", Icons.business),
                          const SizedBox(height: 10),
                          field(nameController, "Medicine Name", Icons.medical_services, onChange: (v) {
                            checkMedicineExists(
                              v,
                              companyController.text.isEmpty ? "UNKNOWN" : companyController.text,
                            );
                          }),
                          if (existingMedicine != null) ...[
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _infoChip(
                                  'Existing Qty',
                                  '${(existingMedicine!['quantity'] ?? existingMedicine!['stock'] ?? '')}',
                                  color: Colors.yellowAccent,
                                ),
                                _infoChip(
                                  'Existing Price',
                                  '\u09F3 ${(existingMedicine!['price'] ?? '')}',
                                  color: Colors.yellowAccent,
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: field(qtyController, "Quantity", Icons.confirmation_number, number: true),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: field(priceController, "Price", Icons.attach_money, number: true, decimal: true),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          ElevatedButton.icon(
                            onPressed: isLoading ? null : saveMedicine,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _accent,
                              foregroundColor: Colors.black,
                              minimumSize: const Size(double.infinity, 48),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            icon: isLoading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.check_circle_outline),
                            label: Text(existingMedicine != null ? "Update Medicine" : "Add Medicine"),
                          ),
                        ],
                      ),
                    ),
                  ),

                // SEARCH FIELDS (always visible)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                  child: _glassCard(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        _sectionHeader('Search', 'Find medicines fast', Icons.search),
                        const SizedBox(height: 12),
                        field(searchController, "Search Medicine", Icons.search, onChange: (v) {
                          setState(() {
                            searchText = v.trim();
                            if (companySearchText.isNotEmpty || companySearchController.text.isNotEmpty) {
                              companySearchText = "";
                              companySearchController.clear();
                            }
                          });
                        }, isSearch: true, onClear: () {
                          setState(() {
                            searchController.clear();
                            searchText = "";
                          });
                        }),
                        const SizedBox(height: 10),
                        field(companySearchController, "Search Company", Icons.business, onChange: (v) {
                          setState(() {
                            companySearchText = v.trim();
                            if (searchText.isNotEmpty || searchController.text.isNotEmpty) {
                              searchText = "";
                              searchController.clear();
                            }
                          });
                        }, isSearch: true, onClear: () {
                          setState(() {
                            companySearchController.clear();
                            companySearchText = "";
                          });
                        }),
                      ],
                    ),
                  ),
                ),

                // LIST
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: getMedicines(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator(color: Colors.white));
                      }

                      final docs = snapshot.data!.docs;

                      // If companySearchText is set, filter client-side to include docs that match
                      List<QueryDocumentSnapshot> visibleDocs = docs;
                      if (companySearchText.trim().isNotEmpty) {
                        final wanted = companySearchText.trim();
                        final wantedUpper = wanted.toUpperCase();
                        final wantedLower = wanted.toLowerCase();
                        final wantedSlug = wantedLower.replaceAll(' ', '_');

                        visibleDocs = docs.where((doc) {
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

                          return compUpper.contains(wantedUpper) ||
                              compLower.contains(wantedLower) ||
                              compSlug.contains(wantedSlug);
                        }).toList();
                      }

                      if (visibleDocs.isEmpty) {
                        return const Center(child: Text("No medicines found", style: TextStyle(color: Colors.white70)));
                      }

                      return ListView.builder(
                        padding: const EdgeInsets.only(bottom: 120),
                        itemCount: visibleDocs.length,
                        itemBuilder: (context, index) {
                          final docSnap = visibleDocs[index];
                          final raw = docSnap.data() as Map<String, dynamic>;
                          // prefer 'medicineName' (human-friendly) and fallback to 'medicineNameLower'
                          final displayName = (raw['medicineName'] ?? raw['medicineNameLower'] ?? '').toString();
                          final company = (raw['companyName'] ?? raw['companyNameUpper'] ?? '').toString();
                          final price = raw['price'] ?? 0;
                          final qtyVal = raw['quantity'] ?? raw['stock'] ?? raw['qty'] ?? 0;
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
                                      displayName.toUpperCase(),
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                    ),
                                    subtitle: Text(
                                      "Company: $company\nQty: $qtyVal | ৳$price",
                                      style: const TextStyle(color: Colors.white70),
                                    ),
                                    trailing: _canDelete
                                        ? IconButton(
                                            icon: const Icon(Icons.delete, color: Colors.white70),
                                            tooltip: 'Delete permanently',
                                            onPressed: () => _confirmAndDelete(docSnap.reference, displayName),
                                          )
                                        : null,
                                  ),
                                ),
                              ),
                            ),
                          ); */
                          return _glassCard(
                            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            padding: const EdgeInsets.all(12),
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
                                        displayName.toUpperCase(),
                                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        company.isEmpty ? 'No company' : company,
                                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                                      ),
                                      const SizedBox(height: 8),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: [
                                          _infoChip('Qty', qtyVal.toString()),
                                          _infoChip('Price', '\u09F3 $price', color: _accent),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                if (_canDelete)
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: Colors.white70),
                                    tooltip: 'Delete permanently',
                                    onPressed: () => _confirmAndDelete(docSnap.reference, displayName),
                                  ),
                              ],
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
    );
  }

  Widget field(TextEditingController? c, String label, IconData icon,
      {bool number = false,
      bool decimal = false,
      bool isSearch = false,
      Function(String)? onChange,
      VoidCallback? onClear}) {
    final hasText = c != null && c.text.trim().isNotEmpty;
    final bgOpacity = isSearch ? 0.12 : 0.06;
    final borderOpacity = isSearch ? 0.32 : 0.18;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(bgOpacity),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withOpacity(borderOpacity)),
          ),
          child: TextField(
            controller: c,
            keyboardType: number
                ? TextInputType.numberWithOptions(decimal: decimal)
                : TextInputType.text,
            cursorColor: _accent,
            style: const TextStyle(color: Colors.white),
            onChanged: onChange,
            decoration: InputDecoration(
              labelText: isSearch ? null : label,
              hintText: isSearch ? label : null,
              labelStyle: const TextStyle(color: Colors.white70),
              hintStyle: const TextStyle(color: Colors.white70),
              prefixIcon: isSearch
                  ? Container(
                      width: 58,
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(icon, color: _accent),
                          const SizedBox(width: 8),
                          Container(
                            width: 1,
                            height: 22,
                            color: Colors.white38,
                          ),
                        ],
                      ),
                    )
                  : Icon(icon, color: Colors.white),
              prefixIconConstraints: const BoxConstraints(minWidth: 56, minHeight: 48),
              suffixIcon: isSearch && hasText && onClear != null
                  ? IconButton(
                      icon: const Icon(Icons.close, color: Colors.white70),
                      onPressed: onClear,
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: isSearch ? 16 : 14),
            ),
          ),
        ),
      ),
    );
  }
}


