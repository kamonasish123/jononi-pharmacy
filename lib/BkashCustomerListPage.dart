// BkashCustomerListPage.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'BkashCustomerAccountPage.dart';

class BkashCustomerListPage extends StatefulWidget {
  const BkashCustomerListPage({super.key});

  @override
  State<BkashCustomerListPage> createState() => _BkashCustomerListPageState();
}

class _BkashCustomerListPageState extends State<BkashCustomerListPage> {
  final TextEditingController _searchController = TextEditingController();
  String searchText = "";

  Stream<QuerySnapshot> _customersStream() {
    final col = FirebaseFirestore.instance.collection('bkash_customers');
    if (searchText.trim().isEmpty) {
      return col.orderBy('nameLower').snapshots();
    }
    final prefix = searchText.trim().toLowerCase();
    return col
        .orderBy('nameLower')
        .startAt([prefix])
        .endAt([prefix + '\uf8ff'])
        .snapshots();
  }

  Future<void> _createAccountDialog() async {
    final nameC = TextEditingController();
    final addressC = TextEditingController();

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Create Bkash Customer Account'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameC, decoration: const InputDecoration(labelText: 'Name *')),
            TextField(controller: addressC, decoration: const InputDecoration(labelText: 'Address (optional)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final name = nameC.text.trim();
              final addr = addressC.text.trim();
              if (name.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Name is required')));
                return;
              }

              final col = FirebaseFirestore.instance.collection('bkash_customers');
              final exists = await col.where('nameLower', isEqualTo: name.toLowerCase()).limit(1).get();
              if (exists.docs.isNotEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Account with this name already exists')));
                return;
              }

              await col.add({
                'name': name,
                'nameLower': name.toLowerCase(),
                'address': addr.isEmpty ? null : addr,
                'balance': 0.0,
                'createdAt': FieldValue.serverTimestamp(),
              });

              Navigator.pop(context);
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF01684D),
      appBar: AppBar(
        centerTitle: true,
        backgroundColor: const Color(0xFF01684D),
        title: TextField(
          controller: _searchController,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Search by name',
            hintStyle: TextStyle(color: Colors.white70),
            border: InputBorder.none,
            prefixIcon: Icon(Icons.search, color: Colors.white70),
          ),
          onChanged: (v) => setState(() => searchText = v),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: Colors.white),
            tooltip: 'Create account',
            onPressed: _createAccountDialog,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.yellow[700],
        child: const Icon(Icons.add, color: Colors.black),
        onPressed: _createAccountDialog,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _customersStream(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(child: Text('No accounts found', style: TextStyle(color: Colors.white70)));
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (_, i) {
              final doc = docs[i];
              final d = doc.data() as Map<String, dynamic>;
              final name = (d['name'] ?? '').toString();
              final address = d['address'] as String?;
              final balance = (d['balance'] ?? 0);
              final bal = (balance is num) ? (balance.toDouble()) : double.tryParse(balance.toString()) ?? 0.0;

              return Card(
                color: Colors.white.withOpacity(0.08),
                margin: const EdgeInsets.symmetric(horizontal: 12),
                child: ListTile(
                  title: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  subtitle: Text(address ?? 'No address', style: const TextStyle(color: Colors.white70)),
                  trailing: Text('৳${bal.toStringAsFixed(2)}', style: TextStyle(color: bal >= 0 ? Colors.greenAccent : Colors.redAccent, fontWeight: FontWeight.bold)),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => BkashCustomerAccountPage(
                          accountId: doc.id,
                          accountData: d,
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
    );
  }
}
