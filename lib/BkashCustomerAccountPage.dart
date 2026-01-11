// BkashCustomerAccountPage.dart
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart' as pdf;
import 'package:printing/printing.dart';
import 'package:flutter/services.dart' show rootBundle;

class BkashCustomerAccountPage extends StatefulWidget {
  final String accountId;
  final Map<String, dynamic> accountData;

  const BkashCustomerAccountPage({
    super.key,
    required this.accountId,
    required this.accountData,
  });

  @override
  State<BkashCustomerAccountPage> createState() => _BkashCustomerAccountPageState();
}

class _BkashCustomerAccountPageState extends State<BkashCustomerAccountPage> {
  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  DateTime selectedDate = DateTime.now();

  String get dateString => DateFormat('yyyy-MM-dd').format(selectedDate);

  Future<void> pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => selectedDate = picked);
  }

  Stream<QuerySnapshot> _transactionsForDayStream(String accountId) {
    final start = DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
    final end = start.add(const Duration(days: 1));
    return firestore
        .collection('bkash_customers')
        .doc(accountId)
        .collection('transactions')
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('createdAt', isLessThan: Timestamp.fromDate(end))
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  // ---------------- open dialog for send/receive (also used for edit)
  Future<void> _openTransactionDialog({
    required String accountId,
    required String type, // 'send' or 'receive'
    required String mode, // 'bkash' or 'account'
    String? docId,
    Map<String, dynamic>? initial,
  }) async {
    // controllers (prefill from initial when editing)
    final phoneController = TextEditingController(text: initial?['phone']?.toString() ?? '');
    final pinController = TextEditingController(text: initial?['pin']?.toString() ?? '');
    final amountController = TextEditingController(text: initial?['amount']?.toString() ?? '');
    final percentController = TextEditingController(text: initial?['percent']?.toString() ?? '2');
    final finalAmountController = TextEditingController(text: initial?['finalAmount']?.toString() ?? '');
    final referenceController = TextEditingController(text: initial?['reference']?.toString() ?? '');
    final noteController = TextEditingController(text: initial?['note']?.toString() ?? '');
    final nameController = TextEditingController(text: initial?['name']?.toString() ?? (type == 'receive' ? 'Receive' : ''));

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (context, setState) {
          void recomputeFinalFromAmount() {
            final a = double.tryParse(amountController.text) ?? 0.0;
            final p = double.tryParse(percentController.text) ?? 0.0;
            final computed = a + a * (p / 100.0);
            finalAmountController.text = computed.toStringAsFixed(2);
          }

          final isBkash = mode == 'bkash';
          final isSend = type == 'send';
          final isReceive = type == 'receive';

          // initialize computation
          if (isBkash && isSend && finalAmountController.text.isEmpty && amountController.text.isNotEmpty) {
            recomputeFinalFromAmount();
          }

          return AlertDialog(
            title: Text('${isBkash ? 'Bkash' : 'Account'} — ${isSend ? 'Send' : 'Receive'}'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isBkash) ...[
                    TextField(
                      controller: phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(labelText: 'Phone number'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: pinController,
                      keyboardType: TextInputType.number,
                      obscureText: false,
                      decoration: const InputDecoration(labelText: 'PIN (visible)'),
                    ),
                    const SizedBox(height: 12),
                  ] else ...[
                    TextField(
                      controller: nameController,
                      decoration: InputDecoration(labelText: 'Name', hintText: type == 'receive' ? 'Receive' : ''),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // For send flows we have amount + percent + final (bkash) or final only (transaction send)
                  if (isSend) ...[
                    if (isBkash) ...[
                      TextField(
                        controller: amountController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Amount (base)'),
                        onChanged: (_) => setState(() => recomputeFinalFromAmount()),
                      ),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: percentController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(labelText: 'Percentage (%)'),
                            onChanged: (_) => recomputeFinalFromAmount(),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: finalAmountController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(labelText: 'Final amount (editable)'),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 8),
                    ] else ...[
                      // transaction send: only final amount required (no extra amount/percent)
                      TextField(
                        controller: finalAmountController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Final amount (required)'),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ] else ...[
                    // receive: only final amount
                    TextField(
                      controller: finalAmountController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Final amount (required)'),
                    ),
                    const SizedBox(height: 8),
                  ],

                  TextField(
                    controller: referenceController,
                    decoration: const InputDecoration(labelText: 'Reference (optional)'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: noteController,
                    decoration: const InputDecoration(labelText: 'Note (optional)'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () async {
                  // parse values
                  final finalAmount = double.tryParse(finalAmountController.text.trim()) ??
                      (isSend ? (double.tryParse(amountController.text.trim()) ?? 0.0) : 0.0);
                  final amount = double.tryParse(amountController.text.trim()) ?? 0.0;
                  final percent = double.tryParse(percentController.text.trim()) ?? (isBkash && isSend ? 2.0 : 0.0);

                  if (finalAmount <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid final amount')));
                    return;
                  }

                  if (isBkash && isSend && pinController.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PIN is required for Bkash send')));
                    return;
                  }

                  final accRef = firestore.collection('bkash_customers').doc(accountId);
                  final txCol = accRef.collection('transactions');

                  if (docId != null) {
                    // editing existing transaction: need to compute balance delta
                    final existingDoc = await txCol.doc(docId).get();
                    if (!existingDoc.exists) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Record not found')));
                      Navigator.pop(ctx);
                      return;
                    }

                    final old = existingDoc.data() as Map<String, dynamic>;
                    final oldFinal = ((old['finalAmount'] ?? old['amount'] ?? 0) as num).toDouble();
                    final oldType = (old['type'] ?? '').toString();

                    // compute new effect on balance: receive -> +final, send -> -final
                    final newEffect = (type == 'receive') ? finalAmount : -finalAmount;
                    final oldEffect = (oldType == 'receive') ? oldFinal : -oldFinal;
                    final delta = newEffect - oldEffect; // amount to apply to account.balance

                    final batch = firestore.batch();
                    batch.update(txCol.doc(docId), {
                      'mode': mode,
                      'type': type,
                      'phone': isBkash ? phoneController.text.trim() : null,
                      'pin': isBkash ? pinController.text.trim() : null,
                      'amount': isSend ? (amount > 0 ? amount : null) : null,
                      'percent': (isBkash && isSend) ? percent : null,
                      'finalAmount': finalAmount,
                      'reference': referenceController.text.trim().isEmpty ? null : referenceController.text.trim(),
                      'note': noteController.text.trim().isEmpty ? null : noteController.text.trim(),
                      'name': !isBkash ? nameController.text.trim() : null,
                      'updatedAt': FieldValue.serverTimestamp(),
                    });

                    batch.update(accRef, {'balance': FieldValue.increment(delta)});

                    await batch.commit();
                    Navigator.pop(ctx);
                    return;
                  }

                  // create new transaction
                  final batch = firestore.batch();
                  final newDoc = txCol.doc();

                  batch.set(newDoc, {
                    'mode': mode,
                    'type': type,
                    'phone': isBkash ? phoneController.text.trim() : null,
                    'pin': isBkash ? pinController.text.trim() : null,
                    'amount': isSend ? (amount > 0 ? amount : null) : null,
                    'percent': (isBkash && isSend) ? percent : null,
                    'finalAmount': finalAmount,
                    'reference': referenceController.text.trim().isEmpty ? null : referenceController.text.trim(),
                    'note': noteController.text.trim().isEmpty ? null : noteController.text.trim(),
                    'name': !isBkash ? nameController.text.trim() : null,
                    'createdAt': FieldValue.serverTimestamp(),
                  });

                  // update account balance
                  final balanceDelta = (type == 'receive') ? finalAmount : -finalAmount;
                  batch.update(accRef, {'balance': FieldValue.increment(balanceDelta)});

                  await batch.commit();
                  Navigator.pop(ctx);
                },
                child: Text(docId == null ? (isSend ? 'Send' : 'Receive') : 'Update'),
              ),
            ],
          );
        });
      },
    );
  }

  Future<void> _deleteTransactionAndReverse(String accountId, DocumentSnapshot txDoc) async {
    final m = txDoc.data() as Map<String, dynamic>? ?? {};
    final finalAmount = ((m['finalAmount'] ?? (m['amount'] ?? 0)) as num).toDouble();
    final type = (m['type'] ?? '').toString();

    final batch = firestore.batch();
    final accRef = firestore.collection('bkash_customers').doc(accountId);

    // reverse: if original was receive (added), now subtract; if send (subtracted), now add back
    final reverse = (type == 'receive') ? -finalAmount : finalAmount;

    batch.update(accRef, {'balance': FieldValue.increment(reverse)});
    batch.delete(txDoc.reference);

    await batch.commit();
  }

  // ---------------- PDF generation - include phone/pin/final amount etc.
  Future<void> _generateDailyPdfAndShare(String accountId, Map<String, dynamic> accData) async {
    final start = DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
    final end = start.add(const Duration(days: 1));
    final qsnap = await firestore
        .collection('bkash_customers')
        .doc(accountId)
        .collection('transactions')
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('createdAt', isLessThan: Timestamp.fromDate(end))
        .orderBy('createdAt', descending: true)
        .get();

    final docs = qsnap.docs;
    final txns = docs.map((d) {
      final m = d.data() as Map<String, dynamic>;
      final ts = m['createdAt'] as Timestamp?;
      return <String, dynamic>{
        'type': (m['type'] ?? 'receive').toString(),
        'mode': (m['mode'] ?? '').toString(),
        'phone': (m['phone'] ?? '')?.toString() ?? '',
        'pin': (m['pin'] ?? '')?.toString() ?? '',
        'amount': ((m['amount'] ?? 0) as num).toDouble(),
        'percent': ((m['percent'] ?? 0) as num).toDouble(),
        'finalAmount': ((m['finalAmount'] ?? 0) as num).toDouble(),
        'reference': (m['reference'] ?? '')?.toString() ?? '',
        'note': (m['note'] ?? '')?.toString() ?? '',
        'name': (m['name'] ?? '')?.toString() ?? '',
        'createdAt': ts,
      };
    }).toList();

    double totalReceive = 0.0;
    double totalSend = 0.0;
    for (final t in txns) {
      final f = (t['finalAmount'] as double);
      if (t['type'] == 'receive') totalReceive += f;
      if (t['type'] == 'send') totalSend += f;
    }

    final accountName = (accData['name'] ?? 'Account').toString();

    // compute account balance and due according to rule
    final rawBalance = accData['balance'] ?? 0;
    final accountBalance = (rawBalance is num) ? rawBalance.toDouble() : double.tryParse(rawBalance.toString()) ?? 0.0;
    final double currentBalanceToShow = accountBalance >= 0.0 ? accountBalance : 0.0;
    final double dueToShow = accountBalance < 0.0 ? accountBalance.abs() : 0.0;

    final pdfDoc = pw.Document();

    // load font so currency sign and Bengali characters show correctly
    try {
      final ByteData fontData = await rootBundle.load('assets/fonts/NotoSansBengali-Regular.ttf');
      final pw.Font ttf = pw.Font.ttf(fontData);

      pdfDoc.addPage(
        pw.MultiPage(
          pageFormat: pdf.PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(18),
          build: (pw.Context ctx) {
            return <pw.Widget>[
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                    pw.Text(accountName, style: pw.TextStyle(font: ttf, fontSize: 18, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 4),
                    pw.Text('Date: $dateString', style: pw.TextStyle(font: ttf, fontSize: 12)),
                  ]),
                  pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                    pw.Text('Daily Summary', style: pw.TextStyle(font: ttf, fontSize: 14, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 4),
                    pw.Text('Receive: ৳${totalReceive.toStringAsFixed(2)}', style: pw.TextStyle(font: ttf, fontSize: 12)),
                    pw.Text('Send: ৳${totalSend.toStringAsFixed(2)}', style: pw.TextStyle(font: ttf, fontSize: 12)),
                  ]),
                ],
              ),
              pw.SizedBox(height: 12),
              pw.Divider(),
              pw.SizedBox(height: 8),
              pw.Row(children: [
                pw.Expanded(flex: 2, child: pw.Text('Time', style: pw.TextStyle(font: ttf, fontWeight: pw.FontWeight.bold))),
                pw.Expanded(flex: 2, child: pw.Text('Type', style: pw.TextStyle(font: ttf, fontWeight: pw.FontWeight.bold))),
                pw.Expanded(flex: 2, child: pw.Text('Mode', style: pw.TextStyle(font: ttf, fontWeight: pw.FontWeight.bold))),
                pw.Expanded(flex: 3, child: pw.Text('Phone / PIN', style: pw.TextStyle(font: ttf, fontWeight: pw.FontWeight.bold))),
                pw.Expanded(flex: 2, child: pw.Text('Amount ', style: pw.TextStyle(font: ttf, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.right)),
                pw.Expanded(flex: 4, child: pw.Text(' Reference / Note', style: pw.TextStyle(font: ttf, fontWeight: pw.FontWeight.bold))),
              ]),
              pw.SizedBox(height: 6),
              ...txns.map((t) {
                final ts = t['createdAt'] as Timestamp?;
                final timeStr = ts != null ? DateFormat('hh:mm a').format(ts.toDate()) : '';
                final type = (t['type'] ?? '').toString();
                final mode = (t['mode'] ?? '').toString();
                final phone = (t['phone'] ?? '')?.toString() ?? '';
                final pin = (t['pin'] ?? '')?.toString() ?? '';
                final name = (t['name'] ?? '')?.toString() ?? '';
                // include name under phone/pin when available
                String phonePin = phone;
                if (pin.isNotEmpty) {
                  phonePin = (phonePin.isNotEmpty ? '$phonePin / $pin' : pin);
                }
                if (name.isNotEmpty) {
                  // place name on a new line under phone/pin
                  phonePin = phonePin.isNotEmpty ? '$phonePin\nName: $name' : '$name';
                }

                final amt = (t['finalAmount'] as double).toStringAsFixed(2);
                final ref = (t['reference'] ?? '')?.toString() ?? '';
                final note = (t['note'] ?? '')?.toString() ?? '';
                final refNote = (ref.isNotEmpty && note.isNotEmpty) ? '$ref • $note' : (ref.isNotEmpty ? ref : note);
                final displayRefNote = refNote.isNotEmpty ? ' $refNote' : '';

                return pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 6),
                  child: pw.Row(children: [
                    pw.Expanded(flex: 2, child: pw.Text(timeStr, style: pw.TextStyle(font: ttf))),
                    pw.Expanded(flex: 2, child: pw.Text(type.capitalize(), style: pw.TextStyle(font: ttf))),
                    pw.Expanded(flex: 2, child: pw.Text(mode, style: pw.TextStyle(font: ttf))),
                    pw.Expanded(flex: 3, child: pw.Text(phonePin, style: pw.TextStyle(font: ttf))),
                    pw.Expanded(flex: 2, child: pw.Text(amt, textAlign: pw.TextAlign.right, style: pw.TextStyle(font: ttf))),
                    pw.Expanded(flex: 4, child: pw.Text(displayRefNote, style: pw.TextStyle(font: ttf))),
                  ]),
                );
              }).toList(),
              pw.SizedBox(height: 12),
              pw.Divider(),

              // ===== replaced totals with Current balance / Due according to your rule =====
              pw.SizedBox(height: 8),
              pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
                pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                  pw.Text('Current balance: ৳${currentBalanceToShow.toStringAsFixed(2)}', style: pw.TextStyle(font: ttf, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 6),
                  pw.Text('Due: ৳${dueToShow.toStringAsFixed(2)}', style: pw.TextStyle(font: ttf, fontWeight: pw.FontWeight.bold, color: dueToShow > 0 ? pdf.PdfColors.red : pdf.PdfColors.black)),
                ]),
              ]),
              pw.SizedBox(height: 20),
              pw.Text('Generated by Jononi Pharmacy app', style: pw.TextStyle(font: ttf, fontSize: 10, color: pdf.PdfColors.grey)),
            ];
          },
        ),
      );
    } catch (e, st) {
      debugPrint('PDF font load/share error: $e\n$st');
      // fallback: build pdf without font (same as before) to avoid crash
      final rawBalanceFallback = accData['balance'] ?? 0;
      final accountBalanceFallback = (rawBalanceFallback is num) ? rawBalanceFallback.toDouble() : double.tryParse(rawBalanceFallback.toString()) ?? 0.0;
      final double currentBalanceFallback = accountBalanceFallback >= 0.0 ? accountBalanceFallback : 0.0;
      final double dueFallback = accountBalanceFallback < 0.0 ? accountBalanceFallback.abs() : 0.0;

      pdfDoc.addPage(
        pw.MultiPage(
          pageFormat: pdf.PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(18),
          build: (pw.Context ctx) {
            return <pw.Widget>[
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                    pw.Text(accountName, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 4),
                    pw.Text('Date: $dateString', style: pw.TextStyle(fontSize: 12)),
                  ]),
                  pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                    pw.Text('Daily Summary', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 4),
                    pw.Text('Receive: ৳${totalReceive.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 12)),
                    pw.Text('Send: ৳${totalSend.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 12)),
                  ]),
                ],
              ),
              // simplified fallback content...
              pw.SizedBox(height: 12),

              // show current balance and due even in fallback
              pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
                pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                  pw.Text('Current balance: ৳${currentBalanceFallback.toStringAsFixed(2)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 6),
                  pw.Text('Due: ৳${dueFallback.toStringAsFixed(2)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                ]),
              ]),

              pw.SizedBox(height: 12),
              pw.Text('Transactions exported (font load failed).'),
            ];
          },
        ),
      );
    }

    final bytes = await pdfDoc.save();
    await Printing.sharePdf(bytes: bytes, filename: '${accountName}_$dateString.pdf');
  }

  @override
  Widget build(BuildContext context) {
    final accountDocRef = firestore.collection('bkash_customers').doc(widget.accountId);

    return StreamBuilder<DocumentSnapshot>(
      stream: accountDocRef.snapshots(),
      builder: (context, accSnap) {
        if (accSnap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Color(0xFF01684D),
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final accData = (accSnap.data?.data() ?? widget.accountData) as Map<String, dynamic>;
        final rawBalance = accData['balance'] ?? 0;
        final balance = (rawBalance is num) ? rawBalance.toDouble() : double.tryParse(rawBalance.toString()) ?? 0.0;

        final balanceLabel = balance < 0 ? 'Due' : 'Balance';
        final balanceDisplay = balance < 0 ? (balance.abs()).toStringAsFixed(2) : balance.toStringAsFixed(2);
        final balanceColor = balance < 0 ? Colors.redAccent : Colors.greenAccent;

        return StreamBuilder<QuerySnapshot>(
          stream: _transactionsForDayStream(widget.accountId),
          builder: (context, snapTx) {
            double dailyReceive = 0;
            double dailySend = 0;
            final txDocs = snapTx.data?.docs ?? [];
            for (final d in txDocs) {
              final m = d.data() as Map<String, dynamic>? ?? {};
              final type = (m['type'] ?? '').toString();
              final amt = ((m['finalAmount'] ?? (m['amount'] ?? 0)) as num).toDouble();
              if (type == 'receive') dailyReceive += amt;
              if (type == 'send') dailySend += amt;
            }

            return Scaffold(
              backgroundColor: const Color(0xFF01684D),
              appBar: AppBar(
                title: Text('${(accData['name'] ?? 'Account').toString()} — $dateString'),
                centerTitle: true,
                backgroundColor: const Color(0xFF01684D),
                actions: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('$balanceLabel: ৳$balanceDisplay', style: TextStyle(fontSize: 13, color: balanceColor, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text('Today: +${dailyReceive.toStringAsFixed(2)} / -${dailySend.toStringAsFixed(2)}', style: const TextStyle(fontSize: 11, color: Colors.white70)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.picture_as_pdf),
                    onPressed: () => _generateDailyPdfAndShare(widget.accountId, accData),
                    tooltip: 'Export daily PDF',
                  ),
                  IconButton(icon: const Icon(Icons.calendar_today), onPressed: pickDate),
                ],
              ),
              floatingActionButton: FloatingActionButton(
                backgroundColor: Colors.yellow[700],
                child: const Icon(Icons.add, color: Colors.black),
                onPressed: () async {
                  await showModalBottomSheet(
                    context: context,
                    builder: (_) {
                      return SafeArea(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ListTile(title: Text('Account actions for ${(accData['name'] ?? 'Account').toString()}')),
                            ListTile(
                              leading: const Icon(Icons.call_received),
                              title: const Text('Receive (add to account)'),
                              onTap: () {
                                Navigator.pop(context);
                                _openTransactionDialog(accountId: widget.accountId, type: 'receive', mode: 'account');
                              },
                            ),
                            ListTile(
                              leading: const Icon(Icons.send),
                              title: const Text('Bkash — Send (phone/pin/%)'),
                              onTap: () {
                                Navigator.pop(context);
                                _openTransactionDialog(accountId: widget.accountId, type: 'send', mode: 'bkash');
                              },
                            ),
                            const SizedBox(height: 8),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
              body: Builder(builder: (ctx) {
                if (snapTx.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (txDocs.isEmpty) {
                  return const Center(child: Text('No transactions for this day', style: TextStyle(color: Colors.white70)));
                }

                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 120),
                  itemCount: txDocs.length,
                  itemBuilder: (_, idx) {
                    final doc = txDocs[idx];
                    final m = doc.data() as Map<String, dynamic>? ?? {};
                    final type = (m['type'] ?? 'receive').toString();
                    final finalAmount = ((m['finalAmount'] ?? (m['amount'] ?? 0)) as num).toDouble();
                    final reference = (m['reference'] ?? '')?.toString() ?? '';
                    final note = (m['note'] ?? '')?.toString() ?? '';
                    final mode = (m['mode'] ?? '').toString();
                    final phone = (m['phone'] ?? '')?.toString() ?? '';
                    final pin = (m['pin'] ?? '')?.toString() ?? '';
                    final name = (m['name'] ?? '')?.toString() ?? '';
                    final time = m['createdAt'] != null ? DateFormat('hh:mm a').format((m['createdAt'] as Timestamp).toDate()) : '';

                    return Card(
                      color: Colors.white.withOpacity(0.12),
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      child: ListTile(
                        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(type.toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 6),
                          if (mode == 'bkash') ...[
                            Text('Phone: ${phone.isEmpty ? '-' : phone}', style: const TextStyle(color: Colors.white70)),
                            Text('PIN: ${pin.isEmpty ? '-' : pin}', style: const TextStyle(color: Colors.white70)),
                          ] else ...[
                            // show name field for non-bkash (transaction) entries
                            Text('Name: ${name.isNotEmpty ? name : '-'}', style: const TextStyle(color: Colors.white70)),
                          ],
                          Text('Final: ৳${finalAmount.toStringAsFixed(2)}', style: const TextStyle(color: Colors.yellowAccent, fontWeight: FontWeight.bold)),
                          if (reference.isNotEmpty) Text('Ref: $reference', style: const TextStyle(color: Colors.white70)),
                          if (note.isNotEmpty) Text('Note: $note', style: const TextStyle(color: Colors.white70)),
                          Text('Time: $time', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                        ]),
                        trailing: PopupMenuButton<String>(
                          onSelected: (v) async {
                            if (v == 'edit') {
                              await _openTransactionDialog(accountId: widget.accountId, type: type, mode: mode.isEmpty ? 'account' : mode, docId: doc.id, initial: m);
                            } else if (v == 'delete') {
                              final ok = await showDialog<bool>(
                                context: context,
                                builder: (_) => AlertDialog(
                                  title: const Text('Delete transaction?'),
                                  content: const Text('This will remove the transaction and adjust account balance.'),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                                    ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
                                  ],
                                ),
                              );
                              if (ok == true) {
                                await _deleteTransactionAndReverse(widget.accountId, doc);
                              }
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'edit', child: Text('Edit')),
                            PopupMenuItem(value: 'delete', child: Text('Delete')),
                          ],
                        ),
                      ),
                    );
                  },
                );
              }),
            );
          },
        );
      },
    );
  }
}

// small helper for capitalize used in PDF
extension _StringCap on String {
  String capitalize() {
    if (isEmpty) return this;
    return this[0].toUpperCase() + substring(1);
  }
}
