// personal_page.dart (fixed stop session and total minutes)
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class PersonalPage extends StatelessWidget {
  const PersonalPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SafeArea(child: PersonalSinglePage()),
    );
  }
}

class PersonalSinglePage extends StatefulWidget {
  const PersonalSinglePage({super.key});

  @override
  State<PersonalSinglePage> createState() => _PersonalSinglePageState();
}

class _PersonalSinglePageState extends State<PersonalSinglePage> {
  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  final bgColor = const Color(0xFF01684D);

  // date string for today (yyyy-MM-dd)
  String get todayDate => DateFormat('yyyy-MM-dd').format(DateTime.now());

  int _selectedTab = 0; // 0 = Cost, 1 = Attendance

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text('Personal'),
        backgroundColor: bgColor,
        centerTitle: true,
        elevation: 0,
        actions: [
          // simple tab indicator
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Center(child: Text(_selectedTab == 0 ? 'Cost' : 'Attendance', style: const TextStyle(fontSize: 14))),
          ),
        ],
      ),
      body: Column(
        children: [
          // Tab buttons
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: _selectedTab == 0 ? Colors.white : Colors.white24),
                    onPressed: () => setState(() => _selectedTab = 0),
                    child: Text('Cost', style: TextStyle(color: _selectedTab == 0 ? bgColor : Colors.white)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: _selectedTab == 1 ? Colors.white : Colors.white24),
                    onPressed: () => setState(() => _selectedTab = 1),
                    child: Text('Attendance', style: TextStyle(color: _selectedTab == 1 ? bgColor : Colors.white)),
                  ),
                ),
              ],
            ),
          ),

          // Body area
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 0),
              decoration: BoxDecoration(
                color: bgColor,
              ),
              child: _selectedTab == 0 ? PersonalCostWidget(firestore: firestore) : EmployeeListWidget(firestore: firestore),
            ),
          ),
        ],
      ),
    );
  }
}

/// ------------------------ COST WIDGET ------------------------
class PersonalCostWidget extends StatefulWidget {
  final FirebaseFirestore firestore;
  const PersonalCostWidget({required this.firestore, super.key});

  @override
  State<PersonalCostWidget> createState() => _PersonalCostWidgetState();
}

class _PersonalCostWidgetState extends State<PersonalCostWidget> {
  String get dateString => DateFormat('yyyy-MM-dd').format(DateTime.now());

  CollectionReference<Map<String, dynamic>> entriesRef() {
    return widget.firestore.collection('personal_costs').doc(dateString).collection('entries').withConverter(
      fromFirestore: (snap, _) => snap.data() as Map<String, dynamic>,
      toFirestore: (map, _) => map,
    );
  }

