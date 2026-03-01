// AdminPanelPage.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

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
class AdminPanelPage extends StatefulWidget {
  const AdminPanelPage({super.key});

  @override
  State<AdminPanelPage> createState() => _AdminPanelPageState();
}

class _AdminPanelPageState extends State<AdminPanelPage> {
  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  final currentUser = FirebaseAuth.instance.currentUser;

  final List<String> roles = ['admin', 'manager', 'assistant manager', 'senior seller', 'seller'];

  String _myRole = 'seller';
  bool _loadingRole = true;
  final TextEditingController _promoteEmailController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadMyRole();
  }

  Future<void> _loadMyRole() async {
    if (currentUser == null) {
      setState(() {
        _loadingRole = false;
        _myRole = 'seller';
      });
      return;
    }
    try {
      final doc = await firestore.collection('users').doc(currentUser!.uid).get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        setState(() {
          _myRole = (data['role'] ?? 'seller').toString();
          _loadingRole = false;
        });
      } else {
        setState(() {
          _myRole = 'seller';
          _loadingRole = false;
        });
      }
    } catch (e) {
      setState(() {
        _myRole = 'seller';
        _loadingRole = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed loading role: $e')));
    }
  }

  bool get _isAdmin {
    return _myRole.toLowerCase() == 'admin';
  }

  bool get _canEditRoles {
    // only admin and manager can edit roles and approve/reject
    final lr = _myRole.toLowerCase();
    return lr == 'admin' || lr == 'manager';
  }

  Widget _metaPill(String text, {IconData? icon, Color? color}) {
    final c = color ?? Colors.white70;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withOpacity(0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: c),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  /// Helper to check whether the current user (editor) may change target user's role to `newRole`,
  /// and whether editor may change target user's current role at all.
  /// Returns null when allowed, otherwise an error message.
  Future<String?> _checkPermissionForRoleChange(String targetUid, String newRole) async {
    final editorRole = _myRole.toLowerCase();
    // refresh editor role from server to be safe
    try {
      final meDoc = await firestore.collection('users').doc(currentUser!.uid).get();
      if (meDoc.exists) {
        final meRole = (meDoc.data() as Map<String, dynamic>)['role'] ?? editorRole;
        // use updated
        // (we won't force setState here â€” we'll still use _myRole for UI)
      }
    } catch (_) {}

    // fetch target user's role
    String targetRole = '';
    try {
      final tdoc = await firestore.collection('users').doc(targetUid).get();
      if (tdoc.exists) {
        targetRole = ((tdoc.data() as Map<String, dynamic>)['role'] ?? '').toString().toLowerCase();
      }
    } catch (_) {
      // if fetch fails, be conservative and disallow changing admin
      targetRole = '';
    }

    // admin can do anything
    if (_isAdmin) return null;

    // manager rules:
    // - cannot change admins (targetRole == 'admin')
    // - cannot assign 'admin' role
    if (editorRole == 'manager') {
      if (targetRole == 'admin') return 'Manager cannot modify an Admin user.';
      if (newRole.toLowerCase() == 'admin') return 'Only an Admin can assign the admin role.';
      return null; // allowed otherwise
    }

    // anyone else cannot change roles
    return 'Only Admin or Manager can change roles.';
  }

  Future<void> _updateRole(String uid, String newRole, String userEmail) async {
    // Permission checks before attempting update
    final permErr = await _checkPermissionForRoleChange(uid, newRole);
    if (permErr != null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(permErr)));
      return;
    }

    try {
      final batch = firestore.batch();
      final userRef = firestore.collection('users').doc(uid);
      batch.update(userRef, {'role': newRole, 'updatedAt': FieldValue.serverTimestamp()});
      // optional: audit log for role changes
      final auditRef = firestore.collection('admin_audit').doc();
      batch.set(auditRef, {
        'type': 'role_change',
        'targetUid': uid,
        'targetEmail': userEmail,
        'newRole': newRole,
        'changedByUid': currentUser?.uid,
        'changedByEmail': currentUser?.email,
        'ts': FieldValue.serverTimestamp(),
      });
      await batch.commit();

      // reload our role if we changed our own role
      if (currentUser != null && currentUser!.uid == uid) {
        await _loadMyRole();
      }

      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Role updated to "$newRole" for $userEmail')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to update role: $e')));
    }
  }

  /// Find user by email and set their role (used for quick set admin)
  Future<void> _setRoleByEmail(String email, String roleToSet) async {
    if (email.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Type an email first')));
      return;
    }
    try {
      final q = await firestore.collection('users').where('email', isEqualTo: email).limit(1).get();
      if (q.docs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No user document found for that email. Create user first.')));
        return;
      }
      final doc = q.docs.first;

      // permission check
      final permErr = await _checkPermissionForRoleChange(doc.id, roleToSet);
      if (permErr != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(permErr)));
        return;
      }

      await _updateRole(doc.id, roleToSet, email);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  Future<void> _approveUser(String uid, String email, String roleToSet) async {
    if (!_canEditRoles) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('You do not have permission to approve users.')));
      return;
    }

    // check permissions for assigning a role
    final permErr = await _checkPermissionForRoleChange(uid, roleToSet);
    if (permErr != null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(permErr)));
      return;
    }

    try {
      final me = currentUser;
      final userRef = firestore.collection('users').doc(uid);
      final auditRef = firestore.collection('admin_audit').doc();

      await firestore.runTransaction((tx) async {
        tx.update(userRef, {
          'approved': true,
          'status': 'approved', // mark approved
          'approvedAt': FieldValue.serverTimestamp(),
          'approvedBy': me?.uid,
          'role': roleToSet,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        tx.set(auditRef, {
          'type': 'approve_user',
          'targetUid': uid,
          'targetEmail': email,
          'assignedRole': roleToSet,
          'byUid': me?.uid,
          'byEmail': me?.email,
          'ts': FieldValue.serverTimestamp(),
        });
      });

      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('User approved')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Approve failed: $e')));
    }
  }

  Future<void> _rejectUser(String uid, String email) async {
    if (!_canEditRoles) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('You do not have permission to reject users.')));
      return;
    }

    try {
      final me = currentUser;
      final userRef = firestore.collection('users').doc(uid);
      final auditRef = firestore.collection('admin_audit').doc();

      await firestore.runTransaction((tx) async {
        // Important: remove 'status' and 'approvalRequestedAt' so user doesn't persist in pending.
        // When the user re-requests approval they should write `approvalRequestedAt` and `status: 'pending'`.
        tx.update(userRef, {
          'approved': false,
          'rejectedAt': FieldValue.serverTimestamp(),
          'rejectedBy': me?.uid,
          'approvalRequestedAt': FieldValue.delete(), // optional cleanup
          'status': FieldValue.delete(), // remove status so user can re-request later
          'updatedAt': FieldValue.serverTimestamp(),
        });
        tx.set(auditRef, {
          'type': 'reject_user',
          'targetUid': uid,
          'targetEmail': email,
          'byUid': me?.uid,
          'byEmail': me?.email,
          'ts': FieldValue.serverTimestamp(),
        });
      });

      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('User rejected')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Reject failed: $e')));
    }
  }

  Future<void> _revokeApprovedUser(String uid, String email) async {
    if (!_canEditRoles) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('You do not have permission to revoke approvals.')));
      return;
    }

    // Do not allow revoking an Admin's approval unless current user is admin
    try {
      final tdoc = await firestore.collection('users').doc(uid).get();
      final targetRole = (tdoc.exists ? (tdoc.data() as Map<String, dynamic>)['role'] : null)?.toString().toLowerCase() ?? '';
      if (targetRole == 'admin' && !_isAdmin) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Only an Admin may revoke another Admin.')));
        return;
      }
    } catch (_) {
      // proceed conservatively
    }

    try {
      final me = currentUser;
      final userRef = firestore.collection('users').doc(uid);
      final auditRef = firestore.collection('admin_audit').doc();

      await firestore.runTransaction((tx) async {
        tx.update(userRef, {
          'approved': false,
          'status': 'pending', // put back in pending so admin must re-approve
          'approvalRequestedAt': FieldValue.serverTimestamp(),
          'revokedAt': FieldValue.serverTimestamp(),
          'revokedBy': me?.uid,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        tx.set(auditRef, {
          'type': 'revoke_approval',
          'targetUid': uid,
          'targetEmail': email,
          'byUid': me?.uid,
          'byEmail': me?.email,
          'ts': FieldValue.serverTimestamp(),
        });
      });

      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('User approval revoked')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Revoke failed: $e')));
    }
  }

  Future<void> _confirmApproveDialog(String uid, String email, String currentRole) async {
    String chosen = currentRole.isNotEmpty ? currentRole : 'seller';
    await showDialog(
      context: context,
      builder: (ctx) {
        bool loading = false;
        return StatefulBuilder(builder: (c, setState) {
          return AlertDialog(
            title: const Text('Approve user'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Approve: $email'),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: chosen,
                  items: roles.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => chosen = v);
                  },
                ),
                if (loading) const Padding(padding: EdgeInsets.only(top: 12), child: CircularProgressIndicator()),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: loading
                    ? null
                    : () async {
                  setState(() => loading = true);
                  await _approveUser(uid, email, chosen);
                  if (mounted) Navigator.pop(ctx);
                },
                child: const Text('Approve'),
              ),
            ],
          );
        });
      },
    );
  }

  Future<void> _confirmRejectDialog(String uid, String email) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject user'),
        content: Text('Reject account for $email ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reject')),
        ],
      ),
    );

    if (ok == true) {
      await _rejectUser(uid, email);
    }
  }

  Future<void> _confirmRevokeDialog(String uid, String email) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Revoke approval'),
        content: Text('Revoke approval for $email ? This will require them to be approved again.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Revoke')),
        ],
      ),
    );

    if (ok == true) {
      await _revokeApprovedUser(uid, email);
    }
  }

  @override
  void dispose() {
    _promoteEmailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).copyWith(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: Colors.transparent,
      colorScheme: Theme.of(context).colorScheme.copyWith(
            brightness: Brightness.dark,
            primary: _accent,
            secondary: _accent,
          ),
      dividerColor: Colors.white12,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withOpacity(0.12),
        labelStyle: const TextStyle(color: Colors.white70),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.28)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: _accent.withOpacity(0.7)),
        ),
      ),
    );

    return Theme(
      data: theme,
      child: DefaultTabController(
        length: 2,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            title: const Text(
              'Admin Panel - Users',
              style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white),
            ),
            centerTitle: true,
            backgroundColor: Colors.transparent,
            elevation: 0,
            actions: [
              if (_loadingRole)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Center(child: CircularProgressIndicator(color: Colors.white)),
                ),
              if (!_loadingRole)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white.withOpacity(0.2)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.verified_user, size: 14, color: _accent),
                        const SizedBox(width: 6),
                        Text(
                          _myRole.toUpperCase(),
                          style: const TextStyle(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
            bottom: const TabBar(
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              indicatorColor: _accent,
              tabs: [
                Tab(text: 'Pending'),
                Tab(text: 'All Users'),
              ],
            ),
          ),
          body: Stack(
            children: [
              _buildBackdrop(),
              SafeArea(
                top: false,
                child: Padding(
              padding: const EdgeInsets.only(top: kToolbarHeight + kTextTabBarHeight + 16),
              child: TabBarView(
                    children: [
            // ---------------------------
            // Pending tab
            // ---------------------------
            Column(
              children: [
                // Keep your quick promote UI consistent (as above). It remains visible here.
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withOpacity(0.18)),
                        ),
                        child: Column(
                          children: [
                            LayoutBuilder(
                              builder: (ctx, constraints) {
                                final field = TextField(
                                  controller: _promoteEmailController,
                                  decoration: const InputDecoration(
                                    labelText: 'Email to change role (e.g. rkamonasish@gmail.com)',
                                  ),
                                );
                                final button = ElevatedButton(
                                  onPressed: _canEditRoles
                                      ? () async {
                                          final email = _promoteEmailController.text.trim();
                                          if (email.isEmpty) {
                                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Type an email first')));
                                            return;
                                          }
                                          final chosen = await showDialog<String?>(
                                            context: context,
                                            builder: (ctx) => AlertDialog(
                                              title: const Text('Choose role'),
                                              content: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: roles.map((r) {
                                                  return ListTile(
                                                    title: Text(r),
                                                    onTap: () => Navigator.pop(ctx, r),
                                                  );
                                                }).toList(),
                                              ),
                                            ),
                                          );
                                          if (chosen == null) return;
                                          await _setRoleByEmail(email, chosen);
                                        }
                                      : null,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _accent,
                                    foregroundColor: Colors.black,
                                  ),
                                  child: const Text('Set Role'),
                                );

                                final isNarrow = constraints.maxWidth < 420;
                                if (isNarrow) {
                                  return Column(
                                    children: [
                                      field,
                                      const SizedBox(height: 8),
                                      SizedBox(width: double.infinity, child: button),
                                    ],
                                  );
                                }
                                return Row(
                                  children: [
                                    Expanded(child: field),
                                    const SizedBox(width: 8),
                                    button,
                                  ],
                                );
                              },
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                icon: const Icon(Icons.star, size: 18, color: _accent),
                                label: const Text('Set rkamonasish@gmail.com as admin'),
                                onPressed: _canEditRoles
                                    ? () async {
                                        final ok = await showDialog<bool>(
                                          context: context,
                                          builder: (ctx) => AlertDialog(
                                            title: const Text('Confirm'),
                                            content: const Text('Set rkamonasish@gmail.com as admin?'),
                                            actions: [
                                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                              ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Yes')),
                                            ],
                                          ),
                                        );
                                        if (ok == true) {
                                          await _setRoleByEmail('rkamonasish@gmail.com', 'admin');
                                        }
                                      }
                                    : null,
                              ),
                            ),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text('Only Admin / Manager can change roles.', style: TextStyle(color: Colors.grey.shade300)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // Pending approvals list (query users where approved == false)
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: firestore.collection('users').where('approved', isEqualTo: false).snapshots(),
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

                      final allDocs = snap.data?.docs ?? [];

                      // Client-side filter: show entries that are actually "pending"
                      // Show if:
                      //  - status == 'pending' or 'requested'
                      //  - OR approvalRequestedAt exists (user re-requested)
                      final pendingDocs = allDocs.where((d) {
                        final data = d.data() as Map<String, dynamic>;
                        final status = (data['status'] ?? '').toString().toLowerCase();
                        final hasRequest = data.containsKey('approvalRequestedAt') && data['approvalRequestedAt'] != null;
                        return status == 'pending' || status == 'requested' || hasRequest;
                      }).toList();

                      // optional: sort by approvalRequestedAt desc if available
                      pendingDocs.sort((a, b) {
                        final ad = (a.data() as Map<String, dynamic>)['approvalRequestedAt'] as Timestamp?;
                        final bd = (b.data() as Map<String, dynamic>)['approvalRequestedAt'] as Timestamp?;
                        final at = ad?.millisecondsSinceEpoch ?? 0;
                        final bt = bd?.millisecondsSinceEpoch ?? 0;
                        return bt.compareTo(at);
                      });

                      if (pendingDocs.isEmpty) {
                        return const Center(child: Text('No pending approval requests', style: TextStyle(color: Colors.white70)));
                      }

                      return ListView.separated(
                        padding: const EdgeInsets.only(bottom: 120),
                        itemCount: pendingDocs.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final doc = pendingDocs[i];
                          final data = doc.data() as Map<String, dynamic>;
                          final uid = doc.id;
                          final name = (data['displayName'] ?? data['name'] ?? '').toString();
                          final email = (data['email'] ?? '').toString();
                          final role = (data['role'] ?? 'seller').toString();
                          final ts = data['approvalRequestedAt'] as Timestamp?;
                          final requestedAt = ts != null ? ts.toDate() : null;
                          final requestedAtStr = requestedAt != null
                              ? '${requestedAt.year}-${requestedAt.month.toString().padLeft(2, '0')}-${requestedAt.day.toString().padLeft(2, '0')} ${requestedAt.hour.toString().padLeft(2, '0')}:${requestedAt.minute.toString().padLeft(2, '0')}'
                              : null;

                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
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
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        CircleAvatar(
                                          child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?'),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                name.isNotEmpty ? name : email,
                                                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              if (name.isNotEmpty)
                                                Text(
                                                  email,
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: const TextStyle(fontSize: 13, color: Colors.white70),
                                                ),
                                              const SizedBox(height: 6),
                                              Wrap(
                                                spacing: 8,
                                                runSpacing: 6,
                                                children: [
                                                  _metaPill('Role: $role'),
                                                  if (requestedAtStr != null) _metaPill(requestedAtStr, icon: Icons.access_time),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              tooltip: 'Approve',
                                              icon: const Icon(Icons.check_circle, color: Colors.greenAccent),
                                              onPressed: _canEditRoles ? () => _confirmApproveDialog(uid, email, role) : null,
                                            ),
                                            IconButton(
                                              tooltip: 'Reject',
                                              icon: const Icon(Icons.cancel, color: Colors.redAccent),
                                              onPressed: _canEditRoles ? () => _confirmRejectDialog(uid, email) : null,
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
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

            // ---------------------------
            // All Users tab (only approved users shown)
            // ---------------------------
            Column(
              children: [
                // Keep same quick promote UI here as well
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withOpacity(0.18)),
                        ),
                        child: Column(
                          children: [
                            LayoutBuilder(
                              builder: (ctx, constraints) {
                                final field = TextField(
                                  controller: _promoteEmailController,
                                  decoration: const InputDecoration(
                                    labelText: 'Email to change role (e.g. rkamonasish@gmail.com)',
                                  ),
                                );
                                final button = ElevatedButton(
                                  onPressed: _canEditRoles
                                      ? () async {
                                          final email = _promoteEmailController.text.trim();
                                          if (email.isEmpty) {
                                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Type an email first')));
                                            return;
                                          }
                                          final chosen = await showDialog<String?>(
                                            context: context,
                                            builder: (ctx) => AlertDialog(
                                              title: const Text('Choose role'),
                                              content: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: roles.map((r) {
                                                  return ListTile(
                                                    title: Text(r),
                                                    onTap: () => Navigator.pop(ctx, r),
                                                  );
                                                }).toList(),
                                              ),
                                            ),
                                          );
                                          if (chosen == null) return;
                                          await _setRoleByEmail(email, chosen);
                                        }
                                      : null,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _accent,
                                    foregroundColor: Colors.black,
                                  ),
                                  child: const Text('Set Role'),
                                );

                                final isNarrow = constraints.maxWidth < 420;
                                if (isNarrow) {
                                  return Column(
                                    children: [
                                      field,
                                      const SizedBox(height: 8),
                                      SizedBox(width: double.infinity, child: button),
                                    ],
                                  );
                                }
                                return Row(
                                  children: [
                                    Expanded(child: field),
                                    const SizedBox(width: 8),
                                    button,
                                  ],
                                );
                              },
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                icon: const Icon(Icons.star, size: 18, color: _accent),
                                label: const Text('Set rkamonasish@gmail.com as admin'),
                                onPressed: _canEditRoles
                                    ? () async {
                                        final ok = await showDialog<bool>(
                                          context: context,
                                          builder: (ctx) => AlertDialog(
                                            title: const Text('Confirm'),
                                            content: const Text('Set rkamonasish@gmail.com as admin?'),
                                            actions: [
                                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                              ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Yes')),
                                            ],
                                          ),
                                        );
                                        if (ok == true) {
                                          await _setRoleByEmail('rkamonasish@gmail.com', 'admin');
                                        }
                                      }
                                    : null,
                              ),
                            ),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text('Only Admin / Manager can change roles.', style: TextStyle(color: Colors.grey.shade300)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // All users list (only approved users shown)
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: firestore.collection('users').where('approved', isEqualTo: true).snapshots(), // show only approved users
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                      final docs = snap.data?.docs ?? [];
                      if (docs.isEmpty) return const Center(child: Text('No user records', style: TextStyle(color: Colors.white70)));

                      return ListView.separated(
                        padding: const EdgeInsets.only(bottom: 120),
                        itemCount: docs.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final doc = docs[i];
                          final data = doc.data() as Map<String, dynamic>;
                          final uid = doc.id;
                          final name = (data['displayName'] ?? data['name'] ?? '').toString();
                          final email = (data['email'] ?? '').toString();
                          final role = (data['role'] ?? 'seller').toString();

                          final isMe = currentUser != null && currentUser!.uid == uid;
                          String selectedRole = role;
                          final roleNorm = role.toLowerCase();

                          final tileColor = isMe ? Colors.white.withOpacity(0.12) : Colors.white.withOpacity(0.08);

                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: BackdropFilter(
                                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: tileColor,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: Colors.white.withOpacity(0.18)),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            CircleAvatar(child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?')),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    name.isNotEmpty ? name : email,
                                                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                  if (name.isNotEmpty)
                                                    Text(
                                                      email,
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: const TextStyle(fontSize: 13, color: Colors.white70),
                                                    ),
                                                ],
                                              ),
                                            ),
                                            IconButton(
                                              icon: const Icon(Icons.copy, size: 20, color: Colors.white70),
                                              tooltip: 'Copy UID',
                                              onPressed: () {
                                                Clipboard.setData(ClipboardData(text: uid));
                                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('UID copied')));
                                              },
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 6,
                                          children: [
                                            _metaPill('Role: $role'),
                                            if (isMe) _metaPill('You', icon: Icons.person),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: AbsorbPointer(
                                                absorbing: !_canEditRoles,
                                                child: DropdownButtonFormField<String>(
                                                  isExpanded: true,
                                                  value: selectedRole,
                                                  dropdownColor: _bgEnd,
                                                  style: const TextStyle(color: Colors.white),
                                                  items: roles.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                                                  onChanged: (val) {
                                                    if (val == null) return;
                                                    showDialog<bool>(
                                                      context: context,
                                                      builder: (ctx) => AlertDialog(
                                                        title: const Text('Confirm role change'),
                                                        content: Text('Change role for $email to \"$val\"?'),
                                                        actions: [
                                                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                                          ElevatedButton(
                                                            onPressed: () => Navigator.pop(ctx, true),
                                                            child: const Text('Yes'),
                                                          ),
                                                        ],
                                                      ),
                                                    ).then((confirmed) {
                                                      if (confirmed == true) {
                                                        _updateRole(uid, val, email);
                                                      }
                                                    });
                                                  },
                                                  decoration: InputDecoration(
                                                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                                    isDense: true,
                                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            IconButton(
                                              icon: const Icon(Icons.block, size: 20, color: Colors.redAccent),
                                              tooltip: roleNorm == 'admin'
                                                  ? 'Cannot revoke an admin (unless you are Admin)'
                                                  : 'Revoke approval (user will need approval again)',
                                              onPressed: (_canEditRoles && roleNorm != 'admin')
                                                  ? () => _confirmRevokeDialog(uid, email)
                                                  : (!_canEditRoles ? null : (_isAdmin ? () => _confirmRevokeDialog(uid, email) : null)),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
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
          ],
          ),
        ),
      ),
    ],
  ),
),
),
);
  }
}



