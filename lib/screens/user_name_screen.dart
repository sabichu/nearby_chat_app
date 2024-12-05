import 'package:flutter/material.dart';
import 'package:nearby_chat_app/screens/home_screen.dart';

class UserNameScreen extends StatefulWidget {
  @override
  _UserNameScreenState createState() => _UserNameScreenState();
}

class _UserNameScreenState extends State<UserNameScreen> {
  final TextEditingController _controller = TextEditingController();
  String? _errorMessage;

  void _validateAndProceed() {
    String name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() {
        _errorMessage = "El nombre no puede estar vacío.";
      });
      return;
    }
    if (name.length > 16) {
      setState(() {
        _errorMessage = "El nombre no puede exceder 16 caracteres.";
      });
      return;
    }
    if (!RegExp(r"^[a-zA-Z0-9\s\-_]+$").hasMatch(name)) {
      setState(() {
        _errorMessage =
            "Solo se permiten letras, números, espacios, guiones y guiones bajos.";
      });
      return;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => HomeScreen(userName: name),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Choose your username',
                style: TextStyle(fontSize: 24, color: Colors.white),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _controller,
                decoration: InputDecoration(
                  labelText: "Username",
                  errorText: _errorMessage,
                  labelStyle: const TextStyle(color: Colors.white),
                  enabledBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white),
                  ),
                  focusedBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.blue),
                  ),
                ),
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _validateAndProceed,
                child: const Text("Start chatting"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
