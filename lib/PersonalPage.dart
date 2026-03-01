// personal_page.dart (fixed stop session and total minutes)
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


class PersonalPage extends StatelessWidget {
  const PersonalPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          _buildBackdrop(),
          const SafeArea(child: PersonalSinglePage()),
        ],
      ),
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
  int _selectedTab = 0;

  Widget _buildTabButton(String label, int index) {
    final selected = _selectedTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedTab = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withOpacity(selected ? 0.24 : 0.12)),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: selected ? _bgStart : Colors.white70,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(64),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withOpacity(0.18)),
                ),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Personal',
                        style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      constraints: const BoxConstraints.tightFor(width: 110, height: 28),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withOpacity(0.2)),
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          _selectedTab == 0 ? 'Cost' : 'Attendance',
                          style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
                          maxLines: 1,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white.withOpacity(0.16)),
                      ),
                      child: Row(
                        children: [
                          _buildTabButton('Cost', 0),
                          const SizedBox(width: 8),
                          _buildTabButton('Attendance', 1),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: _selectedTab == 0
                    ? PersonalCostWidget(firestore: firestore)
                    : EmployeeListWidget(firestore: firestore),
              ),
            ],
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
      builder: (_) => Theme(
        data: _dialogTheme(context),
        child: AlertDialog(
          backgroundColor: _bgEnd,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: Colors.white.withOpacity(0.12)),
          ),
          title: Text(type == 'receive' ? 'Receive (add)' : 'Cost (spend)'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: reasonCtrl, decoration: const InputDecoration(labelText: 'Reason')),
                const SizedBox(height: 8),
                TextField(controller: amountCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Amount')),
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
            preferredSize: const Size.fromHeight(72),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white.withOpacity(0.18)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Date: $dateString',
                            style: const TextStyle(color: Colors.white70),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'Receive: ৳${totalReceive.toStringAsFixed(2)}',
                              style: const TextStyle(color: Colors.white, fontSize: 13),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              'Cost: ৳${totalCost.toStringAsFixed(2)}',
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
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
          body: Stack(
            children: [
              Builder(builder: (ctx) {
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
                            builder: (_) => Theme(
                              data: _dialogTheme(context),
                              child: AlertDialog(
                                backgroundColor: _bgEnd,
                                surfaceTintColor: Colors.transparent,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                  side: BorderSide(color: Colors.white.withOpacity(0.12)),
                                ),
                                title: const Text('Delete entry?'),
                                content: const Text('Remove this entry permanently.'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                                  ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
                                ],
                              ),
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
              Positioned(
                left: 16,
                bottom: 16,
                child: SafeArea(
                  child: FloatingActionButton(
                    heroTag: 'back_personal_cost_fab',
                    mini: true,
                    backgroundColor: Colors.white.withOpacity(0.12),
                    onPressed: () => Navigator.maybePop(context),
                    child: const Icon(Icons.arrow_back, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
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
      builder: (_) => Theme(
        data: _dialogTheme(context),
        child: AlertDialog(
          backgroundColor: _bgEnd,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: Colors.white.withOpacity(0.12)),
          ),
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
      ),
    );
  }

  Future<void> _deleteEmployee(DocumentSnapshot doc) async {
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
          title: const Text('Delete employee?'),
          content: const Text('This will delete the employee and all their attendance records.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
          ],
        ),
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
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        backgroundColor: _accent,
        child: const Icon(Icons.add, color: Colors.black),
        onPressed: _addEmployeeDialog,
      ),
      body: Stack(
        children: [
          Column(
            children: [
              // search
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
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
                        onChanged: (v) => setState(() => _search = v),
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          hintText: 'Search employee...',
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
          Positioned(
            left: 16,
            bottom: 16,
            child: SafeArea(
              child: FloatingActionButton(
                heroTag: 'back_personal_list_fab',
                mini: true,
                backgroundColor: Colors.white.withOpacity(0.12),
                onPressed: () => Navigator.maybePop(context),
                child: const Icon(Icons.arrow_back, color: Colors.white),
              ),
            ),
          ),
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
  static const Color _bgStart = Color(0xFF041A14);
  static const Color _bgEnd = Color(0xFF0E5A42);
  static const Color _accent = Color(0xFFFFD166);

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

  Widget _infoChip({required String label, required String value, Color? color}) {
    final c = color ?? Colors.white70;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withOpacity(0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(color: Colors.white60, fontSize: 11)),
          const SizedBox(width: 6),
          Text(value, style: TextStyle(color: c, fontWeight: FontWeight.w600, fontSize: 11)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.employeeName, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
            Text(dateString, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_today, color: Colors.white),
            onPressed: pickDate,
          ),
        ],
      ),
      floatingActionButton: SafeArea(
        minimum: const EdgeInsets.only(bottom: 8),
        child: Column(
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
      ),
      body: Stack(
        children: [
          _buildBackdrop(),
          SafeArea(
            child: StreamBuilder<QuerySnapshot>(
              stream: attendanceForDayStream(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: Colors.white));
                }
                final docs = snap.data?.docs ?? [];
                if (docs.isEmpty) {
                  return const Center(
                    child: Text('No attendance sessions for this day', style: TextStyle(color: Colors.white70)),
                  );
                }
                int totalMinutes = 0;
                for (final d in docs) {
                  final m = d.data() as Map<String, dynamic>? ?? {};
                  final dm = m['durationMinutes'];
                  if (dm is num) totalMinutes += dm.toInt();
                }

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.white.withOpacity(0.18)),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 34,
                                  height: 34,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.12),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white.withOpacity(0.2)),
                                  ),
                                  child: const Icon(Icons.timer_outlined, color: Colors.white70, size: 18),
                                ),
                                const SizedBox(width: 10),
                                const Expanded(
                                  child: Text(
                                    'Total outside today',
                                    style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                                  ),
                                ),
                                Text(
                                  _formatDuration(totalMinutes),
                                  style: const TextStyle(color: Colors.yellowAccent, fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                              ],
                            ),
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

                          return Container(
                            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.white.withOpacity(0.16)),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.18),
                                  blurRadius: 12,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          const Icon(Icons.play_arrow_rounded, color: Colors.greenAccent, size: 18),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              'Start $startStr',
                                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          const Icon(Icons.stop_rounded, color: Colors.orangeAccent, size: 18),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              'End $endStr',
                                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 6,
                                        children: [
                                          _infoChip(label: 'Duration', value: durStr, color: Colors.white),
                                          if (createdAt != null)
                                            _infoChip(
                                              label: 'Logged',
                                              value: DateFormat('hh:mm a').format(createdAt),
                                              color: Colors.white70,
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                PopupMenuButton<String>(
                                  onSelected: (v) async {
                                    if (v == 'delete') {
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
                                            title: const Text('Delete session?'),
                                            content: const Text('This will remove this attendance session.'),
                                            actions: [
                                              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                                              ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
                                            ],
                                          ),
                                        ),
                                      );
                                      if (ok == true) {
                                        await d.reference.delete();
                                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Deleted')));
                                      }
                                    }
                                  },
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}



