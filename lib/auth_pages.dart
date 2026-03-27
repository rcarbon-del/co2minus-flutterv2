import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'user_provider.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const Color brandNavy = Color(0xFF2D3E50);
    const Color brandGreen = Color(0xFFC8FFB0);
    final userProvider = Provider.of<UserProvider>(context);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Background
          Positioned.fill(
            child: RepaintBoundary(
              child: Image.asset(
                'assets/images/background.png',
                fit: BoxFit.cover,
              ),
            ),
          ),
          
          // Content
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(flex: 3),
                // Logo Area - Removed Circle & Enlarged
                TweenAnimationBuilder<double>(
                  duration: const Duration(milliseconds: 800),
                  curve: Curves.easeOutBack,
                  tween: Tween(begin: 0.0, end: 1.0),
                  builder: (context, value, child) => Transform.scale(
                    scale: value,
                    child: child,
                  ),
                  child: Image.asset(
                    'assets/images/logo.png',
                    height: 200, 
                    width: 200,
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(height: 16), 
                _AnimatedTextSlide(
                  delay: 200,
                  child: Text(
                    userProvider.displayName == "Guest" 
                        ? "CO2-" 
                        : userProvider.displayName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: brandNavy,
                      fontSize: 48,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1.5,
                    ),
                  ),
                ),
                const _AnimatedTextSlide(
                  delay: 400,
                  child: Text(
                    "One footprint at a time.",
                    style: TextStyle(
                      color: Color(0x992D3E50),
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Spacer(flex: 2),
                
                // Action Buttons with Staggered Entrance
                _AnimatedTextSlide(
                  delay: 600,
                  child: _AuthButton(
                    text: "GET STARTED",
                    color: brandNavy,
                    textColor: Colors.white,
                    onPressed: () => Navigator.push(
                      context,
                      PageRouteBuilder(
                        pageBuilder: (context, animation, secondaryAnimation) => const SignUpScreen(),
                        transitionsBuilder: (context, animation, secondaryAnimation, child) {
                          return FadeTransition(opacity: animation, child: child);
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _AnimatedTextSlide(
                  delay: 800,
                  child: _AuthButton(
                    text: "SIGN IN",
                    color: brandGreen,
                    textColor: brandNavy,
                    onPressed: () => Navigator.push(
                      context,
                      PageRouteBuilder(
                        pageBuilder: (context, animation, secondaryAnimation) => const SignInScreen(),
                        transitionsBuilder: (context, animation, secondaryAnimation, child) {
                          return FadeTransition(opacity: animation, child: child);
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 48),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    const Color brandNavy = Color(0xFF2D3E50);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/background.png',
              fit: BoxFit.cover,
            ),
          ),
          CustomScrollView(
            slivers: [
              SliverAppBar(
                backgroundColor: Colors.transparent,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, color: brandNavy),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 20),
                      _AnimatedTextSlide(
                        child: const Text(
                          "Welcome\nBack",
                          style: TextStyle(
                            color: brandNavy,
                            fontSize: 40,
                            fontWeight: FontWeight.w900,
                            height: 1.1,
                            letterSpacing: -1.0,
                          ),
                        ),
                      ),
                      const SizedBox(height: 40),
                      _AnimatedTextSlide(
                        delay: 200,
                        child: _SmokeyGlassTextField(
                          controller: _emailController,
                          hint: "Email Address",
                          icon: Icons.email_outlined,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _AnimatedTextSlide(
                        delay: 300,
                        child: _SmokeyGlassTextField(
                          controller: _passwordController,
                          hint: "Password",
                          icon: Icons.lock_outline_rounded,
                          isPassword: true,
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: _AnimatedTextSlide(
                          delay: 400,
                          child: TextButton(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => const ForgotPasswordScreen()),
                            ),
                            child: Text(
                              "Forgot Password?",
                              style: TextStyle(
                                color: brandNavy.withValues(alpha: 0.6),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),
                      _AnimatedTextSlide(
                        delay: 500,
                        child: Consumer<UserProvider>(
                          builder: (context, userProvider, child) {
                            return _AuthButton(
                              text: "SIGN IN",
                              color: brandNavy,
                              textColor: Colors.white,
                              onPressed: () async {
                                try {
                                  await userProvider.signInWithEmail(
                                    _emailController.text,
                                    _passwordController.text,
                                  );
                                  if (context.mounted) {
                                    Navigator.popUntil(context, (route) => route.isFirst);
                                  }
                                } catch (e) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(e.toString())),
                                  );
                                }
                              },
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 24),
                      const _AnimatedTextSlide(delay: 600, child: _OrDivider()),
                      const SizedBox(height: 24),
                      _AnimatedTextSlide(
                        delay: 700,
                        child: Consumer<UserProvider>(
                          builder: (context, userProvider, child) {
                            return _GoogleButton(
                              onPressed: () async {
                                try {
                                  await userProvider.signInWithGoogle();
                                  if (context.mounted) {
                                    Navigator.popUntil(context, (route) => route.isFirst);
                                  }
                                } catch (e) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(e.toString())),
                                  );
                                }
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  DateTime? _dateOfBirth;

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime(DateTime.now().year - 13), 
      firstDate: DateTime(1920),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _dateOfBirth) {
      setState(() {
        _dateOfBirth = picked;
      });
    }
  }

  bool _isUnderage(DateTime dob) {
    final now = DateTime.now();
    int age = now.year - dob.year;
    if (now.month < dob.month || (now.month == dob.month && now.day < dob.day)) {
      age--;
    }
    return age < 13;
  }

  @override
  Widget build(BuildContext context) {
    const Color brandNavy = Color(0xFF2D3E50);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/background.png',
              fit: BoxFit.cover,
            ),
          ),
          CustomScrollView(
            slivers: [
              SliverAppBar(
                backgroundColor: Colors.transparent,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, color: brandNavy),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 20),
                      _AnimatedTextSlide(
                        child: const Text(
                          "Create\nAccount",
                          style: TextStyle(
                            color: brandNavy,
                            fontSize: 40,
                            fontWeight: FontWeight.w900,
                            height: 1.1,
                            letterSpacing: -1.0,
                          ),
                        ),
                      ),
                      const SizedBox(height: 40),
                      _AnimatedTextSlide(
                        delay: 200,
                        child: _SmokeyGlassTextField(
                          controller: _nameController,
                          hint: "Full Name",
                          icon: Icons.person_outline_rounded,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _AnimatedTextSlide(
                        delay: 300,
                        child: GestureDetector(
                          onTap: () => _selectDate(context),
                          child: AbsorbPointer(
                            child: _SmokeyGlassTextField(
                              hint: _dateOfBirth == null
                                  ? 'Date of Birth'
                                  : "${_dateOfBirth!.month}/${_dateOfBirth!.day}/${_dateOfBirth!.year}",
                              icon: Icons.calendar_today_outlined,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _AnimatedTextSlide(
                        delay: 400,
                        child: _SmokeyGlassTextField(
                          controller: _emailController,
                          hint: "Email Address",
                          icon: Icons.email_outlined,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _AnimatedTextSlide(
                        delay: 500,
                        child: _SmokeyGlassTextField(
                          controller: _passwordController,
                          hint: "Password",
                          icon: Icons.lock_outline_rounded,
                          isPassword: true,
                        ),
                      ),
                      const SizedBox(height: 32),
                      _AnimatedTextSlide(
                        delay: 600,
                        child: Consumer<UserProvider>(
                          builder: (context, userProvider, child) {
                            return _AuthButton(
                              text: "CREATE ACCOUNT",
                              color: brandNavy,
                              textColor: Colors.white,
                              onPressed: () async {
                                if (_dateOfBirth == null) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text("Please select your date of birth.")),
                                  );
                                  return;
                                }
                                
                                if (_isUnderage(_dateOfBirth!)) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text("You must be at least 13 years old to use CO2-.")),
                                  );
                                  return;
                                }

                                try {
                                  await userProvider.signUpWithEmail(
                                    _emailController.text,
                                    _passwordController.text,
                                    _nameController.text,
                                    _dateOfBirth,
                                  );
                                  if (context.mounted) {
                                    Navigator.popUntil(context, (route) => route.isFirst);
                                  }
                                } catch (e) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(e.toString())),
                                  );
                                }
                              },
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 24),
                      const _AnimatedTextSlide(delay: 700, child: _OrDivider()),
                      const SizedBox(height: 24),
                      _AnimatedTextSlide(
                        delay: 800,
                        child: Consumer<UserProvider>(
                          builder: (context, userProvider, child) {
                            return _GoogleButton(
                              onPressed: () async {
                                try {
                                  await userProvider.signInWithGoogle();
                                  if (context.mounted) {
                                    Navigator.popUntil(context, (route) => route.isFirst);
                                  }
                                } catch (e) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(e.toString())),
                                  );
                                }
                              },
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class ForgotPasswordScreen extends StatelessWidget {
  const ForgotPasswordScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const Color brandNavy = Color(0xFF2D3E50);
    final _emailController = TextEditingController();

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/background.png',
              fit: BoxFit.cover,
            ),
          ),
          CustomScrollView(
            slivers: [
              SliverAppBar(
                backgroundColor: Colors.transparent,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, color: brandNavy),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 20),
                      _AnimatedTextSlide(
                        child: const Text(
                          "Reset\nPassword",
                          style: TextStyle(
                            color: brandNavy,
                            fontSize: 40,
                            fontWeight: FontWeight.w900,
                            height: 1.1,
                            letterSpacing: -1.0,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _AnimatedTextSlide(
                        delay: 200,
                        child: Text(
                          "Enter your email address and we'll send you a link to reset your password.",
                          style: TextStyle(
                            color: brandNavy.withValues(alpha: 0.6),
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(height: 40),
                      _AnimatedTextSlide(
                        delay: 300,
                        child: _SmokeyGlassTextField(
                          controller: _emailController,
                          hint: "Email Address",
                          icon: Icons.email_outlined,
                        ),
                      ),
                      const SizedBox(height: 32),
                      _AnimatedTextSlide(
                        delay: 400,
                        child: Consumer<UserProvider>(
                          builder: (context, userProvider, child) {
                            return _AuthButton(
                              text: "SEND RESET LINK",
                              color: brandNavy,
                              textColor: Colors.white,
                              onPressed: () async {
                                try {
                                  await userProvider.resetPassword(_emailController.text);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text("Password reset email sent.")),
                                  );
                                } catch (e) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(e.toString())),
                                  );
                                }
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AnimatedTextSlide extends StatelessWidget {
  final Widget child;
  final int delay;

  const _AnimatedTextSlide({required this.child, this.delay = 0});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutQuart,
      tween: Tween(begin: 0.0, end: 1.0),
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - value)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

class _SmokeyGlassTextField extends StatelessWidget {
  final String hint;
  final IconData icon;
  final bool isPassword;
  final TextEditingController? controller;

  const _SmokeyGlassTextField({
    required this.hint,
    required this.icon,
    this.isPassword = false,
    this.controller,
  });

  @override
  Widget build(BuildContext context) {
    const Color brandNavy = Color(0xFF2D3E50);
    return Container(
      decoration: BoxDecoration(
        color: brandNavy.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2), width: 1.5),
      ),
      child: TextField(
        controller: controller,
        obscureText: isPassword,
        style: const TextStyle(color: brandNavy, fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: brandNavy.withValues(alpha: 0.4)),
          prefixIcon: Icon(icon, color: brandNavy.withValues(alpha: 0.4)),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        ),
      ),
    );
  }
}

class _AuthButton extends StatelessWidget {
  final String text;
  final Color color;
  final Color textColor;
  final VoidCallback onPressed;

  const _AuthButton({
    required this.text,
    required this.color,
    required this.textColor,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 60,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.2),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: textColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          elevation: 0,
        ),
        child: Text(
          text,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 1.0),
        ),
      ),
    );
  }
}

class _GoogleButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _GoogleButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    const Color brandNavy = Color(0xFF2D3E50);
    return Container(
      width: double.infinity,
      height: 60,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: brandNavy.withValues(alpha: 0.1), width: 1.5),
      ),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const FaIcon(FontAwesomeIcons.google, color: brandNavy, size: 20),
            const SizedBox(width: 12),
            Text(
              "CONTINUE WITH GOOGLE",
              style: TextStyle(
                color: brandNavy.withValues(alpha: 0.8),
                fontWeight: FontWeight.w900,
                fontSize: 14,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    const Color brandNavy = Color(0xFF2D3E50);
    return Row(
      children: [
        Expanded(child: Divider(color: brandNavy.withValues(alpha: 0.1))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            "OR",
            style: TextStyle(
              color: brandNavy.withValues(alpha: 0.3),
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
        ),
        Expanded(child: Divider(color: brandNavy.withValues(alpha: 0.1))),
      ],
    );
  }
}
