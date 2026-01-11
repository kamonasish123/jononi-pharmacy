import 'package:flutter/material.dart';
import 'CheckStockPage.dart';
import 'NewOrderPage.dart';

class CompanyDetailPage extends StatelessWidget {
  final String companyId;
  final String companyName;

  const CompanyDetailPage({
    super.key,
    required this.companyId,
    required this.companyName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF01684D),
      appBar: AppBar(
        title: Text(companyName),
        backgroundColor: Colors.green,
      ),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () {
                // Go to check stock page
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CheckStockPage(
                      companyId: companyId,
                      companyName: companyName,
                    ),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                minimumSize: Size(double.infinity, 50),
                backgroundColor: Colors.white,
              ),
              child: Text("Check Stock Medicine"),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                // Go to new order page
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => NewOrderPage(
                      companyId: companyId,
                      companyName: companyName,
                    ),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                minimumSize: Size(double.infinity, 50),
                backgroundColor: Colors.orangeAccent,
              ),
              child: Text("Order Medicine"),
            ),
          ],
        ),
      ),
    );
  }
}
