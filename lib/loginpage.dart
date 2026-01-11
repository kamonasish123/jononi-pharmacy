// loginpage.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:jononipharmacy/registerpage.dart';
import 'Homepage.dart';

class loginpage extends StatefulWidget {
  @override
  State<loginpage> createState() => _loginpageState();
}

class _loginpageState extends State<loginpage> {
  final TextEditingController emailcontroler = TextEditingController();
  final TextEditingController passwordcontroller = TextEditingController();

  bool isChecked = false;
  bool _obscure = true;

  @override
  void dispose() {
    emailcontroler.dispose();
    passwordcontroller.dispose();
    super.dispose();
  }

  Future<void> _showLoadingDialog(BuildContext ctx, {String message = 'Please wait...'}) async {
    showDialog(
      context: ctx,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
  }

  Future<void> _showInfoDialog(BuildContext ctx, {required String title, required String message, List<Widget>? actions}) async {
    await showDialog(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: actions ??
            [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('OK'),
              )
            ],
      ),
    );
  }

  bool _looksLikeEmail(String s) {
    // Simple heuristic — keep it light (don't change UI)
    return s.contains('@') && s.contains('.');
  }

  /// Write/merge an approval request for the user so admin can easily find & approve.
  /// Returns true on success.
  Future<bool> _sendApprovalRequest({required String uid, required String email, String? name}) async {
    try {
      final ref = FirebaseFirestore.instance.collection('approval_requests').doc(uid);
      await ref.set({
        'uid': uid,
        'email': email,
        'name': name ?? '',
        'status': 'pending',
        'lastRequestedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Also update the users/{uid} doc so AdminPanel sees the pending request immediately:
      final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
      await userRef.set({
        'status': 'pending',
        'approvalRequestedAt': FieldValue.serverTimestamp(),
        'approved': false, // ensure they remain unapproved
      }, SetOptions(merge: true));

      // optional small feedback
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Admin notified of approval request'),
          backgroundColor: Colors.green,
        ));
      }
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to notify admin: $e')));
      }
      return false;
    }
  }

  /// Nice pending-approval dialog with a "Notify Admin" button.
  /// This dialog *does not* sign the user out until notify completes; after notify completes we sign out.
  Future<void> _showPendingDialog({required String uid, required String email, String? name}) async {
    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Row(children: const [
            Icon(Icons.hourglass_top, color: Colors.orange),
            SizedBox(width: 8),
            Text('Account pending approval')
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Your account has been created and is waiting for admin approval.'),
              const SizedBox(height: 8),
              const Text('You cannot enter sensitive pages until an admin approves your account.'),
              const SizedBox(height: 12),
              Text('Email: $email'),
              if (name != null && name.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text('Name: $name'),
              ],
            ],
          ),
          actions: [
            // Close -> sign the user out (we keep behavior similar to previous)
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                // sign out to avoid leaving an unapproved session active
                try {
                  await FirebaseAuth.instance.signOut();
                } catch (_) {}
              },
              child: const Text('Close'),
            ),

            // Notify Admin -> attempt to write approval_requests then sign out
            ElevatedButton.icon(
              icon: const Icon(Icons.notification_add),
              label: const Text('Notify Admin'),
              onPressed: () async {
                // Close the dialog and show loading while notifying
                Navigator.of(ctx).pop();
                _showLoadingDialog(context, message: 'Notifying admin...');

                final ok = await _sendApprovalRequest(uid: uid, email: email, name: name);

                // remove loading
                Navigator.of(context).pop();

                // After notify attempt, sign out to match previous "not allowed" behaviour
                try {
                  await FirebaseAuth.instance.signOut();
                } catch (_) {}

                if (ok) {
                  // Optionally show a confirmation dialog
                  await _showInfoDialog(context,
                      title: 'Requested',
                      message: 'Admin has been notified. You will be able to login after approval.');
                } else {
                  await _showInfoDialog(context,
                      title: 'Failed',
                      message: 'Failed to notify admin. Please try again later.');
                }
              },
            )
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: const Color(0xFF01684D),

      // Keep keyboard-safe padding and SafeArea
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: h * 0.04),

              // Logo (responsive)
              Center(
                child: ClipOval(
                  child: Container(
                    width: h * 0.24,
                    height: h * 0.24,
                    color: Colors.white, // ✅ logo background color
                    child: Image.asset(
                      'assets/images/logofile.png',
                      fit: BoxFit.contain, // ✅ important
                    ),
                  ),
                ),
              ),


              SizedBox(height: h * 0.035),

              // EMAIL LABEL
              Container(
                margin: const EdgeInsets.only(left: 30),
                width: 200,
                padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFB83257),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  "Email Address",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),

              const SizedBox(height: 6),

              // EMAIL FIELD
              Container(
                margin: const EdgeInsets.only(left: 26, right: 25),
                child: TextField(
                  controller: emailcontroler,
                  style: const TextStyle(color: Colors.white, fontSize: 20),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.1),
                    hintText: "Enter your email",
                    hintStyle: const TextStyle(color: Colors.black),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Colors.black, width: 4),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Colors.red, width: 4),
                    ),
                  ),
                ),
              ),

              SizedBox(height: h * 0.015),

              // PASSWORD LABEL
              Container(
                margin: const EdgeInsets.only(left: 30),
                width: 200,
                padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFB83257),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  "Password",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),

              const SizedBox(height: 6),

              // PASSWORD FIELD
              Container(
                margin: const EdgeInsets.only(left: 26, right: 25),
                child: TextField(
                  controller: passwordcontroller,
                  obscureText: _obscure,
                  obscuringCharacter: "*",
                  style: const TextStyle(color: Colors.white, fontSize: 20),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.1),
                    hintText: "Enter your password",
                    hintStyle: const TextStyle(color: Colors.black),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscure ? Icons.visibility_off : Icons.visibility,
                        color: Colors.black,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscure = !_obscure;
                        });
                      },
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Colors.black, width: 4),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Colors.red, width: 4),
                    ),
                  ),
                ),
              ),

              SizedBox(height: h * 0.025),

              // LOGIN BUTTON
              Center(
                child: ElevatedButton(
                  onPressed: () async {
                    String email = emailcontroler.text.trim();
                    String password = passwordcontroller.text.trim();

                    if (email.isEmpty || password.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            "Email and password cannot be empty",
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }

                    try {
                      // 1️⃣ Sign in
                      final cred = await FirebaseAuth.instance
                          .signInWithEmailAndPassword(
                        email: email,
                        password: password,
                      );

                      // 2️⃣ Check approval
                      final uid = cred.user!.uid;
                      final snap = await FirebaseFirestore.instance
                          .collection('users')
                          .doc(uid)
                          .get();
                      final data = snap.data();
                      final role = data?['role'];
                      final approved = data?['approved'] == true;

                      // ✅ Admin always allowed
                      final canLogin = role == 'admin' || approved;

                      if (!canLogin) {
                        // Show nicer dialog that allows the user to notify admin.
                        await _showPendingDialog(uid: uid, email: email, name: data?['name']?.toString());
                        return;
                      }

                      // If role is admin but approved missing/false, ensure approved true on their doc
                      if (role == 'admin' && !approved) {
                        try {
                          await FirebaseFirestore.instance.collection('users').doc(uid).set({'approved': true}, SetOptions(merge: true));
                        } catch (_) {
                          // ignore failure to update; admin will still be allowed
                        }
                      }

                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (_) => HomePage()),
                      );
                    } on FirebaseAuthException catch (e) {
                      String message;

                      if (e.code == 'invalid-credential') {
                        message = "Incorrect email or password";
                      } else if (e.code == 'user-not-found') {
                        message = "No user found for this email";
                      } else if (e.code == 'wrong-password') {
                        message = "Incorrect password";
                      } else if (e.code == 'invalid-email') {
                        message = "Invalid email address";
                      } else {
                        message = "Login failed (${e.code})";
                      }

                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            message,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    "Login",
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
              ),

              SizedBox(height: h * 0.02),

              // BOTTOM BUTTONS
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6.0),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.only(left: 20),
                        decoration: BoxDecoration(
                          color: const Color(0xFFB83257),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: TextButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => RegisterPage()),
                            );
                          },
                          child: const Text(
                            "Create Account",
                            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(width: 20),

                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.only(right: 20),
                        decoration: BoxDecoration(
                          color: const Color(0xFFB83257),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: TextButton(
                          onPressed: () async {
                            String email = emailcontroler.text.trim();

                            if (email.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    "Please enter your email first",
                                    textAlign: TextAlign.center,
                                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                                  ),
                                  backgroundColor: Colors.red,
                                ),
                              );
                              return;
                            }

                            // simple email format check
                            if (!_looksLikeEmail(email)) {
                              await _showInfoDialog(
                                context,
                                title: 'Invalid Email',
                                message: 'Please enter a valid email address.',
                              );
                              return;
                            }

                            // Show loading while attempting to send reset
                            _showLoadingDialog(context);

                            try {
                              // Try to send password reset directly.
                              await FirebaseAuth.instance.sendPasswordResetEmail(email: email);

                              // hide loading
                              Navigator.pop(context);

                              await _showInfoDialog(
                                context,
                                title: 'Check your email',
                                message: 'A password reset link has been sent to $email. Please check your inbox and spam folder.',
                              );
                            } on FirebaseAuthException catch (e) {
                              // hide loading if still showing
                              try {
                                Navigator.pop(context);
                              } catch (_) {}

                              if (e.code == 'user-not-found') {
                                // No account — suggest creating one (same as previous behavior)
                                final create = await showDialog<bool>(
                                  context: context,
                                  builder: (dialogCtx) => AlertDialog(
                                    title: const Text('No account found'),
                                    content: Text('No account is registered with "$email". Would you like to create an account?'),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(dialogCtx, false), child: const Text('Cancel')),
                                      ElevatedButton(onPressed: () => Navigator.pop(dialogCtx, true), child: const Text('Create Account')),
                                    ],
                                  ),
                                );

                                if (create == true) {
                                  Navigator.push(context, MaterialPageRoute(builder: (_) => RegisterPage()));
                                }
                                return;
                              }

                              String err = 'Failed to send reset email.';
                              if (e.code == 'invalid-email') err = 'Invalid email address.';
                              await _showInfoDialog(context, title: 'Error', message: '$err (${e.code})');
                            } catch (e) {
                              // hide loading if still showing
                              try {
                                Navigator.pop(context);
                              } catch (_) {}

                              await _showInfoDialog(context, title: 'Error', message: 'Failed to send reset email: $e');
                            }
                          },
                          child: const Text(
                            "Forgot Password",
                            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(height: h * 0.04),
            ],
          ),
        ),
      ),
    );
  }
}
