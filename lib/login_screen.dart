// login_screen.dart
import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'registerpage.dart';
import 'home_screen.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController emailcontroler = TextEditingController();
  final TextEditingController passwordcontroller = TextEditingController();

  final FocusNode _passwordFocus = FocusNode();

  bool isChecked = false;
  bool _obscure = true;
  bool _showHeader = false;
  bool _showCard = false;

  ThemeData _dialogTheme(BuildContext context) {
    final base = Theme.of(context);
    const bg = Color(0xFF0E5A42);
    const accent = Color(0xFFFFD166);
    return base.copyWith(
      dialogBackgroundColor: bg,
      colorScheme: base.colorScheme.copyWith(
        surface: bg,
        onSurface: Colors.white,
        primary: accent,
      ),
      textTheme: base.textTheme.apply(bodyColor: Colors.white, displayColor: Colors.white),
      iconTheme: const IconThemeData(color: Colors.white70),
      inputDecorationTheme: const InputDecorationTheme(
        labelStyle: TextStyle(color: Colors.white70),
        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white30)),
        focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: accent)),
      ),
      dividerColor: Colors.white24,
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _showHeader = true);
      Future.delayed(const Duration(milliseconds: 140), () {
        if (!mounted) return;
        setState(() => _showCard = true);
      });
    });
  }

  @override
  void dispose() {
    emailcontroler.dispose();
    passwordcontroller.dispose();
    _passwordFocus.dispose();
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
      builder: (dialogCtx) => Theme(
        data: _dialogTheme(context),
        child: AlertDialog(
          backgroundColor: const Color(0xFF0E5A42),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: Colors.white.withOpacity(0.12)),
          ),
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
      ),
    );
  }

  bool _looksLikeEmail(String s) {
    // Simple heuristic — keep it light (don't change UI)
    return s.contains('@') && s.contains('.');
  }

  InputDecoration _inputDecoration({
    required String label,
    required IconData icon,
    String? hint,
    Widget? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon, color: Colors.white.withValues(alpha: 0.85)),
      suffixIcon: suffix,
      labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontWeight: FontWeight.w600),
      hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.08),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFFFC857), width: 1.6),
      ),
    );
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
        return Theme(
          data: _dialogTheme(context),
          child: AlertDialog(
            backgroundColor: const Color(0xFF0E5A42),
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(color: Colors.white.withOpacity(0.12)),
            ),
            title: Row(
              children: const [
                Icon(Icons.hourglass_top, color: Colors.orange),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Account pending approval',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
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
                  if (!mounted) return;

                  // remove loading
                  Navigator.of(context).pop();

                  // After notify attempt, sign out to match previous "not allowed" behaviour
                  try {
                    await FirebaseAuth.instance.signOut();
                  } catch (_) {}

                  if (!mounted) return;
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
          ),
        );
      },
    );
  }

  Future<void> _handleForgotPassword() async {
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

    if (!_looksLikeEmail(email)) {
      await _showInfoDialog(
        context,
        title: 'Invalid Email',
        message: 'Please enter a valid email address.',
      );
      return;
    }

    _showLoadingDialog(context);

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (!mounted) return;

      Navigator.pop(context);

      await _showInfoDialog(
        context,
        title: 'Check your email',
        message: 'A password reset link has been sent to $email. Please check your inbox and spam folder.',
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      try {
        Navigator.pop(context);
      } catch (_) {}

      if (e.code == 'user-not-found') {
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

        if (!mounted) return;
        if (create == true) {
          Navigator.push(context, MaterialPageRoute(builder: (_) => RegisterPage()));
        }
        return;
      }

      String err = 'Failed to send reset email.';
      if (e.code == 'invalid-email') err = 'Invalid email address.';
      if (!mounted) return;
      await _showInfoDialog(context, title: 'Error', message: '$err (${e.code})');
    } catch (e) {
      if (!mounted) return;
      try {
        Navigator.pop(context);
      } catch (_) {}

      if (!mounted) return;
      await _showInfoDialog(context, title: 'Error', message: 'Failed to send reset email: $e');
    }
  }

  Future<void> _handleLogin() async {
    String email = emailcontroler.text.trim();
    String password = passwordcontroller.text.trim();

    if (email.isEmpty || password.isEmpty) {
      if (!mounted) return;
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
      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (!mounted) return;

      final uid = cred.user!.uid;
      final snap = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final data = snap.data();
      final role = data?['role'];
      final approved = data?['approved'] == true;

      final canLogin = role == 'admin' || approved;

      if (!canLogin) {
        await _showPendingDialog(uid: uid, email: email, name: data?['name']?.toString());
        return;
      }

      if (role == 'admin' && !approved) {
        try {
          await FirebaseFirestore.instance.collection('users').doc(uid).set({'approved': true}, SetOptions(merge: true));
        } catch (_) {
          // ignore failure to update; admin will still be allowed
        }
      }

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => HomePage()),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
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

  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final h = media.size.height;
    final viewInsets = media.viewInsets.bottom;
    final logoSize = h > 750 ? 120.0 : 104.0;

    const Color accent = Color(0xFFFFD166);

    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF041A14), Color(0xFF0E5A42)],
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
                  colors: [accent.withValues(alpha: 0.35), Colors.transparent],
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
                  colors: [Colors.white.withValues(alpha: 0.18), Colors.transparent],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(24, 24, 24, viewInsets + 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AnimatedOpacity(
                        opacity: _showHeader ? 1 : 0,
                        duration: const Duration(milliseconds: 420),
                        curve: Curves.easeOut,
                        child: AnimatedSlide(
                          offset: _showHeader ? Offset.zero : const Offset(0, 0.05),
                          duration: const Duration(milliseconds: 420),
                          curve: Curves.easeOut,
                          child: Column(
                            children: [
                              Container(
                                width: logoSize,
                                height: logoSize,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(22),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.25),
                                      blurRadius: 18,
                                      offset: const Offset(0, 10),
                                    ),
                                  ],
                                ),
                                padding: const EdgeInsets.all(12),
                                child: Image.asset('assets/images/logofile.png', fit: BoxFit.contain),
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                "Jononi Pharmacy",
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 26,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.2,
                                ),
                              ),
                              const SizedBox(height: 6),
                              const SizedBox.shrink(),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(height: h * 0.03),
                      AnimatedOpacity(
                        opacity: _showCard ? 1 : 0,
                        duration: const Duration(milliseconds: 520),
                        curve: Curves.easeOut,
                        child: AnimatedSlide(
                          offset: _showCard ? Offset.zero : const Offset(0, 0.06),
                          duration: const Duration(milliseconds: 520),
                          curve: Curves.easeOut,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(22),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                              child: Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(22),
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    const Text(
                                      "Sign in",
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 20,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      "Use your staff account to continue.",
                                      style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 13),
                                    ),
                                    const SizedBox(height: 18),
                                    TextField(
                                      controller: emailcontroler,
                                      keyboardType: TextInputType.emailAddress,
                                      textInputAction: TextInputAction.next,
                                      autofillHints: const [AutofillHints.email],
                                      onSubmitted: (_) => FocusScope.of(context).requestFocus(_passwordFocus),
                                      style: const TextStyle(color: Colors.white, fontSize: 16),
                                      decoration: _inputDecoration(
                                        label: "Email Address",
                                        hint: "name@example.com",
                                        icon: Icons.email_outlined,
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    TextField(
                                      controller: passwordcontroller,
                                      focusNode: _passwordFocus,
                                      obscureText: _obscure,
                                      obscuringCharacter: "*",
                                      textInputAction: TextInputAction.done,
                                      autofillHints: const [AutofillHints.password],
                                      onSubmitted: (_) => _handleLogin(),
                                      style: const TextStyle(color: Colors.white, fontSize: 16),
                                      decoration: _inputDecoration(
                                        label: "Password",
                                        hint: "Enter your password",
                                        icon: Icons.lock_outline,
                                        suffix: IconButton(
                                          icon: Icon(
                                            _obscure ? Icons.visibility_off : Icons.visibility,
                                            color: Colors.white.withValues(alpha: 0.85),
                                          ),
                                          onPressed: () => setState(() => _obscure = !_obscure),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        Checkbox(
                                          value: isChecked,
                                          onChanged: (v) => setState(() => isChecked = v ?? false),
                                          activeColor: accent,
                                          checkColor: Colors.black,
                                          side: BorderSide(color: Colors.white.withValues(alpha: 0.6)),
                                        ),
                                        Text(
                                          "Remember me",
                                          style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 13),
                                        ),
                                        const Spacer(),
                                        TextButton(
                                          onPressed: _handleForgotPassword,
                                          style: TextButton.styleFrom(
                                            foregroundColor: accent,
                                          ),
                                          child: const Text(
                                            "Forgot password?",
                                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    SizedBox(
                                      height: 52,
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          gradient: const LinearGradient(
                                            colors: [Color(0xFFFFD166), Color(0xFFFFB54A)],
                                          ),
                                          borderRadius: BorderRadius.circular(14),
                                        ),
                                        child: ElevatedButton(
                                          onPressed: _handleLogin,
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.transparent,
                                            shadowColor: Colors.transparent,
                                            foregroundColor: Colors.black,
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(14),
                                            ),
                                          ),
                                          child: const Text(
                                            "Login",
                                            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                                          ),
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
                      const SizedBox(height: 16),
                      OutlinedButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => RegisterPage()),
                          );
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: BorderSide(color: Colors.white.withValues(alpha: 0.35)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: const Text(
                          "Create New Account",
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        "By signing in, you agree to follow store access policies.",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}





