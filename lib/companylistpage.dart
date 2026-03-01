import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'CompanyDetailPage.dart';

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

class CompanyListPage extends StatefulWidget {
  const CompanyListPage({super.key});

  @override
  State<CompanyListPage> createState() => _CompanyListPageState();
}

class _CompanyListPageState extends State<CompanyListPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchText = "";
  String _currentUserRole = 'seller';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchText = _searchController.text.trim().toLowerCase();
      });
    });
    _loadMyRole();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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

  bool get _canDelete {
    final nr = _normalizeRole(_currentUserRole);
    return nr == 'admin';
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

  Future<void> _deleteCompany(String companyUpper) async {
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
          title: const Text('Delete company?'),
          content: Text('Delete all medicines for "$companyUpper"? This cannot be undone.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
          ],
        ),
      ),
    );

    if (ok != true) return;

    try {
      final col = FirebaseFirestore.instance.collection('medicines');
      final docsToDelete = <String, DocumentReference>{};

      final q1 = await col.where('companyNameUpper', isEqualTo: companyUpper).get();
      for (final d in q1.docs) {
        docsToDelete[d.id] = d.reference;
      }

      final q2 = await col.where('companyName', isEqualTo: companyUpper).get();
      for (final d in q2.docs) {
        docsToDelete[d.id] = d.reference;
      }

      final refs = docsToDelete.values.toList();
      if (refs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No medicines found for this company')));
        return;
      }

      const chunkSize = 400;
      for (var i = 0; i < refs.length; i += chunkSize) {
        final batch = FirebaseFirestore.instance.batch();
        final end = (i + chunkSize) > refs.length ? refs.length : (i + chunkSize);
        for (var j = i; j < end; j++) {
          batch.delete(refs[j]);
        }
        await batch.commit();
      }

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Company deleted')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .collection('medicines')
        .orderBy('companyName')
        .snapshots();

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text("Companies", style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
        backgroundColor: Colors.transparent,
        centerTitle: true,
        elevation: 0,
      ),
      body: Stack(
        children: [
          _buildBackdrop(),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12.0),
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
                          controller: _searchController,
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            hintText: "Search companies (name or part of name)",
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
                    stream: stream,
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator(color: Colors.white));
                      }

                      final docs = snapshot.data!.docs;
                      final companySet = <String>{};

                      for (var d in docs) {
                        final data = d.data() as Map<String, dynamic>;
                        final name = (data['companyName'] ?? "Unknown").toString();
                        final nameUpper = name.trim().isEmpty ? "UNKNOWN" : name.toUpperCase();
                        if (nameUpper.trim().isNotEmpty) companySet.add(nameUpper);
                      }

                      final companies = companySet.toList()..sort();

                      final filtered = _searchText.isEmpty
                          ? companies
                          : companies.where((c) => c.contains(_searchText.toUpperCase())).toList();

                      if (filtered.isEmpty) {
                        return const Center(
                          child: Text("No companies found", style: TextStyle(fontSize: 16, color: Colors.white70)),
                        );
                      }

                      return ListView.separated(
                        padding: const EdgeInsets.only(bottom: 120, top: 8),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 4),
                        itemBuilder: (_, i) {
                          final company = filtered[i];
                          final companyId = company.toLowerCase().replaceAll(" ", "_");

                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
                                    title: Text(company, style: const TextStyle(color: Colors.white)),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (_canDelete)
                                          IconButton(
                                            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                            tooltip: 'Delete company',
                                            onPressed: () => _deleteCompany(company),
                                          ),
                                        const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.white70),
                                      ],
                                    ),
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => CompanyDetailPage(
                                            companyId: companyId,
                                            companyName: company,
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


