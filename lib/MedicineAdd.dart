// MedicineAddPage.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class MedicineAddPage extends StatefulWidget {
  @override
  _MedicineAddPageState createState() => _MedicineAddPageState();
}

class _MedicineAddPageState extends State<MedicineAddPage> {
  final TextEditingController companyController = TextEditingController();
  final TextEditingController nameController = TextEditingController();
  final TextEditingController qtyController = TextEditingController();
  final TextEditingController priceController = TextEditingController();

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
      backgroundColor: Color(0xFF01684D),
      appBar: AppBar(
        title: Text("Medicine Manager"),
        backgroundColor: Color(0xFF01684D),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            // INPUT AREA (only show add/update fields when NOT searching)
            if (!isSearching)
              Expanded(
                flex: 0,
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    children: [
                      field(companyController, "Company Name (optional)", Icons.business),
                      SizedBox(height: 10),
                      field(nameController, "Medicine Name", Icons.medical_services, onChange: (v) {
                        checkMedicineExists(
                          v,
                          companyController.text.isEmpty ? "UNKNOWN" : companyController.text,
                        );
                      }),
                      if (existingMedicine != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            "Existing → Qty: ${(existingMedicine!['quantity'] ?? existingMedicine!['stock'] ?? '')} | ৳${(existingMedicine!['price'] ?? '')}",
                            style: TextStyle(color: Colors.yellowAccent),
                          ),
                        ),
                      SizedBox(height: 10),
                      field(qtyController, "Quantity", Icons.confirmation_number, number: true),
                      SizedBox(height: 10),
                      field(priceController, "Price", Icons.attach_money, number: true),
                      SizedBox(height: 15),
                      ElevatedButton(
                        onPressed: isLoading ? null : saveMedicine,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.yellow[700],
                          foregroundColor: Colors.black,
                          minimumSize: Size(double.infinity, 48),
                        ),
                        child: isLoading ? CircularProgressIndicator() : Text(existingMedicine != null ? "Update" : "Add"),
                      ),
                      SizedBox(height: 15),
                    ],
                  ),
                ),
              ),

            // SEARCH FIELDS (always visible)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
              child: Column(
                children: [
                  field(null, "Search Medicine", Icons.search, onChange: (v) {
                    setState(() {
                      searchText = v.trim();
                      companySearchText = "";
                    });
                  }),
                  SizedBox(height: 10),
                  field(null, "Search Company", Icons.business, onChange: (v) {
                    setState(() {
                      companySearchText = v.trim();
                      searchText = "";
                    });
                  }),
                ],
              ),
            ),

            // LIST
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: getMedicines(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return Center(child: CircularProgressIndicator(color: Colors.white));
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
                    return Center(child: Text("No medicines found", style: TextStyle(color: Colors.white70)));
                  }

                  return ListView.builder(
                    itemCount: visibleDocs.length,
                    itemBuilder: (context, index) {
                      final docSnap = visibleDocs[index];
                      final raw = docSnap.data() as Map<String, dynamic>;
                      // prefer 'medicineName' (human-friendly) and fallback to 'medicineNameLower'
                      final displayName = (raw['medicineName'] ?? raw['medicineNameLower'] ?? '').toString();
                      final company = (raw['companyName'] ?? raw['companyNameUpper'] ?? '').toString();
                      final price = raw['price'] ?? 0;
                      final qtyVal = raw['quantity'] ?? raw['stock'] ?? raw['qty'] ?? 0;
                      return Card(
                        color: Color(0xFFB83257),
                        margin: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        child: ListTile(
                          title: Text(
                            displayName.toString().toUpperCase(),
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            "Company: $company\nQty: $qtyVal | ৳$price",
                            style: TextStyle(color: Colors.white70),
                          ),
                          trailing: _canDelete
                              ? IconButton(
                            icon: const Icon(Icons.delete, color: Colors.white70),
                            tooltip: 'Delete permanently',
                            onPressed: () => _confirmAndDelete(docSnap.reference, displayName),
                          )
                              : null,
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
    );
  }

  Widget field(TextEditingController? c, String label, IconData icon, {bool number = false, Function(String)? onChange}) {
    return TextField(
      controller: c,
      keyboardType: number ? TextInputType.number : TextInputType.text,
      style: TextStyle(color: Colors.white),
      onChanged: onChange,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.white70),
        prefixIcon: Icon(icon, color: Colors.white),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: Colors.white70),
          borderRadius: BorderRadius.circular(8),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: Colors.white),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}
