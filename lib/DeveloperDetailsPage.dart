import 'package:flutter/material.dart';

class DeveloperDetailsPage extends StatelessWidget {
  const DeveloperDetailsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,

      appBar: AppBar(
        backgroundColor: const Color(0xFF01684D),
        centerTitle: true,
        title: const Text(
          "Developer Details",
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),

      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [

            /// Header
            const Text(
              "This app developed by RoyGroup",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF01684D),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),

            /// Developer Cards
            developerCard("Kamonasish Roy", "+8801795985912"),
            const SizedBox(height: 12),
            developerCard("Shuvasish Roy", "+8801771815801"),

            const Spacer(),

            /// Footer
            const Text(
              "© All copyright reserved Jononi Pharmacy",
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  /// Developer Card Widget
  Widget developerCard(String name, String phone) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 6,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.person, color: Color(0xFF01684D), size: 36),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                phone,
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
