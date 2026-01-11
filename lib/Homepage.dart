// HomePage.dart
import 'dart:async';
import 'dart:io' show File;
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:jononipharmacy/BkashCustomerListPage.dart';
import 'package:jononipharmacy/PersonalPage.dart';
import 'package:jononipharmacy/bkash_page.dart';

import 'MedicineAdd.dart';
import 'companylistpage.dart';
import 'CustomerDueListPage.dart';
import 'DeveloperDetailsPage.dart';
import 'AdminPanelPage.dart';
import 'ExchangeDetailPage.dart';
import 'LowStockPage.dart';
import 'SellPage.dart';
import 'loginpage.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // admin email used for the small approve-button (lowercased)
  final String _adminEmail = 'rkamonasish@gmail.com';

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final User? user = FirebaseAuth.instance.currentUser;

  String? photoUrl;
  String currentUserRole = "seller";

  // subscription to users/{uid} doc to reflect role changes live
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userSub;

  // new: controller for top search bar
  final TextEditingController topSearchController = TextEditingController();

  @override
  void initState() {
    super.initState();

    _startUserListener();
    fetchCurrentUserRole();
  }

  @override
  void dispose() {
    topSearchController.dispose();
    _userSub?.cancel();
    super.dispose();
  }

  /// start listening to users/{uid} so role/photo updates are reflected immediately
  void _startUserListener() {
    if (user == null) return;
    final docRef = FirebaseFirestore.instance.collection('users').doc(user!.uid);
    _userSub?.cancel();
    _userSub = docRef.snapshots().listen((snap) {
      if (!mounted) return;
      if (snap.exists) {
        final m = snap.data();
        setState(() {
          // update role and photo if present in the doc
          if (m != null && m['role'] != null) {
            currentUserRole = m['role'].toString();
          }
          if (m != null && m['photoUrl'] != null) {
            photoUrl = m['photoUrl'].toString();
          }
        });
      }
    }, onError: (e) {
      debugPrint('user listener error: $e');
    });
  }

  /// Load user photo from Firestore (one-time fallback; listener will update afterward)
  Future<void> loadUserProfile() async {
    if (user == null) return;

    try {
      final doc = await FirebaseFirestore.instance.collection("users").doc(user!.uid).get();

      if (doc.exists) {
        setState(() {
          photoUrl = doc.data()?["photoUrl"];
        });
      } else {
        // If no doc, keep photoUrl null — user can set it via profile dialog
      }
    } catch (e) {
      // keep default avatar if Firestore read fails
      debugPrint('loadUserProfile error: $e');
    }
  }

  /// Load current user role — if the users/{uid} doc is missing, create it
  Future<void> fetchCurrentUserRole() async {
    if (user == null) return;
    final docRef = FirebaseFirestore.instance.collection('users').doc(user!.uid);

    try {
      final doc = await docRef.get();

      if (doc.exists) {
        final map = doc.data();
        setState(() {
          currentUserRole = (map?['role'] ?? 'seller').toString();
          photoUrl = (map?['photoUrl'] ?? photoUrl)?.toString();
        });
      } else {
        // create a users/{uid} doc for this auth user so role & rules work
        const adminEmail = 'rkamonasish@gmail.com';
        final role = (user!.email?.toLowerCase() == adminEmail) ? 'admin' : 'seller';

        await docRef.set({
          'email': user!.email ?? '',
          'name': user!.displayName ?? '',
          'role': role,
          'photoUrl': photoUrl ?? '',
          'approved': false, // NEW: require admin approval
          'createdAt': FieldValue.serverTimestamp(),
        });

        setState(() {
          currentUserRole = role;
        });

        debugPrint('Created users/${user!.uid} with role $role');
      }
    } catch (e) {
      // If anything fails, fallback to seller and keep app functional.
      debugPrint('fetchCurrentUserRole error: $e');
      setState(() {
        currentUserRole = 'seller';
      });
    }
  }

  /// Normalize role strings to a canonical form:
  /// - lowercased
  /// - spaces/hyphens collapsed to underscores
  /// This accepts "senior seller", "senior_seller", "Senior-Seller" equally.
  String _normalizeRole(String? role) {
    if (role == null) return '';
    return role.toLowerCase().replaceAll(RegExp(r'[\s\-]+'), '_').trim();
  }

  /// helper: returns true if user is admin or manager
  bool get _isAdminOrManager {
    final nr = _normalizeRole(currentUserRole);
    return nr == 'admin' || nr == 'manager';
  }

  /// helper: returns true for limited roles which must be blocked from certain pages
  bool get _isLimitedRole {
    final nr = _normalizeRole(currentUserRole);
    return nr == 'assistant_manager' || nr == 'senior_seller' || nr == 'seller';
  }

  /// Access check helper for known page keys:
  /// - 'bkash_customer' -> BkashCustomerListPage
  /// - 'personal' -> PersonalPage
  /// all other pages return true for the limited roles.
  bool canAccess(String pageKey) {
    if (_isAdminOrManager) return true; // full access
    if (_isLimitedRole) {
      // restricted for limited roles
      if (pageKey == 'bkash_customer' || pageKey == 'personal') return false;
      return true; // allowed for other pages
    }
    // default allow (if role unknown)
    return true;
  }

  Future<void> _showAccessDeniedDialog(String title) async {
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Access denied'),
        content: Text('You do not have permission to open "$title". Please ask an admin or manager.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ],
      ),
    );
  }

  /// Random avatar (stable per user)
  String randomAvatar(String uid) {
    return "https://api.dicebear.com/7.x/personas/png?seed=$uid";
  }

  ImageProvider profileImage() {
    if (photoUrl != null && photoUrl!.isNotEmpty) {
      return NetworkImage(photoUrl!);
    } else if (user != null) {
      return NetworkImage(randomAvatar(user!.uid));
    } else {
      return const AssetImage('assets/default_avatar.png') as ImageProvider;
    }
  }

  /// Open profile dialog where user can change name and photo
  Future<void> _openProfileDialog() async {
    if (user == null) return;

    final usersRef = FirebaseFirestore.instance.collection('users').doc(user!.uid);
    String initialName = user!.displayName ?? "Admin User";
    // Attempt to read stored name from users doc as well
    try {
      final doc = await usersRef.get();
      if (doc.exists) {
        final map = doc.data();
        if (map != null && (map['name'] as String?)?.isNotEmpty == true) {
          initialName = map['name'];
        }
      }
    } catch (_) {}

    final nameController = TextEditingController(text: initialName);
    String? localPreview = photoUrl;
    bool uploading = false;

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (context, setState) {
          // -------------------- Cloudinary unsigned upload --------------------
          // Cloudinary config: change upload preset name below to your unsigned preset name
          const String _cloudName = 'dyvr2h7qc';
          const String _uploadPreset = 'profile_unsigned'; // <- replace with your unsigned preset name

          Future<void> pickAndUploadImage() async {
            try {
              setState(() => uploading = true);

              if (kIsWeb) {
                // Web: use file_picker to get bytes
                final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true, allowMultiple: false);
                if (result == null || result.files.isEmpty) {
                  setState(() => uploading = false);
                  return;
                }
                final platformFile = result.files.first;
                final bytes = platformFile.bytes;
                final filename = platformFile.name;

                if (bytes == null) {
                  setState(() => uploading = false);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to read selected file.')));
                  return;
                }

                final uri = Uri.parse('https://api.cloudinary.com/v1_1/$_cloudName/image/upload');
                final request = http.MultipartRequest('POST', uri);
                request.fields['upload_preset'] = _uploadPreset;
                request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));

                final streamedResponse = await request.send();
                final resp = await http.Response.fromStream(streamedResponse);

                if (resp.statusCode == 200) {
                  final data = json.decode(resp.body) as Map<String, dynamic>;
                  localPreview = data['secure_url'] as String?;
                  setState(() => uploading = false);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Photo uploaded')));
                } else {
                  debugPrint('Cloudinary web upload failed: ${resp.statusCode} ${resp.body}');
                  setState(() => uploading = false);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload failed: ${resp.statusCode}')));
                }
              } else {
                // Mobile: use image_picker and upload file path
                final ImagePicker picker = ImagePicker();
                final XFile? picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
                if (picked == null) {
                  setState(() => uploading = false);
                  return;
                }

                final file = File(picked.path);
                final uri = Uri.parse('https://api.cloudinary.com/v1_1/$_cloudName/image/upload');
                final request = http.MultipartRequest('POST', uri);
                request.fields['upload_preset'] = _uploadPreset;
                request.files.add(await http.MultipartFile.fromPath('file', file.path));

                final streamedResponse = await request.send();
                final resp = await http.Response.fromStream(streamedResponse);

                if (resp.statusCode == 200) {
                  final data = json.decode(resp.body) as Map<String, dynamic>;
                  localPreview = data['secure_url'] as String?;
                  setState(() => uploading = false);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Photo uploaded')));
                } else {
                  debugPrint('Cloudinary mobile upload failed: ${resp.statusCode} ${resp.body}');
                  setState(() => uploading = false);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload failed: ${resp.statusCode}')));
                }
              }
            } catch (e, st) {
              debugPrint('Cloudinary upload error: $e\n$st');
              setState(() => uploading = false);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Photo upload failed: $e")));
            }
          }
          // -------------------- end Cloudinary upload --------------------

          Future<void> setPhotoFromUrl() async {
            final ctrl = TextEditingController(text: localPreview ?? '');
            final ok = await showDialog<bool>(
              context: context,
              builder: (dialogCtx) {
                return AlertDialog(
                  title: const Text('Photo URL'),
                  content: TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'Image URL')),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(dialogCtx, false), child: const Text('Cancel')),
                    TextButton(onPressed: () => Navigator.pop(dialogCtx, true), child: const Text('Set')),
                  ],
                );
              },
            );

            if (ok == true) {
              final url = ctrl.text.trim();
              if (url.isNotEmpty) {
                setState(() => localPreview = url);
              }
            }
          }

          return AlertDialog(
            title: const Text('Profile'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 40,
                    backgroundImage: (localPreview != null && localPreview!.isNotEmpty) ? NetworkImage(localPreview!) : profileImage(),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Display name'),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        icon: const Icon(Icons.photo_camera),
                        label: const Text('Pick photo'),
                        onPressed: uploading ? null : () => pickAndUploadImage(),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.link),
                        label: const Text('Use URL'),
                        onPressed: uploading ? null : () => setPhotoFromUrl(),
                      ),
                    ],
                  ),
                  if (uploading) ...[
                    const SizedBox(height: 12),
                    const LinearProgressIndicator(),
                    const SizedBox(height: 6),
                    const Text('Uploading photo...'),
                  ],
                  const SizedBox(height: 8),
                  const Text('Tip: you can paste an image URL if device upload isn\'t available.'),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () async {
                  final newName = nameController.text.trim().isEmpty ? "Admin User" : nameController.text.trim();

                  try {
                    // Update FirebaseAuth displayName if different
                    if ((user!.displayName ?? '') != newName) {
                      await user!.updateDisplayName(newName);
                    }

                    final updateData = <String, dynamic>{
                      'name': newName,
                      'photoUrl': localPreview ?? '',
                      'updatedAt': FieldValue.serverTimestamp(),
                    };

                    // ensure the users doc exists (merge)
                    await usersRef.set(updateData, SetOptions(merge: true));

                    // update local state
                    setState(() {
                      photoUrl = localPreview;
                    });

                    // listener will pick up doc changes; still call these to be safe
                    await loadUserProfile();
                    await fetchCurrentUserRole();

                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile updated')));
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to update profile: $e')));
                  }
                },
                child: const Text('Save'),
              ),
            ],
          );
        });
      },
    );
  }

  /// Toggle (or set) the `approved` flag for a user identified by email.
  /// Returns a message describing result.
  Future<String> _toggleApprovalForEmail(String targetEmail) async {
    final firestore = FirebaseFirestore.instance;
    final q = await firestore.collection('users').where('email', isEqualTo: targetEmail.toLowerCase()).limit(1).get();

    if (q.docs.isEmpty) {
      return 'No user found with email: $targetEmail';
    }

    final doc = q.docs.first;
    final docRef = firestore.collection('users').doc(doc.id);
    final data = doc.data();
    final currently = (data['approved'] == true);

    await docRef.set({'approved': !currently, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
    return 'User ${data['email'] ?? doc.id} approved=${!currently}';
  }

  /// Show a dialog (admin only) to enter an email and toggle approval
  Future<void> _showApproveUserDialog() async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) {
        bool loading = false;
        return StatefulBuilder(builder: (c, setState) {
          return AlertDialog(
            title: const Text('Approve / Revoke user'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Enter user email to approve or revoke approval:'),
                TextField(controller: ctrl, decoration: const InputDecoration(hintText: 'user@example.com')),
                if (loading) const SizedBox(height: 12),
                if (loading) const CircularProgressIndicator(),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: loading ? null : () async {
                  final email = ctrl.text.trim().toLowerCase();
                  if (email.isEmpty) return;
                  setState(() => loading = true);
                  try {
                    final msg = await _toggleApprovalForEmail(email);
                    Navigator.pop(ctx, msg);
                  } catch (e) {
                    Navigator.pop(ctx, 'Error: $e');
                  }
                },
                child: const Text('Toggle'),
              ),
            ],
          );
        });
      },
    );

    if (result != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result)));
    }
  }

  /// Request approval (sets a timestamp field; admin can review)
  Future<void> _requestApproval() async {
    if (user == null) return;
    final docRef = FirebaseFirestore.instance.collection('users').doc(user!.uid);
    try {
      await docRef.set({'approvalRequestedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Approval requested — admin will review.')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Request failed: $e')));
    }
  }

  /// Open a dialog to pick or create a pharmacy, then navigate to ExchangeDetailPage
  Future<void> openExchangePharmacyPicker(BuildContext context) async {
    final firestore = FirebaseFirestore.instance;
    final controller = TextEditingController();
    bool creating = false;

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (context, setState) {
          // Query stream: if search text empty -> all; else prefix search on nameLower
          Stream<QuerySnapshot> streamForQuery() {
            final q = controller.text.trim().toLowerCase();
            final col = firestore.collection('pharmacies');
            if (q.isEmpty) {
              return col.orderBy('nameLower').limit(200).snapshots();
            } else {
              return col
                  .orderBy('nameLower')
                  .startAt([q])
                  .endAt([q + '\uf8ff'])
                  .limit(200)
                  .snapshots();
            }
          }

          return AlertDialog(
            title: const Text("Select Pharmacy"),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: controller,
                    decoration: const InputDecoration(
                      hintText: "Search or type a pharmacy name",
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 300,
                    child: StreamBuilder<QuerySnapshot>(
                      stream: streamForQuery(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        final docs = snapshot.data?.docs ?? [];
                        // if no results show helpful message
                        if (docs.isEmpty) {
                          return Center(
                            child: Text(
                              controller.text.trim().isEmpty
                                  ? "No pharmacies yet. Type a name above and press Create New."
                                  : "No matches for \"${controller.text.trim()}\". You can create it.",
                              textAlign: TextAlign.center,
                            ),
                          );
                        }

                        return ListView.builder(
                          itemCount: docs.length,
                          itemBuilder: (_, i) {
                            final d = docs[i];
                            final data = d.data() as Map<String, dynamic>;
                            final name = (data['name'] ?? '').toString();
                            return ListTile(
                              title: Text(name),
                              subtitle: Text("ID: ${d.id}"),
                              onTap: () {
                                Navigator.pop(context); // close dialog
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ExchangeDetailPage(
                                      pharmacyId: d.id,
                                      pharmacyName: name,
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text("Close")),
              TextButton(
                onPressed: creating
                    ? null
                    : () async {
                  final name = controller.text.trim();
                  if (name.isEmpty) {
                    // show small hint
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Type a pharmacy name to create.")));
                    return;
                  }

                  setState(() => creating = true);

                  try {
                    final nameLower = name.toLowerCase();

                    // check if exists
                    final existsQ = await firestore.collection('pharmacies').where('nameLower', isEqualTo: nameLower).limit(1).get();

                    if (existsQ.docs.isNotEmpty) {
                      // already exists -> open it
                      final doc = existsQ.docs.first;
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ExchangeDetailPage(
                            pharmacyId: doc.id,
                            pharmacyName: (doc.data() as Map<String, dynamic>)['name'] ?? name,
                          ),
                        ),
                      );
                    } else {
                      // create new pharmacy doc
                      final newDocRef = await firestore.collection('pharmacies').add({
                        'name': name,
                        'nameLower': nameLower,
                        'totalDue': 0,
                        'createdAt': FieldValue.serverTimestamp(),
                      });

                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ExchangeDetailPage(
                            pharmacyId: newDocRef.id,
                            pharmacyName: name,
                          ),
                        ),
                      );
                    }
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
                  } finally {
                    if (mounted) setState(() => creating = false);
                  }
                },
                child: creating ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator()) : const Text("Create New"),
              ),
            ],
          );
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // If no authenticated user, return original scaffold (shouldn't normally happen)
    if (user == null) {
      return Scaffold(
        key: _scaffoldKey,
        backgroundColor: const Color(0xFF01684D),
        body: const Center(child: Text('Not signed in', style: TextStyle(color: Colors.white))),
      );
    }

    // Listen to live user doc so role changes reflect immediately
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('users').doc(user!.uid).snapshots(),
      builder: (context, snap) {
        // Defaults to current cached values (so we don't break behavior)
        String liveRole = currentUserRole;
        String? livePhoto = photoUrl;
        bool liveApproved = true; // default to true if field not present (so existing users keep access)

        if (snap.hasData && snap.data!.exists) {
          final data = snap.data!.data();
          if (data != null) {
            if (data['role'] != null) liveRole = data['role'].toString();
            if (data['photoUrl'] != null) livePhoto = data['photoUrl'].toString();
            if (data.containsKey('approved')) liveApproved = (data['approved'] == true);
          }
        }

        // If user is NOT approved, and is not admin/manager (and not the admin email),
        // block the whole app and show an "Awaiting approval" page.
        final normalized = _normalizeRole(liveRole);
        final isAdminOrManager = (normalized == 'admin' || normalized == 'manager') || (user?.email?.toLowerCase() == _adminEmail);

        if (!liveApproved && !isAdminOrManager) {
          // Blocked UI
          return Scaffold(
            key: _scaffoldKey,
            backgroundColor: const Color(0xFF01684D),
            appBar: AppBar(
              systemOverlayStyle: SystemUiOverlayStyle.light,
              centerTitle: true,
              elevation: 0,
              backgroundColor: const Color(0xFF01684D),
              title: const Text("Jononi Pharmacy - Awaiting approval"),
            ),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.hourglass_top, size: 84, color: Colors.white70),
                    const SizedBox(height: 16),
                    const Text(
                      "Your account is awaiting admin approval.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      "An administrator must approve your account before you can use the app. "
                          "You will not be able to navigate to other pages until approval.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 18),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.refresh),
                      label: const Text("Request approval (notify admin)"),
                      onPressed: _requestApproval,
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () async {
                        await FirebaseAuth.instance.signOut();
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(builder: (_) => loginpage()),
                              (route) => false,
                        );
                      },
                      child: const Text("Logout", style: TextStyle(color: Colors.white70)),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      "If you think this is a mistake contact: $_adminEmail",
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white60, fontSize: 12),
                    )
                  ],
                ),
              ),
            ),
          );
        }

        // local access checker using liveRole & liveApproved
        bool localCanAccess(String pageKey) {
          if (!liveApproved) return false; // optional: require 'approved' true if present
          final nr = _normalizeRole(liveRole);
          if (nr == 'admin' || nr == 'manager') return true;
          if (nr == 'assistant_manager' || nr == 'senior_seller' || nr == 'seller') {
            if (pageKey == 'bkash_customer' || pageKey == 'personal') return false;
            return true;
          }
          return true;
        }

        // use livePhoto for drawer/profile avatar (if available), else fallback to profileImage()
        final avatarImage = (livePhoto != null && livePhoto.isNotEmpty) ? NetworkImage(livePhoto) : profileImage();

        // Build UI (keeps everything same as your original layout)
        return Scaffold(
          key: _scaffoldKey,
          backgroundColor: const Color(0xFF01684D),

          /// Drawer
          drawer: Drawer(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                UserAccountsDrawerHeader(
                  decoration: const BoxDecoration(
                    color: Color(0xFF01684D),
                  ),
                  currentAccountPicture: CircleAvatar(
                    backgroundImage: avatarImage,
                  ),
                  accountName: Text(user?.displayName ?? "User Name"),
                  accountEmail: Text("${user?.email ?? ""}\nRole: ${liveRole.toUpperCase()}"),
                ),

                // Main user options
                // Profile now opens profile dialog
                drawerItem(Icons.person, "Profile", () {
                  Navigator.pop(context); // close drawer
                  _openProfileDialog();
                }),
                drawerItem(Icons.settings, "Settings"),
                drawerItem(Icons.help, "Help"),
                const Divider(),

                // Admin Panel Section
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Text(
                    "Admin Panel",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ),
                drawerItem(Icons.dashboard, "Admin Panel", () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminPanelPage()));
                }),
                drawerItem(Icons.medical_services, "Medicine Control", () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => MedicineAddPage()));
                }),
                drawerItem(Icons.report, "Reports"),
                const Divider(),

                // Developer Details Section
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Text(
                    "Developer Details",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ),
                drawerItem(Icons.person, "Developer Details", () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const DeveloperDetailsPage()));
                }),
                const Divider(),

                // Logout
                drawerItem(Icons.logout, "Logout", () async {
                  // Close drawer first
                  Navigator.pop(context);

                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      title: const Text('Logout'),
                      content: const Text('Are you sure you want to logout?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext, false),
                          child: const Text('Cancel'),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(dialogContext, true),
                          child: const Text('Logout'),
                        ),
                      ],
                    ),
                  );

                  if (confirmed != true) return;

                  await FirebaseAuth.instance.signOut();

                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => loginpage()),
                        (route) => false,
                  );
                })
              ],
            ),
          ),

          /// AppBar
          appBar: AppBar(
            systemOverlayStyle: SystemUiOverlayStyle.light,
            centerTitle: true,
            elevation: 0,
            backgroundColor: const Color(0xFF01684D),

            // Profile (left)
            leading: InkWell(
              onTap: () {
                _scaffoldKey.currentState!.openDrawer();
              },
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: CircleAvatar(
                  backgroundImage: avatarImage,
                ),
              ),
            ),

            // Title + Role
            title: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "Jononi Pharmacy",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                Text(
                  liveRole.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),

          /// Body
          body: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                // Search Bar (now wired to topSearchController)
                Container(
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 8),
                      const Icon(Icons.search, color: Colors.black54),
                      const SizedBox(width: 6),
                      Expanded(
                        child: TextField(
                          controller: topSearchController,
                          decoration: const InputDecoration(
                            hintText: "Search medicine name, price, stock...",
                            border: InputBorder.none,
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      if (topSearchController.text.isNotEmpty)
                        IconButton(
                          icon: const Icon(Icons.clear, color: Colors.black54),
                          onPressed: () => setState(() => topSearchController.clear()),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 70),

                // If search text is non-empty, show medicine search results (name, price, stock).
                // Otherwise show the original Menu Grid (unchanged).
                Expanded(
                  child: topSearchController.text.trim().isNotEmpty
                      ? _buildMedicineSearchResults(topSearchController.text.trim())
                      : GridView.count(
                    crossAxisCount: 3,
                    mainAxisSpacing: 20,
                    crossAxisSpacing: 12,
                    children: [
                      // Sell
                      InkWell(
                        onTap: () {
                          if (!localCanAccess('sell')) {
                            _showAccessDeniedDialog('Sell');
                            return;
                          }
                          Navigator.push(context, MaterialPageRoute(builder: (_) => const SellPage()));
                        },
                        child: const MenuCard(Icons.shopping_cart, "Sell"),
                      ),

                      // bKash (main page, allowed for all)
                      InkWell(
                        onTap: () {
                          if (!localCanAccess('bkash')) {
                            _showAccessDeniedDialog('bKash');
                            return;
                          }
                          Navigator.push(context, MaterialPageRoute(builder: (_) => const BkashPage()));
                        },
                        child: const MenuCard(Icons.account_balance_wallet, "bKash"),
                      ),

                      // Due List
                      InkWell(
                        onTap: () {
                          if (!localCanAccess('due_list')) {
                            _showAccessDeniedDialog('Due List');
                            return;
                          }
                          Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomerDueListPage()));
                        },
                        child: const MenuCard(Icons.list_alt, "Due List"),
                      ),

                      // Add Medicine
                      InkWell(
                        onTap: () {
                          if (!localCanAccess('add_medicine')) {
                            _showAccessDeniedDialog('Add Medicine');
                            return;
                          }
                          Navigator.push(context, MaterialPageRoute(builder: (_) => MedicineAddPage()));
                        },
                        child: const MenuCard(Icons.add_box, "Add Medicine"),
                      ),

                      // Order List
                      InkWell(
                        onTap: () {
                          if (!localCanAccess('order_list')) {
                            _showAccessDeniedDialog('Order List');
                            return;
                          }
                          Navigator.push(context, MaterialPageRoute(builder: (_) => const CompanyListPage()));
                        },
                        child: const MenuCard(Icons.inventory, "Order List"),
                      ),

                      // Low Item
                      InkWell(
                        onTap: () {
                          if (!localCanAccess('low_item')) {
                            _showAccessDeniedDialog('Low Item');
                            return;
                          }
                          Navigator.push(context, MaterialPageRoute(builder: (_) => const LowStockPage()));
                        },
                        child: const MenuCard(Icons.warning, "Low Item"),
                      ),

                      // Borrow Item (Exchange)
                      InkWell(
                        onTap: () {
                          if (!localCanAccess('borrow_item')) {
                            _showAccessDeniedDialog('Borrow Item');
                            return;
                          }
                          openExchangePharmacyPicker(context);
                        },
                        child: const MenuCard(Icons.handshake, "Borrow Item"),
                      ),

                      // Bkash Customer (RESTRICTED)
                      Builder(builder: (ctx) {
                        final allowed = localCanAccess('bkash_customer');
                        return InkWell(
                          onTap: () {
                            if (!allowed) {
                              _showAccessDeniedDialog('Bkash Customer');
                              return;
                            }
                            Navigator.push(context, MaterialPageRoute(builder: (_) => const BkashCustomerListPage()));
                          },
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              const MenuCard(Icons.account_balance, "Bkash Customer"),
                              if (!allowed)
                                Container(
                                  color: Colors.black.withOpacity(0.45),
                                ),
                              if (!allowed)
                                const Center(child: Icon(Icons.lock, color: Colors.white70, size: 28)),
                            ],
                          ),
                        );
                      }),

                      // Personal (RESTRICTED)
                      Builder(builder: (ctx) {
                        final allowed = localCanAccess('personal');
                        return InkWell(
                          onTap: () {
                            if (!allowed) {
                              _showAccessDeniedDialog('Personal');
                              return;
                            }
                            Navigator.push(context, MaterialPageRoute(builder: (_) => const PersonalPage()));
                          },
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              const MenuCard(Icons.personal_injury, "Personal"),
                              if (!allowed)
                                Container(
                                  color: Colors.black.withOpacity(0.45),
                                ),
                              if (!allowed)
                                const Center(child: Icon(Icons.lock, color: Colors.white70, size: 28)),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMedicineSearchResults(String query) {
    final q = query.toLowerCase();

    // Use a live stream ordered by medicineNameLower (normalized) so updates are visible and consistent.
    // We'll filter client-side for case-insensitive prefix match, then
    // group by medicineNameLower and keep the most appropriate doc per name.
    final stream = FirebaseFirestore.instance
        .collection('medicines')
        .orderBy('medicineNameLower')
        .limit(500)
        .snapshots();

    return StreamBuilder<QuerySnapshot>(
      stream: stream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        final allDocs = snap.data?.docs ?? [];

        // client-side filter (case-insensitive prefix) using normalized fields when available
        final matching = allDocs.where((d) {
          final data = d.data() as Map<String, dynamic>;
          final nameLower = (data['medicineNameLower'] ?? (data['medicineName'] ?? '')).toString().toLowerCase();
          return nameLower.startsWith(q);
        }).toList();

        if (matching.isEmpty) {
          return const Center(child: Text('No medicines found', style: TextStyle(color: Colors.white70)));
        }

        // Group by medicineNameLower and pick the best doc per name.
        // Selection priority:
        // 1) larger updatedAt/createdAt timestamp
        // 2) if timestamps equal or missing, prefer the doc with larger quantity/stock
        final Map<String, QueryDocumentSnapshot> bestByName = {};
        for (final d in matching) {
          final data = d.data() as Map<String, dynamic>;
          final nameLower = (data['medicineNameLower'] ?? (data['medicineName'] ?? '')).toString().toLowerCase();

          // prefer updatedAt then createdAt
          Timestamp? updated = (data['updatedAt'] as Timestamp?) ?? (data['createdAt'] as Timestamp?);
          final int ts = (updated?.millisecondsSinceEpoch ?? 0);

          if (!bestByName.containsKey(nameLower)) {
            bestByName[nameLower] = d;
          } else {
            final existing = bestByName[nameLower]!;
            final existingData = existing.data() as Map<String, dynamic>;
            Timestamp? exUpdated = (existingData['updatedAt'] as Timestamp?) ?? (existingData['createdAt'] as Timestamp?);
            final int exTs = (exUpdated?.millisecondsSinceEpoch ?? 0);

            if (ts > exTs) {
              bestByName[nameLower] = d;
            } else if (ts == exTs) {
              // tie-breaker: prefer higher quantity/stock
              final currQtyRaw = data['quantity'] ?? data['stock'] ?? data['qty'] ?? 0;
              final existQtyRaw = existingData['quantity'] ?? existingData['stock'] ?? existingData['qty'] ?? 0;
              final int currQty = (currQtyRaw is num) ? currQtyRaw.toInt() : int.tryParse(currQtyRaw.toString()) ?? 0;
              final int existQty = (existQtyRaw is num) ? existQtyRaw.toInt() : int.tryParse(existQtyRaw.toString()) ?? 0;
              if (currQty >= existQty) {
                bestByName[nameLower] = d;
              }
            }
            // else keep existing
          }
        }

        final results = bestByName.values.toList()
          ..sort((a, b) {
            final an = (a.data() as Map<String, dynamic>)['medicineName'] ?? '';
            final bn = (b.data() as Map<String, dynamic>)['medicineName'] ?? '';
            return an.toString().toLowerCase().compareTo(bn.toString().toLowerCase());
          });

        return ListView.separated(
          padding: const EdgeInsets.only(bottom: 120),
          itemCount: results.length,
          separatorBuilder: (_, __) => const Divider(color: Colors.white24),
          itemBuilder: (_, i) {
            final d = results[i];
            final data = d.data() as Map<String, dynamic>;
            final name = (data['medicineName'] ?? data['medicineNameLower'] ?? '').toString();
            final price = (data['price'] ?? 0).toString();
            // prefer 'quantity' then 'stock' then 'qty'
            final stockVal = data['quantity'] ?? data['stock'] ?? data['qty'] ?? 0;
            final stock = (stockVal is num) ? stockVal.toString() : stockVal.toString();
            return Card(
              color: Colors.white.withOpacity(0.06),
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: ListTile(
                title: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: Text('Price: ৳$price • Stock: $stock', style: const TextStyle(color: Colors.white70)),
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: Text(name),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Price: ৳$price'),
                          const SizedBox(height: 6),
                          Text('Stock: $stock'),
                          const SizedBox(height: 6),
                          Text('ID: ${d.id}'),
                        ],
                      ),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
                      ],
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  // Drawer item helper
  static Widget drawerItem(IconData icon, String title, [VoidCallback? onTap]) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      onTap: onTap ?? () {},
    );
  }
}

/// Menu Card
class MenuCard extends StatelessWidget {
  final IconData icon;
  final String title;

  const MenuCard(this.icon, this.title, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 6,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 36, color: const Color(0xFF01684D)),
          const SizedBox(height: 8),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