  Future<void> _openAddDialog(String type) async {
    final reasonCtrl = TextEditingController();
    final amountCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(type == 'receive' ? 'Receive (add)' : 'Cost (spend)'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: reasonCtrl, decoration: const InputDecoration(labelText: 'Reason')),
              const SizedBox(height: 8),
              TextField(controller: amountCtrl, keyboardType: TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Amount')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final reason = reasonCtrl.text.trim();
              final amt = double.tryParse(amountCtrl.text.trim()) ?? 0.0;
              if (amt <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter valid amount')));
                return;
              }
              await entriesRef().add({
                'type': type,
                'reason': reason.isEmpty ? null : reason,
                'amount': amt,
                'createdAt': FieldValue.serverTimestamp(),
              });
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> streamEntries() => entriesRef().orderBy('createdAt', descending: true).snapshots();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: streamEntries(),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? [];
        double totalReceive = 0.0;
        double totalCost = 0.0;
        for (final d in docs) {
          final m = d.data();
          final amt = ((m['amount'] ?? 0) as num).toDouble();
          if ((m['type'] ?? '') == 'receive') totalReceive += amt;
          else totalCost += amt;
        }

        return Scaffold(
          backgroundColor: Colors.transparent,
          appBar: PreferredSize(
            preferredSize: const Size.fromHeight(48),
            child: Container(
              color: const Color(0xFF01684D),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Text('Date: $dateString', style: const TextStyle(color: Colors.white70)),
                  const Spacer(),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('Receive: ৳${totalReceive.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white, fontSize: 13)),
                      Text('Cost: ৳${totalCost.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          floatingActionButton: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FloatingActionButton(
                heroTag: 'receive',
                backgroundColor: Colors.green,
                onPressed: () => _openAddDialog('receive'),
                child: const Icon(Icons.add),
                tooltip: 'Add Receive',
              ),
              const SizedBox(height: 10),
              FloatingActionButton(
                heroTag: 'cost',
                backgroundColor: Colors.red,
                onPressed: () => _openAddDialog('cost'),
                child: const Icon(Icons.remove),
                tooltip: 'Add Cost',
              ),
            ],
          ),
          body: Builder(builder: (ctx) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (docs.isEmpty) {
              return const Center(child: Text('No entries for today', style: TextStyle(color: Colors.white70)));
            }
            return ListView.builder(
              padding: const EdgeInsets.only(bottom: 120, top: 12),
              itemCount: docs.length,
              itemBuilder: (_, i) {
                final d = docs[i];
                final m = d.data();
                final type = (m['type'] ?? 'cost').toString();
                final reason = (m['reason'] ?? '').toString();
                final amount = ((m['amount'] ?? 0) as num).toDouble();
                final createdAt = m['createdAt'] as Timestamp?;
                final timeStr = createdAt != null ? DateFormat('hh:mm a').format(createdAt.toDate()) : '';

                final isReceive = type == 'receive';
                return Card(
                  color: isReceive ? Colors.white.withOpacity(0.10) : Colors.white.withOpacity(0.06),
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: ListTile(
                    title: Text(reason.isEmpty ? (isReceive ? 'Receive' : 'Cost') : reason, style: const TextStyle(color: Colors.white)),
                    subtitle: Text('Time: $timeStr', style: const TextStyle(color: Colors.white70)),
                    trailing: Text('৳${amount.toStringAsFixed(0) == amount.toStringAsFixed(2) ? amount.toStringAsFixed(0) : amount.toStringAsFixed(2)}', style: TextStyle(color: isReceive ? Colors.greenAccent : Colors.redAccent, fontWeight: FontWeight.bold)),
                    onLongPress: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: const Text('Delete entry?'),
                          content: const Text('Remove this entry permanently.'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
                          ],
                        ),
                      );
                      if (ok == true) {
                        await entriesRef().doc(d.id).delete();
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Deleted')));
                      }
                    },
                  ),
                );
              },
            );
          }),
        );
      },
    );
  }
}

/// ------------------------ EMPLOYEE / ATTENDANCE ------------------------
class EmployeeListWidget extends StatefulWidget {
  final FirebaseFirestore firestore;
  const EmployeeListWidget({required this.firestore, super.key});

  @override
  State<EmployeeListWidget> createState() => _EmployeeListWidgetState();
}

class _EmployeeListWidgetState extends State<EmployeeListWidget> {
  String _search = '';

  Stream<QuerySnapshot> _employeesStream() {
    final col = widget.firestore.collection('employees').orderBy('nameLower');
    if (_search.trim().isEmpty) return col.snapshots();
    final q = _search.trim().toLowerCase();
    return widget.firestore.collection('employees').orderBy('nameLower').startAt([q]).endAt([q + '\uf8ff']).snapshots();
  }

