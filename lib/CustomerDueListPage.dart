// CustomerDueListPage.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'CustomerDueDetailPage.dart';

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
      // ignore ƒ?" default role will be 'seller'
    }
  }

  bool get _canDelete {
    final nr = (currentUserRole).toLowerCase().replaceAll(RegExp(r'[\s\-]+'), '_').trim();
    return nr == 'admin' || nr == 'manager';
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
      inputDecorationTheme: const InputDecorationTheme(
        labelStyle: TextStyle(color: Colors.white70),
        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white30)),
        focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: _accent)),
      ),
      dividerColor: Colors.white24,
    );
  }

  String _initials(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    final first = parts.first.isNotEmpty ? parts.first[0].toUpperCase() : '';
    final last = parts.last.isNotEmpty ? parts.last[0].toUpperCase() : '';
    return (first + last).isEmpty ? '?' : (first + last);
  }

  Widget _infoRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 14, color: Colors.white54),
        const SizedBox(width: 6),
        Expanded(
          child: Text(text, style: const TextStyle(color: Colors.white70)),
        ),
      ],
    );
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
      builder: (_) => Theme(
        data: _dialogTheme(context),
        child: AlertDialog(
          backgroundColor: _bgEnd,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: Colors.white24),
          ),
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
      builder: (_) => Theme(
        data: _dialogTheme(context),
        child: AlertDialog(
          backgroundColor: _bgEnd,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: Colors.white24),
          ),
          title: const Text('Delete customer?'),
          content: Text('Permanently delete "$displayName" from database? This cannot be undone.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
          ],
        ),
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
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text("Customer Due List", style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: _accent,
        onPressed: createCustomer,
        child: const Icon(Icons.person_add, color: Colors.black),
      ),
      body: Stack(
        children: [
          _buildBackdrop(),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white.withOpacity(0.18)),
                        ),
                        child: TextField(
                          controller: searchController,
                          onChanged: (v) {
                            setState(() {
                              searchText = v.trim().toLowerCase();
                            });
                          },
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            hintText: "Search customer by name",
                            hintStyle: TextStyle(color: Colors.white70),
                            prefixIcon: Icon(Icons.search, color: Colors.white),
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
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
                        padding: const EdgeInsets.only(bottom: 120),
                        itemCount: docs.length,
                        itemBuilder: (_, index) {
                          final d = docs[index].data() as Map<String, dynamic>;
                          final dueRaw = (d['totalDue'] ?? 0);
                          final double due =
                              (dueRaw is num) ? dueRaw.toDouble() : double.tryParse(dueRaw.toString()) ?? 0.0;
                          final customerRef = snapshot.data!.docs[index].reference;
                          final displayName = (d['name'] ?? 'Unknown').toString();
                          final address = (d['address'] ?? 'Not set').toString();
                          final phone = (d['phone'] ?? 'Not set').toString();
                          final dueColor = due > 0 ? Colors.redAccent : Colors.greenAccent;

                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: BackdropFilter(
                                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.07),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: Colors.white.withOpacity(0.18)),
                                  ),
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    leading: Container(
                                      width: 42,
                                      height: 42,
                                      decoration: BoxDecoration(
                                        color: _accent.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      alignment: Alignment.center,
                                      child: Text(
                                        _initials(displayName),
                                        style: const TextStyle(
                                          color: _accent,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    title: Text(
                                      displayName,
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        _infoRow(Icons.location_on_outlined, address),
                                        const SizedBox(height: 4),
                                        _infoRow(Icons.call_outlined, phone),
                                      ],
                                    ),
                                    trailing: SizedBox(
                                      width: _canDelete ? 120 : 90,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Expanded(
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: dueColor.withOpacity(0.18),
                                                borderRadius: BorderRadius.circular(999),
                                                border: Border.all(color: dueColor.withOpacity(0.45)),
                                              ),
                                              child: Text(
                                                "৳${due.toStringAsFixed(2)}",
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  color: dueColor,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ),
                                          if (_canDelete) ...[
                                            const SizedBox(width: 8),
                                            InkWell(
                                              onTap: () => _confirmAndDeleteCustomer(customerRef, displayName),
                                              borderRadius: BorderRadius.circular(10),
                                              child: Container(
                                                width: 34,
                                                height: 34,
                                                decoration: BoxDecoration(
                                                  color: Colors.white.withOpacity(0.06),
                                                  borderRadius: BorderRadius.circular(10),
                                                  border: Border.all(color: Colors.white24),
                                                ),
                                                child: const Icon(Icons.delete, color: Colors.white70, size: 18),
                                              ),
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
    );
  }
}
