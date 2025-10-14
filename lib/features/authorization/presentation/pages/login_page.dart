import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import 'signup_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  bool isLoading = false;

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.deepPurple,
        title: const Text('Login'),
        elevation: 0,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const SizedBox(height: 40),
              Text(
                'Welcome Back!',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.deepPurple,
                ),
              ),
              const SizedBox(height: 20),
              _buildTextField(
                controller: emailController,
                label: 'Email or Username',
                icon: Icons.email,
                isPassword: false,
              ),
              const SizedBox(height: 15),
              _buildTextField(
                controller: passwordController,
                label: 'Password',
                icon: Icons.lock,
                isPassword: true,
              ),
              const SizedBox(height: 25),
              _buildLoginButton(authProvider),
              const SizedBox(height: 10),
              _buildSignUpTextButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required bool isPassword,
  }) {
    return TextField(
      controller: controller,
      obscureText: isPassword,
      style: const TextStyle(fontSize: 18),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.deepPurple),
        prefixIcon: Icon(icon, color: Colors.deepPurple),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: Colors.deepPurple),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: Colors.grey),
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Widget _buildLoginButton(AuthProvider authProvider) {
    return ElevatedButton(
      onPressed: isLoading
          ? null
          : () async {
              setState(() => isLoading = true);
              final success = await authProvider.login(
                email: emailController.text.contains('@')
                    ? emailController.text
                    : null,
                username: emailController.text.contains('@')
                    ? null
                    : emailController.text,
                password: passwordController.text,
              );
              setState(() => isLoading = false);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(success ? 'Login Successful' : 'Login Failed'),
                ),
              );
              if (success && mounted) {
                Navigator.pushReplacementNamed(
                  context,
                  '/home',
                ); // Navigate to home
              }
            },
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.deepPurple,
        padding: const EdgeInsets.symmetric(vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
      ),
      child: isLoading
          ? const CircularProgressIndicator(color: Colors.white)
          : const Text(
              'Login',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
    );
  }

  Widget _buildSignUpTextButton() {
    return TextButton(
      onPressed: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const SignupPage()),
      ),
      child: const Text(
        "Don’t have an account? Sign up",
        style: TextStyle(
          fontSize: 16,
          color: Colors.deepPurple,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
