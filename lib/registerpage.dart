// registerpage.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'login_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final nameController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  final FocusNode _emailFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();
  final FocusNode _confirmFocus = FocusNode();

  bool _obscure = true;
  bool _showHeader = false;
  bool _showCard = false;

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
    nameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  Future<void> _createApprovalRequest({required String uid, required String email, String? name}) async {
    try {
      final ref = FirebaseFirestore.instance.collection('approval_requests').doc(uid);
      await ref.set({
        'uid': uid,
        'email': email,
        'name': name ?? '',
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      // non-blocking — we still let user register
      debugPrint('approval request create failed: $e');
    }
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
      prefixIcon: Icon(icon, color: Colors.white.withOpacity(0.85)),
      suffixIcon: suffix,
      labelStyle: TextStyle(color: Colors.white.withOpacity(0.9), fontWeight: FontWeight.w600),
      hintStyle: TextStyle(color: Colors.white.withOpacity(0.6)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      filled: true,
      fillColor: Colors.white.withOpacity(0.08),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFFFD166), width: 1.6),
      ),
    );
  }

  Future<void> _handleRegister() async {
    String email = emailController.text.trim();
    String password = passwordController.text.trim();
    String confirmPassword = confirmPasswordController.text.trim();

    bool isValidEmail = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email);

    if (!isValidEmail) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Invalid email address",
            textAlign: TextAlign.center,
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (password.length < 6) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Password must be at least 6 characters long",
            textAlign: TextAlign.center,
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (password != confirmPassword) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Password and Confirm Password do not match",
            textAlign: TextAlign.center,
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      try {
        final u = cred.user;
        if (u != null) {
          final String adminEmail = 'rkamonasish@gmail.com';
          final role = email.toLowerCase() == adminEmail.toLowerCase() ? 'admin' : 'seller';

          final bool isAdmin = role == 'admin';
          final userDocData = <String, dynamic>{
            'email': email,
            'role': role,
            'name': nameController.text.trim(),
            'nameLower': nameController.text.trim().toLowerCase(),
            'photoUrl': null,
            'createdAt': FieldValue.serverTimestamp(),
            'approved': isAdmin ? true : false,
          };

          if (!isAdmin) {
            userDocData['status'] = 'pending';
            userDocData['approvalRequestedAt'] = FieldValue.serverTimestamp();
          } else {
            userDocData['approved'] = true;
            userDocData['status'] = 'approved';
            userDocData['approvedAt'] = FieldValue.serverTimestamp();
          }

          await FirebaseFirestore.instance.collection('users').doc(u.uid).set(userDocData, SetOptions(merge: true));

          if (!isAdmin) {
            await _createApprovalRequest(uid: u.uid, email: email, name: nameController.text.trim());
          }
        }
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Registered but failed to save profile: $e')));
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Registration Successful",
            textAlign: TextAlign.center,
          ),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => LoginPage()),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      String message = "";

      if (e.code == 'email-already-in-use') {
        message = "Email already in use";
      } else if (e.code == 'invalid-email') {
        message = "Invalid email format";
      } else if (e.code == 'weak-password') {
        message = "Weak password";
      } else {
        message = "Error: ${e.code}";
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            message,
            textAlign: TextAlign.center,
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
    final logoSize = h > 750 ? 110.0 : 96.0;

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
                  colors: [accent.withOpacity(0.35), Colors.transparent],
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
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(24, 24, 24, viewInsets + 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
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
                                      color: Colors.black.withOpacity(0.25),
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
                                "Create your account",
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.2,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                "Access is approved by admin before activation.",
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.75),
                                  fontSize: 13,
                                  letterSpacing: 0.4,
                                ),
                              ),
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
                                  color: Colors.white.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(22),
                                  border: Border.all(color: Colors.white.withOpacity(0.22)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    const Text(
                                      "Register",
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 20,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      "Use a valid email. Admin approval required.",
                                      style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13),
                                    ),
                                    const SizedBox(height: 18),
                                    TextField(
                                      controller: nameController,
                                      textInputAction: TextInputAction.next,
                                      autofillHints: const [AutofillHints.name],
                                      onSubmitted: (_) => FocusScope.of(context).requestFocus(_emailFocus),
                                      style: const TextStyle(color: Colors.white, fontSize: 16),
                                      decoration: _inputDecoration(
                                        label: "Full Name (optional)",
                                        hint: "Your name",
                                        icon: Icons.person_outline,
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    TextField(
                                      controller: emailController,
                                      focusNode: _emailFocus,
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
                                      controller: passwordController,
                                      focusNode: _passwordFocus,
                                      obscureText: _obscure,
                                      obscuringCharacter: "*",
                                      textInputAction: TextInputAction.next,
                                      autofillHints: const [AutofillHints.newPassword],
                                      onSubmitted: (_) => FocusScope.of(context).requestFocus(_confirmFocus),
                                      style: const TextStyle(color: Colors.white, fontSize: 16),
                                      decoration: _inputDecoration(
                                        label: "Password",
                                        hint: "Create a strong password",
                                        icon: Icons.lock_outline,
                                        suffix: IconButton(
                                          icon: Icon(
                                            _obscure ? Icons.visibility_off : Icons.visibility,
                                            color: Colors.white.withOpacity(0.85),
                                          ),
                                          onPressed: () => setState(() => _obscure = !_obscure),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    TextField(
                                      controller: confirmPasswordController,
                                      focusNode: _confirmFocus,
                                      obscureText: _obscure,
                                      obscuringCharacter: "*",
                                      textInputAction: TextInputAction.done,
                                      autofillHints: const [AutofillHints.newPassword],
                                      onSubmitted: (_) => _handleRegister(),
                                      style: const TextStyle(color: Colors.white, fontSize: 16),
                                      decoration: _inputDecoration(
                                        label: "Confirm Password",
                                        hint: "Re-enter your password",
                                        icon: Icons.verified_user_outlined,
                                        suffix: IconButton(
                                          icon: Icon(
                                            _obscure ? Icons.visibility_off : Icons.visibility,
                                            color: Colors.white.withOpacity(0.85),
                                          ),
                                          onPressed: () => setState(() => _obscure = !_obscure),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 16),
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
                                          onPressed: _handleRegister,
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.transparent,
                                            shadowColor: Colors.transparent,
                                            foregroundColor: Colors.black,
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(14),
                                            ),
                                          ),
                                          child: const Text(
                                            "Create Account",
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
                          Navigator.pop(context);
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: BorderSide(color: Colors.white.withOpacity(0.35)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: const Text(
                          "Back to Login",
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        "By creating an account you agree to follow store access policies.",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 11),
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






