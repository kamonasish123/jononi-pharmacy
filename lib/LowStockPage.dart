import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class LowStockPage extends StatefulWidget {
  const LowStockPage({super.key});

  @override
  State<LowStockPage> createState() => _LowStockPageState();
}

class _LowStockPageState extends State<LowStockPage> {
  int selectedLimit = 10;

  final List<int> limits = [5, 10, 15, 20, 30, 50, 100];

  final Color bgColor = const Color(0xFF01684D);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text("Low Stock Medicines"),
        centerTitle: true,
        backgroundColor: bgColor,
        elevation: 0,
      ),
      body: Column(
        children: [
          // 🔘 FILTER BUTTONS
          SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: limits.map((limit) {
                final isSelected = selectedLimit == limit;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: ChoiceChip(
                    label: Text("≤ $limit"),
                    selected: isSelected,
                    selectedColor: Colors.yellow[700],
                    backgroundColor: Colors.white,
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.black : Colors.black87,
                      fontWeight: FontWeight.bold,
                    ),
                    onSelected: (_) {
                      setState(() {
                        selectedLimit = limit;
                      });
                    },
                  ),
                );
              }).toList(),
            ),
          ),

          const Divider(color: Colors.white54, height: 1),

          // 📦 MEDICINE LIST
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('medicines')
                  .where('quantity', isLessThanOrEqualTo: selectedLimit)
                  .orderBy('quantity')
                  .snapshots(),
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
                      "No low stock medicines 🎉",
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final d = docs[index].data() as Map<String, dynamic>;
                    final int qty = d['quantity'];

                    return Card(
                      color: Colors.white.withOpacity(0.1), // ✅ opacity white
                      margin: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        leading: const Icon(
                          Icons.warning_amber_rounded,
                          color: Colors.red, // ✅ red warning icon
                          size: 30,
                        ),
                        title: Text(
                          d['medicineName'].toString().toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: Text(
                          "Company: ${d['companyName']}\nStock: $qty",
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
    );
  }
}