  Future<void> _addEmployeeDialog() async {
    final ctrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add Employee'),
        content: TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'Name')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final name = ctrl.text.trim();
              if (name.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Type a name')));
                return;
              }
              final lower = name.toLowerCase();
              final existing = await widget.firestore.collection('employees').where('nameLower', isEqualTo: lower).limit(1).get();
              if (existing.docs.isNotEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Employee already exists')));
                // select existing? we just notify
                return;
              }
              await widget.firestore.collection('employees').add({
                'name': name,
                'nameLower': lower,
                'createdAt': FieldValue.serverTimestamp(),
              });
              Navigator.pop(context);
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteEmployee(DocumentSnapshot doc) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete employee?'),
        content: const Text('This will delete the employee and all their attendance records.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    final id = doc.id;
    final batch = widget.firestore.batch();
    final empRef = widget.firestore.collection('employees').doc(id);
    // delete attendance docs (iterate)
    final attSnap = await empRef.collection('attendance').get();
    for (final a in attSnap.docs) batch.delete(a.reference);
    batch.delete(empRef);
    await batch.commit();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Employee removed')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF01684D),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.yellow[700],
        child: const Icon(Icons.add, color: Colors.black),
        onPressed: _addEmployeeDialog,
      ),
      body: Column(
        children: [
          // search
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: TextField(
              onChanged: (v) => setState(() => _search = v),
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'Search employee...',
                hintStyle: TextStyle(color: Colors.white70),
                prefixIcon: Icon(Icons.search, color: Colors.white),
                filled: true,
                fillColor: Color(0xFF0C6B56),
                border: OutlineInputBorder(borderSide: BorderSide.none),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _employeesStream(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                final docs = snap.data?.docs ?? [];
                if (docs.isEmpty) return const Center(child: Text('No employees', style: TextStyle(color: Colors.white70)));
                return ListView.separated(
                  padding: const EdgeInsets.only(bottom: 120),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.white10),
                  itemBuilder: (_, i) {
                    final d = docs[i];
                    final m = d.data() as Map<String, dynamic>? ?? {};
                    final name = (m['name'] ?? '').toString();
                    return Card(
                      color: Colors.white.withOpacity(0.06),
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      child: ListTile(
                        title: Text(name, style: const TextStyle(color: Colors.white)),
                        subtitle: Text('Tap to manage attendance', style: const TextStyle(color: Colors.white70)),
                        onTap: () {
                          Navigator.push(context, MaterialPageRoute(builder: (_) => EmployeeAttendancePage(employeeId: d.id, employeeName: name)));
                        },
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.redAccent),
                          onPressed: () => _deleteEmployee(d),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          )
        ],
      ),
    );
  }
}

/// ----------------- EMPLOYEE ATTENDANCE PAGE -----------------
class EmployeeAttendancePage extends StatefulWidget {
  final String employeeId;
  final String employeeName;
  const EmployeeAttendancePage({required this.employeeId, required this.employeeName, super.key});

  @override
  State<EmployeeAttendancePage> createState() => _EmployeeAttendancePageState();
}

class _EmployeeAttendancePageState extends State<EmployeeAttendancePage> {
  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  DateTime selectedDate = DateTime.now();

  String get dateString => DateFormat('yyyy-MM-dd').format(selectedDate);

  Future<void> pickDate() async {
    final picked = await showDatePicker(context: context, initialDate: selectedDate, firstDate: DateTime(2020), lastDate: DateTime(2100));
    if (picked != null) setState(() => selectedDate = picked);
  }

  CollectionReference attendanceCol() {
    return firestore.collection('employees').doc(widget.employeeId).collection('attendance');
  }

