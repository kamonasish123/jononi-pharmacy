// CustomerDueListPage.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'CustomerDueDetailPage.dart';

class CustomerDueListPage extends StatefulWidget {
  const CustomerDueListPage({super.key});

  @override
  State<CustomerDueListPage> createState() => _CustomerDueListPageState();
}

class _CustomerDueListPageState extends State<CustomerDueListPage> {
  final TextEditingController searchController = TextEditingController();
  String searchText = "";

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
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
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

  bool get _canDelete {
    final nr = (currentUserRole).toLowerCase().replaceAll(RegExp(r'[\s\-]+'), '_').trim();
    return nr == 'admin' || nr == 'manager';
  }

  // ---------------- STREAM ----------------
  Stream<QuerySnapshot> getCustomers() {
    final col = FirebaseFirestore.instance.collection('customers');

    if (searchText.isEmpty) {
      return col.orderBy('nameLower').limit(50).snapshots();
    }

    final prefix = searchText.toLowerCase();
    return col
        .orderBy('nameLower')
        .startAt([prefix])
        .endAt([prefix + '\uf8ff'])
        .snapshots();
  }

  // ---------------- CREATE CUSTOMER ----------------
  Future<void> createCustomer() async {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final addressController = TextEditingController();

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Create New Customer"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: "Name *"),
            ),
            TextField(
              controller: phoneController,
              decoration: const InputDecoration(labelText: "Phone (optional)"),
            ),
            TextField(
              controller: addressController,
              decoration: const InputDecoration(labelText: "Address (optional)"),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Name is required")),
                );
                return;
              }

              final exists = await FirebaseFirestore.instance
                  .collection('customers')
                  .where('nameLower', isEqualTo: name.toLowerCase())
                  .limit(1)
                  .get();

              if (exists.docs.isNotEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Customer already exists")),
                );
                return;
              }

              await FirebaseFirestore.instance.collection('customers').add({
                'name': name,
                'nameLower': name.toLowerCase(),
                'phone': phoneController.text.trim().isEmpty ? null : phoneController.text.trim(),
                'address': addressController.text.trim().isEmpty ? null : addressController.text.trim(),
                'totalDue': 0,
                'createdAt': FieldValue.serverTimestamp(),
              });

              Navigator.pop(context);
            },
            child: const Text("Create"),
          ),
        ],
      ),
    );
  }

  // ---------------- DELETE CUSTOMER ----------------
  Future<void> _confirmAndDeleteCustomer(DocumentReference customerRef, String displayName) async {
    if (!_canDelete) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('You do not have permission to delete customers')));
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete customer?'),
        content: Text('Permanently delete "$displayName" from database? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );

    if (ok != true) return;

    try {
      // try to remove subcollection documents (customer_dues) if present
      final duedocs = await customerRef.collection('customer_dues').get();
      final batch = FirebaseFirestore.instance.batch();
      for (final d in duedocs.docs) {
        batch.delete(d.reference);
      }
      // delete the customer doc
      batch.delete(customerRef);
      await batch.commit();

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Customer deleted')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF01684D),
      appBar: AppBar(
        title: const Text("Customer Due List"),
        centerTitle: true,
        backgroundColor: const Color(0xFF01684D),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.yellow[700],
        onPressed: createCustomer,
        child: const Icon(Icons.person_add, color: Colors.black),
      ),
      body: Column(
        children: [
          // 🔍 SEARCH BAR
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: searchController,
              onChanged: (v) {
                setState(() {
                  searchText = v.trim().toLowerCase();
                });
              },
              decoration: InputDecoration(
                hintText: "Search customer by name",
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          // 📋 CUSTOMER LIST
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: getCustomers(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  );
                }

                final docs = snapshot.data!.docs;
                if (docs.isEmpty) {
                  return const Center(
                    child: Text(
                      "No customer found",
                      style: TextStyle(color: Colors.white70),
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (_, index) {
                    final d = docs[index].data() as Map<String, dynamic>;
                    final dueRaw = (d['totalDue'] ?? 0);
                    final double due = (dueRaw is num) ? dueRaw.toDouble() : double.tryParse(dueRaw.toString()) ?? 0.0;
                    final customerRef = snapshot.data!.docs[index].reference;
                    final displayName = d['name'] ?? 'Unknown';

                    return Card(
                      color: Colors.white.withOpacity(0.1),
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      child: ListTile(
                        title: Text(
                          "Name : ${d['name']}",
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Address : ${d['address'] ?? 'null'}",
                              style: const TextStyle(color: Colors.white70),
                            ),
                            Text(
                              "Phone : ${d['phone'] ?? 'null'}",
                              style: const TextStyle(color: Colors.white70),
                            ),
                          ],
                        ),
                        trailing: SizedBox(
                          width: _canDelete ? 110 : 80,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Expanded(
                                child: Text(
                                  "৳${due.toStringAsFixed(2)}",
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                    color: due > 0 ? Colors.red : Colors.green,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              if (_canDelete) ...[
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: const Icon(Icons.delete, color: Colors.white70),
                                  tooltip: 'Delete customer (admin/manager only)',
                                  onPressed: () => _confirmAndDeleteCustomer(customerRef, displayName),
                                ),
                              ],
                            ],
                          ),
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => CustomerDueDetailPage(
                                customerId: docs[index].id,
                                customerData: d,
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
