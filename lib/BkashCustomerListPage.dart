// BkashCustomerListPage.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'BkashCustomerAccountPage.dart';
import 'BkashMobileAccountPage.dart';

class BkashCustomerListPage extends StatefulWidget {
  const BkashCustomerListPage({super.key});

  @override
  State<BkashCustomerListPage> createState() => _BkashCustomerListPageState();
}

class _BkashCustomerListPageState extends State<BkashCustomerListPage> {
  final TextEditingController _searchController = TextEditingController();
  String searchText = "";
  String _currentUserRole = 'seller';
  bool _isDeletingMobile = false;
  static const Color _bgStart = Color(0xFF041A14);
  static const Color _bgEnd = Color(0xFF0E5A42);
  static const Color _accent = Color(0xFFFFD166);

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

  String _normalizeMobile(String input) {
    final digits = input.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('880') && digits.length == 13) {
      return '0${digits.substring(3)}';
    }
    return digits;
  }

  Stream<QuerySnapshot> _mobileAccountsStream() {
    final col = FirebaseFirestore.instance.collection('bkash_mobile_accounts');
    final q = searchText.trim();
    if (q.isEmpty) {
      return col.orderBy('mobileDigits').snapshots();
    }
    final digits = q.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) {
      return col.orderBy('mobileDigits').snapshots();
    }
    return col.orderBy('mobileDigits').startAt([digits]).endAt([digits + '\uf8ff']).snapshots();
  }

  Future<void> _createAccountDialog() async {
    final nameC = TextEditingController();
    final addressC = TextEditingController();

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
      ),
    );
  }

  Future<void> _createMobileAccountDialog() async {
    final mobileC = TextEditingController();
    bool isCreating = false;
    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setState) => Theme(
          data: _dialogTheme(context),
          child: AlertDialog(
            backgroundColor: _bgEnd,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: Colors.white24),
            ),
            title: const Text('Add Bkash Mobile Account'),
            content: TextField(
              controller: mobileC,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Mobile number *'),
            ),
            actions: [
              TextButton(
                onPressed: isCreating ? null : () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: isCreating
                    ? null
                    : () async {
                        if (isCreating) return;
                        setState(() => isCreating = true);
                        try {
                          final raw = mobileC.text.trim();
                          final digits = _normalizeMobile(raw);
                          if (digits.isEmpty || digits.length < 11) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Mobile number must be at least 11 digits')));
                            return;
                          }
                          final col = FirebaseFirestore.instance.collection('bkash_mobile_accounts');
                          final exists = await col.where('mobileDigits', isEqualTo: digits).limit(1).get();
                          if (exists.docs.isNotEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('This mobile already exists')));
                            return;
                          }
                          await col.add({
                            'mobile': raw,
                            'mobileDigits': digits,
                            'balance': 0.0,
                            'createdAt': FieldValue.serverTimestamp(),
                          });
                          if (!context.mounted) return;
                          Navigator.pop(context);
                        } catch (e) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to create: $e')));
                        } finally {
                          if (!context.mounted) return;
                          setState(() => isCreating = false);
                        }
                      },
                child: Text(isCreating ? 'Creating...' : 'Create'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _deleteMobileAccount(String id, String mobile) async {
    if (_isDeletingMobile) return;
    bool isConfirming = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setState) => Theme(
          data: _dialogTheme(context),
          child: AlertDialog(
            backgroundColor: _bgEnd,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(color: Colors.white.withOpacity(0.12)),
            ),
            title: const Text('Delete mobile account?'),
            content: Text('Delete "$mobile"? This cannot be undone.'),
            actions: [
              TextButton(
                onPressed: isConfirming ? null : () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: isConfirming
                    ? null
                    : () {
                        if (isConfirming) return;
                        setState(() => isConfirming = true);
                        Navigator.pop(context, true);
                      },
                child: Text(isConfirming ? 'Deleting...' : 'Delete'),
              ),
            ],
          ),
        ),
      ),
    );
    if (ok != true) return;
    setState(() => _isDeletingMobile = true);
    try {
      final mobRef = FirebaseFirestore.instance.collection('bkash_mobile_accounts').doc(id);
      final txCol = mobRef.collection('transactions');
      final txSnap = await txCol.get();
      const chunkSize = 400;
      final refs = txSnap.docs.map((d) => d.reference).toList();
      for (var i = 0; i < refs.length; i += chunkSize) {
        final batch = FirebaseFirestore.instance.batch();
        final end = (i + chunkSize) > refs.length ? refs.length : (i + chunkSize);
        for (var j = i; j < end; j++) {
          batch.delete(refs[j]);
        }
        await batch.commit();
      }
      await mobRef.delete();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Mobile account deleted')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    } finally {
      if (!mounted) return;
      setState(() => _isDeletingMobile = false);
    }
  }

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
          _currentUserRole = (data?['role'] ?? 'seller').toString();
        });
      }
    } catch (_) {
      // keep default role
    }
  }

  String _normalizeRole(String? role) {
    if (role == null) return '';
    return role.toLowerCase().replaceAll(RegExp(r'[\s\-]+'), '_').trim();
  }

  bool get _isAdmin {
    final nr = _normalizeRole(_currentUserRole);
    return nr == 'admin';
  }

  Future<void> _deleteCustomer(String id, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => Theme(
        data: _dialogTheme(context),
        child: AlertDialog(
          backgroundColor: _bgEnd,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: Colors.white.withOpacity(0.12)),
          ),
          title: const Text('Delete customer?'),
          content: Text('Delete "$name" and all its transactions? This cannot be undone.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
          ],
        ),
      ),
    );

    if (ok != true) return;

    try {
      final custRef = FirebaseFirestore.instance.collection('bkash_customers').doc(id);
      final txCol = custRef.collection('transactions');
      final txSnap = await txCol.get();
      const chunkSize = 400;
      final refs = txSnap.docs.map((d) => d.reference).toList();
      for (var i = 0; i < refs.length; i += chunkSize) {
        final batch = FirebaseFirestore.instance.batch();
        final end = (i + chunkSize) > refs.length ? refs.length : (i + chunkSize);
        for (var j = i; j < end; j++) {
          batch.delete(refs[j]);
        }
        await batch.commit();
      }
      await custRef.delete();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Customer deleted')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          'Bkash Customers',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white),
        ),
        elevation: 0,
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Create account',
            onPressed: _createAccountDialog,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: _accent,
        child: const Icon(Icons.add, color: Colors.black),
        onPressed: _createAccountDialog,
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
                                controller: _searchController,
                                style: const TextStyle(color: Colors.white),
                                decoration: const InputDecoration(
                                  hintText: 'Search name or mobile',
                                  hintStyle: TextStyle(color: Colors.white54),
                                  border: InputBorder.none,
                                ),
                                onChanged: (v) => setState(() => searchText = v),
                              ),
                            ),
                            if (_searchController.text.isNotEmpty)
                              IconButton(
                                icon: const Icon(Icons.clear, color: Colors.white70),
                                onPressed: () => setState(() {
                                  _searchController.clear();
                                  searchText = '';
                                }),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.only(bottom: 120),
                      children: [
                        const Text(
                          'Accounts',
                          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        StreamBuilder<QuerySnapshot>(
                          stream: _customersStream(),
                          builder: (context, snap) {
                            if (snap.connectionState == ConnectionState.waiting) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 12),
                                child: Center(child: CircularProgressIndicator(color: Colors.white)),
                              );
                            }
                            final docs = snap.data?.docs ?? [];
                            if (docs.isEmpty) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 8),
                                child: Text('No accounts found', style: TextStyle(color: Colors.white70)),
                              );
                            }

                            return ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: docs.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 6),
                              itemBuilder: (_, i) {
                                final doc = docs[i];
                                final d = doc.data() as Map<String, dynamic>;
                                final name = (d['name'] ?? '').toString();
                                final address = d['address'] as String?;
                                final balance = (d['balance'] ?? 0);
                                final bal = (balance is num) ? (balance.toDouble()) : double.tryParse(balance.toString()) ?? 0.0;

                                final addr = (address == null || address.trim().isEmpty) ? 'No address' : address.trim();
                                final balColor = bal >= 0 ? Colors.greenAccent : Colors.redAccent;
                                return Container(
                                  margin: const EdgeInsets.symmetric(vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.08),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: Colors.white.withOpacity(0.16)),
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
                                        _initials(name),
                                        style: const TextStyle(color: _accent, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    title: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                                    subtitle: Text(addr, style: const TextStyle(color: Colors.white70)),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: balColor.withOpacity(0.18),
                                            borderRadius: BorderRadius.circular(999),
                                            border: Border.all(color: balColor.withOpacity(0.45)),
                                          ),
                                          child: Text(
                                            "\u09F3${bal.toStringAsFixed(2)}",
                                            style: TextStyle(color: balColor, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                        if (_isAdmin)
                                          IconButton(
                                            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                            tooltip: 'Delete customer',
                                            onPressed: () => _deleteCustomer(doc.id, name),
                                          ),
                                      ],
                                    ),
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
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Bkash Mobile List',
                                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add, color: _accent),
                              tooltip: 'Add mobile account',
                              onPressed: _createMobileAccountDialog,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        StreamBuilder<QuerySnapshot>(
                          stream: _mobileAccountsStream(),
                          builder: (context, snap) {
                            if (snap.connectionState == ConnectionState.waiting) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 8),
                                child: Center(child: CircularProgressIndicator(color: Colors.white)),
                              );
                            }
                            final docs = snap.data?.docs ?? [];
                            if (docs.isEmpty) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 6),
                                child: Text('No mobile accounts found', style: TextStyle(color: Colors.white70)),
                              );
                            }
                            return ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: docs.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 6),
                              itemBuilder: (_, i) {
                                final doc = docs[i];
                                final d = doc.data() as Map<String, dynamic>;
                                final mobile = (d['mobile'] ?? d['mobileDigits'] ?? '').toString();
                                final balance = (d['balance'] ?? 0);
                                final bal = (balance is num) ? (balance.toDouble()) : double.tryParse(balance.toString()) ?? 0.0;
                                final balColor = bal >= 0 ? Colors.greenAccent : Colors.redAccent;
                                return Container(
                                  margin: const EdgeInsets.symmetric(vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.08),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: Colors.white.withOpacity(0.16)),
                                  ),
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    leading: Container(
                                      width: 42,
                                      height: 42,
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.08),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      alignment: Alignment.center,
                                      child: const Icon(Icons.phone_android, color: Colors.white70),
                                    ),
                                    title: Text(mobile, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                                    subtitle: const Text('Bkash Mobile Account', style: TextStyle(color: Colors.white70)),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: balColor.withOpacity(0.18),
                                            borderRadius: BorderRadius.circular(999),
                                            border: Border.all(color: balColor.withOpacity(0.45)),
                                          ),
                                          child: Text(
                                            "\u09F3${bal.toStringAsFixed(2)}",
                                            style: TextStyle(color: balColor, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                        if (_isAdmin)
                                          IconButton(
                                            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                            tooltip: 'Delete mobile account',
                                            onPressed: () => _deleteMobileAccount(doc.id, mobile),
                                          ),
                                      ],
                                    ),
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => BkashMobileAccountPage(
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
                      ],
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