  Stream<QuerySnapshot> attendanceForDayStream() {
    final start = DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
    final end = start.add(const Duration(days: 1));
    return attendanceCol()
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('createdAt', isLessThan: Timestamp.fromDate(end))
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  Future<void> _startSession() async {
    // create attendance doc with startAt (endAt null)
    final now = DateTime.now();
    await attendanceCol().add({
      'startAt': Timestamp.fromDate(now),
      'endAt': null,
      'durationMinutes': null,
      'createdAt': FieldValue.serverTimestamp(),
      'date': dateString,
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Started session')));
  }

  Future<void> _stopSession() async {
    // find last open session (endAt == null) and update it
    try {
      // fetch recent sessions and find the first one that's still open for the selected date
      final q = await attendanceCol().orderBy('startAt', descending: true).limit(50).get();
      DocumentSnapshot? openDoc;
      for (final d in q.docs) {
        final m = d.data() as Map<String, dynamic>? ?? {};
        // ensure this session belongs to the selected date and is still open
        final docDate = (m['date'] ?? '').toString();
        if (m['endAt'] == null && docDate == dateString) {
          openDoc = d;
          break;
        }
      }
      if (openDoc == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No running session found')));
        return;
      }

      final startTs = (openDoc['startAt'] as Timestamp?);
      if (startTs == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid start time')));
        return;
      }
      final now = DateTime.now();
      final minutes = now.difference(startTs.toDate()).inMinutes;
      await openDoc.reference.update({
        'endAt': Timestamp.fromDate(now),
        'durationMinutes': minutes,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Stopped — $minutes minutes')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to stop session: $e')));
    }
  }

  String _formatDuration(int totalMinutes) {
    final h = totalMinutes ~/ 60;
    final m = totalMinutes % 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF01684D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF01684D),
        title: Column(
          children: [
            Text(widget.employeeName, style: const TextStyle(fontSize: 16)),
            Text(dateString, style: const TextStyle(fontSize: 12)),
          ],
        ),
        centerTitle: true,
        actions: [
          IconButton(icon: const Icon(Icons.calendar_today), onPressed: pickDate),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.extended(
            heroTag: 'start',
            backgroundColor: Colors.green,
            onPressed: _startSession,
            label: const Text('START (Left)'),
            icon: const Icon(Icons.play_arrow),
          ),
          const SizedBox(height: 10),
          FloatingActionButton.extended(
            heroTag: 'stop',
            backgroundColor: Colors.orange,
            onPressed: _stopSession,
            label: const Text('STOP (Returned)'),
            icon: const Icon(Icons.stop),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: attendanceForDayStream(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) return const Center(child: Text('No attendance sessions for this day', style: TextStyle(color: Colors.white70)));
          int totalMinutes = 0;
          for (final d in docs) {
            final m = d.data() as Map<String, dynamic>? ?? {};
            final dm = m['durationMinutes'];
            if (dm is num) totalMinutes += dm.toInt();
          }

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: Card(
                  color: Colors.white.withOpacity(0.06),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                    child: Row(
                      children: [
                        Expanded(child: Text('Total outside today', style: const TextStyle(color: Colors.white70))),
                        Text(_formatDuration(totalMinutes), style: const TextStyle(color: Colors.yellowAccent, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: docs.length,
                  padding: const EdgeInsets.only(bottom: 120),
                  itemBuilder: (_, i) {
                    final d = docs[i];
                    final m = d.data() as Map<String, dynamic>? ?? {};
                    final start = (m['startAt'] as Timestamp?)?.toDate();
                    final end = (m['endAt'] as Timestamp?)?.toDate();
                    final dur = m['durationMinutes'] as num?;
                    final createdAt = (m['createdAt'] as Timestamp?)?.toDate();
                    final startStr = start != null ? DateFormat('hh:mm a').format(start) : '-';
                    final endStr = end != null ? DateFormat('hh:mm a').format(end) : '-';
                    final durStr = (dur != null) ? _formatDuration(dur.toInt()) : 'running';

                    return Card(
                      color: Colors.white.withOpacity(0.08),
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      child: ListTile(
                        title: Text('Start: $startStr  —  End: $endStr', style: const TextStyle(color: Colors.white)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 6),
                            Text('Duration: $durStr', style: const TextStyle(color: Colors.white70)),
                            if (createdAt != null) Text('Logged: ${DateFormat('hh:mm a').format(createdAt)}', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                          ],
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (v) async {
                            if (v == 'delete') {
                              final ok = await showDialog<bool>(
                                context: context,
                                builder: (_) => AlertDialog(
                                  title: const Text('Delete session?'),
                                  content: const Text('This will remove this attendance session.'),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                                    ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
                                  ],
                                ),
                              );
                              if (ok == true) {
                                // reverse effect on totals not needed (attendance only)
                                await d.reference.delete();
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Deleted')));
                              }
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'delete', child: Text('Delete')),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
