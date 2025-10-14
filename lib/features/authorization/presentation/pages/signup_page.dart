import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';

class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final emailController = TextEditingController();
  final usernameController = TextEditingController();
  final nameController = TextEditingController();
  final passwordController = TextEditingController();
  bool isLoading = false;

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.deepPurple,
        title: const Text('Signup'),
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
                'Create Account',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.deepPurple,
                ),
              ),
              const SizedBox(height: 20),
              _buildTextField(
                controller: emailController,
                label: 'Email',
                icon: Icons.email,
                isPassword: false,
              ),
              const SizedBox(height: 15),
              _buildTextField(
                controller: usernameController,
                label: 'Username',
                icon: Icons.person,
                isPassword: false,
              ),
              const SizedBox(height: 15),
              _buildTextField(
                controller: nameController,
                label: 'Full Name',
                icon: Icons.person_add,
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
              _buildSignupButton(authProvider),
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

  Widget _buildSignupButton(AuthProvider authProvider) {
    return ElevatedButton(
      onPressed: isLoading
          ? null
          : () async {
              setState(() => isLoading = true);
              final success = await authProvider.signup(
                email: emailController.text,
                username: usernameController.text,
                name: nameController.text,
                password: passwordController.text,
              );
              setState(() => isLoading = false);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    success ? 'Signup Successful' : 'Signup Failed',
                  ),
                ),
              );
              if (success && mounted) {
                Navigator.pop(context);
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
              'Signup',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
    );
  }
}
