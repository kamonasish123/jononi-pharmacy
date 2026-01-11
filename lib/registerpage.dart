// registerpage.dart
import 'package:flutter/material.dart';
import 'package:jononipharmacy/loginpage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class RegisterPage extends StatefulWidget {
  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final nameController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  bool _obscure = true;

  @override
  void dispose() {
    nameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
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

  Widget _label(String text, double fontSize) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 26),
      padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFB83257),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white,
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }

  Widget _textField(TextEditingController controller, {required String hint, bool obscure = false, Widget? suffix, double fontSize = 18}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 26, vertical: 6),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        obscuringCharacter: "*",
        style: TextStyle(color: Colors.white, fontSize: fontSize),
        decoration: InputDecoration(
          filled: true,
          fillColor: Colors.white.withOpacity(0.1),
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.black),
          suffixIcon: suffix,
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
    );
  }

  @override
  Widget build(BuildContext context) {
    // Responsive sizes
    final media = MediaQuery.of(context);
    final h = media.size.height;
    final textScale = media.textScaleFactor;
    // scale fonts a bit with screen height
    final labelFont = (h > 750) ? 22.0 : 20.0;
    final inputFont = (h > 750) ? 20.0 : 18.0;
    final logoSize = (h > 800) ? h * 0.22 : h * 0.20;

    return Scaffold(
      backgroundColor: const Color(0xFF01684D),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.only(bottom: media.viewInsets.bottom + 16),
          child: Column(
            children: [
              SizedBox(height: media.padding.top + (h * 0.02)),

              // Logo (responsive)
              Center(
                child: ClipOval(
                  child: Container(
                    width: logoSize,
                    height: logoSize,
                    color: Colors.white, // ✅ solid logo background
                    child: Image.asset(
                      'assets/images/logofile.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),


              SizedBox(height: h * 0.025),

              // (Optional) Name field — kept out if you don't want to show; it's present as controller in your logic.
              // If you prefer not to show name input visually, remove this block. Currently omitted to keep layout same as original.

              // EMAIL LABEL
              _label("Email Address", labelFont),
              const SizedBox(height: 5),
              // EMAIL FIELD
              _textField(emailController, hint: "Enter your email", fontSize: inputFont),

              SizedBox(height: h * 0.02),

              // PASSWORD LABEL
              _label("Password", labelFont),
              const SizedBox(height: 5),
              // PASSWORD FIELD
              _textField(
                passwordController,
                hint: "Enter your password",
                obscure: _obscure,
                suffix: IconButton(
                  icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility, color: Colors.black),
                  onPressed: () {
                    setState(() {
                      _obscure = !_obscure;
                    });
                  },
                ),
                fontSize: inputFont,
              ),

              SizedBox(height: h * 0.02),

              // CONFIRM LABEL
              _label("Confirm Password", labelFont),
              const SizedBox(height: 5),
              _textField(
                confirmPasswordController,
                hint: "Re-enter your password",
                obscure: _obscure,
                suffix: IconButton(
                  icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility, color: Colors.black),
                  onPressed: () {
                    setState(() {
                      _obscure = !_obscure;
                    });
                  },
                ),
                fontSize: inputFont,
              ),

              SizedBox(height: h * 0.03),

              // REGISTER BUTTON
              Container(
                width: double.infinity,
                margin: const EdgeInsets.symmetric(horizontal: 26),
                child: ElevatedButton(
                  onPressed: () async {
                    String email = emailController.text.trim();
                    String password = passwordController.text.trim();
                    String confirmPassword = confirmPasswordController.text.trim();

                    // Email validation regex
                    bool isValidEmail = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email);

                    if (!isValidEmail) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("Invalid email address",
                            textAlign: TextAlign.center,
                            // reduced font to avoid very large snack text on small screens
                          ),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }
                    if (password.length < 6) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("Password must be at least 6 characters long",
                            textAlign: TextAlign.center,
                          ),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }

                    if (password != confirmPassword) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("Password and Confirm Password do not match",
                            textAlign: TextAlign.center,
                          ),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }

                    // If everything is valid
                    try {
                      // create auth user
                      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
                        email: email,
                        password: password,
                      );

                      // create Firestore user doc so app can read role later
                      try {
                        final u = cred.user;
                        if (u != null) {
                          // if this specific email should be admin, adjust here:
                          final String adminEmail = 'rkamonasish@gmail.com';
                          // compare lowercased for robustness
                          final role = email.toLowerCase() == adminEmail.toLowerCase() ? 'admin' : 'seller';

                          final bool isAdmin = role == 'admin';
                          // Write user doc; for non-admins mark approved:false and pending fields so admin panel sees them
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
                            // ensure admin has approved true
                            userDocData['approved'] = true;
                            userDocData['status'] = 'approved';
                            userDocData['approvedAt'] = FieldValue.serverTimestamp();
                          }

                          await FirebaseFirestore.instance.collection('users').doc(u.uid).set(userDocData, SetOptions(merge: true));

                          // create approval request automatically for non-admins (so admin panel & audit see them)
                          if (!isAdmin) {
                            await _createApprovalRequest(uid: u.uid, email: email, name: nameController.text.trim());
                          }
                        }
                      } catch (e) {
                        // Firestore write failed, but registration succeeded — show non-blocking message
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Registered but failed to save profile: $e')));
                      }

                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            "Registration Successful",
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: labelFont * 0.9, fontWeight: FontWeight.bold),
                          ),
                          backgroundColor: Colors.green,
                        ),
                      );

                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => loginpage()),
                      );

                    } on FirebaseAuthException catch (e) {
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
                            style: TextStyle(fontSize: inputFont * 0.9, fontWeight: FontWeight.bold),
                          ),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  },

                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFB83257),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    "Register",
                    style: TextStyle(fontSize: inputFont, fontWeight: FontWeight.bold),
                  ),
                ),
              ),

              // Move the 'Already have an account? Login' just below the register button (more visible)
              const SizedBox(height: 12),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                child: const Text(
                  "Already have an account? Login",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),

              SizedBox(height: h * 0.03),
            ],
          ),
        ),
      ),
    );
  }
}
