// CustomerDueDetailPage.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

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

class CustomerDueDetailPage extends StatefulWidget {
  final String customerId;
  final Map<String, dynamic> customerData;

  const CustomerDueDetailPage({Key? key, required this.customerId, required this.customerData}) : super(key: key);

  @override
  State<CustomerDueDetailPage> createState() => _CustomerDueDetailPageState();
}

class _CustomerDueDetailPageState extends State<CustomerDueDetailPage> {
  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  double totalDue = 0.0;
  double balance = 0.0;

  @override
  void initState() {
    super.initState();
    totalDue = ((widget.customerData['totalDue'] ?? 0) as num).toDouble();
    balance = ((widget.customerData['balance'] ?? 0) as num).toDouble();
  }

  Stream<QuerySnapshot> getHistoryStream() {
    return firestore
        .collection('customers')
        .doc(widget.customerId)
        .collection('customer_dues')
        .orderBy('createdAt', descending: true)
        .snapshots();
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
        Expanded(child: Text(text, style: const TextStyle(color: Colors.white70))),
      ],
    );
  }

  Widget _statCard(String title, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }

  // ---------------- Add Due / Payment (modified) ----------------
  // If adding due: check existing balance first and consume it, remaining becomes totalDue.
  // If adding payment: reduce totalDue; if payment > totalDue, excess becomes balance.
  Future<void> addEntry(bool isPayment) async {
    final controller = TextEditingController();
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
          title: Text(isPayment ? "Add Payment" : "Add Due"),
          content: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: "Amount (৳)"),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
            ElevatedButton(
              onPressed: () async {
                final amount = double.tryParse(controller.text);
                if (amount == null || amount <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Enter valid amount")));
                  return;
                }

                final custRef = firestore.collection('customers').doc(widget.customerId);

                try {
                  // get fresh snapshot so we base decisions on latest balance/totalDue
                  final snap = await custRef.get();
                  final currMap = snap.data() ?? {};
                  final currBalance = ((currMap['balance'] ?? 0) as num).toDouble();
                  final currDue = ((currMap['totalDue'] ?? 0) as num).toDouble();

                  final batch = firestore.batch();

                  if (isPayment) {
                    // Only allow payments when there is a positive due and current balance is 0.
                    // (UI also disables the button, but enforce here too.)
                    if (currDue <= 0 || currBalance != 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Payment not allowed: no due or customer has non-zero balance")),
                      );
                      return;
                    }

                    // Determine how much actually pays the due and any excess becomes balance
                    final payTowardsDue = amount <= currDue ? amount : currDue;
                    final excess = (amount - payTowardsDue);

                    // Log payment entry for the amount applied to due (if > 0)
                    if (payTowardsDue > 0) {
                      final dueDocRef = custRef.collection('customer_dues').doc();
                      batch.set(dueDocRef, {
                        'type': 'paid',
                        'amount': payTowardsDue,
                        'createdAt': FieldValue.serverTimestamp(),
                      });

                      // decrement totalDue by the amount applied
                      batch.update(custRef, {'totalDue': FieldValue.increment(-payTowardsDue)});

                      // also add to due_entries/{today}/entries so SellPage daily totals include it
                      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
                      final entryRef = firestore.collection('due_entries').doc(today).collection('entries').doc();
                      batch.set(entryRef, {
                        'type': 'paid',
                        'customerId': widget.customerId,
                        'name': widget.customerData['name'] ?? '',
                        'phone': widget.customerData['phone'] ?? null,
                        'address': widget.customerData['address'] ?? null,
                        'amount': payTowardsDue,
                        'createdAt': FieldValue.serverTimestamp(),
                      });
                    }

                    // If there's excess payment beyond the due, convert it to balance
                    if (excess > 0) {
                      // increment balance by excess
                      batch.update(custRef, {'balance': FieldValue.increment(excess)});

                      // log the excess as a deposit/overpayment for audit
                      final depositDoc = custRef.collection('customer_dues').doc();
                      batch.set(depositDoc, {
                        'type': 'deposit_from_overpayment',
                        'amount': excess,
                        'note': 'Overpayment converted to balance',
                        'createdAt': FieldValue.serverTimestamp(),
                      });

                      // also log in due_entries so daily totals include the deposit if needed
                      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
                      final depositEntryRef = firestore.collection('due_entries').doc(today).collection('entries').doc();
                      batch.set(depositEntryRef, {
                        'type': 'deposit',
                        'customerId': widget.customerId,
                        'name': widget.customerData['name'] ?? '',
                        'phone': widget.customerData['phone'] ?? null,
                        'address': widget.customerData['address'] ?? null,
                        'amount': excess,
                        'createdAt': FieldValue.serverTimestamp(),
                      });
                    }

                    await batch.commit();

                    // update local UI values conservatively
                    setState(() {
                      totalDue = (currDue - (amount <= currDue ? amount : currDue));
                      if (totalDue < 0) totalDue = 0.0;
                      balance = (currBalance + (amount > currDue ? (amount - currDue) : 0.0));
                    });

                    Navigator.pop(context);
                    return;
                  }

                  // ADD DUE flow (new behavior): first use available balance to cover new due
                  double remainingDue = amount;
                  double amountCoveredByBalance = 0.0;

                  if (currBalance > 0) {
                    amountCoveredByBalance = (currBalance >= amount) ? amount : currBalance;
                    remainingDue = amount - amountCoveredByBalance;
                  }

                  // 1) If some balance is used -> decrement balance
                  if (amountCoveredByBalance > 0) {
                    batch.update(custRef, {'balance': FieldValue.increment(-amountCoveredByBalance)});
                  }

                  // 2) If remainingDue > 0 -> create a 'due' entry and increment totalDue
                  if (remainingDue > 0) {
                    final dueDocRef = custRef.collection('customer_dues').doc();
                    batch.set(dueDocRef, {
                      'type': 'due',
                      'amount': remainingDue,
                      'createdAt': FieldValue.serverTimestamp(),
                      // note: store how much was covered by balance (for audit)
                      'coveredByBalance': amountCoveredByBalance > 0 ? amountCoveredByBalance : null,
                    });

                    batch.update(custRef, {'totalDue': FieldValue.increment(remainingDue)});
                  } else {
                    // Entire due covered by balance - still log an entry for audit
                    final dueDocRef = custRef.collection('customer_dues').doc();
                    batch.set(dueDocRef, {
                      'type': 'due_covered_by_balance',
                      'amount': amount,
                      'coveredByBalance': amount,
                      'createdAt': FieldValue.serverTimestamp(),
                    });
                  }

                  await batch.commit();

                  // Update local UI values
                  setState(() {
                    // new balance = currBalance - amountCoveredByBalance
                    balance = (currBalance - amountCoveredByBalance);
                    if (balance < 0) balance = 0.0;
                    // new totalDue = currDue + remainingDue
                    totalDue = (currDue + remainingDue);
                  });

                  Navigator.pop(context);
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Operation failed: $e")));
                }
              },
              child: const Text("Submit"),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- Add Account (new) ----------------
  // Deposit money to customer's account: first reduces totalDue (if any), remaining becomes balance.
  Future<void> addAccount() async {
    final controller = TextEditingController();
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
          title: const Text("Add Account (Deposit)"),
          content: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: "Amount (৳)"),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
            ElevatedButton(
              onPressed: () async {
                final amount = double.tryParse(controller.text);
                if (amount == null || amount <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Enter valid amount")));
                  return;
                }

                final custRef = firestore.collection('customers').doc(widget.customerId);

                try {
                  final snap = await custRef.get();
                  final curr = snap.data() ?? {};
                  final currDue = ((curr['totalDue'] ?? 0) as num).toDouble();
                  final currBalance = ((curr['balance'] ?? 0) as num).toDouble();

                  double payTowardsDue = 0.0;
                  double addToBalance = 0.0;

                  if (currDue > 0) {
                    // first use deposit to reduce existing due
                    payTowardsDue = (amount >= currDue) ? currDue : amount;
                    addToBalance = amount - payTowardsDue;
                  } else {
                    // no due: full amount goes to balance
                    payTowardsDue = 0.0;
                    addToBalance = amount;
                  }

                  final batch = firestore.batch();

                  // if paying some due
                  if (payTowardsDue > 0) {
                    // add a 'paid' customer_dues entry
                    final dueDocRef = custRef.collection('customer_dues').doc();
                    batch.set(dueDocRef, {
                      'type': 'paid_from_deposit',
                      'amount': payTowardsDue,
                      'note': 'Deposit used to clear due',
                      'createdAt': FieldValue.serverTimestamp(),
                    });
                    // decrement totalDue
                    batch.update(custRef, {'totalDue': FieldValue.increment(-payTowardsDue)});
                  }

                  // if some left -> increment balance
                  if (addToBalance > 0) {
                    batch.update(custRef, {'balance': FieldValue.increment(addToBalance)});

                    // also log the deposit in customer_dues for audit (type 'deposit' or 'account_add')
                    final depositDoc = custRef.collection('customer_dues').doc();
                    batch.set(depositDoc, {
                      'type': 'deposit',
                      'amount': addToBalance,
                      'createdAt': FieldValue.serverTimestamp(),
                    });
                  }

                  await batch.commit();

                  // update local UI
                  setState(() {
                    totalDue = (currDue - payTowardsDue);
                    if (totalDue < 0) totalDue = 0.0;
                    balance = (currBalance + addToBalance);
                  });

                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Deposit processed')));
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
                }
              },
              child: const Text("Submit"),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.customerData['name'] ?? 'Unknown';
    final phone = widget.customerData['phone'] ?? 'N/A';
    final address = widget.customerData['address'] ?? 'N/A';

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text("Customer Due Details", style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
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
                    borderRadius: BorderRadius.circular(16),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withOpacity(0.18)),
                        ),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(
                            children: [
                              Container(
                                width: 46,
                                height: 46,
                                decoration: BoxDecoration(
                                  color: _accent.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  _initials(name.toString()),
                                  style: const TextStyle(color: _accent, fontWeight: FontWeight.bold),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name.toString(),
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                                    ),
                                    const SizedBox(height: 6),
                                    _infoRow(Icons.location_on_outlined, address.toString()),
                                    const SizedBox(height: 4),
                                    _infoRow(Icons.call_outlined, phone.toString()),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Container(height: 1, color: Colors.white12),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _statCard(
                                  "Total Due",
                                  "৳${totalDue.toStringAsFixed(2)}",
                                  totalDue > 0 ? Colors.redAccent : Colors.greenAccent,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _statCard(
                                  "Balance",
                                  "৳${balance.toStringAsFixed(2)}",
                                  balance < 0 ? Colors.redAccent : Colors.greenAccent,
                                ),
                              ),
                            ],
                          ),
                        ]),
                      ),
                    ),
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => addEntry(false),
                        icon: const Icon(Icons.add, size: 18),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          minimumSize: const Size.fromHeight(46),
                        ),
                        label: const Text("Add Due"),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: (totalDue > 0 && balance == 0) ? () => addEntry(true) : null,
                        icon: const Icon(Icons.payments_outlined, size: 18),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          minimumSize: const Size.fromHeight(46),
                        ),
                        label: const Text("Add Payment"),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => addAccount(),
                        icon: const Icon(Icons.account_balance_wallet_outlined, size: 18),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _accent,
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          minimumSize: const Size.fromHeight(46),
                        ),
                        label: const Text("Add Account"),
                      ),
                    ),
                  ]),
                ),

                const SizedBox(height: 10),

                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: getHistoryStream(),
                    builder: (context, snap) {
                      if (!snap.hasData) return const Center(child: CircularProgressIndicator(color: Colors.white));
                      final docs = snap.data!.docs;
                      if (docs.isEmpty) {
                        return const Center(child: Text("No history found", style: TextStyle(color: Colors.white70)));
                      }
                      return ListView.builder(
                        padding: const EdgeInsets.only(bottom: 120),
                        itemCount: docs.length,
                        itemBuilder: (_, i) {
                          final d = docs[i].data() as Map<String, dynamic>;
                          final time = (d['createdAt'] as Timestamp?) != null
                              ? DateFormat('dd MMM yyyy - hh:mm a').format((d['createdAt'] as Timestamp).toDate())
                              : '';
                          final type = (d['type'] ?? '').toString();
                          final isPaid = type.startsWith('paid');
                          final isPositive = isPaid || type.startsWith('deposit');
                          final amount = ((d['amount'] ?? 0) as num).toDouble();

                          String titleText;
                          if (type == 'deposit') {
                            titleText = "Deposit : ৳${amount.toStringAsFixed(2)}";
                          } else if (type == 'due_covered_by_balance') {
                            titleText = "Due (covered by balance) : ৳${amount.toStringAsFixed(2)}";
                          } else if (type == 'paid_from_deposit') {
                            titleText = "Paid (from deposit) : ৳${amount.toStringAsFixed(2)}";
                          } else if (type == 'deposit_from_overpayment') {
                            titleText = "Overpayment converted to balance : ৳${amount.toStringAsFixed(2)}";
                          } else {
                            titleText = "${isPaid ? 'Paid' : 'Due'} : ৳${amount.toStringAsFixed(2)}";
                          }

                          final iconColor = isPositive ? Colors.greenAccent : Colors.redAccent;

                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    leading: Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: iconColor.withOpacity(0.18),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Icon(
                                        isPositive ? Icons.arrow_downward : Icons.arrow_upward,
                                        color: iconColor,
                                        size: 18,
                                      ),
                                    ),
                                    title: Text(titleText, style: const TextStyle(color: Colors.white)),
                                    subtitle: Text(time, style: const TextStyle(color: Colors.white70)),
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
