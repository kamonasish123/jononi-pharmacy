// CustomerDueDetailPage.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

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

  // ---------------- Add Due / Payment (modified) ----------------
  // If adding due: check existing balance first and consume it, remaining becomes totalDue.
  // If adding payment: reduce totalDue; if payment > totalDue, excess becomes balance.
  Future<void> addEntry(bool isPayment) async {
    final controller = TextEditingController();
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(isPayment ? "Add Payment" : "Add Due"),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: "Amount"),
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
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Payment not allowed: no due or customer has non-zero balance")));
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
                  // Entire due covered by balance — still log an entry for audit
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
    );
  }

  // ---------------- Add Account (new) ----------------
  // Deposit money to customer's account: first reduces totalDue (if any), remaining becomes balance.
  Future<void> addAccount() async {
    final controller = TextEditingController();
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Add Account (Deposit)"),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: "Amount"),
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.customerData['name'] ?? 'Unknown';
    final phone = widget.customerData['phone'] ?? 'N/A';
    final address = widget.customerData['address'] ?? 'N/A';

    return Scaffold(
      backgroundColor: const Color(0xFF01684D),
      appBar: AppBar(
        title: const Text("Customer Due Details"),
        centerTitle: true,
        backgroundColor: const Color(0xFF01684D),
      ),
      body: Column(
        children: [
          Card(
            color: Colors.white.withOpacity(0.1),
            margin: const EdgeInsets.all(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text("Name : $name", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                Text("Address : $address", style: const TextStyle(color: Colors.white70)),
                Text("Phone : $phone", style: const TextStyle(color: Colors.white70)),
                const Divider(color: Colors.white),
                // Show both balance and total due
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text("Total Due", style: TextStyle(color: Colors.white70)),
                      const SizedBox(height: 4),
                      Text("৳${totalDue.toStringAsFixed(2)}", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: totalDue > 0 ? Colors.red : Colors.green)),
                    ]),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      const Text("Balance", style: TextStyle(color: Colors.white70)),
                      const SizedBox(height: 4),
                      Text("৳${balance.toStringAsFixed(2)}", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: balance < 0 ? Colors.red : Colors.greenAccent)),
                    ]),
                  ],
                ),
              ]),
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: [
              Expanded(child: ElevatedButton(onPressed: () => addEntry(false), style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent), child: const Text("Add Due"))),
              const SizedBox(width: 8),
              // Add Payment button should only work when totalDue is positive and current balance is 0.
              Expanded(
                child: ElevatedButton(
                  onPressed: (totalDue > 0 && balance == 0) ? () => addEntry(true) : null,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                  child: const Text("Add Payment"),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: ElevatedButton(onPressed: () => addAccount(), style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent), child: const Text("Add Account"))),
            ]),
          ),

          const SizedBox(height: 10),

          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: getHistoryStream(),
              builder: (context, snap) {
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                final docs = snap.data!.docs;
                if (docs.isEmpty) return const Center(child: Text("No history found", style: TextStyle(color: Colors.white70)));
                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (_, i) {
                    final d = docs[i].data() as Map<String, dynamic>;
                    final time = (d['createdAt'] as Timestamp?) != null ? DateFormat('dd MMM yyyy • hh:mm a').format((d['createdAt'] as Timestamp).toDate()) : '';
                    final type = (d['type'] ?? '').toString();
                    final isPaid = type.startsWith('paid');
                    final amount = ((d['amount'] ?? 0) as num).toDouble();

                    // Provide friendly label for deposit/covered_by_balance entries
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

                    return Card(
                      color: Colors.white.withOpacity(0.1),
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      child: ListTile(
                        leading: Icon(isPaid ? Icons.arrow_downward : Icons.arrow_upward, color: isPaid ? Colors.green : Colors.red),
                        title: Text(titleText, style: const TextStyle(color: Colors.white)),
                        subtitle: Text(time, style: const TextStyle(color: Colors.white70)),
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
