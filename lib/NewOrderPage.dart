// NewOrderPage.dart
import 'dart:ui';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'EditOrderPage.dart';

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

class NewOrderPage extends StatefulWidget {
  final String companyId;
  final String companyName;

  const NewOrderPage({Key? key, required this.companyId, required this.companyName}) : super(key: key);

  @override
  State<NewOrderPage> createState() => _NewOrderPageState();
}

class _NewOrderPageState extends State<NewOrderPage> {
  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  DateTime selectedDate = DateTime.now();
  double dailyTotal = 0.0;

  List<Map<String, dynamic>> items = [];
  TextEditingController paidController = TextEditingController(text: "0");

  String get dateString => DateFormat('yyyy-MM-dd').format(selectedDate);
  double get subTotal => items.fold(0.0, (sum, i) => sum + ((i['total'] ?? 0) as num).toDouble());
  double get paid => double.tryParse(paidController.text) ?? 0.0;
  double get due => subTotal - paid;

  Future<void> pickDate() async {
    DateTime? picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2023),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => selectedDate = picked);
  }

  Stream<QuerySnapshot> getOrdersForDate(String date) {
    return firestore
        .collection('orders')
        .doc(widget.companyId)
        .collection('bills')
        .doc(date)
        .collection('orders')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  void editItem(int index) {
    final qtyController = TextEditingController(text: items[index]['qty'].toString());
    final priceController = TextEditingController(text: items[index]['price'].toString());

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(items[index]['name']),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: qtyController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: "Quantity"),
            ),
            TextField(
              controller: priceController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: "Price"),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              final qty = int.tryParse(qtyController.text);
              final price = double.tryParse(priceController.text);
              if (qty == null || price == null) return;
              setState(() {
                items[index]['qty'] = qty;
                items[index]['price'] = price;
                items[index]['total'] = qty * price;
              });
              Navigator.pop(context);
            },
            child: const Text("Update"),
          ),
          TextButton(
            onPressed: () {
              setState(() => items.removeAt(index));
              Navigator.pop(context);
            },
            child: const Text("Delete", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> saveOrder() async {
    if (items.isEmpty) return;

    final data = {
      'items': items,
      'subTotal': subTotal,
      'paid': paid,
      'due': due,
      // finalAmount may be null for new orders; EditOrderPage will set it when used
      'finalAmount': null,
      'createdAt': FieldValue.serverTimestamp(),
    };

    await firestore
        .collection('orders')
        .doc(widget.companyId)
        .collection('bills')
        .doc(dateString)
        .collection('orders')
        .add(data);

    setState(() => items.clear());
    paidController.text = "0";

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Order saved successfully")),
    );
  }

  /// Share order as PDF - uses embedded Bengali-capable font from assets so \u09F3  renders correctly.
  /// Shows fields in the requested order:
  /// Total
  /// Final amount
  /// Paid
  /// Due
  /// Company: <name>
  /// Generated by Jononi Pharmacy, Shunashar.
  Future<void> shareOrder(Map<String, dynamic> orderData) async {
    try {
      // load font from assets (ByteData) and pass ByteData directly to pw.Font.ttf
      final ByteData fontData = await rootBundle.load('assets/fonts/NotoSansBengali-Regular.ttf');
      final pw.Font ttf = pw.Font.ttf(fontData);

      final pdf = pw.Document();
      final itemsList = (orderData['items'] as List?) ?? [];

      // compute a final amount to show:
      // prefer explicit 'finalAmount' when present and non-null,
      // otherwise prefer 'subTotal' if available,
      // otherwise sum items' totals as a last resort.
      double computeFinalAmount() {
        if (orderData.containsKey('finalAmount') && orderData['finalAmount'] != null) {
          final v = orderData['finalAmount'];
          if (v is num) return v.toDouble();
          return double.tryParse(v.toString()) ?? 0.0;
        }
        if (orderData.containsKey('subTotal') && orderData['subTotal'] != null) {
          final v = orderData['subTotal'];
          if (v is num) return v.toDouble();
          return double.tryParse(v.toString()) ?? 0.0;
        }
        // fallback: sum items
        double s = 0.0;
        for (final it in itemsList) {
          try {
            s += ((it['total'] ?? 0) as num).toDouble();
          } catch (_) {}
        }
        return s;
      }

      final double finalAmtToShow = computeFinalAmount();

      pdf.addPage(
        pw.Page(
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text("Order - $dateString",
                    style: pw.TextStyle(font: ttf, fontSize: 18, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 8),
                if (itemsList.isNotEmpty)
                  ...List.generate(itemsList.length, (i) {
                    final item = itemsList[i] as Map<String, dynamic>;
                    final name = item['name'] ?? '';
                    final qty = item['qty'] ?? '';
                    final price = item['price'] ?? '';
                    final total = item['total'] ?? '';
                    return pw.Text(
                      "$name $qty x \u09F3 $price = \u09F3 $total",
                      style: pw.TextStyle(font: ttf, fontSize: 12),
                    );
                  })
                else
                  pw.Text("No items", style: pw.TextStyle(font: ttf)),
                pw.Divider(),

                // ORDERED FIELDS: total, final, paid, due, company, generated by...
                pw.Text("Total = \u09F3 ${(orderData['subTotal'] ?? 0).toString()}", style: pw.TextStyle(font: ttf, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 4),
                pw.Text("Final amount = \u09F3 ${finalAmtToShow.toStringAsFixed(2)}", style: pw.TextStyle(font: ttf)),
                pw.SizedBox(height: 4),
                pw.Text("Paid = \u09F3 ${(orderData['paid'] ?? 0).toString()}", style: pw.TextStyle(font: ttf)),
                pw.SizedBox(height: 4),
                pw.Text("Due = \u09F3 ${(orderData['due'] ?? 0).toString()}", style: pw.TextStyle(font: ttf)),
                pw.SizedBox(height: 10),
                pw.Text("Company: ${widget.companyName}", style: pw.TextStyle(font: ttf, fontStyle: pw.FontStyle.italic)),
                pw.SizedBox(height: 8),
                pw.Text("Generated by Jononi Pharmacy, Shunashar.", style: pw.TextStyle(font: ttf, fontSize: 10)),
              ],
            );
          },
        ),
      );

      final bytes = await pdf.save();

      // Use Printing.sharePdf to open share dialog / save dialog on device.
      await Printing.sharePdf(bytes: bytes, filename: "order.pdf");
    } catch (e, st) {
      // Show error to user so they know why PDF wasn't created
      debugPrint('shareOrder error: $e\n$st');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to create PDF: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          "${widget.companyName} - $dateString",
          style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(Icons.calendar_today, color: Colors.white), onPressed: pickDate),
          IconButton(
            icon: const Icon(Icons.attach_money, color: Colors.white),
            onPressed: () {
              showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text("Daily Total"),
                  content: Text("Total Order: \u09F3 ${dailyTotal.toStringAsFixed(2)}"),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context), child: const Text("Close"))
                  ],
                ),
              );
            },
          )
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: _accent,
        child: const Icon(Icons.add, color: Colors.black),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => EditOrderPage(
                companyId: widget.companyId,
                companyName: widget.companyName,
                date: dateString,
              ),
            ),
          );
        },
      ),
      body: Stack(
        children: [
          _buildBackdrop(),
          SafeArea(
            child: StreamBuilder<QuerySnapshot>(
              stream: getOrdersForDate(dateString),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator(color: Colors.white));
                }

                final docs = snapshot.data!.docs;
                // dailyTotal uses finalAmount if present, otherwise subTotal
                dailyTotal = docs.fold(0.0, (sum, d) {
                  final data = d.data() as Map<String, dynamic>;
                  final finalAmt = (data['finalAmount'] ?? data['subTotal']) as num;
                  return sum + finalAmt.toDouble();
                });

                if (docs.isEmpty) {
                  return const Center(child: Text("No orders for this day.", style: TextStyle(color: Colors.white)));
                }

                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 120, top: 8),
                  itemCount: docs.length,
                  itemBuilder: (_, index) {
                    final doc = docs[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final time = data['createdAt'] != null
                        ? DateFormat('hh:mm a').format((data['createdAt'] as Timestamp).toDate())
                        : '';
                    final displayFinal = (data['finalAmount'] ?? data['subTotal']) as num;

                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                              child: Container(
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: Colors.white.withOpacity(0.18)),
                                ),
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(16),
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => EditOrderPage(
                                            companyId: widget.companyId,
                                            companyName: widget.companyName,
                                            date: dateString,
                                            orderId: doc.id,
                                            orderData: data,
                                          ),
                                        ),
                                      );
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text("Date: $dateString  Time: $time", style: const TextStyle(color: Colors.white)),
                                          const SizedBox(height: 6),
                                          ...List.generate(
                                            (data['items'] as List).length,
                                            (i) {
                                              final item = (data['items'] as List)[i];
                                              return Text(
                                                "${item['name']} ${item['qty']} x ${item['price']} = ${item['total']}",
                                                style: const TextStyle(color: Colors.white70),
                                              );
                                            },
                                          ),
                                          const SizedBox(height: 8),
                                          Container(height: 1, color: Colors.white12),
                                          const SizedBox(height: 8),
                                          Text("Total = \u09F3 ${data['subTotal']}", style: const TextStyle(color: Colors.white)),
                                          if ((data['finalAmount'] ?? data['subTotal']) != null)
                                            Text(
                                              "Final amount = \u09F3 ${displayFinal.toStringAsFixed(2)}",
                                              style: const TextStyle(color: Colors.yellowAccent, fontWeight: FontWeight.bold),
                                            ),
                                          Text("Paid = \u09F3 ${data['paid']}", style: const TextStyle(color: Colors.white70)),
                                          Text(
                                            "Due = \u09F3 ${data['due']}",
                                            style: TextStyle(color: (data['due'] ?? 0) > 0 ? Colors.redAccent : Colors.greenAccent),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: 12,
                            right: 12,
                            child: InkWell(
                              onTap: () => shareOrder(data),
                              borderRadius: BorderRadius.circular(18),
                              child: Container(
                                width: 36,
                                height: 36,
                                decoration: const BoxDecoration(
                                  color: _accent,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.share, color: Colors.black, size: 18),
                              ),
                            ),
                          ),
                        ],
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





