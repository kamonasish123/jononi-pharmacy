import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'CompanyDetailPage.dart';

class CompanyListPage extends StatefulWidget {
  const CompanyListPage({super.key});

  @override
  State<CompanyListPage> createState() => _CompanyListPageState();
}

class _CompanyListPageState extends State<CompanyListPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchText = "";

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchText = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .collection('medicines')
        .orderBy('companyName')
        .snapshots();

    return Scaffold(
      backgroundColor: const Color(0xFF01684D), // page background as requested
      appBar: AppBar(
        title: const Text("Companies"),
        backgroundColor: const Color(0xFF01684D), // match background for consistency
        centerTitle: true,
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Search bar
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: "Search companies (name or part of name)",
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),

            // List from Firestore
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
                    // store uppercase to dedupe case-insensitively and display uppercase everywhere
                    final nameUpper = name.trim().isEmpty ? "UNKNOWN" : name.toUpperCase();
                    if (nameUpper.trim().isNotEmpty) companySet.add(nameUpper);
                  }

                  // Convert to list and sort (all entries are uppercase)
                  final companies = companySet.toList()..sort();

                  // Apply search filter (supports partial match anywhere)
                  final filtered = _searchText.isEmpty
                      ? companies
                      : companies.where((c) => c.contains(_searchText.toUpperCase())).toList();

                  if (filtered.isEmpty) {
                    return const Center(
                        child: Text("No companies found", style: TextStyle(fontSize: 16, color: Colors.white70)));
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 4),
                    itemBuilder: (_, i) {
                      final company = filtered[i];
                      // Keep companyId stable and lowercase for routing/lookup
                      final companyId = company.toLowerCase().replaceAll(" ", "_");

                      return Card(
                        color: Colors.white.withOpacity(0.06),
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        child: ListTile(
                          // show uppercase company everywhere
                          title: Text(company, style: const TextStyle(color: Colors.white)),
                          trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.white70),
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
}
